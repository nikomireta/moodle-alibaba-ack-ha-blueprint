#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-moodle}"

wait_for_statefulset() {
  local sts_name="$1"
  kubectl -n "$NAMESPACE" rollout status "statefulset/${sts_name}" --timeout=15m
}

collect_ips() {
  local label_selector="$1"
  kubectl -n "$NAMESPACE" get pods -l "$label_selector" -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sed '/^$/d'
}

create_cluster_if_needed() {
  local seed_pod="$1"
  local label_selector="$2"
  local cluster_name="$3"

  if kubectl -n "$NAMESPACE" exec "$seed_pod" -- redis-cli cluster info 2>/dev/null | grep -q 'cluster_state:ok'; then
    echo "${cluster_name} cluster already initialized, skipping."
    return
  fi

  mapfile -t ips < <(collect_ips "$label_selector")
  if [ "${#ips[@]}" -lt 3 ]; then
    echo "${cluster_name} needs at least 3 pods, found ${#ips[@]}."
    exit 1
  fi

  endpoints=()
  for ip in "${ips[@]}"; do
    endpoints+=("${ip}:6379")
  done

  kubectl -n "$NAMESPACE" exec "$seed_pod" -- redis-cli --cluster create --cluster-replicas 0 --cluster-yes "${endpoints[@]}"
}

wait_for_statefulset redis
wait_for_statefulset redis-cache

create_cluster_if_needed redis-0 'app=redis,appCluster=redis-cluster' 'redis'
create_cluster_if_needed redis-cache-0 'app=redis-cache,appCluster=redis-cache-cluster' 'redis-cache'

echo "Redis clusters initialized in namespace ${NAMESPACE}."
