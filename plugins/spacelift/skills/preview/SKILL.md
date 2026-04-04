---
name: spacelift:preview
description: |
  This skill should be used when the user wants to run a Spacelift local
  preview, trigger a proposed run from the current workspace, or test
  infrastructure changes before pushing.
  Activates on: "local preview", "spacelift preview", "preview spacelift",
  "test changes spacelift", "run preview", "spacelift local", "try changes",
  "anteprima locale", "anteprima spacelift", "provare modifiche spacelift".
---

# Spacelift Preview Skill

Run local previews to test Terraform changes against Spacelift before pushing. Packages local files, uploads to Spacelift, and executes a plan.

**Reference files:** Consult `reference/spacectl-tools.md` for the full MCP tool catalog and CLI equivalents.

## Tools Used

- **Spacelift MCP** (`spacelift.spacectl-mcp`): `local_preview`, `list_stacks`
- **Bash**: CLI fallback via `spacectl stack local-preview`
- **ToolSearch**: Discover available Spacelift MCP tools

## Workflow

### Step 1: Detect Tools

Use **ToolSearch** with query `spacelift` to check if MCP tools are available. See `reference/spacectl-tools.md` § Tool Detection.

### Step 2: Identify the Stack

If the user didn't specify a stack:

1. Check if the current directory is within a Terraform module (look for `*.tf` files)
2. Use `list_stacks` to search for stacks matching the repository or project root
3. If multiple matches, ask the user to pick one

### Step 3: Run Local Preview

**MCP** (recommended): `local_preview` with:
- `stack_id` — the target stack slug
- `path` — workspace path (defaults to current directory)
- `await_for_completion` — set to `"true"` to wait for results (recommended)
- `targets` — array of specific resources to target (optional, for focused previews)
- `environment_variables` — additional env vars for the run (optional)

**CLI fallback**:
```bash
spacectl stack local-preview --id <stack-slug>
```

Optional CLI flags:
- `--target <resource>` — target specific resources
- `--no-tail` — don't stream logs (just trigger and return)
- `--project-root-only` — only package files in the project root
- `--prioritize-run` — prioritize this run in the queue

### Step 4: Present Results

Once the preview completes, present:

1. **Run state**: FINISHED (success) or FAILED
2. **Resource delta**: how many resources will be added, changed, or destroyed
3. **Key changes**: summarize the most significant planned changes
4. **Errors** (if failed): extract and present the error with suggestions

Format as:

```
## Local Preview Results

**Stack**: `<stack-slug>`
**State**: FINISHED
**Delta**: +2 ~1 -0

### Planned Changes
| Action | Resource | Address |
|--------|----------|---------|
| + add  | aws_s3_bucket | module.storage.aws_s3_bucket.logs |
| ~ update | aws_iam_policy | module.iam.aws_iam_policy.access |
```

If the preview failed, invoke the debug workflow from `/spacelift:debug`.

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP tools not available | Fall back to CLI. See `reference/spacectl-tools.md` § CLI Equivalents |
| Stack not found | Use `list_stacks` with search to find the correct slug |
| Preview times out | The run may be queued behind other runs. Check with `get_stack_run` |
| Upload fails | Check that `.gitignore` and `.terraformignore` aren't excluding needed files |
| Authentication failure | Check `SPACELIFT_API_GITHUB_TOKEN` and `SPACELIFT_API_KEY_ENDPOINT` env vars |

## Reference Files

- `reference/spacectl-tools.md` — Full MCP tool catalog, CLI equivalents, GraphQL queries
