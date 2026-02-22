---
name: github:address-review
description: |
  This skill should be used when the user wants to address review comments on a
  pull request: read and reason about each comment, decide whether to implement,
  answer, or push back, apply code changes, reply to individual threads, push the
  new commit, and optionally update the PR description.
  Activates on: "address review", "pr review", "review comments", "respond to review",
  "fix review", "implement feedback", "resolve comments", "reply to review",
  "address feedback", "implementare feedback", "risolvere commenti",
  "rispondere alla review", "gestire review", "affrontare review".
---

# GitHub Address Review Skill

Guides the full "address review" loop for an open pull request: reads all unresolved review threads, categorizes each comment, applies code changes, commits and pushes, replies to every thread, and optionally resolves threads and updates the PR description.

## Tools Used

- **GitHub MCP** (`mcp__github__*`): `pull_request_read`, `add_reply_to_pull_request_comment`, `pull_request_review_write`, `update_pull_request`
- **Git MCP** (`mcp__git__*`): `git_status`, `git_diff_unstaged`, `git_diff_staged`, `git_add`, `git_commit`, `git_branch`
- **Bash**: `gh pr view`, `git push`, `gh api` (GraphQL for resolving threads)
- **Read**: source files to understand context; CLAUDE.md for `github_main_branch`
- **Edit / MultiEdit**: implement code changes from review comments
- **AskUserQuestion**: confirm per-comment action plan, confirm commit message, confirm before pushing, confirm thread resolution

## Workflow

### Step 1: Identify the PR

Run `mcp__git__git_branch()` to detect the current branch. Then:

```bash
gh pr view --json number,title,url,body,headRefName,baseRefName
```

- **PR found**: Show title and URL, proceed to Step 2.
- **No PR for this branch**: Ask via AskUserQuestion for the PR number or URL. Call `mcp__github__pull_request_read` with the provided number to load it.

### Step 2: Read Review Comments

Call `mcp__github__pull_request_read` to fetch:
- All inline review threads (file path + line number + comment body + thread node ID)
- All general PR-level comments
- Review summaries (CHANGES_REQUESTED, APPROVED, COMMENTED)

Filter to **unresolved** threads only.

If `pull_request_read` returns no review threads, fall back to:

```bash
gh pr view <number> --comments
```

### Step 3: Analyze and Categorize Comments

For each unresolved comment or thread, assign one of these categories:

| Category | Meaning | Default action |
|----------|---------|----------------|
| **Actionable** | Requests a concrete code change | Implement |
| **Question** | Asks for clarification or explanation | Answer in reply |
| **Suggestion / Nitpick** | Optional improvement, style preference | Implement or politely decline |
| **Inaccurate / Mistaken** | Reviewer misunderstood the code | Reply with explanation, no code change |

Also note any comment that suggests updating the PR title or description.

### Step 4: Present Analysis and Confirm Plan

Display a structured table of all unresolved comments:

```
# Review Comments — <PR title>

| # | Reviewer | File / Location | Category | Proposed Action |
|---|----------|-----------------|----------|-----------------|
| 1 | @alice   | src/auth.ts:42  | Actionable | Rename variable x → y |
| 2 | @bob     | (general)       | Question   | Answer: explain why we chose X |
| 3 | @alice   | src/auth.ts:88  | Nitpick    | Implement (minor change) |
| 4 | @bob     | src/models.ts:5 | Inaccurate | Explain the existing logic |
```

Ask via AskUserQuestion: "Does this plan look right? Anything to adjust before I proceed?"

The user may override any classification or skip specific comments before continuing.

### Step 5: Implement Code Changes

For each **Actionable** or accepted **Suggestion** comment, working in file order (not comment order):

1. Read the relevant file(s) to understand the current state.
2. Apply the change using Edit or MultiEdit.
3. Note the change made — this text is used in the reply in Step 8.

Group edits by file; apply all changes to the same file in a single pass where possible.

Do **not** commit yet. Proceed through all changes before staging.

### Step 6: Stage and Commit Changes

Skip this step entirely if no code changes were made (only questions or inaccurate comments).

1. Run `mcp__git__git_status()` to confirm which files were modified.
2. Stage all modified files: `mcp__git__git_add(files)`.
3. Run `mcp__git__git_diff_staged()` to review what will be committed.
4. Propose a commit message:
   - Single line, plain English
   - No conventional prefixes (`feat:`, `fix:`, etc.)
   - No attribution
   - Example: "Address review feedback — rename variable, extract helper"
5. Confirm with AskUserQuestion (allow the user to edit the message).
6. Commit: `mcp__git__git_commit(message)`.

### Step 7: Push

```bash
git push
```

- **Success**: Proceed to Step 8.
- **Non-fast-forward**: The remote branch has diverged. Ask via AskUserQuestion whether to pull with rebase first (`git pull --rebase origin <branch>`).

Skip this step if no commit was made in Step 6.

### Step 8: Reply to Each Comment

For every comment in the confirmed plan, post a reply via `mcp__github__add_reply_to_pull_request_comment`:

| Comment type | Reply text |
|-------------|-----------|
| Actionable (implemented) | "Done — [brief description of change, e.g. 'renamed `x` to `userId`']." |
| Question | A clear, concise answer to the question (1–3 sentences). |
| Suggestion (implemented) | "Good call, applied." |
| Suggestion (declined) | "Thanks for the suggestion — keeping the current approach because [reason]." |
| Inaccurate | Politely explain the correct interpretation (e.g. "This `x` is intentionally `null` here because…"). |

Replies must be concise (1–3 sentences). Do not add "Generated with Claude Code" or any attribution.

### Step 9: Resolve Threads (optional)

Ask via AskUserQuestion: "Mark the addressed threads as resolved?"

- **Yes**: For each implemented or answered thread, resolve via GraphQL using the thread node ID from `pull_request_read`:
  ```bash
  gh api graphql -f query='mutation { resolveReviewThread(input: { threadId: "<thread_node_id>" }) { thread { isResolved } } }'
  ```
- **No**: Skip — the reviewer can resolve threads manually.

### Step 10: Update PR Description (optional)

If any comment suggested updating the PR title or description, or if the implemented changes materially changed the PR's scope:

1. Show the current title and body.
2. Propose updated versions.
3. Confirm with AskUserQuestion.
4. Update via `mcp__github__update_pull_request(owner, repo, pull_number, title?, body?)`.

Skip this step if no description changes are warranted.

### Step 11: Summary

Print a final summary:

```
Review addressed
-----------------
PR:        #42 — Add avatar upload to user profile
Commit:    "Address review feedback — rename variable, extract helper"
Pushed:    yes

Comments addressed:
  ✓ @alice  src/auth.ts:42    — implemented (renamed x → userId)
  ✓ @bob    (general)         — answered question about approach
  ✓ @alice  src/auth.ts:88    — implemented (extracted helper)
  ✓ @bob    src/models.ts:5   — explained existing logic

Threads resolved: 3/4 (1 left for reviewer)
PR description:   updated

Next steps:
- Request a re-review: tag reviewer(s) in a PR comment
- Merge when approved: /github:release
```

Adjust based on what actually happened (omit lines for skipped steps).

## Error Handling

| Situation | Action |
|-----------|--------|
| No PR found for current branch | Ask for PR number or URL via AskUserQuestion |
| No unresolved review comments | Report "No unresolved review comments on this PR" and exit |
| `pull_request_read` returns no review threads | Fall back to `gh pr view --comments` via Bash |
| Code change conflicts with current file state | Show the diff, ask the user to resolve manually before continuing |
| `add_reply_to_pull_request_comment` fails | Note in summary; show the generated reply text so the user can post it manually |
| GraphQL resolve thread fails | Note in summary; suggest the reviewer resolves the thread manually |
| `update_pull_request` fails | Show the proposed title/body so the user can update it manually |
| Push non-fast-forward | Offer to pull with rebase first: `git pull --rebase` |
| Nothing to commit (only questions/inaccurate) | Skip Steps 6 and 7 silently, continue to Step 8 |

## Reference Files

- No additional reference files — PR data is fetched from the GitHub MCP at runtime.
