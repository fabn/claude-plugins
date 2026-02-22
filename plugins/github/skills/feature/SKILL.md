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

Guides the full feature development workflow: branch → stage → commit → push → PR. Reads project config from CLAUDE.md and uses Git MCP tools for all local operations.

## Tools Used

- **Git MCP** (`mcp__git__*`): `git_branch`, `git_status`, `git_diff_unstaged`, `git_diff_staged`, `git_log`, `git_add`, `git_commit`, `git_create_branch`, `git_checkout`
- **GitHub MCP** (`mcp__github__*`): `create_pull_request`, `search_issues`, `list_issues`, `projects_list`
- **Bash**: `git push -u origin <branch>` (push to remote — NOT `push_files`); `gh project item-edit` (conditional board update)
- **Read**: local CLAUDE.md for project config
- **AskUserQuestion**: confirm branch name, commit message, PR details

## Workflow

### Step 1: Read Local Config

Read the project's `CLAUDE.md` (in the current directory) and look for a `<!-- github-plugin-config -->` block:

```markdown
<!-- github-plugin-config -->
<!-- github_main_branch: main -->
<!-- github_branch_prefix: feature -->
```

Extract:
- `github_main_branch` — default `main`
- `github_branch_prefix` — default `feature`
- `github_project_number` — optional; used in Step 8a for board status update
- `github_project_owner` — optional; used in Step 8a for board status update

If no CLAUDE.md or no config block, proceed with defaults silently.

### Step 2: Detect Repo State

Run `mcp__git__git_branch()` to list branches and identify the current branch.
Run `mcp__git__git_status()` to get the working tree state.

Use this to determine which path to take in Step 3.

### Step 3: Branch Management

**If on the main branch** (`github_main_branch`):

1. Ask the user to describe the feature/change (one sentence)
2. Suggest a branch type using AskUserQuestion with options:
   - `feature` (default from `github_branch_prefix`)
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

- **Yes**: Use `mcp__github__search_issues` or `mcp__github__list_issues` to find open issues. Show a short list and ask the user to confirm which ones to link.
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
- **Base**: `github_main_branch` from config (default: `main`)

Confirm title and body with AskUserQuestion before creating.

Call `mcp__github__create_pull_request(owner, repo, title, body, head, base)`.

Do **not** add "Generated with Claude Code" or any attribution to the PR body.

### Step 8a: Update Project Board Status (conditional)

After the PR is created, check both conditions:

1. `github_project_number` is set in CLAUDE.md
2. At least one issue was linked to the PR in Step 7

If **both conditions are true**, ask via AskUserQuestion:

> "Move linked issue(s) to 'In review' on the project board?"

- **Yes**: For each linked issue, discover the Status field ID via `mcp__github__projects_list` (`list_project_fields`), find the "In review" option ID, and run:
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

- No additional reference files — project config is read from CLAUDE.md at runtime
