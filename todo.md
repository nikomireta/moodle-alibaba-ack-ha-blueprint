# Alibaba2 TODO (Next Steps)

## 1) Stabilization (now)
- [ ] Verify cron warning is gone in Moodle admin (`Site administration > Notifications`).
- [ ] Change temporary admin password and store it in a secure vault.
- [ ] Re-check runtime health:
  - `kubectl -n moodle get pods`
  - `kubectl -n moodle get svc moodle-svc`
  - `kubectl -n moodle exec deployment/moodle-deployment -- php /var/www/html/admin/cli/cfg.php --component=tool_task --name=lastcronstart`

## 2) Canonical Access
- [ ] Decide final access mode:
  - Bootstrap mode: keep dynamic URL (`moodle_www_root = ""`, `moodle_ssl_proxy = "false"`), or
  - Production mode: set fixed HTTPS domain and enable SSL proxy.
- [ ] If production mode: point DNS to current LB IP and validate CSS/JS paths from domain.

## 3) Data and Backup Safety
- [ ] Verify NAS persistence with upload/download test from Moodle UI.
- [ ] Verify ObjectFS writes for large files (if enabled).
- [ ] Define backup routine for:
  - RDS (snapshot + retention)
  - NAS content
  - Moodle app config/secrets

## 4) Production-Load Preparation
- [ ] Confirm `production-load` tfvars profile:
  - autoscaling enabled
  - readonly RDS enabled
  - nodepool min/max set
- [ ] Add observability minimum set (latency, error rate, CPU/memory, DB connections, Redis latency).
- [ ] Freeze image tag and manifest revision for load campaign.

## 5) Load Test Execution
- [ ] Run warm-up, steady-state, then spike/soak (see `docs/load-test-plan.md`).
- [ ] Fill `docs/capacity-report-template.md` with evidence (not claim-only).
- [ ] Only claim high concurrency after repeatable SLO pass.

## 6) GitHub Publish Readiness
- [ ] Final pass on `README.md` quickstart (copy-paste verified from clean environment).
- [ ] Remove sensitive values from examples/state artifacts before publish.
- [ ] Commit with release note of tested baseline and known limits.
