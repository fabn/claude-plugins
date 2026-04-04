---
name: spacelift:spacelift
description: |
  This skill should be used when the user wants to interact with Spacelift CI/CD
  for Terraform: inspect stacks, read run logs, debug failed plans or applies,
  run local previews, list stacks and dependencies, manage runs, or explore the
  Spacelift GraphQL schema.
  Activates on: "spacelift", "spacelift logs", "spacelift run", "spacelift preview",
  "spacelift status", "check spacelift", "why did spacelift fail", "spacelift stack",
  "local preview", "preview spacelift", "spacelift plan failed", "run spacelift",
  "list stacks", "spacelift dependencies", "spacelift changes", "trigger run",
  "confirm run", "discard run", "spacelift resources", "spacelift policies",
  "controlla spacelift", "log spacelift", "anteprima locale spacelift",
  "stato spacelift", "perché spacelift ha fallito", "lancia run spacelift".
---

# Spacelift Skill

Interact with Spacelift CI/CD to inspect stacks, read run logs, debug failures, run local previews, and manage infrastructure runs.

This skill supports two modes of operation:

- **MCP tools** (preferred): Use the `spacelift.spacectl-mcp` MCP server tools (prefixed `mcp__spacelift_spacectl-mcp__`). These are the primary interface.
- **CLI fallback**: Use `spacectl` via Bash when MCP tools are unavailable or for operations not covered by MCP (e.g., `spacectl stack dependencies`).

## Prerequisites

- `spacectl` must be installed (via `mise install spacectl` or direct download)
- Authentication requires these environment variables:
  - `SPACELIFT_API_KEY_ENDPOINT` — Spacelift instance URL (e.g. `https://mycompany.app.spacelift.io`)
  - `SPACELIFT_API_GITHUB_TOKEN` — GitHub token for Spacelift API auth

## Tools Used

- **Spacelift MCP** (`spacelift.spacectl-mcp`): `list_stacks`, `get_stack_run`, `get_stack_run_logs`, `get_stack_run_changes`, `list_stack_runs`, `list_stack_proposed_runs`, `local_preview`, `trigger_stack_run`, `confirm_stack_run`, `discard_stack_run`, `list_resources`, `list_contexts`, `list_policies`, `list_modules`, `introspect_graphql_schema`, and others.
- **Bash**: CLI fallback via `spacectl` commands, and for operations like `spacectl stack dependencies` not available via MCP.
- **ToolSearch**: Discover available Spacelift MCP tools at runtime.

## Step 0: Detect Available Tools

Before executing any operation, check which tools are available:

1. Use **ToolSearch** with query `spacelift` to discover MCP tools
2. If MCP tools are found (names starting with `mcp__spacelift_spacectl-mcp__`), use them as primary interface
3. If MCP tools are NOT available, fall back to CLI commands via Bash:
   - All `spacectl` commands must be prefixed with: `eval "$(mise activate bash)" && spacectl ...`
   - Verify authentication with `spacectl whoami`

## Capabilities

### 1. List Stacks

**MCP**: `list_stacks` — supports `search`, `limit`, and `next_page_cursor` parameters for pagination and filtering.

**CLI fallback**:
```bash
spacectl stack list -o json
```

### 2. Show Stack Details

**MCP**: Use `list_stacks` with `search` parameter to find the stack, or use GraphQL via `get_graphql_type_details` for schema exploration.

**CLI fallback**:
```bash
spacectl stack show --id <stack-slug> -o json
```

### 3. List Runs for a Stack

**MCP**:
- Tracked runs (triggered by pushes): `list_stack_runs` with `stack_id`
- Preview runs (triggered by PRs): `list_stack_proposed_runs` with `stack_id`

Both support `next_page_cursor` for pagination.

**CLI fallback**:
```bash
spacectl stack run list --id <stack-slug> -o json
spacectl stack run list --id <stack-slug> --preview-runs -o json
```

### 4. Find Run ID from Current Branch

1. Get current branch: `git branch --show-current`
2. Use `list_stack_proposed_runs` (MCP) or `spacectl stack run list --preview-runs` (CLI) for the stack
3. Filter results by `branch` field matching current git branch

**Alternative — from a PR:** Use GitHub MCP tools to get PR check runs. Spacelift checks have names like `spacelift/<stack-slug>` and the `details_url` contains the run URL with the run ID as the last path segment.

### 5. Read Run Logs

**MCP** (recommended): `get_stack_run_logs` with `stack_id` and `run_id`. Supports `skip` and `limit` for pagination through large logs.

**CLI fallback**:
```bash
spacectl stack logs --id <stack-slug> --run <run-id>
```

Optional CLI flags:
- `--phase PLANNING` or `--phase APPLYING` — filter by phase
- `--run-latest` — use latest run
- `--tail` — tail live logs

**Via GraphQL API** (for granular phase-level logs):
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

**Strip ANSI codes** from CLI log output for readability: pipe through `sed 's/\x1b\[[0-9;]*m//g'`.

### 6. Show Run Details and Changes

**MCP**:
- Run details: `get_stack_run` with `stack_id` and `run_id`
- Resource changes: `get_stack_run_changes` with `stack_id` and `run_id`

**CLI fallback**:
```bash
spacectl stack changes --id <stack-slug> --run <run-id>
```

### 7. Run Local Preview

**MCP** (recommended): `local_preview` with `stack_id`. Supports:
- `path` — local workspace path (defaults to current directory)
- `await_for_completion` — `"true"` to wait and return logs, `"false"` to trigger and return
- `targets` — array of specific resources to target
- `environment_variables` — additional env vars for the run

**CLI fallback**:
```bash
spacectl stack local-preview --id <stack-slug>
```

Optional CLI flags:
- `--no-tail` — don't stream logs
- `--target <resource>` — target specific resources
- `--project-root-only` — only package project root files
- `--prioritize-run` — prioritize in queue

### 8. Stack Dependencies

**CLI only** (not available via MCP):
```bash
spacectl stack dependencies on --id <stack-slug>    # stacks this one depends on
spacectl stack dependencies off --id <stack-slug>   # stacks that depend on this one
```

### 9. Run Management

**MCP**:
- Confirm a run: `confirm_stack_run` with `stack_id` and `run_id`
- Discard a run: `discard_stack_run` with `stack_id` and `run_id`
- Trigger a new run: `trigger_stack_run` with `stack_id`, optional `run_type` (`PROPOSED` or `TRACKED`) and `commit_sha`

**CLI fallback**:
```bash
spacectl stack retry --id <stack-slug> --run <run-id>
spacectl stack confirm --id <stack-slug> --run <run-id>
spacectl stack discard --id <stack-slug> --run <run-id>
spacectl stack deploy --id <stack-slug>
spacectl stack cancel --id <stack-slug> --run <run-id>
```

### 10. List Resources

**MCP**: `list_resources` — optionally filter by `stack_id` to see resources managed by a specific stack.

### 11. Contexts and Policies

**MCP**:
- List contexts: `list_contexts` with optional `search`, `limit`
- Search contexts: `search_contexts` with `labels`, `space` filters
- Get context details: `get_context` with `context_id`
- List policies: `list_policies` with optional `search`
- Get policy details: `get_policy` with `policy_id`
- Policy samples: `list_policy_samples`, `get_policy_sample`

### 12. Modules

**MCP**:
- List modules: `list_modules` with optional `search`
- Search modules: `search_modules` with `terraform_provider`, `labels`, `space` filters
- Module details: `get_module` with `module_id`
- Module versions: `list_module_versions`, `get_module_version`
- Module guide: `get_module_guide` for operational guidance

### 13. GraphQL Schema Exploration

**MCP**:
- Full schema: `introspect_graphql_schema` with `format` (`summary` or `detailed`)
- Search fields: `search_graphql_schema_fields` with `search_term` and `search_scope`
- Type details: `get_graphql_type_details` with `type_name`

**CLI fallback**:
```bash
spacectl api --schema   # dump full schema
```

### 14. Advanced GraphQL Queries (CLI only)

For custom queries not covered by MCP tools:

```bash
spacectl api '
query {
  stack(id: "<stack-slug>") {
    id name branch repository projectRoot
    trackedRun { id state title }
  }
}'
```

## Workflow: Debug a Failed Spacelift Run

1. **Identify the run** — use `list_stack_proposed_runs` or `list_stack_runs` to find the failed run, or get it from PR check runs
2. **Get run details** — use `get_stack_run` to see state and history
3. **Fetch logs** — use `get_stack_run_logs` to read the error output. For large logs, use `skip` and `limit` to paginate
4. **Get changes** — use `get_stack_run_changes` to see what resources were affected
5. **Parse the error** — look for Terraform error blocks (`Error:` lines), strip ANSI codes if using CLI
6. **Present findings** — show the relevant error with context and suggest fixes

## Workflow: Check Stack Status After Push

1. Get current branch: `git branch --show-current`
2. Determine which stack is affected (from project root or ask user)
3. Use `list_stack_proposed_runs` filtering by branch
4. If a run exists, show its state and delta via `get_stack_run`
5. If FAILED, automatically fetch and present logs via `get_stack_run_logs`

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP tools not available | Fall back to CLI commands via Bash. Ensure `spacectl` is installed with `mise install spacectl` |
| spacectl not found | Run `mise install spacectl` to install it |
| Authentication failure | Check `SPACELIFT_API_GITHUB_TOKEN` and `SPACELIFT_API_KEY_ENDPOINT` env vars |
| Stack not found | Use `list_stacks` with search to find the correct slug |
| Run not found | Use `list_stack_runs` or `list_stack_proposed_runs` to verify the run ID |
| GraphQL error | Use `introspect_graphql_schema` or `search_graphql_schema_fields` to check available fields |
| No preview runs for branch | The PR may not have triggered Spacelift yet, or the stack may not watch that repository |
| Large log output | Use `skip` and `limit` parameters with `get_stack_run_logs` to paginate |
