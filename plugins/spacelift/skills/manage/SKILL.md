---
name: spacelift:manage
description: |
  This skill should be used when the user wants to manage Spacelift runs:
  confirm a pending run, discard a run, trigger a new deployment, retry a
  failed run, or cancel a queued run.
  Activates on: "confirm run", "confirm spacelift", "discard run", "discard spacelift",
  "trigger run", "trigger spacelift", "deploy spacelift", "retry spacelift",
  "cancel run", "cancel spacelift", "run spacelift", "lancia spacelift",
  "conferma run", "scarta run", "annulla run spacelift", "rilancia spacelift".
---

# Spacelift Manage Skill

Manage Spacelift runs: confirm, discard, trigger, retry, and cancel runs.

**Reference files:** Consult `reference/spacectl-tools.md` for the full MCP tool catalog and CLI equivalents.

## Tools Used

- **Spacelift MCP** (`spacelift.spacectl-mcp`): `confirm_stack_run`, `discard_stack_run`, `trigger_stack_run`, `list_stack_runs`, `list_stack_proposed_runs`, `get_stack_run`
- **Bash**: CLI fallback via `spacectl` (also covers `retry` and `cancel` not available via MCP)
- **ToolSearch**: Discover available Spacelift MCP tools
- **AskUserQuestion**: Confirmation before destructive actions

## Workflow

### Step 1: Detect Tools

Use **ToolSearch** with query `spacelift` to check if MCP tools are available. See `reference/spacectl-tools.md` § Tool Detection.

### Step 2: Identify the Action

| User intent | MCP Tool | CLI Equivalent |
|-------------|----------|----------------|
| Confirm a pending run | `confirm_stack_run` | `spacectl stack confirm --id <slug> --run <id>` |
| Discard a pending run | `discard_stack_run` | `spacectl stack discard --id <slug> --run <id>` |
| Trigger a tracked deployment | `trigger_stack_run` (type: `TRACKED`) | `spacectl stack deploy --id <slug>` |
| Trigger a proposed run | `trigger_stack_run` (type: `PROPOSED`) | N/A |
| Retry a failed run | N/A (CLI only) | `spacectl stack retry --id <slug> --run <id>` |
| Cancel a queued run | N/A (CLI only) | `spacectl stack cancel --id <slug> --run <id>` |

### Step 3: Find the Run (if not provided)

If the user only provided a stack name:

1. Use `list_stack_runs` to find tracked runs pending confirmation (state `UNCONFIRMED`)
2. Use `list_stack_proposed_runs` for preview runs
3. Present the candidate run to the user for confirmation

### Step 4: Confirm Before Acting

**Always ask for confirmation** before executing destructive actions:

- Confirming a run → show the run's delta (resource changes) and ask: "This will apply +X ~Y -Z changes. Confirm?"
- Discarding → show what will be discarded and ask: "Discard run `<id>` on `<stack>`?"
- Triggering a deployment → show the stack and ask: "Trigger a new tracked run on `<stack>`?"

Use `get_stack_run` and `get_stack_run_changes` to gather the details needed for the confirmation prompt.

### Step 5: Execute and Report

Execute the action and report the result:

```
Run `<run-id>` on stack `<stack-slug>` confirmed. The apply phase is now in progress.
```

For triggered runs, report the new run ID so the user can track it.

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP tools not available | Fall back to CLI. See `reference/spacectl-tools.md` § CLI Equivalents |
| Run not in expected state | Show current state — e.g., "Run is FINISHED, nothing to confirm" |
| No pending runs found | List recent runs and show their states |
| Permission denied | Check Spacelift account permissions and API key scopes |
| Authentication failure | Check `SPACELIFT_API_GITHUB_TOKEN` and `SPACELIFT_API_KEY_ENDPOINT` env vars |

## Reference Files

- `reference/spacectl-tools.md` — Full MCP tool catalog, CLI equivalents, GraphQL queries
