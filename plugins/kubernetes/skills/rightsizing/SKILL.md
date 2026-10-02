---
name: kubernetes:rightsizing
description: |
  This skill should be used when the user wants to rightsize Kubernetes workloads:
  derive CPU and memory requests and limits from observed usage, find
  over-provisioned or under-provisioned deployments, investigate OOM kills or
  evictions, reclaim cluster cost, or reconcile declared resource values against
  what pods actually consume.
  Requires a metrics backend holding Kubernetes resource metrics (Datadog) and
  read access to the live cluster.
  Activates on: "rightsize pods", "rightsizing", "check resource usage",
  "review pod resources", "optimize cpu requests", "optimize memory requests",
  "are pods over-provisioned", "reduce resource waste", "cluster costs too much",
  "cluster is expensive", "check pod memory", "check pod cpu", "resize pods",
  "tune pod resources", "check for OOM", "oom kills", "pods evicted",
  "node pressure", "pod requests and limits", "capacity review",
  "ridimensionare i pod", "rivedere le risorse dei pod", "ottimizzare cpu e memoria",
  "i pod sono sovradimensionati", "ridurre lo spreco di risorse",
  "il cluster costa troppo", "costi del cluster", "controllare la memoria dei pod",
  "verificare gli oom", "pod sfrattati".
---

# Kubernetes Rightsizing Skill

Derive CPU and memory requests and limits for Kubernetes workloads from observed
usage, reconcile them against the values declared in the repository, and apply
the change behind two verification gates.

Everything project-specific — clusters, namespaces, where each workload's values
are declared, what the knobs are called, which tag means what, how a change is
previewed and applied — comes from `.claude/kubernetes.local.md`, never from
assumption. Schema: `reference/configuration.md`.

The method and its traps are in `reference/method.md`; the queries are in
`reference/metric-queries.md`. Read both before computing anything. Several
traps there are not optional reading, because each one silently produces a
confident wrong answer rather than an error: the metrics backend's **default
rollup averages within buckets**, hiding short spikes entirely; **`memory.usage`
counts page cache**, overstating I/O-heavy containers several-fold; a
**cross-series `sum:` over a window longer than pod lifetime** totals pods that
never coexisted; **`N/A` is unresolved, not absent**, and discarding it throws
away the StatefulSets; and **replica counts derived from pod names** both inflate
and silently delete findings.

## The one rule that governs everything

**Requests are what the scheduler reserves. Limits are not reserved by anyone.**

A savings estimate may count request reductions and nothing else. Lowering a
memory limit frees no capacity — it only narrows the margin before an OOM kill.

So each knob moves for its own reasons:

- **Requests** move in either direction, and are the only figure savings may count.
- **Memory limits** move up for safety, or down only to contain a known leak — never down to save.
- **CPU limits** should be removed outright, which is a correctness change, not a savings one. It also moves the pod out of Guaranteed QoS; say so.

Every limit the analysis deliberately leaves alone is listed in the report as
such, with the margin it currently carries.

## Tools Used

- **Read / Glob / Grep**: settings file and declared resource values.
- **Metrics backend**: usage, requests, limits, replicas, restarts, OOM events. Discover the tools with `ToolSearch("datadog")` rather than assuming names — the server may come from the `datadog` plugin or from a first-party Datadog MCP, and their tool names and per-call query limits differ.
- **`kubernetes.kubernetes-mcp`**: live pod specs, pod ages, deployment and node reads. Read-only.
- **AskUserQuestion**: confirm proposed settings; confirm before applying.
- **Write**: create the settings file on first run.
- **Edit**: update declared resource values.
- **Bash**: `kube-capacity` for node headroom when available, plus the project's own preview, apply and live-read commands.

## Workflow

### Step 1: Load or Create Settings

Read `.claude/kubernetes.local.md` from the project root.

**If it exists**, parse its YAML frontmatter and validate every required key in
`reference/configuration.md`. Report any missing key and ask for that value only.

**If it does not exist**, run a discovery pass *first* so the questions carry
real candidates rather than blanks: the discovery query (Step 2) proposes
cluster and namespace values, and a glob over the repository proposes
declaration files and knob names. Present the candidates, confirm them, write
the file, and tell the user to gitignore it.

Ask once and write it. Never guess a value in order to skip this step — a run
built on guessed namespaces or guessed knob names produces confident nonsense.
Where a value is free-form (globs, shell commands, tag keys), offer detected
candidates as options and fall back to a plain question rather than forcing a
bounded choice.

### Step 2: Discover Clusters and Workloads

Run the discovery query from `reference/metric-queries.md` for each configured
namespace, grouped by cluster and workload.

- **Split the `N/A` grouping value; never discard it.** `N/A` means the workload tag was unresolved, not that there is no workload. StatefulSet pods carry no deployment tag, so on any cluster with an operator-managed data tier that bucket is the databases and caches — often the largest reservations on the cluster. Regroup it by pod and owner kind per `reference/metric-queries.md`, and resolve the remainder against live owner references. Whatever is still unresolved is a reported finding that blocks a change to it, not noise.
- Cross-check against the live cluster. In metrics but not live means deleted; live but not in metrics means new, with no history to size against. Note both; neither is a failure.
- If a configured cluster or namespace returns nothing, say so and continue with the rest.

### Step 3: Parse the Declared Values

For each discovered workload, resolve its declaration through the `workloads`
map in the settings file — that map, not a guess from the name, is what ties a
metrics tag value to a file and a block. Record per environment:

- the current value of each configured knob
- whether the value is conditional, and on which input it branches
- the file and line, so the report can cite them and Step 10 can edit them

A knob absent from the declaration is not a knob set to zero. An absent memory
limit means the container is unbounded; an absent request means the scheduler
reserves nothing. Both are findings.

Compare the declared values against what the cluster reports as requested and
limited. A disagreement means the declaration is not what is deployed — drift, a
manual edit, or a knob name that never rendered. Report it before recommending
anything: a recommendation against a stale declaration edits the wrong number.

### Step 4: Verify the Environment Discriminator

Skip this step when `environments` has a single entry — there is nothing to
discriminate, and verifying a placeholder proves nothing.

Otherwise the settings file names the input that is supposed to separate the
environments, and where that input is observable on a live object. Neither is
trusted until checked.

1. Confirm the configured `environment_discriminator.input` is the input the declarations actually branch on, using the Step 3 findings.
2. Read the live objects in each configured namespace and compare the value at `environment_discriminator.observable_as` (a label, annotation, or container env var — a module or chart input is not a Kubernetes field, so it is only visible where the chart puts it) against the expected value for that environment.
3. If config and live objects disagree, **stop and report the disagreement**. Do not pick a winner.

This step exists because an input named `environment` is a label, not a
guarantee: an environment deliberately mirroring production will declare itself
as production, and keying resource values off that label hands a non-production
environment production's reservations — silently, because nothing about the
result looks wrong.

Every per-environment value later in the run keys off the verified discriminator.

### Step 5: Gather Metrics

Fire the queries in `reference/metric-queries.md` in parallel wherever the
backend allows: averages over each configured window, the coarse binned peak
over the peak window, a fine-grained read over a short recent window, declared
requests and limits, replica counts, restarts, and OOM events.

Both resolutions are required, not alternatives. The coarse read classifies the
workload; the fine read is the only thing that can see a startup transient or
any spike shorter than a bucket. Every peak query must set its rollup function
explicitly — the default averages within buckets and will erase exactly the
spikes being looked for.

Tolerate sparse data. A workload created three days ago has no 30-day average;
record what exists, mark the rest unavailable, and never substitute a shorter
window's value for a longer one without labelling it.

### Step 6: Decide Whether the Observed Figures Are Trustworthy

The measurement window is evidence, not truth. Before anything is sized,
establish the five conditions in `reference/method.md` ("When the sample is not
the ceiling"): the rollup cross-check, pod lifetime against the window,
per-process ceilings, whether the metric counts page cache, and whether a
cross-series sum outlived its pods.

These are inputs to the computation, not commentary on it — each one can move a
recommendation by an order of magnitude, and each overrides a multiplier derived
from the sample. Record which applied to which workload.

### Step 7: Compute

First resolve replicas, which gates both request formulas — see the precondition
in `reference/method.md`. `kubernetes_state.deployment.replicas_desired` is the
only admissible source: never attribute pods to a workload by name, because a
workload whose name prefixes its siblings absorbs their pods and one that
matches nothing resolves to zero and vanishes from the report.

Then apply the formulas, honouring the Step 6 findings over any sample-derived
multiplier, and holding to three rules that each exist to stop a confident wrong
answer:

- A workload whose desired replicas average well below 1 scales to zero. Its average describes only its awake windows, so it is not a steady-state input and the CPU formula does not apply. Exclude it from savings and say why.
- A workload whose replica count will not resolve is a reported finding, never an omission.
- A recommendation within one rung of the current value is a no-op. Report the workload as adequately sized and leave it out of the recommendations — otherwise rounding manufactures under-provisioning.

### Step 8: Node Headroom

Request reductions only become money when they let the cluster run on fewer
nodes. Translate the totals into node terms.

If `kube-capacity` is on PATH, use it — it reports allocatable against requested
per node in one call:

```bash
kube-capacity --util --pods --namespace <namespace>
```

Otherwise fall back to `kubectl top nodes` plus a node read for allocatable.

Report requested-against-allocatable per node pool now, and what it becomes
after the recommendations. State plainly whether the change frees a whole node
or merely loosens packing — both are legitimate outcomes, and only the first is
a cost saving. If `kube-capacity` is absent and would have helped, suggest
installing it (`brew install kube-capacity`, or `kubectl krew install
resource-capacity`) rather than silently doing less.

### Step 9: Report

Present, in this order:

1. **Measurement basis** — metric used for memory, rollup function and bucket size per query, windows. Without these the numbers are not reproducible.
2. **Verified discriminator** — which input separates the environments and how it was confirmed.
3. **Peak trust** — per workload, which of the five Step 6 conditions applied. Before the numbers, because it is what makes them readable.
4. **Workload profile** — avg, typical peak, true peak, spike ratio, profile.
5. **Recommendations** — current vs recommended per knob, with rationale and the file and line of the current value.
6. **Limits left untouched** — every limit deliberately not lowered, and its current margin.
7. **Not sized, and why** — workloads that scale to zero, workloads whose replica count would not resolve, unresolved grouping buckets, and workloads marked `external`. A workload the method could not size is a finding; silence here is how the largest one in a run goes missing.
8. **OOM events, restarts, evictions** — counts and affected workloads, with the window for each.
9. **Risk flags** — current limit close to true peak; no limit at all; no request at all; request far below true peak.
10. **Savings and node consequence — together, in one table.** Request reductions only, per workload and total, multiplied by the replica count from `replicas_desired`, with that count stated — and in the same table the Step 8 before-and-after showing whether the reduction frees a whole node. Never present the millicore total where it can be quoted on its own: only the node figure is money, and if nothing is freed, say nothing is freed. Report a negative total honestly: finding a workload under-requested and raising it is the method working, not a failure.

### Step 10: Apply, Behind Two Gates

Only on explicit confirmation. Show the full diff first and wait.

**Gate 1 — read the rendered change before it lands.** Run `verification.preview`
and read its output. Confirm it contains every intended effect and nothing else.
Check at attribute granularity, not resource granularity: three knobs on one
Deployment are three changed attributes on *one* changed resource, so a resource
count of 1 proves nothing about whether all three landed. An attribute silently
dropped in transit makes a change that validates cleanly and then does nothing;
what exposes it is reading the rendered attributes, and noticing a resource that
should have been created showing as "0 to add". If an intended effect is missing,
stop and report it — do not apply.

**Gate 2 — confirm the live object, not the apply.** Apply via
`verification.apply` if the settings file defines it; otherwise hand off to the
project's own mechanism (`/terraform:apply`, a PR, a CI-owned plan) and say which
— never improvise an apply command. Then read the live object with
`verification.live_read` and check the values on the object itself. A successful
apply is not evidence that the object looks the way you think. Report the live
values, not the apply's exit status.

Preserve formatting and comments; touch only the resource knobs. Where prod and
non-prod need different values, express it with the verified discriminator from
Step 4, not with an environment input that was never confirmed.

## Error Handling

| Condition | Action |
|---|---|
| `.claude/kubernetes.local.md` missing | Run a discovery pass, propose candidates, confirm, write the file. Never guess. |
| Settings file missing a required key | Name the key, ask for that value only, continue. |
| Workload discovered but absent from the `workloads` map | Ask for its declaration location, or mark it `external: true` if another repository declares it. Do not infer it from the name. |
| Workload's replica count will not resolve | Report it as a finding with no recommendation. Never drop it, and never fall back to counting or name-matching pods. |
| Desired replicas average well below 1 | Scales to zero. Exclude from savings, refuse the awake-window average as a steady state, skip the boot-transient check. |
| `N/A` or any unresolved grouping bucket | Split it by pod and owner kind, then by live owner references. Report whatever remains; do not change anything inside it and do not discard it. |
| Recommendation within one rung of the current value | Report as adequately sized, exclude from recommendations. Do not report it as under- or over-provisioned. |
| A longer window's aggregate implausibly exceeds a shorter one's | Treat as a cross-series sum that outlived its pods. Report the disagreement; do not take the maximum. |
| Single environment configured | `environment_discriminator` may be omitted; skip Step 4 rather than verifying a placeholder. |
| Metrics backend unreachable | Stop. The method has no fallback — there is nothing to size against. |
| Live cluster unreachable | Stop before Step 4. The discriminator, the peak-trust inputs and Gate 2 all need live reads. |
| Configured cluster or namespace returns no series | Report it, continue with the rest. |
| `environment_discriminator` disagrees with live objects | Stop and report the disagreement. Do not choose a winner. |
| Discriminator not observable on any live object | Stop. It cannot be verified, so per-environment values cannot be trusted. |
| Workload in metrics but not live | Mark deleted, exclude from recommendations. |
| Workload live but not in metrics | Mark new, report that it has no usage history. |
| Sparse data for a window | Record what exists, mark the rest unavailable. Never substitute another window's value. |
| Knob absent from the declaration | Report as a finding (unbounded limit, or unreserved request), not as zero. |
| Declared values disagree with what the cluster reports | Report the drift before recommending. Do not edit against a stale declaration. |
| Coarse peak far below the fine-grained peak | The coarse rollup is averaging. Re-query with an explicit `max` rollup; do not size anything until the two agree. |
| No pod survived a meaningful fraction of the peak window, and memory grows within a pod's life | Treat the peak as a lower bound, widen the limit, say why. |
| Recommendation exceeds the top ladder rung | Extend the ladder by doubling and say so. Do not clamp to the top rung. |
| OOM events query returns empty | Not proof of no OOM. Corroborate against restart reasons before dropping the OOM multiplier. |
| `kube-capacity` absent | Fall back to `kubectl top nodes` plus allocatable, and suggest installing it. |
| Preview missing an intended effect | Stop. Do not apply. Report which effect is absent. |
| No `verification.apply` configured | Hand off to the project's mechanism and name it. Never improvise an apply command. |
| Live object disagrees after apply | Report the live values and the discrepancy. Do not re-apply automatically. |

## Reference Files

- **`reference/configuration.md`** — settings schema, key by key, with a complete example.
- **`reference/method.md`** — percentile proxy, profile classification, request and limit formulas, the five sample-is-not-the-ceiling conditions, rounding ladders, savings rule.
- **`reference/metric-queries.md`** — Datadog queries, metric names, unit conversions, the rollup trap, parallel plan.
