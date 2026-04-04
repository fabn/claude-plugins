# Spacelift Tool Reference

Shared reference for all Spacelift skills. Covers MCP tool discovery, tool catalog, CLI equivalents, and GraphQL queries.

---

## Tool Detection

Before executing any Spacelift operation, detect the available interface:

1. Use **ToolSearch** with query `spacelift` to discover MCP tools
2. If tools prefixed `mcp__spacelift_spacectl-mcp__` are found → use MCP as primary interface
3. If MCP tools are NOT available → fall back to `spacectl` CLI via Bash
   - Verify authentication: `spacectl whoami`

---

## MCP Tools Catalog

The `spacelift.spacectl-mcp` MCP server exposes the following tools:

### Stacks

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `list_stacks` | Paginated list of stacks | `search`, `limit`, `next_page_cursor` (all optional) |

### Runs

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `list_stack_runs` | Tracked runs (changes to resources) | `stack_id` |
| `list_stack_proposed_runs` | Preview runs (PRs, local previews) | `stack_id` |
| `get_stack_run` | Single run details | `stack_id`, `run_id` |
| `get_stack_run_logs` | Run log output | `stack_id`, `run_id`, optional `skip`, `limit` |
| `get_stack_run_changes` | Resource changes for a run | `stack_id`, `run_id` |

### Run Management

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `trigger_stack_run` | Start a new run | `stack_id`, optional `run_type` (`PROPOSED`/`TRACKED`), `commit_sha` |
| `confirm_stack_run` | Approve a pending run | `stack_id`, `run_id` |
| `discard_stack_run` | Discard a pending run | `stack_id`, `run_id` |
| `local_preview` | Run local preview | `stack_id`, optional `path`, `await_for_completion`, `targets`, `environment_variables` |

### Resources

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `list_resources` | Infrastructure resources | optional `stack_id` |

### Contexts

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `list_contexts` | Paginated context list | optional `search`, `limit` |
| `search_contexts` | Advanced context search | optional `labels`, `space`, `search` |
| `get_context` | Context details + env vars | `context_id` |

### Policies

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `list_policies` | Paginated policy list | optional `search` |
| `get_policy` | Policy details + body | `policy_id` |
| `list_policy_samples` | Evaluation samples | `policy_id` |
| `list_policy_samples_indexed` | Searchable samples | `policy_id`, optional `search`, `outcome` |
| `get_policy_sample` | Single sample | `policy_id`, `sample_key` |

### Modules

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `list_modules` | Private registry modules | optional `search` |
| `search_modules` | Advanced module search | optional `terraform_provider`, `labels`, `space` |
| `get_module` | Module details | `module_id` |
| `list_module_versions` | Module versions | `module_id`, optional `include_failed` |
| `get_module_version` | Version details | `module_id`, `version_id` |
| `get_module_guide` | Operational guidance | optional `topic` |

### GraphQL Schema

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `introspect_graphql_schema` | Full schema overview | optional `format` (`summary`/`detailed`) |
| `search_graphql_schema_fields` | Search schema fields | `search_term`, optional `search_scope` |
| `get_graphql_type_details` | Type details | `type_name` |

### Other

| MCP Tool | Description | Required Params |
|----------|-------------|-----------------|
| `list_spaces` | All spaces | (none) |
| `get_space` | Space details | `space_id` |
| `list_blueprints` | Blueprints | optional `search` |
| `get_blueprint` | Blueprint details | `blueprint_id` |
| `list_worker_pools` | Worker pools | optional `search` |
| `get_worker_pool` | Worker pool details | `worker_pool_id` |
| `list_api_keys` | API keys (no secrets) | (none) |
| `get_api_key` | API key details | `api_key_id` |
| `get_authentication_guide` | Auth guidance | optional `auth_method` |

---

## CLI Equivalents

When MCP tools are unavailable, use `spacectl` via Bash. Ensure `SPACELIFT_API_KEY_ENDPOINT` and `SPACELIFT_API_GITHUB_TOKEN` are set.

### Stacks

```bash
spacectl stack list -o json
spacectl stack show --id <stack-slug> -o json
```

### Runs

```bash
spacectl stack run list --id <stack-slug> -o json                 # tracked runs
spacectl stack run list --id <stack-slug> --preview-runs -o json  # preview runs
```

### Logs

```bash
spacectl stack logs --id <stack-slug> --run <run-id>
spacectl stack logs --id <stack-slug> --run <run-id> --phase PLANNING
spacectl stack logs --id <stack-slug> --run-latest
spacectl stack logs --id <stack-slug> --run <run-id> --tail
```

**Strip ANSI codes** from CLI output: pipe through `sed 's/\x1b\[[0-9;]*m//g'`.

### Changes

```bash
spacectl stack changes --id <stack-slug> --run <run-id>
```

### Local Preview

```bash
spacectl stack local-preview --id <stack-slug>
spacectl stack local-preview --id <stack-slug> --target <resource>
spacectl stack local-preview --id <stack-slug> --no-tail
spacectl stack local-preview --id <stack-slug> --project-root-only
```

### Run Management

```bash
spacectl stack confirm --id <stack-slug> --run <run-id>
spacectl stack discard --id <stack-slug> --run <run-id>
spacectl stack deploy --id <stack-slug>
spacectl stack retry --id <stack-slug> --run <run-id>
spacectl stack cancel --id <stack-slug> --run <run-id>
```

### Dependencies (CLI only — not available via MCP)

```bash
spacectl stack dependencies on --id <stack-slug>    # stacks this one depends on
spacectl stack dependencies off --id <stack-slug>   # stacks that depend on this one
```

---

## GraphQL Queries (CLI only)

For data not covered by MCP tools, use `spacectl api` with read-only GraphQL queries.

### Stack with recent run

```bash
spacectl api '
query {
  stack(id: "<stack-slug>") {
    id name branch repository projectRoot
    trackedRun { id state title }
  }
}'
```

### Phase-level logs

```bash
spacectl api '
query {
  stack(id: "<stack-slug>") {
    run(id: "<run-id>") {
      state
      history { state timestamp note }
      logs(state: <PHASE>) {
        messages { message timestamp }
      }
    }
  }
}'
```

Valid `state` values for logs: `QUEUED`, `PREPARING`, `INITIALIZING`, `PLANNING`, `APPLYING`, `FINISHED`, `FAILED`.

### Search stacks

```bash
spacectl api '
query {
  stacks(input: {}) {
    edges {
      node { id name repository projectRoot branch }
    }
  }
}'
```
