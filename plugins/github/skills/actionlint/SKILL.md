---
name: github:actionlint
description: |
  This skill should be used when the user wants to configure actionlint CI
  on a repository to automatically lint GitHub Actions workflow files on
  push and pull request events using reviewdog/action-actionlint.
  Activates on: "actionlint", "setup actionlint", "configure actionlint",
  "lint actions", "lint workflows", "lint github actions", "action linter",
  "workflow linting", "configurare actionlint", "lint azioni github",
  "lint workflow github".
---

# GitHub Actionlint Skill

Configures [actionlint](https://github.com/rhysd/actionlint) CI on any repository using [reviewdog/action-actionlint](https://github.com/reviewdog/action-actionlint). The workflow lints `.github/workflows/` files on push and pull request, reporting errors inline on PRs via reviewdog.

## Tools Used

- **Bash**: `ls`, `cat` — detect existing setup in `.github/workflows/`
- **Read**: Load reference docs at runtime — `reference/workflow-template.md` — for the workflow YAML template and configuration notes
- **Write**: Create the workflow file (fresh setup path)
- **Edit**: Patch the existing workflow file (reconfigure path)
- **AskUserQuestion**: Prompts for target branch, fail level, and mandatory pre-write confirmation
- **mcp__git__git_add** / **mcp__git__git_commit**: Stage and commit the generated workflow file

## Workflow

### Step 1: Detect Existing Setup

Run the following commands to inspect the current state of `.github/workflows/`:

```bash
ls .github/workflows/ 2>/dev/null
cat .github/workflows/actionlint.yml 2>/dev/null
cat .github/workflows/actionlint.yaml 2>/dev/null
```

Branch based on what is found:

- **No actionlint workflow exists** — proceed to Step 2 (fresh setup)
- **Workflow file exists** — show current configuration (action version, target branch, fail level, reporter). Ask via AskUserQuestion:
  - "Reconfigure (re-run setup questions)" — continue to Step 2; the existing file will be overwritten
  - "Exit — keep current setup" — stop here, no changes

### Step 2: Ask Configuration Options

Detect the default branch by running:

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||'
```

If detection fails, default to `main`.

Ask via AskUserQuestion with the following options. Show the detected branch and recommended defaults:

**Target branch** (default: detected branch):
- Use detected branch (e.g., `main`)
- Enter a different branch name

**Fail level** — the severity at which actionlint causes the check to fail:
- **`error` (recommended)** — only errors fail the check; warnings are reported but non-blocking
- **`warning`** — both errors and warnings fail the check

Store the choices for use in Steps 3 and 4.

### Step 3: Show Summary and Confirm

Before writing any files, present a summary table via AskUserQuestion. Do NOT write any files before this confirmation.

| File | Action | Key config |
|------|--------|------------|
| `.github/workflows/actionlint.yml` | Create | Branch: `main`; fail level: `error`; reporter: auto-detect (PR check / push check) |

Populate the "Key config" column with the actual choices the user made. Ask: "Create this file?" with options:
- **Proceed** — write the file
- **Cancel** — abort gracefully, no files written

### Step 4: Generate Workflow File

Read `reference/workflow-template.md` and locate the `## Workflow Template` section. Then generate the workflow file:

**`.github/workflows/actionlint.yml`:**

Adapt the template as follows:
- **Target branch:** Replace `main` with the user's choice in both the `push.branches` and `pull_request.branches` arrays
- **Fail level:** Replace `error` with the user's choice in the `fail_level` input

Write the file using the Write tool. If `.github/workflows/` does not exist, create it first with `mkdir -p .github/workflows`.

### Step 5: Commit and Report

Stage the generated file:

```
mcp__git__git_add([".github/workflows/actionlint.yml"])
```

Propose a plain-English commit message (no conventional prefixes). Examples:
- "Add actionlint CI workflow to lint GitHub Actions"
- "Add actionlint workflow for GitHub Actions linting"

Confirm the message with the user via AskUserQuestion, then commit:

```
mcp__git__git_commit(message)
```

If `mcp__git__git_commit` fails, fall back to:

```bash
git add .github/workflows/actionlint.yml
git commit -m "Add actionlint CI workflow"
```

Present a final summary showing:
- Which file was created
- Target branch and fail level chosen
- How the reporter works (auto-detects PR vs push context)
- Next steps: "Push the branch and open a PR to activate the workflow. Actionlint will run automatically on any future changes to `.github/workflows/`."

---

## Error Handling

| Situation | Action |
|-----------|--------|
| `.github/workflows/` directory does not exist | Create it with `mkdir -p .github/workflows` before writing |
| Existing actionlint workflow found | Show current config, offer reconfigure or exit |
| Default branch detection fails | Fall back to `main`, mention it to the user |
| `mcp__git__git_commit` fails | Fall back to `Bash(git add ... && git commit -m "...")` |
| User cancels at confirmation step | Abort gracefully; no files written |

## Related Skills

- **`/github:setup`** — Verify prerequisites (gh CLI, authentication, MCP token)
- **`/github:feature`** — Create a branch, commit, push, and open a pull request

## Reference Files

- `reference/workflow-template.md` — Complete workflow YAML template, configuration notes, and local usage instructions
