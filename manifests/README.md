# Alibaba2 Runtime Manifests

These manifests deploy the runtime layer on ACK with no wrapper apply script.

## Components
- NAS-backed `PersistentVolume` and `PersistentVolumeClaim` for `moodledata`
- Redis clusters for sessions and caches
- PgBouncer RW and RO deployments/services
- PodDisruptionBudgets for Moodle and PgBouncer workloads
- Moodle web deployment and LoadBalancer service
- Moodle cron deployment
- Single runtime tuning source: `runtime.env`

## Prerequisites

```bash
export NAMESPACE=moodle
export NAS_MOUNT_TARGET_DOMAIN="$(terraform -chdir=alibaba2/infra output -raw nas_mount_target_domain)"
export REGISTRY_RUNTIME_ENDPOINT="$(terraform -chdir=alibaba2/infra output -raw cr_registry_endpoint_for_runtime)"
export IMAGE_TAG=v0.1
export MOODLE_IMAGE=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/moodle:${IMAGE_TAG}
export PGBOUNCER_IMAGE=${REGISTRY_RUNTIME_ENDPOINT}/moodle-high-scale/pgbouncer:${IMAGE_TAG}

set -a
source alibaba2/manifests/runtime.env
set +a
```

## Apply Order

```bash
envsubst '${NAMESPACE} ${NAS_MOUNT_TARGET_DOMAIN}' < alibaba2/manifests/00-moodle-data-nfs.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${REDIS_SESSION_REPLICAS} ${REDIS_CACHE_REPLICAS} ${REDIS_CPU_REQUEST} ${REDIS_MEM_REQUEST} ${REDIS_CPU_LIMIT} ${REDIS_MEM_LIMIT} ${REDIS_STORAGE_REQUEST}' < alibaba2/manifests/10-redis-cluster.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${PGBOUNCER_IMAGE} ${PGBOUNCER_RW_REPLICAS} ${PGBOUNCER_RO_REPLICAS} ${PGBOUNCER_CPU_REQUEST} ${PGBOUNCER_MEM_REQUEST} ${PGBOUNCER_CPU_LIMIT} ${PGBOUNCER_MEM_LIMIT}' < alibaba2/manifests/20-pgbouncer.yaml | kubectl apply -f -
envsubst '${NAMESPACE}' < alibaba2/manifests/21-pdb.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${MOODLE_IMAGE} ${MOODLE_WEB_REPLICAS} ${MOODLE_WEB_CPU_REQUEST} ${MOODLE_WEB_MEM_REQUEST} ${MOODLE_WEB_CPU_LIMIT} ${MOODLE_WEB_MEM_LIMIT}' < alibaba2/manifests/30-moodle.yaml | kubectl apply -f -
envsubst '${NAMESPACE} ${MOODLE_IMAGE} ${MOODLE_CRON_REPLICAS} ${MOODLE_CRON_CPU_REQUEST} ${MOODLE_CRON_MEM_REQUEST} ${MOODLE_CRON_CPU_LIMIT} ${MOODLE_CRON_MEM_LIMIT}' < alibaba2/manifests/40-moodle-cron.yaml | kubectl apply -f -
```

## Redis Initialization

```bash
./alibaba2/manifests/11-redis-init.sh moodle
```

## Moodle DB Install (Azure-style)

```bash
kubectl -n moodle exec deployment/moodle-deployment -- \
  php /var/www/html/admin/cli/install_database.php --adminuser=admin_user --adminpass=admin_pass --agree-license
```

## Quick Verification

```bash
kubectl -n moodle get pods
kubectl -n moodle get svc moodle-svc
```

## Cache Verification (Azure-Parity)

```bash
kubectl -n moodle exec deployment/moodle-deployment -- grep -n "redis-cache" /var/www/moodledata/muc/config.php
kubectl -n moodle exec deployment/moodle-deployment -- sh -c "grep -n \"modemappings\" -A20 /var/www/moodledata/muc/config.php"
kubectl -n moodle exec deployment/moodle-deployment -- php /var/www/html/admin/cli/purge_caches.php
```

## Backend Parity Checklist (Before Load Test)

Run these checks before starting any capacity test:

```bash
# 1) All runtime workloads ready.
kubectl -n moodle get pods -o wide

# 2) Moodle uses rediscluster session handler.
kubectl -n moodle exec deployment/moodle-deployment -- sh -c "grep -n \"session_handler_class\" /var/www/html/config.php"

# 3) MUC mapping uses redis-cache for application/session cache modes.
kubectl -n moodle exec deployment/moodle-deployment -- sh -c "grep -n \"modemappings\" -A20 /var/www/moodledata/muc/config.php"

# 4) PgBouncer services resolvable and endpoints available.
kubectl -n moodle get svc pgbouncer-svc pgbouncer-read-svc
kubectl -n moodle get endpoints pgbouncer-svc pgbouncer-read-svc

# 5) NAS is writable through moodledata mount.
kubectl -n moodle exec deployment/moodle-deployment -- sh -c "touch /var/www/moodledata/.nas-write-check && ls -l /var/www/moodledata/.nas-write-check"

# 6) ObjectFS runtime values (when objectfs_s3_enabled=true).
kubectl -n moodle get secret moodle-config -o jsonpath='{.data.OBJECTFS_S3_BUCKET}' | base64 -d; echo
kubectl -n moodle get secret moodle-config -o jsonpath='{.data.OBJECTFS_S3_BASE_URL}' | base64 -d; echo
kubectl -n moodle exec deployment/moodle-deployment -- php /var/www/html/admin/cli/cfg.php --component=tool_objectfs --name=s3_bucket
```

Pre-load gate is passed only when all checks above succeed without manual workaround.
