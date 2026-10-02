# Runbook

## Bring up
Inspect the sibling service first: Dockerfile, port, booking API, health groups, database migrations, cache config, and metrics. Then `make cluster-up`, create the local `ticketflow-db` Secret using the README command, run `make build-image`, `make load-image`, `make deploy`, and `make status`.

## Reach and inspect
Port-forward the Service after confirming its port: `kubectl -n ticketflow port-forward svc/ticketflow 8080:8080`. Use a valid request from the app's actual API contract. Logs: `make logs`. Events: `make status`.

## Roll back
`kubectl rollout undo deployment/ticketflow -n ticketflow`, then `kubectl rollout status deployment/ticketflow -n ticketflow`. Revert and re-apply manifests for configuration changes.

## Observability
Run `make observability`. Confirm Prometheus target health and live dashboard series before relying on alert rules. Configure local Grafana credentials securely before exposing the UI.
