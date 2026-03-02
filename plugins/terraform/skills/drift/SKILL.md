---
name: terraform:drift
description: |
  This skill should be used when the user wants to detect infrastructure drift,
  identify resources where remote state differs from Terraform code, review
  proposed code changes as diffs, approve alignment, and commit verified code.
  Activates on: "terraform drift", "detect drift", "check drift", "infrastructure drift",
  "state drift", "drift detection", "align code with state", "sync terraform state",
  "deriva terraform", "controlla deriva", "allinea codice", "sincronizza stato".
---

# Terraform Drift Skill

Detect infrastructure drift via Terraform plan, propose `.tf` code alignment diffs, get batch approval, re-verify with `terraform fmt`/`validate`/`plan`, and commit verified aligned code. This skill covers drift detection and resolution only — applying infrastructure changes (recreating remotely-deleted resources) is handled by `/terraform:apply`.

## Tools Used

- **AskUserQuestion**: Module selection when multiple modules are found, destructive drift A/B choice per resource, and batch approval gate before applying code edits.
- **Bash**: Git commit after a clean re-verification plan confirms zero changes.

## Workflow

### Step 1: Discover Modules

If the user invoked the skill with a path argument (e.g., `/terraform:drift modules/vpc`), skip discovery and use that path resolved to an absolute path as `absolute_module_path` directly. Proceed to Step 2.

Otherwise:

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
Found 1 module: {relative_path} — running drift detection...
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

### Step 2: Run Plan and Detect Drift

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) and Safety Categorization (Section 3) instructions, executing all MCP tool calls in the current session. Do NOT spawn a subagent.
Working directory: `{absolute_module_path}`
Return: categorized resource list (SAFE/RISKY/DESTRUCTIVE), one-line impact description per resource in plain operational English, total counts per category, and a "No changes" signal if infrastructure matches configuration.

**If plan fails with init required:**

Auto-run: Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution instructions (Section 1) to run `terraform init -backend=false` for the module at `{absolute_module_path}`, then re-run terraform plan, executing all MCP tool calls in the current session. Do NOT spawn a subagent. Do NOT use the -upgrade flag.
Return: categorized resource list as above, or the error output if init or plan fails.

If init fails, surface the error and tell the user:
```
Run `terraform init -backend=false` in `{module_path}` manually and re-run /terraform:drift.
```
Stop.

**If plan fails with any other error:**

Show the raw error output from the agent.
Append:
```
Fix the error above and re-run /terraform:drift.
```
Stop.

**If plan returns no changes:**

Show:
```
No drift detected — remote state matches your code.
```
Stop.

**If plan returns changes**, classify each resource:

- **DESTRUCTIVE drift**: resource exists in `.tf` code AND plan shows `will be destroyed` — meaning the resource no longer exists in remote state (remote deleted it). Cross-check: confirm the resource block exists in the `.tf` files. If it does AND plan shows destruction → DESTRUCTIVE drift.
- **Normal drift**: attribute-level mismatches (remote state has values that differ from code — updates, in-place changes).

Show summary header:
```
{N} resources drifted: {resource1}, {resource2}, ...
```
(List all drifted resources, both destructive and normal.)

Proceed to Step 3 if any DESTRUCTIVE drift resources exist; otherwise skip to Step 4.

### Step 3: DESTRUCTIVE Drift Gate

This step MUST complete for all destructive resources before Step 4 begins.

For each destructive resource, show the hard gate block:

```
DESTRUCTIVE DRIFT: {resource_name}

This resource exists in your .tf code but was deleted from remote infrastructure.

Possible causes:
  - Intentionally deleted via AWS Console or CLI
  - Terminated by another automation or lifecycle policy
  - Removed by another Terraform run outside this codebase

Choose an action:
  (A) Remove from .tf code — aligns code with remote state (resource stays deleted)
  (B) Recreate via terraform apply — restores the resource to match your code
```

Ask via AskUserQuestion: `"Enter A or B for {resource_name}:"`

**If user chooses A:** Note this resource for inclusion in the Step 4 diff batch as a deletion diff (remove the entire resource block from the `.tf` file). Continue to next destructive resource.

**If user chooses B:** Show:
```
To recreate {resource_name}, run /terraform:apply after this drift session.
```
Exclude this resource from code alignment. Continue to next destructive resource.

**Edge case — all drift was destructive and user chose B for all of them:**
```
No code changes to commit. Run /terraform:apply to recreate the deleted resources.
```
Stop.

### Step 4: Present Normal Drift Diffs and Batch Approval Gate

First, instruct the agent to generate diffs WITHOUT applying:

Read `plugins/terraform/agents/terraform-engineer.md` and follow its File Operations (Section 4) instructions, executing all Read and Grep tool calls in the current session. Do NOT spawn a subagent.
For each drifted resource (including destructive resources where user chose A):
- Read the current `.tf` file content
- Compare with remote state values from the plan output
- Produce a before/after diff in `.tf` file syntax showing which lines would change

IMPORTANT: Do NOT apply any edits. Return the complete set of proposed diffs only.

Present all diffs as inline before/after blocks per resource:
```
Proposed code changes to align with remote state:

--- {relative_tf_file_path} ({resource_name})
- {old_line}
+ {new_line}

--- {relative_tf_file_path} ({resource_name_2})
+ {new_block_lines}
```

Then ask via AskUserQuestion:
```
Apply all {N} code changes above? [yes/no]
```

**If user says no:**
```
Changes not applied. Drift still exists on: {resource list}
```
Stop.

**If user says yes:** Instruct the agent to apply all proposed edits via File Operations (Section 4), using the same inline agent reference pattern:

Read `plugins/terraform/agents/terraform-engineer.md` and follow its File Operations (Section 4) instructions, executing all Edit tool calls in the current session. Do NOT spawn a subagent.
Apply all proposed edits from the diff set above to the relevant `.tf` files.

Proceed to Step 5.

### Step 5: Re-verify and Commit

After edits are applied, run in sequence:

**1. terraform fmt**

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) instructions to run `terraform fmt` for the module at `{absolute_module_path}`, executing all MCP tool calls in the current session. Do NOT spawn a subagent.

If `ExecuteTerraformCommand` does not support fmt, fall back to:
```bash
Bash: terraform fmt {absolute_module_path}
```
(fmt is low-risk; Bash fallback is acceptable here.)

If fmt fails: show the error. Tell user:
```
Fix the formatting issue and re-run /terraform:drift.
```
Stop.

**2. terraform validate**

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) instructions to run `terraform validate` for the module at `{absolute_module_path}`, executing all MCP tool calls in the current session. Do NOT spawn a subagent.

If validate fails: show the validation error. Tell user:
```
Fix the configuration error and re-run /terraform:drift.
```
Stop.

**3. Re-run plan (re-verification)**

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) and Safety Categorization (Section 3) instructions, executing all MCP tool calls in the current session. Do NOT spawn a subagent.
Working directory: `{absolute_module_path}`

**If plan shows zero changes:**

Show:
```
✓ Drift resolved. Code is aligned with remote state.
```

Run via Bash:
```bash
git add {list of .tf files that were edited} && git commit -m "Align .tf code with remote state — resolved drift on: {resource list}"
```
(Use specific file paths — do NOT use `git add -A` or `git add .`)

Show:
```
Committed: {commit hash} — {commit message}
```

**If plan still shows changes:**

Show:
```
Re-verification failed — plan still shows {N} change(s) after code alignment.
```

Show the remaining categorized changes using the same format as Step 3 of the plan skill (DESTRUCTIVE → RISKY → SAFE sections with emoji headers).

Show:
```
Do not commit. Review the residual changes and re-run /terraform:drift.
```
Stop.

## Error Handling

| Situation | Action |
|-----------|--------|
| No modules found | "No Terraform modules found. Run terraform init in your module directory first." Stop. |
| User types invalid module number | Re-show the numbered list via AskUserQuestion. Show "Please enter a number between 1 and {N}." |
| No drift detected | "No drift detected — remote state matches your code." Stop. |
| User rejects batch approval | "Changes not applied. Drift still exists on: {resource list}" Stop. |
| User chooses B for all destructive drift (no normal drift) | "No code changes to commit. Run /terraform:apply to recreate the deleted resources." Stop. |
| Plan fails during drift detection — init required | Auto-run terraform init -backend=false (no consent, no -upgrade). Retry plan. |
| Plan fails — other error | Show raw error. Append "Fix the error above and re-run /terraform:drift." Stop. |
| terraform fmt fails after edits | Show error. "Fix the formatting issue and re-run /terraform:drift." Stop. |
| terraform validate fails after edits | Show validation error. "Fix the configuration error and re-run /terraform:drift." Stop. |
| Re-verification plan not clean | Show residual changes categorized (DESTRUCTIVE → RISKY → SAFE). "Review and re-run /terraform:drift." Stop. Do NOT commit. |
| git commit fails | Show git error. Tell user to commit manually: `git add {files} && git commit -m "Align .tf code with remote state — resolved drift on: {resource list}"` |
| All destructive drift resolved via B (recreate) and no normal drift | "No code changes to commit. Run /terraform:apply to recreate the deleted resources." Stop. |
