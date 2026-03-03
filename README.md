# Moodle 4.5 on Alibaba Cloud (Terraform + ACK)

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
- Fast bootstrap with small HA baseline.
- Clear path to production hardening and load testing.

This repository does not include by default:
- Automated DNS + TLS + WAF/CDN edge stack.
- Automatic 200k concurrency guarantee.

## Repository Layout

```text
alibaba2/
  infra/       # Terraform infrastructure (network, ACK, DB, storage, registry, runtime secrets)
  images/      # Docker images (moodle, pgbouncer)
  manifests/   # Kubernetes manifests (PVC, redis, pgbouncer, moodle, cron)
  docs/        # Load-test plan, parity/capacity docs
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
cp alibaba2/infra/terraform.tfvars.example alibaba2/infra/terraform.tfvars
```

Edit `alibaba2/infra/terraform.tfvars` at minimum:

```hcl
project_name       = "moodle-high-scale"
region             = "ap-southeast-1"
moodle_environment = "development"

# Bootstrap mode (recommended first run)
moodle_www_root  = ""
moodle_ssl_proxy = "false"

# Registry must be enabled to build/push/pull images
cr_enabled = true

# Optional: reuse existing ACR EE instance
# cr_existing_instance_id = "cri-xxxxxxxx"
```

### 3) Create infrastructure

```bash
terraform -chdir=alibaba2/infra init
terraform -chdir=alibaba2/infra plan
terraform -chdir=alibaba2/infra apply
```

If first apply fails because Kubernetes provider is not ready yet, wait a few minutes and run apply again.

### 4) Export kubeconfig

```bash
terraform -chdir=alibaba2/infra output -raw ack_kube_config > /tmp/ack-kubeconfig
export KUBECONFIG=/tmp/ack-kubeconfig
```

### 5) Build and push images

Use public endpoint for push and runtime endpoint for cluster pulls.

```bash
export REGISTRY_PUSH_ENDPOINT="$(terraform -chdir=alibaba2/infra output -raw cr_registry_endpoint_for_push)"
export REGISTRY_RUNTIME_ENDPOINT="$(terraform -chdir=alibaba2/infra output -raw cr_registry_endpoint_for_runtime)"
export CR_USER="$(terraform -chdir=alibaba2/infra output -raw cr_registry_username)"
export CR_PASS="$(terraform -chdir=alibaba2/infra output -raw cr_registry_password)"
export IMAGE_TAG="v$(date +%Y%m%d-%H%M%S)"

nslookup "${REGISTRY_PUSH_ENDPOINT}"
echo "${CR_PASS}" | docker login "${REGISTRY_PUSH_ENDPOINT}" --username "${CR_USER}" --password-stdin

docker build -t ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG} alibaba2/images/moodle
docker build -t ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG} alibaba2/images/pgbouncer
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
export NAS_MOUNT_TARGET_DOMAIN="$(terraform -chdir=alibaba2/infra output -raw nas_mount_target_domain)"
export MOODLE_IMAGE=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG}
export PGBOUNCER_IMAGE=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG}

envsubst '${NAMESPACE} ${NAS_MOUNT_TARGET_DOMAIN}' < alibaba2/manifests/00-moodle-data-nfs.yaml | kubectl apply -f -
envsubst '${NAMESPACE}' < alibaba2/manifests/10-redis-cluster.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${PGBOUNCER_IMAGE}' < alibaba2/manifests/20-pgbouncer.yaml | kubectl apply -f -
envsubst '${NAMESPACE}' < alibaba2/manifests/21-pdb.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${MOODLE_IMAGE}' < alibaba2/manifests/30-moodle.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${MOODLE_IMAGE}' < alibaba2/manifests/40-moodle-cron.yaml | kubectl apply -f -
```

### 8) Initialize Redis clusters

```bash
./alibaba2/manifests/11-redis-init.sh moodle
```

### 9) Install Moodle database

```bash
kubectl -n moodle exec -it deployment/moodle-deployment -- /bin/bash
php /var/www/html/admin/cli/install_database.php --adminuser=admin --adminpass='AdminTemp!2026' --agree-license
exit
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

docker build -t ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG} alibaba2/images/moodle
docker build -t ${REGISTRY_PUSH_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG} alibaba2/images/pgbouncer
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

## Profiles

### Bootstrap (recommended first)

```hcl
moodle_www_root  = ""
moodle_ssl_proxy = "false"
```

Use this for first deployment on IP/domain without TLS.

### Production URL mode

```hcl
moodle_www_root  = "https://lms.example.com"
moodle_ssl_proxy = "true"
```

Then apply and restart Moodle pods:

```bash
terraform -chdir=alibaba2/infra apply
kubectl -n moodle rollout restart deployment/moodle-deployment deployment/moodle-cron-deployment
```

### Production-load profile

Use only after baseline is stable:

```hcl
ack_enable_nodepool_autoscaling = true
rds_category                    = "HighAvailability"
rds_readonly_enabled            = true
```

Note: `rds_readonly_enabled=true` is not supported when `rds_category="Basic"`.

## ObjectFS (OSS S3-Compatible)

Enable in `terraform.tfvars`:

```hcl
objectfs_s3_enabled                  = true
objectfs_s3_use_sdk_creds            = false
objectfs_s3_create_ram_credentials   = false
objectfs_s3_bucket_name              = null
objectfs_s3_region                   = null
objectfs_s3_base_url                 = null
objectfs_s3_key_prefix               = "objectfs/"
```

If runtime cannot use instance metadata credentials, inject AK/SK during apply/destroy:

```bash
export TF_VAR_objectfs_s3_access_key="<access-key>"
export TF_VAR_objectfs_s3_secret="<secret-key>"
```

Verify effective ObjectFS values:

```bash
terraform -chdir=alibaba2/infra output objectfs_s3_bucket_effective
terraform -chdir=alibaba2/infra output objectfs_s3_region_effective
terraform -chdir=alibaba2/infra output objectfs_s3_base_url_effective
```

## Common Issues

### `docker push` fails with `no such host` for `...registry-vpc...`
Use `cr_registry_endpoint_for_push` (public endpoint) from Terraform output.

### Pod `ImagePullBackOff` with `401` or `not found`
- Refresh `acr-regcred` secret from latest Terraform outputs.
- Ensure the new tag was pushed successfully.
- Restart deployments after secret/tag update.

### ACK nodepool fails with autoscaler RAM role error
Keep `ack_enable_nodepool_autoscaling=false` until required RAM role is authorized.

### RDS readonly creation fails on Basic tier
Switch to `rds_category = "HighAvailability"` before enabling readonly.

## Load Testing and Capacity Docs

- `alibaba2/docs/load-test-plan.md`
- `alibaba2/docs/capacity-report-template.md`
- `alibaba2/todo.md`

## Destroy

```bash
terraform -chdir=alibaba2/infra destroy
```

If ObjectFS static credentials are in use, export `TF_VAR_objectfs_s3_access_key` and `TF_VAR_objectfs_s3_secret` before destroy as well.
