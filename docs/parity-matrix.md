# Azure vs Alibaba2 Parity Matrix

| Azure Feature/Behavior | Alibaba2 Current Status | Gap | Next Action |
|---|---|---|---|
| Segmented network for app/db/storage | Implemented (VPC + 3 vSwitch) | None for baseline | Keep CIDR and zone overrides documented |
| Managed Kubernetes node pool separation (system/app/jobs/redis/pgbouncer) | Implemented in ACK | None for baseline | Tune per load profile |
| PgBouncer RW + RO services | Implemented (`pgbouncer-svc`, `pgbouncer-read-svc`) | Readonly DB path optional in bootstrap | Enable RDS readonly in production profile when needed |
| Redis session + Redis cache clusters | Implemented (`redis` and `redis-cache`) | None for baseline | Add monitoring and failover drills |
| Shared file storage for `moodledata` | Implemented (NAS NFS PV/PVC) | None for baseline | Validate backup/restore process |
| ObjectFS S3-compatible storage | Implemented behind toggle (`objectfs_s3_enabled`) | RAM permissions often missing on first run | Enable after baseline, verify secret + Moodle cfg values |
| Terraform-generated runtime secrets | Implemented (`moodle-config`, `pgbouncer-config`, `pgbouncer-config-read-replica`) | None for baseline | Add secret rotation runbook |
| One-command DB bootstrap from running pod | Implemented (Azure-style CLI command) | None for baseline | Optionally automate as post-deploy job |
| Dynamic URL bootstrap (IP/domain without cert) | Implemented (`moodle_www_root=""`) | None for baseline | Switch to fixed HTTPS URL in production |
| Fixed canonical URL for production | Implemented via `moodle_www_root` explicit value | Requires DNS/TLS readiness | Cut over after edge/TLS setup |
| HA-lite pod replica baseline | Implemented (`moodle=2`, `pgbouncer=2`, `pgbouncer-read=2`, `cron=1`) | PDB/anti-affinity are best-effort on small clusters | Increase nodes and tighten spread constraints for production |
| Pod disruption protection | Implemented (`21-pdb.yaml`) | None for baseline | Review minAvailable during scale events |
| Public push + VPC runtime pull for registry | Implemented with dedicated outputs (`...for_push`, `...for_runtime`) | Requires operator discipline | Keep quickstart command separation |
| "200k concurrent users" equivalence | Not claimed for bootstrap | No load proof yet | Run phased load campaign and capacity tuning before any claim |
