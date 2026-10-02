#!/usr/bin/env bash
# Experiment: exhaust the database connection pool.
#
# Hypothesis: with the pool reduced to a size smaller than concurrent demand, booking
# requests queue for a connection, latency rises past the 800ms SLI threshold, and once the
# connection timeout is reached requests fail as 5xx rather than hanging indefinitely.
# Expectation: the latency burn-rate alert fires before the availability one.
#
# Blast radius: the local ticketflow namespace only. Reversible by restoring the original
# pool size and rolling the deployment.
#
# Abort criteria: stop and restore if the database pods restart, if Postgres itself becomes
# unreachable, or if the deployment fails to roll back within the timeout.
#
# Run this with load/booking.js driving traffic and the Grafana dashboards open.

set -euo pipefail

ns="${NAMESPACE:-ticketflow}"
cm="${CONFIGMAP:-ticketflow-config}"
small="${SMALL_POOL:-2}"
hold="${HOLD_SECONDS:-300}"

original="$(kubectl get configmap "$cm" -n "$ns" \
  -o jsonpath='{.data.SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE}')"
: "${original:?pool size not set on the ConfigMap, refusing to run}"

restore() {
  echo
  echo "[$(date -u +%H:%M:%SZ)] restoring pool size to ${original}"
  kubectl patch configmap "$cm" -n "$ns" --type merge \
    -p "{\"data\":{\"SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE\":\"${original}\"}}"
  kubectl rollout restart deployment/ticketflow -n "$ns"
  kubectl rollout status deployment/ticketflow -n "$ns" --timeout=180s
  echo "[$(date -u +%H:%M:%SZ)] restored"
}
trap restore EXIT INT TERM

echo "[$(date -u +%H:%M:%SZ)] original pool size: ${original}"
echo "[$(date -u +%H:%M:%SZ)] reducing pool to ${small} for ${hold}s"

kubectl patch configmap "$cm" -n "$ns" --type merge \
  -p "{\"data\":{\"SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE\":\"${small}\"}}"
kubectl rollout restart deployment/ticketflow -n "$ns"
kubectl rollout status deployment/ticketflow -n "$ns" --timeout=180s

echo "[$(date -u +%H:%M:%SZ)] saturated pool is live, holding"
echo "Watch: hikaricp_connections_pending, hikaricp_connections_acquire_seconds,"
echo "       ticketflow:booking_slow_events:ratio5m, ticketflow:booking_bad_events:ratio5m"

sleep "$hold"
