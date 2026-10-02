# Settings File

`.claude/kubernetes.local.md` — per-project, user-managed, gitignored. YAML
frontmatter holds the configuration; the markdown body is free-form notes.

Nothing here can be inferred reliably. Cluster and namespace names are
environment facts; knob names belong to whatever module or chart wraps
Kubernetes rather than to Kubernetes itself; and the mapping from a workload to
the file that declares it is a repository convention. Propose candidates from a
discovery pass, confirm them, write the file, then read it on every run.

## Complete Example

```markdown
---
# Cluster tag values, as the metrics backend spells them.
clusters:
  - prod-eu
  - prod-eu-dr

# Namespaces grouped by environment. These environment names are labels for the
# report — they need not match any tag or input value anywhere.
environments:
  production:
    namespaces: [app-prod]
  staging:
    namespaces: [app-staging]

# Which declared input ACTUALLY separates the environments, where it is
# observable on a live object, and its value in each. Verified in Step 4.
environment_discriminator:
  input: cluster_role
  observable_as: "metadata.labels['app.kubernetes.io/instance']"
  values:
    production: primary
    staging: secondary

# Where resource values are declared. `syntax` selects the edit strategy and
# what Gate 1 should expect to read in the preview.
resource_declarations:
  - glob: "modules/**/*.tf"
    syntax: terraform
  - glob: "charts/*/values*.yaml"
    syntax: helm-values

# Workload tag value -> where its resources are declared. The authoritative
# mapping: a workload name is not assumed to match a file or block name.
workloads:
  api:
    declared_in: "modules/app/api.tf"
    block: 'module "api"'
  worker:
    declared_in: "modules/app/worker.tf"
    block: 'module "worker"'
  web:
    declared_in: "charts/web/values-prod.yaml"
    block: "resources"
  # Declared in another repository. Analysed and reported, never edited here,
  # and not asked about again on the next run.
  search:
    external: true

# The knob names as the wrapping module or chart spells them. Usually NOT the
# Kubernetes field names. Omit a knob the project does not expose.
knobs:
  cpu_requests: cpu_requests
  cpu_limits: cpu_limits
  memory_requests: memory_requests
  memory_limits: memory_limits

# Tag keys used by the metrics backend.
tags:
  cluster: kube_cluster_name
  namespace: kube_namespace
  workload: kube_deployment
  pod: pod_name
  environment: env       # optional
  service: service       # optional

# How a change is previewed, applied, and read back. All project-specific; the
# skill runs what is named here and reads the output. It does not choose them,
# and it never improvises an apply.
verification:
  preview: "terraform plan -out=tfplan && terraform show tfplan"
  apply: "terraform apply tfplan"
  live_read: "kubectl --context {context} -n {namespace} get deployment {workload} -o json"

# Optional. Defaults shown.
windows:
  averages: [1d, 7d, 30d]
  peak: 21d
  restarts: 7d
---

# Notes

Free-form. Good place for workload quirks the metrics cannot show: which
containers run multiple worker processes, which hold a growing in-process
cache, which churn pods, which are I/O-heavy enough that page cache dwarfs the
working set, which cannot be rescheduled cheaply and so want their memory
request at the typical peak rather than the average.
```

## Keys

| Key | Required | Notes |
|---|---|---|
| `clusters` | Yes | Tag values, not display names. Proposed by the discovery query on a first run, before the file is written. |
| `environments` | Yes | Environment label → `namespaces` list. One environment may span several namespaces. |
| `environment_discriminator` | Only with 2+ environments | Omit it entirely when `environments` has a single entry — there is nothing to discriminate, and a placeholder that cannot be verified is worse than an absent key. |
| `environment_discriminator.input` | Yes | The declared input that genuinely separates environments. |
| `environment_discriminator.observable_as` | Yes | Where that input lands on a live object — a label, annotation, or container env var. Without it the discriminator cannot be verified and the run stops. |
| `environment_discriminator.values` | Yes | Expected value per environment label. A mismatch against live objects stops the run. |
| `resource_declarations` | Yes | Globs plus `syntax` (`terraform`, `helm-values`, `manifest`), which selects the edit strategy and the expected preview shape. |
| `workloads` | Yes | Workload tag value → `declared_in` and `block`, or `external: true`. A workload discovered but absent from this map is asked about, never inferred. |
| `workloads.<name>.external` | No | Declared in another repository. Analysed and reported, never edited, and not asked about again. |
| `knobs` | Yes | Maps the four logical knobs to their real names. |
| `tags.cluster` / `.namespace` / `.workload` / `.pod` | Yes | Grouping keys for every query. |
| `tags.environment` / `.service` | No | For scoping queries where namespaces alone do not separate environments, and for grouping the report by service. |
| `verification.preview` | Yes | Renders or plans the change without applying. `terraform plan`, `helm diff`, `kubectl diff`, or a CI-owned plan. |
| `verification.apply` | No | If absent, the skill hands off to the project's mechanism and names it rather than inventing a command. |
| `verification.live_read` | Yes | Reads the live object. `{context}`, `{namespace}` and `{workload}` are substituted. |
| `windows.averages` | No | Default `[1d, 7d, 30d]`. Formulas are stated against whatever this holds. |
| `windows.peak` | No | Default `21d`. Also sets the coarse rollup interval (window ÷ 20). |
| `windows.restarts` | No | Default `7d`. |

## One cluster, several repositories

The schema is per-project, but a cluster's workloads are often declared across
several repositories. The settings file describes one of them, and the skill
sees one at a time, so the two halves of a run have different scopes:

- **The analysis is cluster-wide.** Metrics cover every workload in the configured namespaces regardless of who declares it, and the savings and node-headroom figures are only meaningful at that scope.
- **Drift detection and both apply gates are per-repository.** They can only reach what this project declares.

Mark a workload declared elsewhere with `external: true`. It then counts in the
analysis and the report, is never edited, and is not asked about on the next
run. Without the marker every run stops to ask about workloads this repository
will never own.

When the recommendations span repositories, say which ones, and give each
repository's owner the subset that applies to them rather than one undivided
list.

## Why the discriminator is configured, and then verified anyway

An input named `environment` is a label, not a guarantee. An environment that
deliberately mirrors production will declare itself as production, and keying
resource values off that label hands a non-production environment production's
reservations — silently, because nothing about the result looks wrong.

Hence two keys rather than one. `input` says which input is believed to separate
the environments; `observable_as` says where to go and check. A module or chart
input is not a Kubernetes field, so it is only visible on a live object where
the chart chose to put it — a label, an annotation, an env var. If it is
observable nowhere, it cannot be verified, and per-environment values cannot be
trusted: the run stops rather than guessing.

## Why knob names cannot be assumed

A chart or module input named `memory_requests` may render to
`resources.requests.memory`, or to something else, or to nothing at all. Helm in
particular accepts an unknown value key silently: it is stored in the release,
ignored at template time, and shown by `helm get values` as though it worked. A
wrong knob name is indistinguishable from a working one at every layer except
the rendered manifest — which is exactly what Gate 1 reads.

The same trap exists in Terraform modules: a `variable` a module declares but
never reads accepts input and discards it just as silently.
