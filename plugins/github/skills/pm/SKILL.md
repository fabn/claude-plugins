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

Project management workflow for GitHub issues and project boards. Supports four operations: **Create Issue**, **Expand Epic**, **Triage / Fix**, and **List / Explore Board**. Reads project config via the plugin's shared resolver; works without a board configured (skips board steps).

## Tools Used

- **GitHub MCP** (`mcp__plugin_github_github__*` when this skill ships its bundled GitHub MCP server): `issue_write`, `issue_read`, `list_issues`, `search_issues`, `list_issue_types`, `projects_list`, `projects_get`, `projects_write`, `sub_issue_write`
- **Bash**: `gh repo view` (and `gh` GraphQL / `gh project` as fallback only — see Troubleshooting)
- **AskUserQuestion**: collect issue fields, choose operation, confirm before creating
- **Bash**: `${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh` for project config (and `migrate-config.sh` when it reports the deprecated source)

> **MCP server name may differ.** The tool prefix `mcp__plugin_github_github__` is the one used by the GitHub MCP bundled with this plugin. If the host project ships its own GitHub MCP server (e.g. `mcp__github__*` or another custom name), the bundled one may be disabled to avoid conflicts. Discover the actual prefix at runtime by looking at the available tool list, then substitute it everywhere below. The verb names (`issue_write`, `projects_list`, …) are the same across implementations.

## Config

Resolved by the shared script, never by parsing files inline:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh"
```

It returns `{ "source", "path", "config" }`. **Act on `source` before using `config`:**

| `source` | Meaning | What to do |
|---|---|---|
| `json` | `.claude/github.json` — the current location | Nothing, proceed |
| `claude-md` | the deprecated `<!-- github-plugin-config -->` block | Stop and offer migration (below) |
| `none` | no configuration anywhere | Proceed with this skill's defaults |

The `config` object is normalized to the same shape either way:

```json
{
  "mainBranch": "main",
  "branchPrefix": "feature",
  "project": { "number": 2, "owner": "acme" },
  "roadmap": { "repos": ["acme/platform"], "externalEdges": [] }
}
```

### On `source: "claude-md"`

Tell the user their config is in the deprecated location and offer to move it:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-config.sh"          # add --dry-run to preview
```

It writes `.claude/github.json`, strips the block from `CLAUDE.md` and leaves the surrounding prose intact. If they decline, continue with the values returned — the fallback is removed in 0.8.0, and saying so now is the point of the prompt.

**Do not skip the prompt.** Several skills here degrade quietly without config rather than failing, so once the fallback is gone a silent fallback today and a silent failure tomorrow look identical to the user.

Without `project`, this skill works without a board — it creates issues and skips all board steps.

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

Run `read-config.sh` (see [Config](#config)) and handle `source` first. Use `config.project`; if absent, proceed without a board and say so once.

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

Before collecting fields, call `mcp__plugin_github_github__search_issues` with key words from the user's initial description to detect potential duplicates.

- If duplicates are found: show them and ask "Is this the same issue, or should I proceed with a new one?"
- If no duplicates or user confirms to proceed: continue

### Step 5: Collect Fields

Gather issue details via AskUserQuestion (ask in batches, not one field at a time):

**Always required:**
- **Title** — imperative phrase, Title Case, no ALL CAPS (e.g., "Add Avatar Upload to User Profile")
- **Body** — problem description + acceptance criteria; no implementation code
- **Priority** (required): typically P0 / P1 / P2 — discover the actual options by calling `mcp__plugin_github_github__projects_list` with `list_project_fields` and reading the `Priority` single-select options. Do NOT hardcode the list.
- **Size** (required): typically XS / S / M / L / XL — discover the actual options the same way (the `Size` single-select on the project may include or omit specific buckets). Do NOT hardcode the list.
- **Status** (defaults to `Backlog`): also a single-select on the project board. Set explicitly so the new item lands in the correct column instead of inheriting the project default.

**Conditional:**
- **Milestone** — optional; prompt for Epics
- **Parent issue number** — optional for Task, Feature, Bug (ask: "Does this belong to an Epic or parent issue?")
- **Estimate** (number), **Start date**, **Target date** — optional, offer to set

### Step 6: Confirm Before Creating

Show a preview of the issue and ask the user to confirm via AskUserQuestion before creating anything.

### Step 7: Create Issue

1. If the repo's organization has issue types configured, call `mcp__plugin_github_github__list_issue_types` to get the valid type names (e.g. `Epic`, `Feature`, `Task`, `Bug`). Map the user's choice from Step 3 to the exact type name returned (case-sensitive).
2. Call `mcp__plugin_github_github__issue_write` with `method: "create"`, `owner`, `repo`, `title`, `body`, and `type: <chosen>` if the org supports issue types (omit otherwise — passing `type` to a repo without configured types fails).
3. Capture both the new issue's `number` (for sub-issue parent linking from another issue) and the `id` field (the **global numeric ID**, used as `sub_issue_id` when this issue is linked as a child of a parent). Both are returned in the response.

### Step 8: Add to Project Board (if configured)

If `config.project.number` is set:

1. Add the issue to the project via `mcp__plugin_github_github__projects_write` with `method: "add_project_item"`, `owner`, `project_number`, `item_type: "issue"`, `item_owner` + `item_repo` (the issue's repo, may differ from the project's org), and `issue_number`. The response includes the new project item's `id` (a node-id-style string like `PVTI_…`).

2. Discover field IDs and option IDs — call `mcp__plugin_github_github__projects_list` with `list_project_fields`. For each single-select field (Status, Priority, Size) capture **both** representations from the response: the numeric `id` (e.g. `341154587`, used by `update_project_item`) and the `node_id` / option `id` strings (used by `gh project item-edit` if you fall back to the CLI). Do NOT cache these across runs — discover fresh each time.

3. Set Status (default `Backlog`), Priority and Size via `mcp__plugin_github_github__projects_write` with `method: "update_project_item"`, passing `project_number`, `owner`, the project item's `item_id`, and `updated_field: { id: <field_numeric_id>, value: <option_id_or_value> }` — one call per field.

4. **Fallback (only if MCP `update_project_item` fails)**: use `gh project item-edit --project-id <project_node_id> --id <item_node_id> --field-id <field_node_id> --single-select-option-id <option_id>` — this uses node-id strings throughout, so reach for the `node_id` values you captured in step 2.

### Step 9: Link Sub-Issue to Parent (if parent provided)

If the user specified a parent issue number, call `mcp__plugin_github_github__sub_issue_write` to link this issue as a sub-issue of the parent. Pass `owner` / `repo` / `issue_number` of the **parent**, and `sub_issue_id` = the **global numeric ID** of the new child (the `id` field returned by `issue_write` / `issue_read`, e.g. `4405308405` — *not* its `issue_number`). Because the child is identified by its global ID, this works **cross-repo** within the same org (e.g. parent in `org/aleteia-next`, child in `org/aleteia-wp`) — no GraphQL fallback needed.

### Step 10: Summary

Report:
- Issue URL
- Project board status (added, Priority set, Size set) — or "not added (no project configured)"
- Parent issue link (if applicable)

---

## Operation: Expand Epic

### Step 1: Identify Epic

Ask the user for an Epic issue number, or search `mcp__plugin_github_github__search_issues` with `is:open` plus a label or type filter to find Epics. Present matches and ask the user to confirm which Epic to expand.

### Step 2: Read Epic

Call `mcp__plugin_github_github__issue_read` to get the Epic's title, body, and existing sub-issues.

### Step 3: Collect Sub-Task Descriptions

Read the Epic body and suggest a breakdown of tasks. Ask the user to confirm, add, or remove tasks. Each task should be one sentence describing a specific deliverable.

### Step 4: Confirm All at Once

Present a numbered preview list of all sub-issues to be created. Ask for confirmation before creating anything.

### Step 5: Create Each Sub-Issue

For each task in the confirmed list:

1. Create the issue: `mcp__plugin_github_github__issue_write` (inherit Epic's repo by default; cross-repo is allowed if the user specified a different one). Capture the `id` field from the response — this is the global numeric ID needed in step 2.
2. Link it as a sub-issue: `mcp__plugin_github_github__sub_issue_write` with `method: "add"`, `owner` / `repo` / `issue_number` of the **Epic**, and `sub_issue_id` = the global numeric `id` captured above (NOT the new issue's `number`).
3. Add to project board and set Priority / Size (ask once for defaults to apply to all, or ask per-issue if they differ)

### Step 6: Summary

Report a list of created issue URLs and their sub-issue links to the Epic.

---

## Operation: Triage / Fix

### Step 1: Fetch Open Issues and Project Items

Run the two queries in parallel:

- `mcp__plugin_github_github__list_issues` for the repo (paginate in batches of 10 if needed) — gives you the source-of-truth set of open issues.
- `mcp__plugin_github_github__projects_list` with `list_project_items` (passing the relevant single-select field IDs in `fields`) — gives you what is on the board, with current Priority / Size / Status / parent values.

Build a lookup table keyed by issue number from the project items so you can cheaply tell which issues are on the board and what fields they already have set.

### Step 2: Check Each Issue

For each open issue from Step 1:

- **Not on the board**: the issue number is missing from the project-items lookup table.
- **Missing Priority / Size / Status**: present on the board but the corresponding single-select option is empty in the item's field values.
- **No parent issue**: a Task / Feature / Bug whose `parent` is null. Verify with a GraphQL query (`repository.issue(number: N) { parent { number repository { nameWithOwner } } }`) — `list_issues` does not return parent metadata.

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
- **Not on board**: `mcp__plugin_github_github__projects_write` with `method: "add_project_item"` (same call shape as Create-Issue Step 8.1). Capture the returned project item id.
- **Missing Status / Priority / Size**: `mcp__plugin_github_github__projects_write` with `method: "update_project_item"`, one call per missing field, with `updated_field: { id: <field_numeric_id>, value: <option_id> }`. Default Status to `Backlog` when freshly added in this same fix pass. (Fall back to `gh project item-edit` only if the MCP update fails — see Create-Issue Step 8.4.)
- **Missing parent**: ask the user for the parent issue number, then call `mcp__plugin_github_github__sub_issue_write` with `method: "add"`, `owner` / `repo` / `issue_number` of the parent, and `sub_issue_id` = the **global numeric `id`** of the child issue (re-fetch via `issue_read` if you don't have it cached). Cross-repo within the same org is supported.

### Step 6: Summary

Report how many issues were fixed and what was changed.

---

## Operation: List / Explore Board

### Step 1: Read Config

Use `config.project.number`. If absent, fall back to `mcp__plugin_github_github__list_issues` and note that project board fields (Priority, Size, Status) will not be shown.

### Step 2: Ask for Filters (optional)

Ask via AskUserQuestion whether the user wants to filter by:
- Status (Backlog, Ready, In progress, In review, Done)
- Priority (P0, P1, P2)
- Assignee
- Issue type (Epic, Feature, Task, Bug)

### Step 3: Fetch Items

Call `mcp__plugin_github_github__projects_list` with `list_project_items` using the selected filters. If no project is configured, use `mcp__plugin_github_github__list_issues`.

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
| No `project` in config | Work without board — offer to run `/github:setup` to configure one |
| `read-config.sh` reports `source: claude-md` | Offer `migrate-config.sh`; never migrate without asking |
| `.claude/github.json` is invalid JSON | The script exits 65 naming the parse error — report it, do not guess at defaults |
| Duplicate issue found | Show existing issue, ask whether to continue or abort |
| `update_project_item` fails (field ID changed or schema mismatch) | Re-discover field IDs via `list_project_fields` and retry once. If still failing, fall back to `gh project item-edit` with the captured node-id strings (see Create-Issue Step 8.4). |
| `sub_issue_write` returns "not found" / "invalid" | Likely the wrong field was passed: `sub_issue_id` must be the child's **global numeric ID** (`id` from `issue_write` / `issue_read`), not its `issue_number`. Re-fetch the child via `issue_read` and retry. Cross-repo within the same org is supported natively — no GraphQL fallback needed. Only fall back to `gh api graphql` `addSubIssue` mutation if the MCP call genuinely fails after this correction. |
| Issue type not available in repo | Use label as fallback, warn user |
| `list_project_items` returns empty | Check project number and owner, suggest re-running `/github:setup` |
| `add_project_item` response missing the item id | Re-call `list_project_items` filtering by the issue number to recover the project item id; if that also fails, fall back to `gh project item-add … --format json` and parse `id` from JSON. |
| Board fields (Priority, Size, Status) not found | Warn that the project may use different field names; show available fields |
| MCP tool prefix mismatch / GitHub MCP unavailable | The host project may be running a different GitHub MCP server with a different prefix (e.g. `mcp__github__*` directly) that disables the bundled one to avoid conflicts. Inspect the available tools, re-bind the same verb names (`issue_write`, `projects_list`, `projects_write`, `sub_issue_write`, …) under the actual prefix, and proceed. If no GitHub MCP is exposed at all, fall back to `gh` CLI: `gh issue create`, `gh project item-add/edit`, `gh api graphql` for sub-issues. |

## Related Skills

- **`/github:setup`** — Configure project defaults including the project board
- **`/github:feature`** — Feature branch workflow; conditionally moves linked issues to "In review"
- **`/github:release`** — Publish draft releases
