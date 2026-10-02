# Service level objectives

Scope: the booking path of TicketFlow running in the local kind cluster. These are the
objectives this repository measures and alerts on. They are deliberately modest, because an
objective nobody can meet teaches nothing and an objective that is never at risk teaches less.

Targets below are committed, not placeholders. They were chosen before baseline measurement
and should be revisited once `docs/CAPACITY.md` holds a real run; any change to a target is a
commit with a reason in its message.

---

## Prerequisite: the histogram must have the right boundaries

The latency SLI counts requests below an exact bucket edge, so the 800ms boundary has to exist
in the histogram. Spring Boot does not create it by default. In `ticketflow-engine`:

```properties
management.endpoints.web.exposure.include=health,info,prometheus
management.metrics.distribution.percentiles-histogram.http.server.requests=true
management.metrics.distribution.slo.http.server.requests=200ms,500ms,800ms,1s,2s
```

Without the `800ms` boundary the series `http_server_requests_seconds_bucket{le="0.8"}` does
not exist, the latency SLI is empty, and the latency alerts can never fire. The
`TicketFlowLatencyBucketMissing` alert exists to catch exactly that failure, because an SLI
that silently reports nothing looks identical to an SLI that is being met.

---

## SLI 1: Booking availability

**Definition.** The proportion of booking requests that do not return a 5xx response.
Actuator endpoints are excluded; they are not user traffic. Client errors are excluded, because
a rejected invalid booking is the service working correctly.

**Objective.** 99.0% over a rolling 30-day window.

**Error budget.** 1.0% of eligible booking requests. At 10 requests per second sustained that
is roughly 259,000 failures permitted per 30 days; at 1 request per second, roughly 25,900. The
budget is a rate, not a count, which is why the alerts measure ratio rather than absolute
failures.

**Why 99.0% and not higher.** This runs on a single-node development cluster with in-cluster
Postgres and Redis and no redundancy below the application tier. Committing to 99.9% would make
every ordinary pod restart an SLO violation, which would train everyone to ignore the alerts.
99.0% leaves enough budget that a breach means something real happened.

**Bad-event ratio:**

```promql
sum(rate(http_server_requests_seconds_count{uri=~".*/bookings.*",uri!~"/actuator.*",status=~"5.."}[WINDOW]))
/
clamp_min(sum(rate(http_server_requests_seconds_count{uri=~".*/bookings.*",uri!~"/actuator.*"}[WINDOW])), 1e-9)
```

`clamp_min` keeps the expression defined when the service is idle. Without it an empty
denominator produces no series, and an alert that evaluates to nothing is an alert that never
fires.

---

## SLI 2: Booking latency

**Definition.** The proportion of booking requests served in under 800ms, measured from
histogram buckets rather than a client-side average.

**Objective.** 95% under 800ms over a rolling 30-day window.

**Error budget.** 5% of booking requests may exceed 800ms.

**Why 800ms and 95%.** A booking write takes a pessimistic row lock, writes an idempotency
record and an outbox row in one transaction, and reads through Redis. Sub-second is a
reasonable promise for that work on local hardware; a tighter target would measure the laptop
rather than the service. The 95th percentile rather than the 99th because the sample volume in
a local environment is too small for a stable p99.

**Bad-event ratio:**

```promql
1 - (
  sum(rate(http_server_requests_seconds_bucket{uri=~".*/bookings.*",le="0.8"}[WINDOW]))
  /
  clamp_min(sum(rate(http_server_requests_seconds_count{uri=~".*/bookings.*"}[WINDOW])), 1e-9)
)
```

---

## Burn-rate alerting

A burn rate of 1 means the budget is being consumed exactly as fast as it is granted and will
run out precisely at the end of the window. Higher multiples exhaust it sooner.

Every alert requires **two windows to breach at once**: a long window for signal and a short
window to confirm the burn is still happening. The long window stops a brief spike from paging;
the short window stops an incident that has already recovered from paging for hours afterwards.

Threshold is `burn_rate × (1 − SLO)`.

### Availability, budget 0.01

| Burn | Threshold | Long window | Short window | Severity | Budget consumed |
|---|---|---|---|---|---|
| 14.4x | 0.144 | 1h | 5m | page | 2% per hour |
| 6x | 0.06 | 6h | 30m | page | 5% per 6 hours |
| 3x | 0.03 | 1d | 2h | ticket | 10% per day |
| 1x | 0.01 | 3d | 6h | ticket | the whole budget, no margin |

### Latency, budget 0.05

| Burn | Threshold | Long window | Short window | Severity |
|---|---|---|---|---|
| 14.4x | 0.72 | 1h | 5m | page |
| 6x | 0.30 | 6h | 30m | page |

The latency thresholds look large because the budget is large. A 0.72 threshold means nearly
three quarters of booking requests are slower than 800ms, which at a 95% objective genuinely is
a fourteen-fold burn.

Rules live in `observability/alerts/ticketflow-rules.yaml`.

---

## Meta-alerts

Two alerts watch the measurement rather than the service:

- `TicketFlowSLIMetricsMissing` fires when no booking request series exist for 10 minutes. The
  application may be down, the ServiceMonitor may not be matching, or the `uri` label may have
  changed shape after a routing change.
- `TicketFlowLatencyBucketMissing` fires when the `le="0.8"` bucket is absent, which means the
  histogram configuration above has been lost.

Both exist because a broken SLI reports success. Silence from a monitoring system should never
be mistaken for health.

---

## Verification status

An alert rule that has never fired has not been tested. Before trusting any of the above:

- [ ] Confirm booking request series are present in Prometheus with the expected `uri` label
- [ ] Confirm the `le="0.8"` bucket exists
- [ ] Confirm the recording rules evaluate and produce series at every window
- [ ] Drive 5xx responses until `TicketFlowAvailabilityFastBurn` moves to firing, and record
      how long it took from first error to page
- [ ] Stop the errors and confirm it resolves
- [ ] Add latency until `TicketFlowLatencyFastBurn` fires, and confirm it resolves
- [ ] Record all of the above in `docs/CAPACITY.md` or the first postmortem

Tick these off in commits as they are done. Until every box is ticked, treat the alerting as
written but unproven, and say so.
