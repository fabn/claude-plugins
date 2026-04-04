---
name: spacelift:debug
description: |
  This skill should be used when the user wants to debug a failed Spacelift
  run, understand why a plan or apply failed, or investigate Spacelift errors.
  Follows a structured workflow: identify the failed run, fetch history and
  logs, parse errors, and present findings with fix suggestions.
  Activates on: "why did spacelift fail", "spacelift plan failed", "spacelift error",
  "debug spacelift", "spacelift apply failed", "spacelift failure", "fix spacelift",
  "what went wrong spacelift", "spacelift broken",
  "perché spacelift ha fallito", "errore spacelift", "spacelift rotto",
  "debug spacelift", "correggi spacelift".
---

# Spacelift Debug Skill

Debug failed Spacelift runs: identify the failure, fetch logs, parse Terraform errors, and suggest fixes.

**Reference files:** Consult `reference/spacectl-tools.md` for the full MCP tool catalog and CLI equivalents.

## Tools Used

- **Spacelift MCP** (`spacelift.spacectl-mcp`): `list_stack_proposed_runs`, `list_stack_runs`, `get_stack_run`, `get_stack_run_logs`, `get_stack_run_changes`
- **Bash**: CLI fallback, GraphQL queries for phase-level history
- **ToolSearch**: Discover available Spacelift MCP tools

## Workflow

### Step 1: Detect Tools

Use **ToolSearch** with query `spacelift` to check if MCP tools are available. See `reference/spacectl-tools.md` § Tool Detection.

### Step 2: Identify the Failed Run

Try these approaches in order:

1. **User provided stack + run ID** → use directly
2. **User provided stack only** → list recent runs, find the one with FAILED state
3. **User mentions "this PR" or "this branch"** →
   - Get branch: `git branch --show-current`
   - `list_stack_proposed_runs` for the stack, filter by branch
   - Pick the most recent FAILED run
4. **User mentions a PR** → use GitHub MCP to get check runs, find the Spacelift check with failed status
5. **No context** → ask for a stack name, then search for recent failures

### Step 3: Get Run History

Use `get_stack_run` (MCP) to see the run's current state and metadata.

For **phase-level history** (which phase failed and when), use the GraphQL query:

```bash
spacectl api '
query {
  stack(id: "<stack-slug>") {
    run(id: "<run-id>") {
      state
      history { state timestamp note }
    }
  }
}'
```

The `history` array shows state transitions. Look for the last state before `FAILED` — this tells you which phase failed (PLANNING, APPLYING, INITIALIZING, etc.).

### Step 4: Fetch Logs

Use `get_stack_run_logs` (MCP) with `stack_id` and `run_id`.

**Strategy for large logs:**
1. First fetch the tail (e.g., `skip: 500, limit: 200`) — errors are usually near the end
2. If no errors found, fetch from the beginning to understand the full context
3. Look for these Terraform error patterns:
   - `Error:` lines (main error message)
   - `on <file> line <N>:` (location)
   - `resource "<type>" "<name>"` (affected resource)
   - `│` bordered blocks (Terraform diagnostic output)

For **phase-specific logs** via CLI GraphQL:

```bash
spacectl api '
query {
  stack(id: "<stack-slug>") {
    run(id: "<run-id>") {
      logs(state: PLANNING) {
        messages { message timestamp }
      }
    }
  }
}'
```

### Step 5: Get Resource Changes

Use `get_stack_run_changes` (MCP) to see what resources were being modified when the failure occurred.

### Step 6: Present Findings

Structure the output as:

```
## Failed Run Analysis

**Stack**: `<stack-slug>`
**Run**: `<run-id>`
**Failed Phase**: PLANNING / APPLYING / INITIALIZING
**Failed At**: <timestamp>

### Error

<extracted error message, clean of ANSI codes>

### Affected Resources

<table of resources being changed>

### Suggested Fix

<analysis of the error with actionable suggestions>
```

Common error categories and suggestions:

| Error Pattern | Likely Cause | Suggestion |
|---------------|-------------|------------|
| `Error: Reference to undeclared resource` | Resource renamed/removed | Check resource references in the module |
| `Error: Invalid provider configuration` | Missing or wrong provider config | Verify provider block and credentials |
| `Error: Error acquiring the state lock` | Concurrent run or stale lock | Wait or force-unlock if stale |
| `Error: Unsupported attribute` | Provider version mismatch | Check provider version constraints |
| `Error: Error creating/updating <resource>` | AWS/cloud API error | Check IAM permissions and resource limits |
| `exit status 1` with no Terraform error | Init or hook failure | Check INITIALIZING phase logs |

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP tools not available | Fall back to CLI. See `reference/spacectl-tools.md` § CLI Equivalents |
| No FAILED runs found | Confirm with user — maybe the run is still in progress or succeeded |
| Logs are empty | Try fetching with different skip/limit, or use GraphQL for phase-specific logs |
| Error is in INITIALIZING phase | Check for `.spacelift/` hooks, provider init issues, or backend config problems |
| Authentication failure | Check `SPACELIFT_API_GITHUB_TOKEN` and `SPACELIFT_API_KEY_ENDPOINT` env vars |

## Reference Files

- `reference/spacectl-tools.md` — Full MCP tool catalog, CLI equivalents, GraphQL queries
