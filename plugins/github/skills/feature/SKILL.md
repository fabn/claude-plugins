---
name: github:feature
description: |
  This skill should be used when the user wants to develop a feature using a
  Git-based workflow: creating a branch, staging files, writing a commit,
  pushing to remote, and opening a pull request. Guides the full flow from
  an empty working tree or a branch with uncommitted changes.
  Activates on: "git", "feature", "branch", "pull request", "pr", "new branch",
  "create branch", "open pr", "submit pr", "feature branch", "commit", "stage",
  "push", "branch feature", "aprire pr", "pull request", "nuova branch",
  "creare branch", "fare commit", "pushare", "aprire pull request".
---

# GitHub Feature Skill

Guides the full feature development workflow: branch → stage → commit → push → PR. Reads project config via the plugin's shared resolver and uses Git MCP tools for all local operations.

## Tools Used

- **Git MCP** (`mcp__git__*`): `git_branch`, `git_status`, `git_diff_unstaged`, `git_diff_staged`, `git_log`, `git_add`, `git_commit`, `git_create_branch`, `git_checkout`
- **GitHub MCP** (`mcp__plugin_github_github__*` when this plugin's bundled GitHub MCP server is active): `create_pull_request`, `search_issues`, `list_issues`, `projects_list`
- **Bash**: `git push -u origin <branch>` (push to remote — NOT `push_files`); `gh project item-edit` (conditional board update)
- **Bash**: `${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh` for project config
- **AskUserQuestion**: confirm branch name, commit message, PR details

> **MCP server name may differ.** The prefix `mcp__plugin_github_github__` is used when this plugin's bundled GitHub MCP server is active. If the host project ships its own GitHub MCP server (often `mcp__github__*`), the bundled one may be disabled to avoid conflicts — discover the actual prefix from the available tool list and substitute it. Verb names are unchanged.

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

## Workflow

### Step 1: Read Local Config

Run the shared resolver and handle `source` first (see [Config](#config)):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh"
```

Use:
- `config.mainBranch` — default `main`
- `config.branchPrefix` — default `feature`
- `config.project` — optional; used in Step 8a for the board status update

With `source: "none"`, proceed with the defaults silently.

### Step 2: Detect Repo State

Run `mcp__git__git_branch()` to list branches and identify the current branch.
Run `mcp__git__git_status()` to get the working tree state.

Use this to determine which path to take in Step 3.

### Step 3: Branch Management

**If on the main branch** (`config.mainBranch`):

1. Ask the user to describe the feature/change (one sentence)
2. Suggest a branch type using AskUserQuestion with options:
   - `feature` (default from `config.branchPrefix`)
   - `fix`
   - `docs`
   - `chore`
3. Derive a kebab-case branch name from the description: `<type>/<kebab-case-description>`
   - Example: `feature/add-user-avatar-upload`
4. Confirm the branch name with AskUserQuestion (show suggested name, allow edit)
5. Check existing branches (from Step 2) for project naming conventions and adjust suggestion if needed
6. Create and checkout: `mcp__git__git_create_branch(branch_name)` + `mcp__git__git_checkout(branch_name)`

**If already on a feature branch**:

Ask via AskUserQuestion:
- "Continue on `<current-branch>`" (recommended)
- "Create a new branch instead"

If user chooses to create a new branch, follow the same flow as above.

### Step 4: Review Changes

Run `mcp__git__git_diff_unstaged()` to show unstaged changes.

If there are already staged files, also run `mcp__git__git_diff_staged()`.

Ask the user which files to include in this commit. Show a list and allow selection. If there are both staged and unstaged files, clarify which to include.

### Step 5: Stage and Commit

1. Stage the selected files: `mcp__git__git_add(files)`
2. Run `mcp__git__git_diff_staged()` to confirm what will be committed
3. Propose a commit message:
   - Single line, plain English
   - No conventional prefixes (`feat:`, `fix:`, etc.)
   - No attribution ("Generated with Claude Code", "Co-Authored-By", etc.)
   - Describes *what changed*, not *why*
   - Example: "Add avatar upload to user profile"
4. Confirm with AskUserQuestion, allow the user to edit
5. Commit: `mcp__git__git_commit(message)`

### Step 6: Push to Remote

Run via Bash:

```bash
git push -u origin <branch-name>
```

- **Success**: Proceed to Step 7
- **Auth failure**: Tell the user to run `gh auth status` and check `gh auth login --web`
- **Non-fast-forward**: The remote branch is ahead. Ask whether to pull first (`git pull --rebase`) or force-push (warn about implications)

### Step 7: Find Related Issues

Ask via AskUserQuestion: "Do you want to link this PR to any issues?"

- **Yes**: Use `mcp__plugin_github_github__search_issues` or `mcp__plugin_github_github__list_issues` to find open issues. Show a short list and ask the user to confirm which ones to link.
- **No / skip**: Proceed without issue links

Collect confirmed issue numbers for the PR body.

### Step 8: Create Pull Request

Collect:
- **Owner/repo**: Extract from `git remote get-url origin` via Bash, or ask
- **Title**: Concise one-liner, plain English, no conventional prefixes
- **Body**: 2–3 bullet points max describing the change, followed by issue links:
  - `Closes #N` for issues this PR resolves
  - `Refs #N` for related issues that are not fully closed
- **Head**: current branch
- **Base**: `config.mainBranch` (default: `main`)

Confirm title and body with AskUserQuestion before creating.

Call `mcp__plugin_github_github__create_pull_request(owner, repo, title, body, head, base)`.

Do **not** add "Generated with Claude Code" or any attribution to the PR body.

### Step 8a: Update Project Board Status (conditional)

After the PR is created, check both conditions:

1. `config.project.number` is set
2. At least one issue was linked to the PR in Step 7

If **both conditions are true**, ask via AskUserQuestion:

> "Move linked issue(s) to 'In review' on the project board?"

- **Yes**: For each linked issue, discover the Status field ID via `mcp__plugin_github_github__projects_list` (`list_project_fields`), find the "In review" option ID, and run:
  ```bash
  gh project item-edit --project-id <project_id> --id <item_id> --field-id <status_field_id> --single-select-option-id <in_review_option_id>
  ```
  Report which issues were updated.
- **No / either condition false**: Skip silently.

### Step 9: Summary

Print a summary:

```
Feature workflow complete
--------------------------
Branch:   feature/add-user-avatar-upload
Commit:   "Add avatar upload to user profile"
PR:       https://github.com/owner/repo/pull/42
Issues:   Closes #17, Refs #20

Next steps:
- Request a review from a teammate
- Monitor CI: /github:release when ready to ship
```

Adjust based on what actually happened (e.g., if no issues were linked, omit that line).

## Error Handling

| Situation | Action |
|-----------|--------|
| Not in a git repository | Tell the user to run this skill from within a git repo directory |
| Push auth failure | Guide to `gh auth status`, suggest `gh auth login --web` |
| Push non-fast-forward | Offer to pull with rebase or warn about force-push consequences |
| Branch already exists | Ask whether to checkout the existing branch or create a new one with a different name |
| Nothing to stage | Tell the user there are no uncommitted changes; suggest checking `git status` |
| Git MCP not available | Inform the user the `git` MCP server is not running; suggest running `/github:setup` |
| GitHub MCP not available | Inform the user the `github` MCP server is not running; check `GITHUB_MCP_TOKEN` and re-run `/github:setup` |
| PR already exists for branch | Report the existing PR URL; ask if they want to push additional commits to it |
| Cannot parse remote URL | Ask the user to provide the GitHub owner and repository name manually |

## Reference Files

- No additional reference files — project config is resolved by `${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh` at runtime
