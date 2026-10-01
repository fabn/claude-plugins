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

**CPU requests**

```
cpu_request = avg_usage × 3
```

Rounded up the CPU ladder, floor `10m`. The 3× factor is generous because CPU is
compressible — a pod above its CPU request is not killed — and because a CPU
request is also the pod's guaranteed share under node contention. Taking the
maximum across windows rather than the longest window keeps a workload that has
recently grown from being sized against its quieter past.

**Then check the result against the startup transient.** If the fine-grained
peak (not the coarse one) shows a boot spike well above `cpu_request`, raise the
request to cover it. Contention bites hardest exactly at boot, and a slow boot
fails readiness probes, which restarts the pod, which boots again. A workload
whose steady state is 11m but which needs 149m for thirty seconds to start is
not a 33m workload. This is the most common cause of a request that must go
**up**, and such a finding is the method working.

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

Four conditions make the observed peak something other than a ceiling. Each one
can move a recommendation by an order of magnitude, and each overrides the
multiplier above. Establish all four before sizing a limit.

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

## Rounding ladders

Round up to the next rung. Ladders exist so recommendations land on values
humans recognise, which matters more than the last few MiB.

**CPU**: `10m, 25m, 50m, 100m, 200m, 500m, 1000m`

**Memory**: `128Mi, 256Mi, 384Mi, 512Mi, 768Mi, 1024Mi, 1536Mi, 2048Mi, 3072Mi, 4096Mi`

Above the top rung, continue by doubling (`2000m`, `4000m`; `8192Mi`,
`16384Mi`) and say that the ladder was extended. Never clamp a recommendation to
the top rung — a workload that needs 6 GiB needs 6 GiB.

## Savings

```
savings = Σ over workloads (current_request − recommended_request) × replicas
```

Requests only, CPU and memory separately. A limit change never enters this
figure — not a reduction, not a raise. State the replica count used; a per-pod
figure understates by a factor of the replica count, and a cluster-wide figure
without it cannot be checked.

Request savings are not yet money. They become money when they let the cluster
run on fewer nodes, which is a question about allocatable capacity per node pool
and not about the sum. Report the sum and the node-level consequence separately.

Report a negative total honestly. A run that finds workloads under-requested and
raises their reservations has done its job; presenting that as a saving, or
omitting it, is the failure.
