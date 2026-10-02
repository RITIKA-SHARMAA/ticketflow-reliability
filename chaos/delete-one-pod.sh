#!/usr/bin/env bash
set -euo pipefail
ns="${NAMESPACE:-ticketflow}"
pod="$(kubectl get pods -n "$ns" -l app=ticketflow -o jsonpath='{.items[0].metadata.name}')"
test -n "$pod"
echo "Deleting one local app pod: $pod"
kubectl delete pod "$pod" -n "$ns"
kubectl rollout status deployment/ticketflow -n "$ns" --timeout=180s
