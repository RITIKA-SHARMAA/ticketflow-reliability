# TicketFlow Reliability

Local Kubernetes operations scaffold for the TicketFlow service: deployment, metrics, SLO alerting, load testing, and reversible failure experiments.

**Status:** starter scaffold. The upstream application could not be inspected and no cluster, request, alert, or load test has been run here. Replace assumptions with the application's actual configuration and record only observed measurements.

## Prerequisites
Docker, kind, kubectl, Helm, k6, Java 17, Maven, and a sibling checkout of [ticketflow-engine](https://github.com/RITIKA-SHARMAA/ticketflow-engine).

## Start
```bash
git clone https://github.com/RITIKA-SHARMAA/ticketflow-engine.git ../ticketflow-engine
# Inspect its Dockerfile, port, routes, Actuator health/metrics, Flyway migrations,
# DB/cache configuration, and booking/idempotency contract before deploying.
make cluster-up
make build-image
make load-image
kubectl create namespace ticketflow --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ticketflow create secret generic ticketflow-db \
  --from-literal=SPRING_DATASOURCE_USERNAME=ticketflow \
  --from-literal=SPRING_DATASOURCE_PASSWORD=local-only-change-me \
  --dry-run=client -o yaml | kubectl apply -f -
make deploy
make status
```

Update `k8s/base` and `load/booking.js` to match the inspected application. Confirm the configured Service port before using `kubectl -n ticketflow port-forward svc/ticketflow 8080:8080`.

## Components
- `k8s/`: kind-oriented Kubernetes manifests and local overlay
- `observability/`: pinned Helm chart values, starter dashboard and alert rules
- `load/`: k6 scenario (API contract placeholders must be replaced)
- `chaos/`: reversible local-only experiment
- `docs/`: runbook, SLO proposal, capacity worksheet, postmortem template

PostgreSQL and Redis are development-grade in-cluster dependencies, not production topology. This is a single local cluster. Do not claim production use, uptime, user impact, or capacity until independently observed. No secrets or fabricated measurements belong in the repository.


## SLO and alerting update

`docs/SLO.md` now defines a 99% booking availability objective and 95% under-800ms latency objective. `observability/alerts/ticketflow-rules.yaml` uses paired long/short windows for availability (14.4x, 6x, 3x, 1x) and latency (14.4x, 6x), plus measurement meta-alerts. These are authored rules, not runtime-validated alerts. Confirm the Spring histogram boundary and actual metric labels before relying on them.
