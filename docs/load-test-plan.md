# Alibaba2 Load Test Plan

## Goal
Produce repeatable evidence for backend capacity and stability before any high-concurrency claim.

## Scope
In scope:
- ACK node pools (app, pgbouncer, redis, system, jobs)
- Moodle web and cron workloads
- Redis session + Redis MUC cache
- PgBouncer RW/RO
- RDS PostgreSQL primary + optional readonly
- NAS + optional ObjectFS

Out of scope for this phase:
- CDN/WAF/edge cache optimization
- Final DNS/TLS global routing behavior

## Preconditions
1. Baseline deployment is healthy (`kubectl -n moodle get pods` all ready).
2. Backend parity checklist in `alibaba2/manifests/README.md` is fully green.
3. `production-load` tfvars settings applied (autoscaling and readonly as needed).
4. Test dataset seeded and stable for repeated runs.

## Test Scenarios
1. Warm-up
- Duration: 15-30 minutes
- Purpose: JIT/cache warmup, ensure stable baseline metrics.

2. Steady-state medium
- Duration: 60 minutes
- Traffic: representative authenticated and anonymous mix.
- Purpose: validate sustained behavior and resource saturation trends.

3. Spike and soak
- Spike: rapid ramp to target concurrency.
- Soak: hold near target for 2-4 hours.
- Purpose: reveal queueing, memory leaks, and reconnect storms.

## Metrics to Collect (Minimum)
1. User-facing
- Request count and success rate
- HTTP 4xx/5xx rates
- p50/p95/p99 latency

2. Kubernetes/compute
- Node CPU/memory usage and throttling
- Pod restarts, OOM, pending scheduling
- HPA/node autoscaling events

3. Database and connection tier
- RDS connection count, CPU, storage IO latency
- PgBouncer pool usage, wait time, rejected clients

4. Cache and storage
- Redis latency and error counters
- NAS/ObjectFS read-write errors and latency symptoms

## Success Criteria (Initial)
- Availability during window: >=99.9%
- 5xx error rate: <=0.5%
- p95 response latency: <=1.5s
- p99 response latency: <=3.0s
- No persistent PgBouncer saturation and no sustained Redis errors

## Failure Criteria
- SLO target breach for >=10 minutes
- Recurring CrashLoopBackOff/OOMKilled
- RDS or Redis saturation without recovery

## Tuning Loop
After each scenario:
1. Record bottleneck and probable root cause.
2. Change one variable group at a time:
- php-fpm workers and process mode
- PgBouncer pool parameters
- node pool min/max bounds and instance class
- RDS class/storage and readonly split
3. Repeat scenario and compare deltas.

## Evidence Artifacts
For every run, publish:
- tfvars profile snapshot
- image tags and manifest revision
- raw metrics export/screenshots
- timeline of incidents and actions
- final summary in `capacity-report-template.md`
