---
name: spacelift:status
description: |
  This skill should be used when the user wants to list Spacelift stacks,
  check stack status, show stack details, view dependencies, or get an
  overview of their Spacelift infrastructure.
  Activates on: "spacelift", "spacelift status", "list stacks", "spacelift stacks",
  "check spacelift", "show stack", "stack details", "spacelift dependencies",
  "spacelift resources", "spacelift overview",
  "stato spacelift", "controlla spacelift", "lista stack", "dipendenze spacelift".
---

# Spacelift Status Skill

List and inspect Spacelift stacks, check their status, view dependencies, and browse managed resources.

**Reference files:** Consult `reference/spacectl-tools.md` for the full MCP tool catalog, CLI equivalents, and GraphQL queries.

## Tools Used

- **Spacelift MCP** (`spacelift.spacectl-mcp`): `list_stacks`, `list_resources`, `list_contexts`, `list_spaces`
- **Bash**: CLI fallback via `spacectl`, stack dependencies (CLI only)
- **ToolSearch**: Discover available Spacelift MCP tools

## Workflow

### Step 1: Detect Tools

Use **ToolSearch** with query `spacelift` to check if MCP tools are available. See `reference/spacectl-tools.md` § Tool Detection.

### Step 2: Identify Request

Determine what the user wants:

| User intent | Action |
|-------------|--------|
| List all stacks | `list_stacks` (MCP) or `spacectl stack list -o json` (CLI) |
| Search for a stack | `list_stacks` with `search` param |
| Stack details | `list_stacks` with `search` to find it, then present details |
| Stack dependencies | `spacectl stack dependencies on/off --id <slug>` (CLI only) |
| Resources for a stack | `list_resources` with `stack_id` |
| All resources | `list_resources` without filters |
| Contexts / Spaces | `list_contexts`, `list_spaces` |

### Step 3: Present Results

Format output as a summary table:

```
| Stack | Status | Branch | Repository |
|-------|--------|--------|------------|
| my-stack | FINISHED | main | org/repo |
```

For a single stack, show full details: name, slug, branch, repository, project root, labels, current state, and latest tracked run status.

### Step 4: Check Status After Push (if relevant)

If the user is on a feature branch and wants to know if Spacelift picked up their changes:

1. Get current branch: `git branch --show-current`
2. Determine the relevant stack (from project root or ask the user)
3. Use `list_stack_proposed_runs` to find preview runs for the branch
4. Report the latest run state and delta

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP tools not available | Fall back to CLI. See `reference/spacectl-tools.md` § CLI Equivalents |
| Authentication failure | Check `SPACELIFT_API_GITHUB_TOKEN` and `SPACELIFT_API_KEY_ENDPOINT` env vars |
| Stack not found | Use `list_stacks` with search to find the correct slug |
| No stacks returned | Verify authentication and permissions on the Spacelift account |

## Reference Files

- `reference/spacectl-tools.md` — Full MCP tool catalog, CLI equivalents, GraphQL queries
