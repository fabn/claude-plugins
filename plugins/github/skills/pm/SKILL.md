---
name: github:pm
description: |
  This skill should be used when the user wants to manage GitHub issues and project
  boards: creating issues (including Epics), expanding Epics into sub-issues,
  triaging issues with missing fields, or listing/filtering the project board.
  Activates on: "issue", "create issue", "new issue", "epic", "task", "bug",
  "feature issue", "project board", "board", "triage", "backlog", "pm",
  "expand epic", "sub-issue", "issue management",
  "creare issue", "nuova issue", "gestione progetto", "bacheca", "backlog".
---

# GitHub PM Skill

Project management workflow for GitHub issues and project boards. Supports four operations: **Create Issue**, **Expand Epic**, **Triage / Fix**, and **List / Explore Board**. Reads project config from CLAUDE.md; works without a board configured (skips board steps silently).

## Tools Used

- **GitHub MCP** (`mcp__github__*`): `issue_write`, `issue_read`, `list_issues`, `search_issues`, `list_issue_types`, `projects_list`, `projects_get`, `projects_write`, `sub_issue_write`
- **Bash**: `gh project item-add`, `gh project item-edit`, `gh repo view`
- **AskUserQuestion**: collect issue fields, choose operation, confirm before creating
- **Read**: CLAUDE.md for project config (`github_project_number`, `github_project_owner`)

## Config

Read from the project's CLAUDE.md `<!-- github-plugin-config -->` block:

```markdown
<!-- github_project_number: 2 -->
<!-- github_project_owner: fabn -->
```

If these keys are missing, the skill works without a project board — it creates issues but skips all board steps.

## Workflow

### Step 0: Choose Operation

Ask the user which operation to perform via AskUserQuestion:

- **Create Issue** — create a new Epic, Feature, Task, or Bug
- **Expand Epic** — generate sub-issues from an existing Epic's description
- **Triage / Fix** — find issues with missing Priority, Size, or parent links and fix them
- **List / Explore Board** — view and filter project board items

Then follow the workflow for the chosen operation.

---

## Operation: Create Issue

### Step 1: Read Config

Read the project's CLAUDE.md and extract `github_project_number` and `github_project_owner` from the `<!-- github-plugin-config -->` block. If missing, proceed without board — note this silently.

### Step 2: Detect Repo

Run via Bash:

```bash
gh repo view --json owner,name
```

Extract `owner` and `name` for all subsequent GitHub MCP calls.

### Step 3: Choose Issue Type

Ask via AskUserQuestion:

- **Epic** — large body of work; container for sub-issues; can have a milestone
- **Feature** — new functionality; can belong to an Epic
- **Task** — specific activity; can belong to an Epic or Feature
- **Bug** — error or regression; can belong to an Epic

### Step 4: Search for Duplicates

Before collecting fields, call `mcp__github__search_issues` with key words from the user's initial description to detect potential duplicates.

- If duplicates are found: show them and ask "Is this the same issue, or should I proceed with a new one?"
- If no duplicates or user confirms to proceed: continue

### Step 5: Collect Fields

Gather issue details via AskUserQuestion (ask in batches, not one field at a time):

**Always required:**
- **Title** — imperative phrase, Title Case, no ALL CAPS (e.g., "Add Avatar Upload to User Profile")
- **Body** — problem description + acceptance criteria; no implementation code
- **Priority** (required): P0 / P1 / P2
- **Size** (required): XS / S / M / XL

**Conditional:**
- **Milestone** — optional; prompt for Epics
- **Parent issue number** — optional for Task, Feature, Bug (ask: "Does this belong to an Epic or parent issue?")
- **Estimate** (number), **Start date**, **Target date** — optional, offer to set

### Step 6: Confirm Before Creating

Show a preview of the issue and ask the user to confirm via AskUserQuestion before creating anything.

### Step 7: Create Issue

Call `mcp__github__issue_write` to create the issue with the collected title and body.

### Step 8: Add to Project Board (if configured)

If `github_project_number` is set:

1. Add the issue to the project:
   ```bash
   gh project item-add <project_number> --owner <owner> --url <issue_url>
   ```
   Capture the returned `item-id` from the output.

2. Discover field IDs — call `mcp__github__projects_list` with `list_project_fields` to get the node IDs for Priority and Size fields (do NOT cache these — discover fresh each time).

3. Set Priority:
   ```bash
   gh project item-edit --project-id <project_id> --id <item_id> --field-id <priority_field_id> --single-select-option-id <option_id>
   ```

4. Set Size using the same pattern.

### Step 9: Link Sub-Issue to Parent (if parent provided)

If the user specified a parent issue number, call `mcp__github__sub_issue_write` to link this issue as a sub-issue of the parent.

### Step 10: Summary

Report:
- Issue URL
- Project board status (added, Priority set, Size set) — or "not added (no project configured)"
- Parent issue link (if applicable)

---

## Operation: Expand Epic

### Step 1: Identify Epic

Ask the user for an Epic issue number, or search `mcp__github__search_issues` with `is:open` plus a label or type filter to find Epics. Present matches and ask the user to confirm which Epic to expand.

### Step 2: Read Epic

Call `mcp__github__issue_read` to get the Epic's title, body, and existing sub-issues.

### Step 3: Collect Sub-Task Descriptions

Read the Epic body and suggest a breakdown of tasks. Ask the user to confirm, add, or remove tasks. Each task should be one sentence describing a specific deliverable.

### Step 4: Confirm All at Once

Present a numbered preview list of all sub-issues to be created. Ask for confirmation before creating anything.

### Step 5: Create Each Sub-Issue

For each task in the confirmed list:

1. Create the issue: `mcp__github__issue_write` (inherit Epic's repo)
2. Link it as a sub-issue: `mcp__github__sub_issue_write(epic_number, new_issue_number)`
3. Add to project board and set Priority / Size (ask once for defaults to apply to all, or ask per-issue if they differ)

### Step 6: Summary

Report a list of created issue URLs and their sub-issue links to the Epic.

---

## Operation: Triage / Fix

### Step 1: Fetch Open Issues

Call `mcp__github__list_issues` to get open issues. Paginate if needed (batches of 10).

### Step 2: Check Each Issue

For each issue, check:

- Missing Priority field on the project board
- Missing Size field on the project board
- Task / Feature / Bug with no parent issue (no sub-issue relationship)
- Issue not added to the project board at all

### Step 3: Report Findings

Present a table:

| # | Title | Missing |
|---|-------|---------|
| 12 | Add dark mode toggle | Priority, Size |
| 18 | Fix login redirect | Not on board |
| 23 | Refactor auth service | No parent |

### Step 4: Ask Which to Fix

Ask the user: "Fix all of these, or select specific ones?" Let the user choose via AskUserQuestion.

### Step 5: Apply Fixes

For each selected issue:
- If not on board: `gh project item-add <project_number> --owner <owner> --url <issue_url>`
- If missing Priority or Size: `gh project item-edit` with the appropriate field and option IDs
- If missing parent: ask the user for the parent issue number, then call `mcp__github__sub_issue_write`

### Step 6: Summary

Report how many issues were fixed and what was changed.

---

## Operation: List / Explore Board

### Step 1: Read Config

Read `github_project_number` from CLAUDE.md. If missing, fall back to `mcp__github__list_issues` and note that project board fields (Priority, Size, Status) will not be shown.

### Step 2: Ask for Filters (optional)

Ask via AskUserQuestion whether the user wants to filter by:
- Status (Backlog, Ready, In progress, In review, Done)
- Priority (P0, P1, P2)
- Assignee
- Issue type (Epic, Feature, Task, Bug)

### Step 3: Fetch Items

Call `mcp__github__projects_list` with `list_project_items` using the selected filters. If no project is configured, use `mcp__github__list_issues`.

### Step 4: Present Table

Display results in a readable table:

| # | Title | Type | Status | Priority | Size |
|---|-------|------|--------|----------|------|
| 7 | Add dark mode toggle | Feature | In progress | P1 | M |
| 12 | Fix login redirect | Bug | Ready | P0 | XS |

### Step 5: Offer Follow-Up

After displaying the board, ask via AskUserQuestion:
- "Create a new issue"
- "Expand an Epic"
- "Done — exit"

---

## Error Handling

| Situation | Action |
|-----------|--------|
| No `github_project_number` in config | Work without board — offer to run `/github:setup` to configure one |
| Duplicate issue found | Show existing issue, ask whether to continue or abort |
| `gh project item-edit` fails (field ID changed) | Re-discover field IDs via `list_project_fields`, retry once |
| `sub_issue_write` fails (cross-repo) | Fall back to `gh api` GraphQL, note in summary |
| Issue type not available in repo | Use label as fallback, warn user |
| `list_project_items` returns empty | Check project number and owner, suggest re-running `/github:setup` |
| `gh project item-add` returns no item-id | Parse output carefully; retry with `--format json` flag |
| Board fields (Priority, Size) not found | Warn that the project may use different field names; show available fields |

## Related Skills

- **`/github:setup`** — Configure project defaults including `github_project_number`
- **`/github:feature`** — Feature branch workflow; conditionally moves linked issues to "In review"
- **`/github:release`** — Publish draft releases
