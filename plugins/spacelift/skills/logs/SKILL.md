---
name: spacelift:logs
description: |
  This skill should be used when the user wants to read Spacelift run logs,
  inspect a specific run, view resource changes, or find the run associated
  with a branch or PR.
  Activates on: "spacelift logs", "spacelift run", "show run", "run logs",
  "read logs", "spacelift changes", "run details", "find run", "run for this branch",
  "spacelift run status", "what changed in the run",
  "log spacelift", "mostra log", "dettagli run", "modifiche run spacelift".
---

# Spacelift Logs Skill

Read Spacelift run logs, inspect run details, view resource changes, and find runs by branch or PR.

**Reference files:** Consult `reference/spacectl-tools.md` for the full MCP tool catalog and CLI equivalents.

## Tools Used

- **Spacelift MCP** (`spacelift.spacectl-mcp`): `get_stack_run`, `get_stack_run_logs`, `get_stack_run_changes`, `list_stack_runs`, `list_stack_proposed_runs`
- **Bash**: CLI fallback via `spacectl`
- **ToolSearch**: Discover available Spacelift MCP tools

## Workflow

### Step 1: Detect Tools

Use **ToolSearch** with query `spacelift` to check if MCP tools are available. See `reference/spacectl-tools.md` § Tool Detection.

### Step 2: Identify the Run

The user may provide:

- **Stack + run ID** → use directly
- **Stack only** → list runs and pick the latest (tracked or proposed depending on context)
- **Branch name** → `list_stack_proposed_runs`, filter by branch
- **"Current branch"** → `git branch --show-current`, then filter proposed runs
- **PR reference** → use GitHub MCP tools (`pull_request_read` with `method: get_check_runs`) to find the Spacelift check. The `details_url` contains the run URL with the run ID as the last path segment.
- **Nothing** → ask the user for a stack name, then list recent runs

### Step 3: Fetch Run Details

Use `get_stack_run` (MCP) to get:
- Run state, type, branch, commit
- Created/updated timestamps
- Delta (resource add/change/delete counts)

### Step 4: Fetch Logs

Use `get_stack_run_logs` (MCP) with `stack_id` and `run_id`.

- For large logs, use `skip` and `limit` to paginate (e.g., `skip: 0, limit: 200`, then `skip: 200, limit: 200`)
- Focus on the end of logs where errors typically appear — use a high `skip` value
- If using CLI fallback, strip ANSI codes: pipe through `sed 's/\x1b\[[0-9;]*m//g'`

For **phase-level logs** (not available via MCP), use the GraphQL query in `reference/spacectl-tools.md` § Phase-level logs.

### Step 5: Fetch Changes (if relevant)

Use `get_stack_run_changes` (MCP) to show which resources were added, changed, or destroyed.

### Step 6: Present Results

Format as:

```
**Run** `<run-id>` on stack `<stack-slug>`
**State**: FINISHED | FAILED | PLANNING | ...
**Branch**: feature/my-change
**Delta**: +3 ~1 -0

<log output or relevant excerpt>
```

For resource changes, show a table:

```
| Action | Resource | Address |
|--------|----------|---------|
| + add  | aws_s3_bucket | module.storage.aws_s3_bucket.main |
| ~ update | aws_iam_role | module.iam.aws_iam_role.lambda |
```

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP tools not available | Fall back to CLI. See `reference/spacectl-tools.md` § CLI Equivalents |
| Run not found | List runs for the stack with `list_stack_runs` or `list_stack_proposed_runs` and verify the run ID |
| No preview runs for branch | The PR may not have triggered Spacelift yet, or the stack doesn't watch that repo |
| Large log output | Use `skip` and `limit` to paginate, or focus on the tail |
| Authentication failure | Check `SPACELIFT_API_GITHUB_TOKEN` and `SPACELIFT_API_KEY_ENDPOINT` env vars |

## Reference Files

- `reference/spacectl-tools.md` — Full MCP tool catalog, CLI equivalents, GraphQL queries
