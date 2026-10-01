# Kubernetes Plugin

Kubernetes workload rightsizing: derive CPU and memory requests from observed usage metrics, size limits for safety rather than savings, reconcile against the values declared in Terraform or Helm, and gate every change behind a rendered-plan check and a live-object check.

## Skills

| Skill | Description |
|-------|-------------|
| `/kubernetes:rightsizing` | Analyze observed CPU and memory usage, compare against declared resource values, and recommend requests and limits — with optional application behind two verification gates |

## Prerequisites

| Requirement | Required | Why |
|---|---|---|
| A metrics backend holding Kubernetes resource metrics (Datadog) | Yes | There is no fallback. The method sizes against observed usage. |
| `kubectl` with a context for each cluster | Yes | Verifying the environment discriminator, reading pod ages and specs, and the post-apply live-object check. |
| Read access to the repository that declares the resource values | Yes | Terraform modules, Helm values, or raw manifests. |
| [`kube-capacity`](https://github.com/robscott/kube-capacity) | No | Node-level allocatable against requested, in one call — which is what turns a request reduction into a node count. Falls back to `kubectl top nodes` plus a node read. |

```bash
brew install kube-capacity          # or
kubectl krew install resource-capacity
```

The metrics backend is deliberately not abstracted. The skill ships concrete, runnable Datadog queries rather than provider-agnostic advice; see `skills/rightsizing/reference/metric-queries.md`. Install the `datadog` plugin alongside this one for the metrics MCP servers and the `DD_*` credentials they need.

## MCP Servers

| Server | Package | Purpose |
|--------|---------|---------|
| `kubernetes.kubernetes-mcp` | `kubernetes-mcp-server` | Live pod specs, pod ages, deployment and node reads |

Started with `--read-only`. The skill never mutates the cluster: changes go through the repository's own declaration and the project's own apply mechanism. The server inherits the ambient environment, so it picks up `KUBECONFIG` if set and falls back to `~/.kube/config` otherwise.

## Getting Started

```
/kubernetes:rightsizing
```

On first run in a project the skill runs a discovery pass, proposes the settings it can detect, and writes `.claude/kubernetes.local.md`. Add that path to `.gitignore` — it is per-developer and holds cluster and namespace names.

## Project Configuration

Everything project-specific lives in `.claude/kubernetes.local.md`: clusters, namespaces per environment, which file declares each workload, what the knobs are called, the metrics tag keys, and the commands that preview, apply and read back a change. The full schema is in `skills/rightsizing/reference/configuration.md`.

Three keys exist because assuming them went wrong in practice:

- **`workloads`** — maps a workload's metrics tag value to the file and block that declares it. A workload name is not assumed to match a file name, because the step downstream of that guess is an `Edit`.
- **`knobs`** — the input names of whatever module or chart wraps Kubernetes, which are often not the Kubernetes field names. Helm accepts an unknown value key silently, so a wrong name is indistinguishable from a working one until the rendered manifest is read.
- **`environment_discriminator`** — the input that genuinely separates the environments, plus where it is observable on a live object so the claim can be checked.

## Skill Details

### `/kubernetes:rightsizing`

Loads or creates the settings, discovers clusters and workloads, parses the declared values, verifies the environment discriminator against live objects, gathers usage at two resolutions, establishes whether the observed peak can be trusted, computes, translates the result into node headroom, reports, and optionally applies.

**Requests are the only savings lever.** A limit is not reserved by the scheduler, so lowering one frees no capacity and only narrows the margin before an OOM kill. Savings count request reductions and nothing else; memory limits move up for safety or down only to contain a known leak; CPU limits are recommended for removal as a correctness change. Every limit left deliberately untouched is listed as such, and request savings are reported separately from the node-level consequence — only the latter is money.

**Four conditions make an observed peak something other than a ceiling,** and the skill establishes all four before sizing a limit, because each can move a recommendation by an order of magnitude:

- The metrics backend's default rollup aggregates with `avg`, so a `max:` query returns bucket means and a short spike vanishes. A 30-second spike to 149m over a 10m steady state, in a 25-hour bucket, reads as 10m. Every peak query sets the rollup function explicitly and is cross-checked against a fine-grained read.
- `memory.usage` counts page cache, which the kernel reclaims and never accounts against the limit — the kubelet kills on working set. On an I/O-heavy container the gap is several-fold. All memory figures use `working_set`.
- Pods replaced faster than the measurement window never showed their ceiling, for any workload whose memory grows over a pod's life.
- A container running N worker processes, each with its own memory ceiling, has a real ceiling far above anything observed.

**Verification is required but unprescribed.** How a change is previewed and applied is project-specific: `terraform plan`, `helm diff`, `kubectl diff`, or a CI system that owns the plan. The skill runs the commands named in the settings file and enforces two gates — read the rendered change and confirm it contains every intended effect at *attribute* granularity, then confirm the live object rather than the success of the apply. With no apply command configured it hands off and says so rather than improvising one.

Reference files:

- `reference/configuration.md` — settings schema
- `reference/method.md` — percentile proxy, profile classification, formulas, the four sample-is-not-the-ceiling conditions, ladders, savings rule
- `reference/metric-queries.md` — Datadog queries, the rollup trap, metric names, unit conversions, parallel plan
