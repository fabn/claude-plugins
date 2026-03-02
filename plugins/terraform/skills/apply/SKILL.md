---
name: terraform:apply
description: |
  This skill should be used when the user wants to apply Terraform changes,
  execute infrastructure updates, deploy planned changes, or confirm and apply
  a Terraform execution plan.
  Activates on: "terraform apply", "apply changes", "deploy changes", "apply plan",
  "execute plan", "run apply", "deploy infrastructure", "apply terraform changes",
  "applica terraform", "applica modifiche", "applica piano terraform", "esegui apply",
  "distribuisci modifiche".
---

# Terraform Apply Skill

Apply Terraform changes after always running a fresh plan analysis. There is no path that skips the plan — apply always requires seeing the plan first. For mixed-change plans (SAFE + RISKY or DESTRUCTIVE resources), presents three options: apply safe resources via `-target`, apply all, or cancel. DESTRUCTIVE changes require per-resource explicit acknowledgment before any destructive apply proceeds.

## Tools Used

- **AskUserQuestion**: Module selection when multiple modules are found, A/B/C menu for mixed plans, confirmation gates (both post-full-plan and post-scoped-plan), and per-resource destructive acknowledgment.

## Workflow

### Step 1: Discover Modules / Handle Explicit Targets

If the user invoked the skill with `-target` arguments upfront (e.g., `/terraform:apply -target=aws_instance.web -target=aws_s3_bucket.data`), skip module discovery. Resolve the git root:

```bash
git rev-parse --show-toplevel
```

Use the current working directory (or the most recent module context if determinable) as `absolute_module_path`. Proceed to Step 3 using those targets for a scoped plan.

Otherwise, use standard module discovery:

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

### Step 2: Run Full Plan and Categorize

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) and Safety Categorization (Section 3) instructions, executing all MCP tool calls in the current session. Do NOT spawn a subagent.
Working directory: `{absolute_module_path}`
Return: categorized resource list (SAFE/RISKY/DESTRUCTIVE), one-line impact description per resource in plain operational English, total counts per category, and a "No changes" signal if infrastructure matches configuration.

**If plan fails with init required:**

Auto-run: Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution instructions (Section 1) to run `terraform init -backend=false` for the module at `{absolute_module_path}`, then re-run terraform plan, executing all MCP tool calls in the current session. Do NOT spawn a subagent. Do NOT use the -upgrade flag.

If init fails, surface the error and tell the user:
```
Run `terraform init -backend=false` in `{module_path}` manually and re-run /terraform:apply.
```
Stop.

**If plan fails with any other error:**

Show the raw error output from the agent.
Append:
```
Fix the error above and re-run /terraform:apply.
```
Stop.

**If plan returns no changes:**

Show:
```
✓ No changes. Infrastructure matches configuration.
```
Stop.

**If plan returns changes:** Proceed to Step 3.

### Step 3: Present Plan Results

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

Proceed to Step 4.

### Step 4: Route Based on Plan Composition

Route to the appropriate apply flow based on what categories are present.

**If plan has DESTRUCTIVE resources (any composition):**

Before presenting any gate, run the Destructive Acknowledgment flow (Step 4D) for each DESTRUCTIVE resource. Complete all acknowledgments before proceeding to the gate.

**Pure SAFE plan (no RISKY, no DESTRUCTIVE):**

Ask via AskUserQuestion: "Type 'apply' to confirm, or anything else to cancel:"
- Response equals exactly `apply`: proceed to Step 5A (apply all).
- Response does not match (attempt 1): "Only 'apply' confirms. Type 'apply' to proceed or anything else to cancel:" (re-prompt once).
- Response does not match (attempt 2): "Apply cancelled." Stop.

**Mixed plan (SAFE resources + at least one RISKY or DESTRUCTIVE resource):**

Show via AskUserQuestion:
```
A: Apply {N_safe} SAFE resources via -target (skip {N_risky_destructive} RISKY/DESTRUCTIVE)
B: Apply all {N_total} resources
C: Cancel

Enter A, B, or C:
```
- **A**: Proceed to Step 5B (targeted apply flow).
- **B**: Ask via AskUserQuestion: "Type 'apply all' to confirm applying ALL resources including RISKY/DESTRUCTIVE, or anything else to cancel:"
  - Response equals exactly `apply all`: proceed to Step 5A (apply all).
  - Response does not match (attempt 1): "Only 'apply all' confirms. Type 'apply all' to proceed or anything else to cancel:" (re-prompt once).
  - Response does not match (attempt 2): "Apply cancelled." Stop.
- **C**: "Apply cancelled." Stop.
- Any invalid input (not A, B, or C): Re-show the A/B/C menu once with "Please enter A, B, or C."

**Pure RISKY plan (RISKY resources, no DESTRUCTIVE, no SAFE):**

Ask via AskUserQuestion: "Type 'apply' to confirm applying RISKY changes, or anything else to cancel:"
- Same two-attempt gate as pure SAFE.
- On confirmation: proceed to Step 5A.

**Pure DESTRUCTIVE plan (all resources are DESTRUCTIVE, no SAFE or RISKY):**

After completing Step 4D for all resources, show gate:
Ask via AskUserQuestion: "All DESTRUCTIVE changes acknowledged. Type 'apply' to confirm, or anything else to cancel:"
- Response equals exactly `apply`: proceed to Step 5A (apply all).
- Response does not match (attempt 1): re-prompt once.
- Response does not match (attempt 2): "Apply cancelled." Stop.

### Step 4D: Destructive Resource Acknowledgment

For each DESTRUCTIVE resource, show:
```
⛔ DESTRUCTIVE CHANGE: {resource_type}.{resource_name}

  THIS RESOURCE WILL BE PERMANENTLY DELETED.

  Key attributes:
    {key_attribute_1}: {value}
    {key_attribute_2}: {value}
    {key_attribute_3}: {value}

  Recommended: Use option A (apply safe resources via -target) first,
  then revisit these destructive changes separately.
```

Ask via AskUserQuestion: "Type '{resource_type}.{resource_name}' to acknowledge this deletion, or 'cancel' to abort:"
- Response equals exactly the resource name (e.g., `aws_instance.prod`): Acknowledged. Continue to next DESTRUCTIVE resource.
- Response equals `cancel` or any other input: "Apply cancelled." Stop.

(One attempt only for destructive acknowledgment — no retry.)

After all DESTRUCTIVE resources are acknowledged, continue to the apply gate in Step 4.

### Step 5A: Apply All

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) instructions to run `terraform apply` for the module at `{absolute_module_path}`, executing all MCP tool calls in the current session. Do NOT spawn a subagent.

**If apply succeeds:**
Show:
```
✓ Apply complete.
```
Include any resource count summary from the agent (e.g., "3 added, 1 changed, 0 destroyed"). Stop.

**If apply fails:**
Show the raw error output from the agent. Append:
```
Apply failed. Review the error above.
```
Stop.

### Step 5B: Targeted Apply Flow

**Run scoped plan for SAFE resources:**

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) and Safety Categorization (Section 3) instructions to run a targeted plan with `-target` flags for all SAFE resources [{safe_resource_1}, {safe_resource_2}, ...] at `{absolute_module_path}`, executing all MCP tool calls in the current session. Do NOT spawn a subagent.

Present the scoped plan output using the same format as Step 3 (summary line + emoji sections for non-empty categories).

**Check for dependency expansion surprises:**

If the scoped plan reveals unexpected RISKY or DESTRUCTIVE resources (not in the original SAFE list):

Show:
```
⚠ Terraform expanded the -target scope to include unexpected changes:
```

Then show the categorized unexpected resources. Re-present the A/B/C menu (from Step 4) for this scoped result. Wait for user choice and route accordingly.

**If the scoped plan is clean (only the expected SAFE resources):**

**Gate 2:** Ask via AskUserQuestion: "Type 'apply' to confirm targeted apply of the SAFE resources, or anything else to cancel:"
- Response equals exactly `apply`: Proceed.
- Response does not match (attempt 1): "Only 'apply' confirms. Type 'apply' to proceed or anything else to cancel:" (re-prompt once).
- Response does not match (attempt 2): "Apply cancelled." Stop.

**Run targeted apply:**

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) instructions to run `terraform apply` with `-target` flags for resources [{safe_resource_1}, {safe_resource_2}, ...] at `{absolute_module_path}`, executing all MCP tool calls in the current session. Do NOT spawn a subagent.

**If apply fails:**
Show the raw error output from the agent. Append:
```
Targeted apply failed. Review the error above. Some resources may have been partially applied — check Terraform state before retrying.
```
Stop.

**If apply succeeds:**
Show:
```
✓ Targeted apply complete.
```
Include any resource count summary from the agent. Proceed to Step 6.

### Step 6: Post-Targeted-Apply — Show Remaining Changes

Re-run the full plan to show what is still pending:

Read `plugins/terraform/agents/terraform-engineer.md` and follow its Plan Execution (Section 1) and Safety Categorization (Section 3) instructions, executing all MCP tool calls in the current session. Do NOT spawn a subagent.
Working directory: `{absolute_module_path}`

**If plan shows no remaining changes:**
```
✓ No remaining changes. All resources are applied.
```
Stop.

**If plan shows remaining changes:**

Show:
```
Remaining changes after targeted apply:
```
Present the remaining changes using the Step 3 format (summary line + emoji sections).

Show:
```
Use /terraform:apply to apply the remaining RISKY/DESTRUCTIVE resources when ready.
```
Stop.

**If re-plan fails:**
Show the error. Append:
```
Could not run post-apply plan. Check Terraform state manually.
```
Stop.

## Error Handling

| Situation | Action |
|-----------|--------|
| No modules found | "No Terraform modules found. Run terraform init in your module directory first." Stop. |
| User types invalid module number | Re-show numbered list via AskUserQuestion. Show "Please enter a number between 1 and {N}." |
| Plan fails — init required | Auto-run terraform init -backend=false (no consent, no -upgrade). Retry plan. If init fails: tell user to run manually. |
| Plan fails — other error | Show raw error. Append "Fix the error above and re-run /terraform:apply." Stop. |
| No changes | "✓ No changes. Infrastructure matches configuration." Stop. |
| Gate wrong input (attempt 1) | Re-prompt once with explanation. |
| Gate wrong input (attempt 2) | "Apply cancelled." Stop. |
| Invalid A/B/C input | Re-show A/B/C menu once with "Please enter A, B, or C." |
| Destructive acknowledgment wrong input | "Apply cancelled." Stop. (No retry.) |
| Scoped plan shows unexpected RISKY/DESTRUCTIVE | Warn prominently. Re-present A/B/C for the scoped result. |
| Targeted apply fails | Show error. "Targeted apply failed. Review the error above. Some resources may have been partially applied — check Terraform state before retrying." Stop. |
| Apply (all) fails | Show error. "Apply failed. Review the error above." Stop. |
| Post-apply re-plan fails | Show error. "Could not run post-apply plan. Check Terraform state manually." Stop. |
| Mixed plan — user picks B but no 'apply all' phrase | Re-prompt once. Auto-cancel on second failure. |
