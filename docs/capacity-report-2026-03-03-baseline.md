# Alibaba2 Capacity Report - Baseline Run (2026-03-03)

## Scope
- Goal: Execute production-load phase attempt on existing Alibaba2 deployment without reinstall.
- Region: `ap-southeast-1`
- Cluster: `c28e9616366ec48b4a4473cb1491d0d03`
- Service endpoint tested: `http://47.237.252.219`

## Applied Configuration
`alibaba2/infra/terraform.tfvars` (effective for this run):
- `moodle_www_root = ""`
- `moodle_ssl_proxy = "false"`
- `ack_enable_nodepool_autoscaling = false` (fallback)
- `rds_readonly_enabled = false` (fallback)
- `ack_node_pool_size_overrides`:
  - `app.desired_size = 4`, `min_size = 2`, `max_size = 20`
  - `pgbouncer.desired_size = 3`, `min_size = 2`, `max_size = 20`
  - `redis.desired_size = 3`, `min_size = 3`, `max_size = 12`

## Execution Summary
1. Attempted `production-load` settings with:
   - `ack_enable_nodepool_autoscaling = true`
   - `rds_readonly_enabled = true`
2. Terraform apply failed with account/product blockers:
   - ACK node pools: `InvalidRamRole.NotFound` for `AliyunCSManagedAutoScalerRole`.
   - RDS readonly: `Commodity.InvalidComponent`.
3. Fallback applied successfully:
   - Disable autoscaling and readonly.
   - Keep manual nodepool scale-up for app and pgbouncer.
4. Runtime rollout completed successfully after refreshing `acr-regcred` using fresh `GetAuthorizationToken` credentials (new nodes initially hit 401 pull errors on VPC registry auth endpoint).

## Health Verification
- Deployments:
  - `moodle-deployment`: `2/2 Available`
  - `moodle-cron-deployment`: `1/1 Available`
  - `pgbouncer-deployment`: `2/2 Available`
  - `pgbouncer-read-deployment`: `2/2 Available`
- Pods: all runtime pods `Running`.
- HTTP checks:
  - `GET /` -> `200 OK`
  - Theme asset endpoint test -> `200 OK`

## Parity Verification
- Session handler: `\cachestore_rediscluster\session`
- MUC mode mappings:
  - mode `1` -> `redis-cache`
  - mode `2` -> `redis-cache`
  - mode `4` -> `default_request`
- ObjectFS backend: `\tool_objectfs\s3_file_system`

## Baseline Load Test (ApacheBench)
Command:
```bash
ab -n 1000 -c 20 -l http://47.237.252.219/
```

Results:
- Complete requests: `1000`
- Failed requests: `0`
- Test duration: `11.689s`
- Throughput: `85.55 req/s`
- Mean response time: `233.770 ms`
- Percentiles:
  - p50: `205 ms`
  - p95: `240 ms`
  - p99: `446 ms`
  - max: `1177 ms`

## Saturation Snapshot (kubectl top)
- Nodes CPU usage observed low (`~0-2%` shown by metrics API), memory mostly below `25%`.
- Moodle pods during snapshot:
  - `moodle-deployment` around `1m CPU`, `38-100Mi RAM` per pod.
- PgBouncer/Redis pods healthy and low utilization in this short run.

## Blockers / Gaps Remaining
1. **Autoscaling not enabled**
   - Blocker: missing RAM role authorization for `AliyunCSManagedAutoScalerRole`.
2. **RDS readonly not enabled**
   - Blocker: `Commodity.InvalidComponent` for readonly creation on current RDS product setup.
3. **Registry pull robustness on new nodes**
   - Requires valid registry credentials (`acr-regcred`) refresh; stale/invalid creds caused 401 on first attempt.
4. **Evidence depth**
   - This is a baseline synthetic HTTP test only, not a full Moodle user-journey load campaign.

## Next Actions
1. Authorize `AliyunCSManagedAutoScalerRole`, then re-enable `ack_enable_nodepool_autoscaling = true`.
2. Validate RDS SKU/edition/entitlement for readonly, then re-test `rds_readonly_enabled = true`.
3. Add repeatable load scenario (login/dashboard/course path) and collect p95/p99 + error rate + DB/Redis/PgBouncer internals over sustained windows.
4. Integrate observability stack and SLO dashboard before any high-concurrency claim.
