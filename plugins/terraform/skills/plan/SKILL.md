---
name: terraform:plan
description: |
  This skill should be used when the user wants to run a Terraform plan,
  analyze infrastructure changes, preview what resources will be created,
  modified, or destroyed, or get a safety-categorized summary of pending changes.
  Activates on: "terraform plan", "run plan", "check changes", "what will terraform do",
  "plan terraform", "show pending changes", "infrastructure diff", "preview changes",
  "infrastructure changes", "what changes", "piano terraform", "pianifica terraform",
  "controlla modifiche", "anteprima modifiche", "differenze infrastruttura".
---

# Terraform Plan Skill

Run a Terraform plan and present a safety-categorized summary of pending infrastructure changes. This skill covers plan execution and output presentation only — applying changes is handled by `/terraform:apply`.

## Tools Used

- **AskUserQuestion**: Module selection when multiple modules are found, and scoped-plan confirmation in mixed-plan flow.

## Workflow

### Step 1: Discover Modules

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Module Discovery algorithm (Section 2), executing all Glob, Bash, and MCP tool calls in the current session. Do NOT spawn a subagent.
Return: sorted list of relative module paths (relative to git root), or the message "No Terraform root modules found in this repository." if none exist.

Based on the agent's response:

**If 0 modules found:**

Show:
```
No Terraform modules found. Run terraform init in your module directory first.
```
Stop.

**If 1 module found:**

Show:
```
Found 1 module: {relative_path} — running plan...
```
Resolve the absolute path (`git_root + "/" + relative_path`). Proceed to Step 2.

**If 2+ modules found:**

Present the numbered list via AskUserQuestion:
```
Found {N} Terraform modules:

  1. {relative_path_1}
  2. {relative_path_2}
  ...

Which module? (1-{N}):
```

Wait for the user to type a number. If the input is not a valid number between 1 and N, re-show the list with:
```
Please enter a number between 1 and {N}.
```

Resolve the selected absolute path (`git_root + "/" + selected_relative_path`). Proceed to Step 2.

### Step 2: Run Plan

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) and Safety Categorization (Section 3) instructions, executing all MCP tool calls in the current session. Do NOT spawn a subagent.
Working directory: `{absolute_module_path}`
Return: categorized resource list (SAFE/RISKY/DESTRUCTIVE), one-line impact description per resource in plain operational English, total counts per category, and a "No changes" signal if infrastructure matches configuration.

**If plan fails with init required:**

Auto-run: Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution instructions (Section 1) to run `terraform init -backend=false` for the module at `{absolute_module_path}`, then re-run terraform plan, executing all MCP tool calls in the current session. Do NOT spawn a subagent. Do NOT use the -upgrade flag.
Return: categorized resource list as above, or the error output if init or plan fails.

If init fails, surface the error and tell the user:
```
Run `terraform init -backend=false` in `{module_path}` manually and re-run /terraform:plan.
```

**If plan fails with any other error:**

Show the raw error output from the agent.
Append:
```
Fix the error above and re-run /terraform:plan.
```
Stop.

**If plan succeeds:** Proceed to Step 3.

### Step 3: Present Plan Results

**If no changes:**

Show:
```
✓ No changes. Infrastructure matches configuration.
```
Done.

**If changes are present:**

Render the summary line (omit zero-count categories):
```
Plan: {total} changes — {N} destructive, {N} risky, {N} safe
```

Render only non-empty sections in order DESTRUCTIVE → RISKY → SAFE:
```
🔴 DESTRUCTIVE (N)
  {resource_name} — {one-line impact description}

🟡 RISKY (N)
  {resource_name} — {one-line impact description}

🟢 SAFE (N)
  {resource_name} — {one-line impact description}
```

If only one category has changes, show only that section — the absence of other sections is itself reassuring.

Proceed to Step 4.

### Step 4: Mixed Plan — Targeted Suggestion

Only execute this step if the plan has BOTH safe resources AND risky or destructive resources (i.e., it is a mixed plan).

**If DESTRUCTIVE resources are present, show this warning block first:**
```
⚠️  DESTRUCTIVE changes detected. The resources listed below as safe-to-target
    do NOT include: {comma-separated destructive resource names}.
    Those changes require separate review and must not be applied without explicit confirmation.
```

Then list the safe resources and ask via AskUserQuestion:
```
Safe resources available for a scoped plan:
  • {safe_resource_1}
  • {safe_resource_2}

Run a scoped plan for just the SAFE resources? [yes/no]
```

**If user says yes:**

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) and Safety Categorization (Section 3) instructions, executing all MCP tool calls in the current session. Do NOT spawn a subagent.
Working directory: `{absolute_module_path}`
Target only these resources: [{safe_resource_1}, {safe_resource_2}, ...]
Return: categorized output in the same format (SAFE/RISKY/DESTRUCTIVE counts and per-resource one-line impact descriptions).

Present the scoped plan result using the same format from Step 3 (summary line + non-empty emoji sections).

**If user says no:**

End gracefully. No further action.

## Error Handling

| Situation | Action |
|-----------|--------|
| No modules found | Show "No Terraform modules found. Run terraform init in your module directory first." Stop. |
| User types invalid module number | Re-show the numbered list via AskUserQuestion. Show "Please enter a number between 1 and {N}." |
| Plan fails — init required | Auto-run terraform init -backend=false (no consent prompt, no -upgrade flag). Retry plan. If init fails: tell user to run manually. |
| Plan fails — auth/credential error | Show raw error from agent. Append "Fix the error above and re-run /terraform:plan." Stop. |
| Plan fails — missing variables | Show raw error from agent. Append "Fix the error above and re-run /terraform:plan." Stop. |
| Any other plan error | Show raw error from agent. Append "Fix the error above and re-run /terraform:plan." Stop. |
| Mixed plan without DESTRUCTIVE | Show safe-resource list and scoped plan offer. No warning block needed. |
| Mixed plan with DESTRUCTIVE | Show DESTRUCTIVE warning block first, then safe-resource list and scoped plan offer. |
| Unusually large plan (>50 resources) | Group by resource type, show count per type, offer to show full list on request. |
