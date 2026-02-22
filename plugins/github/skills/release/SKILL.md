---
name: github:release
description: |
  This skill should be used when the user wants to publish a draft release
  created by Release Drafter. Finds the draft release, checks CI status on
  main, confirms with the user, and publishes. Does NOT merge PRs — it only
  handles the release publishing step.
  Activates on: "release", "publish release", "draft release", "ship release",
  "cut a release", "publish draft", "release drafter", "make a release",
  "rilascio", "pubblicare release", "rilasciare versione".
---

# GitHub Release Skill

Publish a draft release created by [Release Drafter](https://github.com/release-drafter/release-drafter). This skill finds the latest draft, verifies CI is green on main, asks for confirmation, and publishes.

**Scope:** This skill handles release publishing only. It does NOT merge PRs — merge your PR first, then run this skill to publish the resulting draft release.

## Tools Used

- **Bash**: `gh` CLI for repo info, CI status, release publishing
- **GitHub MCP** (`github`): `list_releases` for finding draft releases, `get_me` for auth verification
- **AskUserQuestion**: Mandatory confirmation before publishing
- **ToolSearch**: Discover GitHub MCP tools if not already available

## Workflow

### Step 1: Detect Repository Context

Run `gh repo view --json owner,name` to get the current repository's owner and name.

- If not in a git repository, stop and tell the user to navigate to one
- Confirm the detected repo with the user context (e.g., "Working with owner/repo")

### Step 2: Find Draft Release

Use the GitHub MCP tool to list recent releases:

```
mcp__github__list_releases(owner, repo, perPage: 10)
```

Search the results for releases with `draft: true`.

**Handle edge cases:**
- **No draft found**: Tell the user no draft release exists. Suggest:
  - Check that Release Drafter is configured in the repo
  - Verify a PR was merged recently (Release Drafter creates/updates drafts on merge)
  - Check Release Drafter's workflow run for errors: `gh run list --workflow release-drafter.yml`
- **Multiple drafts found**: Present all drafts to the user via `AskUserQuestion` and ask which one to publish. Show tag name, title, and creation date for each.
- **Single draft found**: Proceed with it. Show the tag, title, and changelog preview.

### Step 3: Check CI on Main

Verify that CI is passing on the main branch:

```bash
gh run list --branch main --limit 5 --json status,conclusion,name,databaseId,headSha
```

- **All completed and successful**: Proceed
- **Any in progress**: Wait for them with `gh run watch <RUN_ID> --exit-status`
- **Any failed**: Stop and report the failure. Show which workflow failed and link to the run. Do NOT proceed to publish with failing CI.
- **No runs found**: Warn the user but allow proceeding (repo may not have CI)

### Step 4: Confirm with User

Present a summary via `AskUserQuestion` before publishing. This step is **mandatory** — never publish without explicit user confirmation.

Show:
- **Tag**: The release tag (e.g., `v1.2.3`)
- **Title**: The release title
- **CI status**: All green / warnings
- **Changelog preview**: First 10-15 lines of the release body

Ask: "Publish this release?" with options:
- **Publish** — Proceed with publishing
- **Cancel** — Abort without changes

### Step 5: Publish Release

Use the `gh` CLI to publish the draft:

```bash
gh release edit <TAG> --draft=false
```

After publishing, verify it succeeded:

```bash
gh release view <TAG> --json tagName,url,isDraft,publishedAt
```

- Confirm `isDraft` is `false`
- If publishing fails, report the error and suggest checking permissions

### Step 6: Report Summary

Present the final summary:

```
## Release Published

**Tag:**       v1.2.3
**URL:**       https://github.com/owner/repo/releases/tag/v1.2.3
**CI status:** All workflows passed
**Published:** 2025-01-15T10:30:00Z

### Changelog
- Feature: Add user authentication (#42)
- Fix: Resolve memory leak in worker (#38)
- Chore: Update dependencies (#35)
```

Include the full changelog from the release body.

## Error Handling

| Situation | Action |
|-----------|--------|
| `gh` CLI not installed | Stop, tell user to run `/github:setup` |
| `gh` not authenticated | Stop, tell user to run `gh auth login` or `/github:setup` |
| Not in a git repository | Stop, tell user to navigate to a git repository |
| No draft release found | Explain Release Drafter may not be configured, suggest checking workflow |
| Multiple draft releases | Present all to user, ask which to publish |
| CI in progress on main | Wait with `gh run watch`, then re-check |
| CI failed on main | Stop, report which workflow failed, do NOT publish |
| User declines to publish | Abort gracefully, no changes made |
| `gh release edit` fails | Report error, suggest checking repo permissions (write access required) |
| Release already published | Inform user the release is already live, no action needed |

## Related Skills

- **`/github:setup`** — Verify prerequisites (gh CLI, authentication, MCP token)
