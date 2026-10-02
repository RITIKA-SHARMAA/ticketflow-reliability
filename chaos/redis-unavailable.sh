#!/usr/bin/env bash
# Experiment: remove the Redis dependency.
#
# Hypothesis: TicketFlow uses Redis as a read-through cache, so losing it should degrade
# rather than fail. Expect every read to fall through to PostgreSQL, latency to rise, and
# the booking path to stay available. If availability drops instead, the cache is a hard
# dependency, which is a finding worth writing down.
#
# Second thing to check: whether the readiness probe reports the pod as not ready while
# Redis is gone. If it does, the readiness check is too strict and will remove healthy
# capacity during a cache outage, turning a degradation into an outage.
#
# Blast radius: the local ticketflow namespace only. Reversible by scaling Redis back up.
#
# Abort criteria: stop and restore if the app pods enter CrashLoopBackOff, since a crash
# loop means the experiment has moved past degradation into failure.
#
# Run this with load/booking.js driving traffic and the Grafana dashboards open.

set -euo pipefail

ns="${NAMESPACE:-ticketflow}"
workload="${REDIS_WORKLOAD:-deployment/redis}"
hold="${HOLD_SECONDS:-300}"

restore() {
  echo
  echo "[$(date -u +%H:%M:%SZ)] scaling ${workload} back to 1"
  kubectl scale "$workload" -n "$ns" --replicas=1
  kubectl rollout status "$workload" -n "$ns" --timeout=120s
  echo "[$(date -u +%H:%M:%SZ)] restored"
}
trap restore EXIT INT TERM

echo "[$(date -u +%H:%M:%SZ)] readiness before the experiment:"
kubectl get pods -n "$ns" -l app=ticketflow \
  -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready

echo "[$(date -u +%H:%M:%SZ)] scaling ${workload} to 0 for ${hold}s"
kubectl scale "$workload" -n "$ns" --replicas=0
kubectl wait --for=delete pod -n "$ns" -l app=redis --timeout=60s || true

echo "[$(date -u +%H:%M:%SZ)] Redis is gone, holding"
echo "Watch: readiness below, booking error ratio, booking latency ratio, Postgres load"

for _ in $(seq 1 "$((hold / 15))"); do
  sleep 15
  printf '[%s] ' "$(date -u +%H:%M:%SZ)"
  kubectl get pods -n "$ns" -l app=ticketflow \
    -o jsonpath='{range .items[*]}{.metadata.name}={.status.containerStatuses[0].ready} {end}'
  echo
done
