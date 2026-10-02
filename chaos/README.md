# Chaos experiments

Local, reversible failure experiments against the development namespace. Each one is a
hypothesis with a stated blast radius and an abort condition, not a random act of breakage.
An experiment whose outcome you already know with certainty is not worth running; an
experiment with no abort condition is not safe to run.

**Never run these against a production or shared cluster.**

## How to run one

1. Bring the stack up and confirm Prometheus is scraping: `make deploy observability`
2. Start traffic in another terminal: `make load-test`
3. Open the Grafana dashboards and the Alertmanager UI
4. Run the experiment: `make chaos-pod`, `make chaos-pool` or `make chaos-redis`
5. Record what actually happened, with timestamps, while it is happening

Every script restores the system on exit, including on Ctrl-C, via a trap.

## The experiments

### `delete-one-pod.sh` — lose one replica

**Hypothesis.** The Deployment recreates the pod, the PodDisruptionBudget and remaining ready
replicas keep serving, and no request fails.

**Watch.** Request rate continuity, error ratio, time from deletion to the replacement passing
its readiness probe.

**Interesting if.** Any 5xx appears. That would mean the Service is routing to a pod before it
is genuinely ready, which points at a readiness probe that returns 200 too early.

**Blast radius.** One application pod. **Abort if** the rollout does not complete in 180s.

### `saturate-db-pool.sh` — exhaust the connection pool

**Hypothesis.** With the pool smaller than concurrent demand, requests queue for a connection,
latency crosses the 800ms SLI threshold, and once the connection timeout expires requests fail
as 5xx rather than hanging.

**Watch.** `hikaricp_connections_pending`, `hikaricp_connections_acquire_seconds`, then the
latency and availability burn ratios. The latency alert should fire before the availability one.

**Interesting if.** Availability degrades before latency does. That would mean requests fail
immediately rather than queueing, which is a different and arguably better behaviour, but not
the one the configuration implies.

**Blast radius.** The local namespace, via a ConfigMap override and a rollout.
**Abort if** Postgres becomes unreachable or the database pods restart.

### `redis-unavailable.sh` — remove the cache

**Hypothesis.** Redis is a read-through cache, so losing it should degrade and not fail. Reads
fall through to PostgreSQL, latency rises, the booking path stays available.

**Watch.** Pod readiness, booking availability ratio, booking latency ratio, Postgres load.

**Interesting if.** Either availability drops, meaning the cache is a hard dependency rather
than an optimisation, or readiness goes false, meaning the readiness probe treats a degraded
dependency as unfit to serve and will withdraw healthy capacity during a cache outage. Both
are findings worth a postmortem.

**Blast radius.** The local Redis workload. **Abort if** app pods enter CrashLoopBackOff.

## Recording the outcome

Write up at least one of these in `docs/postmortems/` using `TEMPLATE.md`. Include real
timestamps, which alert fired and when, what the dashboards showed, how you narrowed the cause,
and what recovered it. Impact is stated against the error budget in `docs/SLO.md`.

Do not write a postmortem for an experiment you did not run.
