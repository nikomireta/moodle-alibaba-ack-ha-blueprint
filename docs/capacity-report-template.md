# Alibaba2 Capacity Report Template

## Run Metadata
- Date:
- Region:
- Cluster ID:
- Commit SHA:
- Image tags (moodle/pgbouncer):
- Test owner:

## Environment Profile
- Terraform profile: bootstrap / production / production-load
- Key tfvars overrides:
- ACK autoscaling: on/off
- RDS readonly: on/off
- ObjectFS: on/off

## Workload Model
- Traffic tool:
- User journey mix:
- Authenticated vs anonymous split:
- Target concurrency/RPS:
- Ramp pattern:
- Test duration:

## SLO Targets
- Availability target:
- Error-rate target:
- p95 target:
- p99 target:

## Results Summary
- Availability observed:
- 5xx observed:
- p95 observed:
- p99 observed:
- Peak stable concurrency:
- Pass/Fail:

## Resource Saturation Snapshot
- ACK app nodes:
- ACK pgbouncer nodes:
- ACK redis nodes:
- Pod-level restarts/OOM:
- HPA/scale events:
- RDS CPU/connection/IO:
- PgBouncer pool pressure:
- Redis latency/errors:

## Incidents During Run
| Time | Symptom | Suspected Cause | Action | Outcome |
|---|---|---|---|---|
| | | | | |

## Bottlenecks and Evidence
1. Bottleneck:
- Evidence:
- Impact:

2. Bottleneck:
- Evidence:
- Impact:

## Tuning Applied
1. Change:
- Why:
- Before/After:

2. Change:
- Why:
- Before/After:

## Regression Check
- Login flow stable: yes/no
- Dashboard load stable: yes/no
- File upload/read stable: yes/no
- Session continuity across rollout: yes/no

## Final Decision
- Ready for next scale step: yes/no
- Required changes before rerun:
- Recommendation for next target concurrency:
