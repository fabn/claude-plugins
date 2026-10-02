# Method

Formulas are stated against the configured windows, not against literal `1d` /
`7d` / `30d`. `avg_usage` means the maximum of the per-window averages over
whatever `windows.averages` holds; `peak window` means `windows.peak`.

All memory quantities are **working set**, never `memory.usage` — see "When the
sample is not the ceiling", condition 4.

## The percentile proxy

Distribution metrics are not needed. A `max` aggregation across pods, rolled up
with an explicit `max` function into roughly 20 buckets over the peak window,
gives enough shape:

```
avg_usage    = max of the per-window average values
typical_peak = mean of the per-bucket maxima
true_peak    = highest per-bucket maximum
spike_ratio  = true_peak / avg_usage
```

`true_peak` is p100 and is insensitive to bucket size, because the maximum of
per-bucket maxima is the overall maximum at any granularity.

`typical_peak` is **not** a fixed percentile — it is the mean high-water mark at
the bucket size used, and it moves with that size. At ~20 buckets over a 21-day
window each bucket is about a day, so `typical_peak` reads as "the typical daily
peak", which approximates p95 for a workload that spikes irregularly but reads
much closer to `true_peak` for one that spikes on a daily cycle. Report the
bucket size alongside the number; without it the figure is not reproducible and
not comparable between runs.

Classify on memory, which is where the consequence of being wrong is a kill
rather than a slowdown. Compute the CPU figures too, but the profile that drives
the limit multiplier is the memory one.

| spike_ratio | Profile | Reading |
|---|---|---|
| < 1.5 | Stable | Peaks sit close to the average. Either a flat workload or a slow grower. |
| 1.5 – 2.5 | Moderate | Real but bounded bursts. |
| > 2.5 | Spiky | Large, unpredictable bursts. The average says little about the ceiling. |

## Requests

Requests are the reservation and the only savings lever. They track typical
usage: a request above typical usage is capacity nobody uses, and a request
below it means the scheduler places the pod where it does not fit.

### Precondition: resolve replicas before computing anything

Read `kubernetes_state.deployment.replicas_desired` for every workload **first**.
It gates both formulas below, and it is the only admissible source for a replica
count. Never derive one by matching pod names to a workload: a workload whose
name is a prefix of its siblings (`x` against `x-worker`, `x-cache`) absorbs
their pods and inflates its saving, and a workload that matches nothing resolves
to zero and vanishes from the report — which is worse, because an inflated
number invites scrutiny and a missing row does not.

| Desired replicas | Meaning | Action |
|---|---|---|
| ≥ 1 | Steady workload | Compute normally. |
| averages well below 1 | Scales to zero | **Exclude from savings. Reject its average as a steady-state input.** |
| resolves to 0 or not at all | Unresolved, not absent | **Report as a finding.** Never drop the workload. |

A zero-replica resolution is a reported finding, never an omission. State the
workload, that its replica count could not be resolved, and that no
recommendation was computed for it.

**Scale-to-zero inverts the CPU formula.** An autoscaled-to-zero worker's
average is computed only over the windows in which it was awake, so it describes
the busiest moment of something that holds nothing at rest. Feeding that to
`avg × 3` sizes a permanent reservation for a transient: a worker measuring 180m
per pod against desired replicas averaging 0.04 would be told to request 1000m,
provisioning a large node on every wake. For these workloads the awake-window
average is not a steady state and the formula does not apply — say so in the
report instead of producing a number.

**CPU requests**

```
cpu_request = avg_usage × 3
```

Rounded up the CPU ladder, floor `10m`. The 3× factor is generous because CPU is
compressible — a pod above its CPU request is not killed — and because a CPU
request is also the pod's guaranteed share under node contention. Taking the
maximum across windows rather than the longest window keeps a workload that has
recently grown from being sized against its quieter past.

**Then check the result against the startup transient — for workloads that stay
up.** If the fine-grained peak (not the coarse one) shows a boot spike well
above `cpu_request`, the workload may be unable to boot inside its probe budget:
a starved boot overruns the probe, the kubelet kills the pod, and it boots again.
A workload whose steady state is 11m but which needs 149m for thirty seconds to
start is not straightforwardly a 33m workload.

**But do not raise the request yet.** Raising it is the most expensive of the
three remedies and the only one that reserves capacity — paid every hour of the
workload's life to survive thirty seconds of it, and it is the figure that
provisions nodes. Work down the ladder in "Is the request really the
constraint?" below and raise the request only when it reaches the bottom.

This whole check does not generalise to a workload that scales to zero, where
every sample is a startup transient and raising the request reserves a node for
something idle most of the time. Apply it only after the replica precondition has
confirmed the workload stays up.

### Is the request really the constraint?

Three things can stop a container from booting in time, and they cost wildly
different amounts to fix. Establish them in this order and stop at the first that
applies; only the last one justifies a larger reservation.

**0. Is a CPU limit capping the boot?** A CPU limit is a hard ceiling at all
times, enforced whether or not the node is busy. A CPU request is a guaranteed
minimum, so it binds only under contention. A container with `request: 50m` and
`limit: 100m` therefore cannot exceed 100m even on a completely idle node, and
its slow boot is caused by the limit, not the reservation.

Remove the CPU limit — which this method already recommends for unrelated
reasons — and re-measure before concluding anything about the request. The free
fix is often already in the recommendation set, sitting above both remedies
below.

**1. Can any probe actually kill the pod?** Read the container's probes. With no
`livenessProbe` and no `startupProbe`, nothing restarts the container for booting
slowly: a starved boot costs latency, not availability. Take the request
reduction. Note separately if slow starts are user-visible anyway — a
scale-to-zero cold path, a queue redelivery window, a deploy gate — but that is a
latency judgement, not a reason to reserve capacity permanently.

**2. Is the probe budget tight against the observed boot duration?** Compute the
budget of whichever probe governs startup:

```
liveness budget  = initialDelaySeconds + periodSeconds × failureThreshold
startup budget   = periodSeconds × failureThreshold
```

and compare it against the **observed boot duration** — how long the transient
lasts, read from the fine-grained query. Duration decides whether the probe
fires; the spike's CPU height is a separate question and does not belong in this
comparison.

> **Provisional threshold.** Treat the budget as tight when it is less than
> **2× the observed boot duration**. This multiplier is a working assumption, not
> a measured result: it is deliberately conservative because a boot that is
> already slow degrades further under contention. Replace it when measured probe
> budgets against measured boot durations are available, and say in the report
> that a provisional threshold was used.

**3. Budget too tight? The remedy is the probe, not the request.** A
`startupProbe` with a generous `failureThreshold` suppresses liveness and
readiness until the application is actually up — no other probe runs until it
succeeds — so it removes the kill without reserving anything, and it is reverted
in one line.

The skill does not edit probes: they are not among the configured `knobs`, and
widening the edit surface past the declared contract is not this skill's job.
So **report the probe as the remedy and hold the request reduction as
conditional** rather than declining it. The report says: this workload can give
back N millicores once its startup probe covers its boot, and here is the budget
it would need. A cut declined in silence is indistinguishable from a cut that
does not exist, and across two repositories this case alone accounted for more
reclaimable request than everything else the method found.

**4. Does the probe fail outside the boot window?** This is the case where the
request genuinely binds, and it has two signatures:

- The budget is already generous and the pod still dies. A `startupProbe` only suppresses other probes *until it succeeds*; once it passes, liveness resumes. A container starved at steady state as well as at boot has its kill deferred by a startup probe, not prevented.
- Individual probe attempts exceed `timeoutSeconds` rather than the budget exhausting. These are different failures. A healthcheck path serving a static file — no interpreter, no database — that cannot answer within the timeout is proof the container is not being scheduled CPU at all, at its *current* request.

In either case raise the request, and report that the direction of error was
**up**: the workload was under-reserved, not over-reserved. Finding this is the
method working, and it is why this ladder ends in a raise rather than in a refusal
to ever raise.

**Memory requests**

```
memory_request = avg_usage
```

Rounded up the memory ladder. No multiplier, with a consequence that must be
stated rather than glossed: the memory request sets the pod's QoS class and its
node-pressure eviction ranking. A Burstable pod using more than its memory
request is evicted ahead of one using less, so sizing at the average accepts
that the workload sits above its request roughly half the time and is an early
eviction candidate when a node comes under pressure.

That is the right trade for a workload that can be rescheduled cheaply. For one
that cannot — a singleton, a slow-warming cache, anything stateful — size the
memory request at `typical_peak` instead and say so in the report. What is not
defensible is inflating every request to the peak: that reserves memory nobody
uses, which is the waste the exercise exists to remove.

## Limits

A limit is not reserved by the scheduler. Lowering one frees nothing and only
narrows the margin before an OOM kill, so a memory limit comes down for one
reason only: to contain a known leak, as a deliberate containment decision,
reported as such and never counted as savings.

**CPU limits**: recommend removing them. A CPU limit throttles a workload that
has CPU available to it, trading latency for nothing. Flag any CPU limit
currently set, and note that removing it drops the pod from Guaranteed to
Burstable QoS where requests and limits were otherwise equal — which changes its
eviction ranking. That consequence is usually worth accepting; it is not
acceptable to leave it unsaid.

**Memory limits**: compute a safe floor from the profile.

| Profile | Safe floor |
|---|---|
| Stable | `typical_peak × 1.2` |
| Moderate | `true_peak × 1.3` |
| Spiky | `true_peak × 1.5` |
| OOM history in the peak window | `true_peak × 2.0`, regardless of profile |

Then:

- Safe floor **above** the current limit → recommend raising it.
- Safe floor **below** the current limit → leave the current limit alone, and list it under "limits left untouched" with its current margin.
- Current limit absent → recommend the safe floor, and flag that the container was unbounded.

The limit must always be at least the request.

OOM history dominates the profile because an OOM kill is proof the ceiling was
reached, and the observed peak is then censored by the kill itself — the workload
wanted more than the highest number in the data.

## When the sample is not the ceiling

Five conditions make the observed figure something other than what it looks
like. Each one can move a recommendation by an order of magnitude, and each
overrides the multiplier above. Establish all five before sizing a limit.

**1. The rollup averaged the spike away.** The metrics backend's automatic
rollup over a long window aggregates with `avg`. A query-level `max:` picks the
highest pod at each point and is then flattened *within* each bucket, so a short
spike is replaced by the bucket's mean. A 30-second spike to 149m against a 10m
steady state, inside a 25-hour bucket, reads as 10m — the spike is gone, not
merely blunted, and nothing about the output looks wrong.

Set the rollup function explicitly on every peak query, and cross-check: read a
short recent window at fine granularity and compare its peak against the coarse
one. If the fine peak is far higher, the coarse query is still averaging. Do not
size anything until the two agree.

**2. Lifetime-truncated peaks.** If pods are replaced far faster than the peak
window is long — node churn, frequent rollouts, eviction — then a workload whose
memory grows over a pod's life (an internal cache, a connection pool, a warming
index) never had the chance to show its ceiling. The observed peak measures pod
lifetime, not demand.

Count distinct pods per workload over the window and read each series' time
extent; compare against current pod ages read live. When no pod survived a
meaningful fraction of the window **and** memory grows within a pod's life, the
peak is a lower bound: size the limit above it and label the peak truncated.
Churn alone, for a workload with flat memory, changes nothing.

**3. Per-process ceilings.** A container running N worker processes, each
entitled to its own memory ceiling, has a real ceiling near:

```
N × per_process_ceiling + parent_overhead
```

which can sit far above anything observed, because the workers rarely peak
together. Read N and the per-process ceiling from the live pod spec and the
declared config, and size the limit against the computed ceiling. Sizing against
the sample produces a limit the workload can legitimately exceed.

**4. The metric counted page cache.** `memory.usage` includes the page cache,
which the kernel reclaims under pressure and does not account against the limit.
The kubelet kills on **working set**. For a container doing heavy file I/O — a
database above all — `usage` can report several times the working set; an
observed factor of ~4.7× on a database container is not an outlier.

Every memory figure here is working set. Sizing a request from `usage` inflates
the reservation and the savings estimate alike; sizing a limit from it is
conservative in direction but wrong in magnitude.

**5. The window outlived the pods, and the cross-series sum stopped meaning
anything.** Condition 1 is about aggregating *within* a bucket; this is its
mirror, aggregating *across* series. A `sum:` over a window much longer than
typical pod lifetime adds up series that came and went, so the total counts pods
that never coexisted. The symptoms are self-evident once looked for: a
per-namespace 30-day sum reading an order of magnitude above that namespace's
own 7-day sum, or a namespace two days old totalling more than a long-lived one.

This condition is dangerous precisely because the method says to take the
**maximum** of the per-window averages — so the most inflated window wins
silently and by construction. Therefore:

- Treat any window much longer than typical pod lifetime as unsafe for a cross-series sum.
- Cross-check every aggregate against a live read before using it. The live read is ground truth for "what is running now"; an aggregate that cannot be reconciled with it is discarded, not averaged in.
- When a longer window disagrees implausibly with a shorter one, that is the finding. Do not resolve it by taking the maximum.

## Rounding ladders

Round up to the next rung. Ladders exist so recommendations land on values
humans recognise, which matters more than the last few MiB.

**CPU**: `10m, 15m, 20m, 25m, 30m, 50m, 75m, 100m, 200m, 500m, 1000m`

**Memory**: `128Mi, 256Mi, 384Mi, 512Mi, 768Mi, 1024Mi, 1536Mi, 2048Mi, 3072Mi, 4096Mi`

Above the top rung, continue by doubling (`2000m`, `4000m`; `8192Mi`,
`16384Mi`) and say that the ladder was extended. Never clamp a recommendation to
the top rung — a workload that needs 6 GiB needs 6 GiB.

### The ladder must not manufacture findings

**A recommendation within one rung of the current value is a no-op. Report the
workload as adequately sized and leave it out of the recommendations.**

Without this rule, rounding invents under-provisioning. On a small cluster most
workloads sit in the single-digit millicore range, where `× 3` lands in the band
whose rungs once stepped by 2–2.5×: a component already at 2.4× its usage rounds
to ~4.8× and gets reported as under-requested. That is the ladder talking, not
the workload — and it argues for inflating something already correctly sized.

The low-end rungs above (`15m, 20m, 30m, 75m`) exist to shrink the amplification
so that "one rung" is a small step rather than a doubling. The two fixes work
together: finer rungs keep the dead band narrow enough that it suppresses noise
without swallowing a real finding.

## Savings

```
savings = Σ over workloads (current_request − recommended_request) × replicas
```

Requests only, CPU and memory separately. A limit change never enters this
figure — not a reduction, not a raise. `replicas` comes from
`replicas_desired` and nothing else, per the precondition above; state the value
used, since a per-pod figure understates by a factor of the replica count and a
cluster-wide figure without it cannot be checked.

Excluded from the sum, and each said out loud instead: workloads that scale to
zero, workloads whose replica count would not resolve, and workloads inside an
unresolved grouping bucket that has not yet been split.

**Request savings are not money, and must never be reported where they can be
quoted alone.** They become money only when they let the cluster run on fewer
nodes, which is a question about allocatable capacity per node pool and not
about the sum. State the millicore total and its node consequence in the same
breath — one table, or one sentence — and if the reduction frees no node, say
that it frees no node.

Report a negative total honestly. A run that finds workloads under-requested and
raises their reservations has done its job; presenting that as a saving, or
omitting it, is the failure.
