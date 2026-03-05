# Moodle on Alibaba Cloud (Terraform + ACK)

Production-oriented Moodle template on Alibaba Cloud with Terraform and Kubernetes.

This stack includes:
- ACK (managed Kubernetes)
- RDS PostgreSQL
- Redis (session + cache clusters)
- PgBouncer (RW + RO)
- NAS for `moodledata`
- OSS/ObjectFS (optional)
- ACR EE for image registry

## Scope

This repository is designed for:
- Single baseline template for 150k concurrent-user design target.
- Fast bootstrap access via LB/IP before DNS/TLS hardening.
- Clear path to staged load testing after readiness is stable.

This repository does not include by default:
- Automated DNS + TLS + WAF/CDN edge stack.
- Proven concurrency guarantee without load-test evidence.

## Repository Layout

All commands in this README assume you run them from the project root.

```text
infra/       # Terraform infrastructure (network, ACK, DB, storage, registry, runtime secrets)
images/      # Docker images (moodle, pgbouncer)
manifests/   # Kubernetes manifests (PVC, redis, pgbouncer, moodle, cron) + runtime.env tunables
README.md
```

## Prerequisites

Install locally:
- Terraform >= 1.5
- kubectl
- Docker
- gettext (`envsubst`)
- jq
- nslookup/dig

Alibaba Cloud permissions should cover at least:
- VPC, ECS, ACK
- RDS
- NAS
- OSS
- ACR EE
- RAM (needed when enabling managed ObjectFS credentials)

## Quickstart (Copy-Paste)

### 1) Configure credentials

```bash
export ALICLOUD_ACCESS_KEY="<your_access_key>"
export ALICLOUD_SECRET_KEY="<your_secret_key>"
```

If your shell uses `ALIBABA_CLOUD_ACCESS_KEY_ID/ALIBABA_CLOUD_ACCESS_KEY_SECRET`:

```bash
export ALICLOUD_ACCESS_KEY="${ALIBABA_CLOUD_ACCESS_KEY_ID}"
export ALICLOUD_SECRET_KEY="${ALIBABA_CLOUD_ACCESS_KEY_SECRET}"
```

### 2) Prepare Terraform variables

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```

Edit `infra/terraform.tfvars` at minimum:

```hcl
project_name       = "moodle-high-scale"
region             = "ap-southeast-1"
moodle_environment = "production"

# Bootstrap mode (recommended first run)
moodle_www_root  = ""
moodle_ssl_proxy = "false"

# Registry must be enabled to build/push/pull images
cr_enabled = true

# Optional: reuse existing ACR EE instance
# cr_existing_instance_id = "cri-xxxxxxxx"

# NAS baseline for moodledata
# (default variable is already "Performance")
# nas_storage_type     = "Performance"
# nas_file_system_type = "standard"
```

If you set `cr_existing_instance_id`, Terraform will reuse that ACR EE instance (no new registry instance is created).
For existing registry, keep these in the same `terraform.tfvars`:

```hcl
cr_enabled                             = true
cr_existing_instance_id                = "cri-xxxxxxxx"
cr_link_ack_vpc_endpoint               = true
cr_vpc_endpoint_enable_privatezone_dns = true
cr_registry_endpoint_prefer_vpc        = true
```

If your push host must use internet endpoint with ACL restriction:

```hcl
cr_enable_internet_acl_service = true
cr_internet_acl_entries = [
  "203.0.113.10/32", # office/VPN egress IP
]
```

### 3) Create infrastructure

```bash
terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra apply
```

If first apply fails because Kubernetes provider is not ready yet, wait a few minutes and run apply again.

### 4) Export kubeconfig

```bash
terraform -chdir=infra output -raw ack_kube_config > /tmp/ack-kubeconfig
export KUBECONFIG=/tmp/ack-kubeconfig
```

### 5) Build and push images

Use public endpoint for push and runtime endpoint for cluster pulls.

```bash
export REGISTRY_PUSH_ENDPOINT="$(terraform -chdir=infra output -raw cr_registry_endpoint_for_push)"
export REGISTRY_RUNTIME_ENDPOINT="$(terraform -chdir=infra output -raw cr_registry_endpoint_for_runtime)"
export CR_USER="$(terraform -chdir=infra output -raw cr_registry_username)"
export CR_PASS="$(terraform -chdir=infra output -raw cr_registry_password)"
export IMAGE_TAG="v$(date +%Y%m%d-%H%M%S)"

nslookup "${REGISTRY_PUSH_ENDPOINT}"
echo "${CR_PASS}" | docker login "${REGISTRY_PUSH_ENDPOINT}" --username "${CR_USER}" --password-stdin

docker build -t ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG} images/moodle
docker build -t ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG} images/pgbouncer
docker push ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG}
docker push ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG}
```

Use a new `IMAGE_TAG` every build.

### 6) Create image pull secret for runtime

```bash
kubectl -n moodle create secret docker-registry acr-regcred \
  --docker-server="${REGISTRY_RUNTIME_ENDPOINT}" \
  --docker-username="${CR_USER}" \
  --docker-password="${CR_PASS}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 7) Deploy manifests

```bash
export NAMESPACE=moodle
export NAS_MOUNT_TARGET_DOMAIN="$(terraform -chdir=infra output -raw nas_mount_target_domain)"
export MOODLE_IMAGE=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG}
export PGBOUNCER_IMAGE=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG}

set -a
source manifests/runtime.env
set +a

envsubst '${NAMESPACE} ${NAS_MOUNT_TARGET_DOMAIN}' < manifests/00-moodle-data-nfs.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${REDIS_SESSION_REPLICAS} ${REDIS_CACHE_REPLICAS} ${REDIS_CPU_REQUEST} ${REDIS_MEM_REQUEST} ${REDIS_CPU_LIMIT} ${REDIS_MEM_LIMIT} ${REDIS_STORAGE_REQUEST}' < manifests/10-redis-cluster.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${PGBOUNCER_IMAGE} ${PGBOUNCER_RW_REPLICAS} ${PGBOUNCER_RO_REPLICAS} ${PGBOUNCER_CPU_REQUEST} ${PGBOUNCER_MEM_REQUEST} ${PGBOUNCER_CPU_LIMIT} ${PGBOUNCER_MEM_LIMIT}' < manifests/20-pgbouncer.yaml | kubectl apply -f -
envsubst '${NAMESPACE}' < manifests/21-pdb.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${MOODLE_IMAGE} ${MOODLE_WEB_REPLICAS} ${MOODLE_WEB_CPU_REQUEST} ${MOODLE_WEB_MEM_REQUEST} ${MOODLE_WEB_CPU_LIMIT} ${MOODLE_WEB_MEM_LIMIT}' < manifests/30-moodle.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${MOODLE_IMAGE} ${MOODLE_CRON_REPLICAS} ${MOODLE_CRON_CPU_REQUEST} ${MOODLE_CRON_MEM_REQUEST} ${MOODLE_CRON_CPU_LIMIT} ${MOODLE_CRON_MEM_LIMIT}' < manifests/40-moodle-cron.yaml | kubectl apply -f -
```

### 8) Initialize Redis clusters

```bash
./manifests/11-redis-init.sh moodle
```

### 9) Install Moodle database

```bash
kubectl -n moodle exec deployment/moodle-deployment -- \
  php /var/www/html/admin/cli/install_database.php --adminuser=admin --adminpass='AdminTemp!2026' --agree-license
```

### 10) Verify runtime

```bash
kubectl -n moodle get pods
kubectl -n moodle get svc moodle-svc
```

Open the external IP shown by `moodle-svc`.

## Operations

### Update image (no reinstall)

```bash
export IMAGE_TAG="v$(date +%Y%m%d-%H%M%S)"

docker build -t ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG} images/moodle
docker build -t ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG} images/pgbouncer
docker push ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG}
docker push ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG}

kubectl -n moodle set image deployment/moodle-deployment moodle=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG}
kubectl -n moodle set image deployment/moodle-cron-deployment moodle-cron=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG}
kubectl -n moodle set image deployment/pgbouncer-deployment pgbouncer=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG}
kubectl -n moodle set image deployment/pgbouncer-read-deployment pgbouncer-read=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG}

kubectl -n moodle rollout status deployment/moodle-deployment --timeout=600s
kubectl -n moodle rollout status deployment/moodle-cron-deployment --timeout=600s
kubectl -n moodle rollout status deployment/pgbouncer-deployment --timeout=600s
kubectl -n moodle rollout status deployment/pgbouncer-read-deployment --timeout=600s
```

### Reset admin password

```bash
kubectl -n moodle exec deployment/moodle-deployment -- \
  php /var/www/html/admin/cli/reset_password.php --username=admin --password='NewStrongPassword!'
```

### Check cron health

```bash
kubectl -n moodle exec deployment/moodle-deployment -- \
  php /var/www/html/admin/cli/cfg.php --component=tool_task --name=lastcronstart
```

## Baseline and Overrides

Default baseline in this template is a single 150k-design configuration:
- ACK node pool autoscaling enabled
- RDS category `HighAvailability`
- RDS readonly enabled
- Runtime replicas/resources loaded from `manifests/runtime.env`
- ObjectFS S3-compatible enabled with auto-generated RAM credentials

For first access without DNS/TLS, keep:

```hcl
moodle_www_root  = ""
moodle_ssl_proxy = "false"
```

If your account has early blockers, override in the same `terraform.tfvars`:

```hcl
# Missing AliyunCSManagedAutoScalerRole authorization.
ack_enable_nodepool_autoscaling = false

# Readonly commodity/entitlement not available yet.
rds_readonly_enabled = false

# RAM policy/user creation blocked in account.
objectfs_s3_enabled = false
```

For canonical production URL:

```hcl
moodle_www_root  = "https://lms.example.com"
moodle_ssl_proxy = "true"
```

Then apply and restart Moodle pods:

```bash
terraform -chdir=infra apply
kubectl -n moodle rollout restart deployment/moodle-deployment deployment/moodle-cron-deployment
```

## ObjectFS (OSS S3-Compatible)

ObjectFS is enabled in the baseline. `moodledata` still stays on NAS/NFS, while ObjectFS offloads file objects to OSS-compatible backend.

Default in `terraform.tfvars`:

```hcl
objectfs_s3_enabled                  = true
objectfs_s3_use_sdk_creds            = false
objectfs_s3_create_ram_credentials   = true
objectfs_s3_bucket_name              = null
objectfs_s3_region                   = null
objectfs_s3_base_url                 = null
objectfs_s3_key_prefix               = "objectfs/"
```

If RAM credential creation is not allowed in your account, fallback in the same `terraform.tfvars`:

```hcl
objectfs_s3_create_ram_credentials = false
```

Then inject AK/SK during apply/destroy:

```bash
export TF_VAR_objectfs_s3_access_key="<access-key>"
export TF_VAR_objectfs_s3_secret="<secret-key>"
```

Verify effective ObjectFS values:

```bash
terraform -chdir=infra output objectfs_s3_bucket_effective
terraform -chdir=infra output objectfs_s3_region_effective
terraform -chdir=infra output objectfs_s3_base_url_effective
```

## Common Issues

### Existing ACR EE works but cluster still cannot pull privately
- Ensure `cr_link_ack_vpc_endpoint=true`.
- Ensure runtime uses `cr_registry_endpoint_for_runtime`.
- Check outputs after apply:
  - `cr_existing_vpc_link_count`
  - `cr_existing_ack_vpc_link_count`
  - `cr_vpc_link_id`
  - `cr_registry_vpc_endpoint`
- If pods show `no such host` for `...registry-vpc...`, run `terraform -chdir=infra apply` again and confirm `cr_vpc_link_status = RUNNING`, then recreate `acr-regcred` and restart affected deployments.
- If Terraform returns `Vpc endpoint linked vpc already exists` while reusing an existing ACR instance, import the existing link into state:

```bash
terraform -chdir=infra import \
  alicloud_cr_vpc_endpoint_linked_vpc.ack_registry[0] \
  "<instance_id>:<vpc_id>:<vswitch_id>:Registry"
```

### `docker push` fails with `no such host` for `...registry-vpc...`
Use `cr_registry_endpoint_for_push` (public endpoint) from Terraform output.

### Pod `ImagePullBackOff` with `401` or `not found`
- Refresh `acr-regcred` secret from latest Terraform outputs.
- Ensure the new tag was pushed successfully.
- Restart deployments after secret/tag update.

### `kubectl` tries `localhost:8080` (`connection refused`)
Your shell is not using ACK kubeconfig (or it expired). Refresh it:

```bash
terraform -chdir=infra output -raw ack_kube_config > /tmp/ack-kubeconfig
export KUBECONFIG=/tmp/ack-kubeconfig
kubectl config current-context
kubectl -n moodle get pods
```

### `kubectl` returns `Unauthorized` after some time
`ack_kube_config` is temporary (default 60 minutes). Refresh it:

```bash
terraform -chdir=infra apply -target=data.alicloud_cs_cluster_credential.ack -auto-approve
terraform -chdir=infra output -raw ack_kube_config > /tmp/ack-kubeconfig
export KUBECONFIG=/tmp/ack-kubeconfig
```

### ACK nodepool fails with autoscaler RAM role error
Keep `ack_enable_nodepool_autoscaling=false` until required RAM role is authorized.

### RDS readonly creation fails with commodity/entitlement error
Temporarily set `rds_readonly_enabled = false` in the same `terraform.tfvars`, then re-enable after account capability is ready.


## Destroy

```bash
terraform -chdir=infra destroy
```

If ObjectFS static credentials are in use, export `TF_VAR_objectfs_s3_access_key` and `TF_VAR_objectfs_s3_secret` before destroy as well.
