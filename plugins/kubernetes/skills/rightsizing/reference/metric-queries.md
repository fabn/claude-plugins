# Metric Queries (Datadog)

Tag keys are written as `{tags.cluster}`, `{tags.namespace}`, `{tags.workload}`,
`{tags.pod}` — substitute from the settings file. The defaults in the example
settings are the common Datadog Kubernetes conventions, but they are
conventions, not guarantees.

Discover the metrics tools with `ToolSearch("datadog")` rather than assuming tool
names. How many queries one call accepts is a property of the specific server,
not of Datadog — read it from the tool schema and pack accordingly.

## The rollup trap — read before writing any peak query

Datadog's automatic rollup over a long window aggregates with **`avg`**. The
query-level aggregator (`max:`) chooses across pods at each point; the rollup
then collapses the points *within* each bucket. Leave it implicit and a `max:`
query returns bucket means.

A 30-second spike to 149m over a 10m steady state, in a 25-hour bucket:

```
(149 × 30 + 10 × (90720 − 30)) / 90720 ≈ 10.0m
```

The spike does not survive at all, and the output looks entirely plausible.

So every peak query sets the function explicitly:

```
.rollup(max, <interval_seconds>)
```

with `interval = peak_window_seconds / 20`. For a 21-day window that is
`90720` (~25h, giving 21 buckets). Then cross-check against the fine-grained
query below; if the two disagree sharply, the coarse one is still averaging.

## Metric names and unit conversions

| Metric | Backend unit | Report unit | Conversion |
|---|---|---|---|
| `kubernetes.memory.working_set` | bytes | MiB | ÷ 1 048 576 |
| `kubernetes.memory.requests` | bytes | MiB | ÷ 1 048 576 |
| `kubernetes.memory.limits` | bytes | MiB | ÷ 1 048 576 |
| `kubernetes.cpu.usage.total` | nanocores | millicores | ÷ 1 000 000 |
| `kubernetes.cpu.requests` | cores | millicores | × 1 000 |
| `kubernetes.cpu.limits` | cores | millicores | × 1 000 |

**Use `working_set`, not `memory.usage`.** `usage` includes the page cache,
which the kernel reclaims and does not account against the limit; the kubelet
kills on working set. On an I/O-heavy container — a database especially — `usage`
can read several times the working set, so a request sized from it reserves
memory the workload does not hold and inflates the savings estimate to match.

CPU usage and CPU requests arrive in different units. Converting one and not the
other produces a recommendation wrong by six orders of magnitude, which is
obvious, or by three, which is not.

## Discovery

```
avg:kubernetes.memory.working_set{{tags.namespace}:<ns>} by {{tags.cluster},{tags.workload}}
```

Window `now-1d`. Returns the live cluster/workload combinations, and on a first
run proposes the `clusters` values for the settings file. Drop the synthetic
`N/A` grouping value — it collects series carrying no workload tag, typically
bare or transient pods, and is not a workload.

## Averages

```
avg:kubernetes.memory.working_set{{tags.namespace}:<ns>,{tags.cluster}:<cluster>} by {{tags.workload}}
avg:kubernetes.cpu.usage.total{{tags.namespace}:<ns>,{tags.cluster}:<cluster>} by {{tags.workload}}
```

Once per configured average window.

## Coarse binned peak — profile classification

```
max:kubernetes.memory.working_set{{tags.namespace}:<ns>,{tags.cluster}:<cluster>} by {{tags.workload}}.rollup(max, 90720)
max:kubernetes.cpu.usage.total{{tags.namespace}:<ns>,{tags.cluster}:<cluster>} by {{tags.workload}}.rollup(max, 90720)
```

Over the peak window. Bucket maxima feed `typical_peak` and `true_peak`. `max`
across pods is the right aggregation: a limit applies per container, so the
worst pod is what a limit must survive.

## Fine-grained peak — startup transients

```
max:kubernetes.cpu.usage.total{{tags.namespace}:<ns>,{tags.workload}:<workload>}.rollup(max, 60)
max:kubernetes.memory.working_set{{tags.namespace}:<ns>,{tags.workload}:<workload>}.rollup(max, 60)
```

Over a short recent window (`now-6h` to `now-2d`) that contains at least one pod
start. This is the only query that can see a spike shorter than a coarse bucket,
and a startup transient an order of magnitude above steady state is normal for
anything with a framework to boot. It feeds the CPU request check in
`method.md`, and it is the cross-check that proves the coarse rollup is honest.

Pick a window containing a restart: use the restart counts below, or the live pod
ages, to find one.

## Declared values as the cluster sees them

```
avg:kubernetes.memory.requests{{tags.namespace}:<ns>} by {{tags.workload}}
avg:kubernetes.memory.limits{{tags.namespace}:<ns>} by {{tags.workload}}
avg:kubernetes.cpu.requests{{tags.namespace}:<ns>} by {{tags.workload}}
avg:kubernetes.cpu.limits{{tags.namespace}:<ns>} by {{tags.workload}}
```

Compare against the repository's declared values. A disagreement means the
declaration is not what is deployed — drift, a manual edit, or a knob name that
never rendered.

## Replica counts

```
avg:kubernetes_state.deployment.replicas_desired{{tags.namespace}:<ns>} by {{tags.workload}}
```

Required by the savings formula, which multiplies per-pod request deltas by
replicas. Cross-check against a live deployment read — an autoscaled workload's
replica count is a moving target, so state which value was used and when.

## Pod churn

```
max:kubernetes.memory.working_set{{tags.namespace}:<ns>} by {{tags.workload},{tags.pod}}.rollup(max, 3600)
```

Over the peak window, grouped by **both** workload and pod — grouping by pod
alone leaves no way to attribute a pod to its workload short of stripping
ReplicaSet hashes from names, which is guesswork. Count distinct pods per
workload and read each series' time extent. Many short series against a small
replica count means churn, feeding condition 2 in `method.md`. Pair with a live
read of current pod ages: the metric shows history, the live read shows now.

## Restarts

```
sum:kubernetes_state.container.restarts{{tags.namespace}:<ns>} by {{tags.workload}}
```

Over `windows.restarts`. Also useful for locating a pod start for the
fine-grained query above.

## OOM events

Search **events**, not logs:

```
source:containerd event_type:oom {tags.namespace}:<ns>
```

Over the peak window.

**An empty result is not proof of no OOM.** Event sources, facets and retention
vary between setups, and this query silently returns nothing when the facet is
absent rather than erroring. Since an OOM finding sets the limit multiplier to
`2.0`, corroborate before concluding there were none: check container restart
reasons on the live objects (`lastState.terminated.reason == "OOMKilled"`) and
look for restart counts that the event search does not explain. Report which
sources were checked.

## Parallel plan

1. Discovery — one call.
2. Averages — one call per cluster per window.
3. Coarse binned peak — one call per cluster.
4. Fine-grained peak — one call per workload of interest.
5. Declared values — one call per namespace.
6. Replica counts — one call per namespace.
7. Pod churn — one call per namespace.
8. Restarts — one call.
9. OOM events — one call.

Groups 2 through 9 are independent and should all be in flight at once. Group 4
depends on group 8 or on live pod ages only for choosing its window; if a
restart time is already known, it parallelises with the rest.
