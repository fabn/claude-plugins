---
name: github:release-drafter
description: |
  This skill should be used when the user wants to configure release-drafter
  on a repository — either setting it up fresh or migrating from v6 to v7.
  Handles versioning strategy (semver or date-based CalVer), autolabeler
  configuration, and optional post-release workflow generation.
  Activates on: "release drafter", "setup release drafter", "configure release drafter",
  "install release drafter", "release drafter setup", "upgrade release drafter",
  "migrate release drafter", "release drafter v7", "release drafter v6",
  "configurare release drafter", "configurazione release drafter", "aggiornare release drafter".
---

# GitHub Release Drafter Skill

Configures [release-drafter v7](https://github.com/release-drafter/release-drafter) on any repository — either from scratch or by migrating an existing v6 setup to v7. Guides through versioning strategy (semver or CalVer), tag prefix, autolabeler setup, and optional post-release actions. All YAML templates are read from reference docs at runtime; nothing is embedded inline in this skill.

After configuring release-drafter with this skill, use `/github:release` to publish draft releases.

## Tools Used

- **Bash**: `ls`, `cat` — detect existing setup in `.github/`, read workflow and config files
- **Read**: Load reference docs at runtime — `reference/config-reference.md`, `reference/migration-checklist.md`, `reference/date-based-versioning.md` — for templates and migration steps
- **Write**: Create new workflow and config files (fresh setup path)
- **Edit**: Patch existing workflow files (upgrade path) — preserves existing config, categories, and labels
- **AskUserQuestion**: Sequential prompts for versioning strategy, tag prefix, autolabeler approach, post-release actions, and mandatory pre-write confirmation
- **mcp__git__git_add** / **mcp__git__git_commit**: Stage and commit all generated files

## Workflow

### Step 1: Detect Existing Setup

Run the following commands to inspect the current state of `.github/`:

```bash
ls .github/workflows/ 2>/dev/null
cat .github/workflows/release-drafter.yml 2>/dev/null
cat .github/release-drafter.yml 2>/dev/null
```

Branch based on what is found:

- **Neither file exists** — proceed to Step 2 (fresh setup)
- **Workflow contains `release-drafter/release-drafter@v6`** — show what was detected (action version, token style, whether autolabeler is embedded), then ask via AskUserQuestion:
  - "Upgrade existing v6 setup to v7" → go to **Upgrade Flow (Step U1)**
  - "Start fresh (existing files will be overwritten)" → warn user that existing files will be replaced and confirm before continuing to Step 2
- **Workflow contains `release-drafter/release-drafter@v7`** — inform the user release-drafter v7 is already configured. Show the detected settings (action version, CalVer or semver, autolabeler approach). Ask via AskUserQuestion:
  - "Reconfigure (re-run setup questions)" → continue to Step 2
  - "Exit — keep current setup" → stop here, no changes
- **Config file exists but workflow is missing** — partial setup detected. Offer to create the missing workflow file. If user agrees, go to Step 2 (the skill will skip writing the config since it already exists, but proceed through questions for workflow generation).

### Step 2: Ask Versioning Strategy

Ask via AskUserQuestion: "Which versioning strategy should release-drafter use?"

Options:
- **Semver (recommended)** — release-drafter resolves version from PR labels (major / minor / patch). Tags like `v1.2.3`. Best for libraries, APIs, and any project where breaking changes need semantic signaling.
- **Date-based (CalVer)** — `YYYY.MM.DD` format with `.N` suffix for same-day collisions. Tags like `v2026.04.02` or `2026.04.02.2`. Good for infrastructure repos, config-driven projects, and continuous delivery pipelines.

Store the choice for use in Steps 3, 4, and 7.

### Step 3: Ask Tag Prefix

Ask via AskUserQuestion: "What tag prefix should release-drafter use?"

Options:
- **`v` (default)** — tags like `v1.2.3` or `v2026.04.02`
- **None** — tags like `1.2.3` or `2026.04.02`
- **Custom** — user types their own prefix (e.g., `release-`)

Store the choice. This affects both `tag-template` and `name-template` in the config, and also the CalVer tag-list pattern in Step 7 if CalVer was chosen.

### Step 4: Ask Autolabeler Opt-in

Ask via AskUserQuestion: "Do you want to configure autolabeler? Autolabeler automatically labels PRs based on branch names and changed file paths."

Options:
- **Yes, separate workflow (recommended)** — creates a dedicated `.github/workflows/autolabeler.yml` using `release-drafter/release-drafter/autolabeler@v7` with its own `pull_request` trigger. The main drafter workflow stays clean (push-only). Cleaner separation of concerns; autolabeler gets only `pull-requests: write`, drafter gets only `pull-requests: read`.
- **Yes, monolithic** — a single `.github/workflows/release-drafter.yml` handles both drafting (on push) and labeling (on PR events) using v7's `disable-releaser` / `disable-autolabeler` conditional flags. Simpler single-file setup.
- **No** — skip autolabeler workflow entirely. The `autolabeler:` stanza will still be included in `.github/release-drafter.yml` as a template for future use.

**Important:** Regardless of approach, the `autolabeler:` stanza always lives in `.github/release-drafter.yml`. Only the workflow trigger changes.

### Step 5: Ask Post-Release Actions

Ask via AskUserQuestion: "Do you want a post-release workflow (`.github/workflows/release.yml`) that triggers when a release is published?"

Common use cases: deploy to production, publish to a package registry (npm, RubyGems, PyPI), build and upload release artifacts, send Slack/email notifications.

Options:
- **Yes** — ask the user to describe what should happen when a release is published. Generate a minimal, customized `release.yml` skeleton based on their description. This is LLM-generated output, not a fixed template — tailor it to the user's actual intent.
- **No** — skip post-release workflow

### Step 6: Show Summary and Confirm

Before writing any files, present a summary table via AskUserQuestion. Do NOT write any files before this confirmation.

Show a table of all files that will be created:

| File | Action | Key config |
|------|--------|------------|
| `.github/release-drafter.yml` | Create | Semver or CalVer; `v` prefix (or custom); categories; autolabeler rules |
| `.github/workflows/release-drafter.yml` | Create | Trigger: push to main; v7; semver or CalVer steps |
| `.github/workflows/autolabeler.yml` | Create (if Option B) | Separate action; reads release-drafter.yml config |
| `.github/workflows/release.yml` | Create (if opted in) | Trigger: release published; [user-described actions] |

Populate the "Key config" column with the actual choices the user made. Ask: "Create these files?" with options:
- **Proceed** — write the files
- **Cancel** — abort gracefully, no files written

### Step 7: Generate Files

Read `reference/config-reference.md` and locate the relevant sections. Then generate each file:

**`.github/release-drafter.yml` (config file):**

Read section `## v7 Config Template` from `reference/config-reference.md`. Adapt as follows:
- **Tag prefix:** If user chose no prefix, replace `v$RESOLVED_VERSION` with `$RESOLVED_VERSION` in both `name-template` and `tag-template`. If user chose a custom prefix, replace `v` with that prefix.
- **CalVer:** If user chose CalVer, omit the `version-resolver:` block entirely (per `reference/date-based-versioning.md` section `## CalVer Compatibility Warnings` — leaving `version-resolver` in with CalVer causes confusion).
- **Autolabeler stanza:** Always include the `autolabeler:` stanza regardless of which autolabeler workflow approach was chosen. The stanza lives in the config file, not the workflow.

**`.github/workflows/release-drafter.yml` (drafter workflow):**

Read section `## v7 Workflow Template` from `reference/config-reference.md`. Adapt as follows:
- **Semver:** Use the template as-is (checkout not required for semver).
- **CalVer:** Read section `## CalVer Workflow Integration` from `reference/date-based-versioning.md`. Replace the single `release-drafter@v7` step with the three-step sequence (checkout with `fetch-depth: 0`, CalVer computation, release-drafter with `version:` input). Adapt the `git tag --list` pattern for the tag prefix chosen in Step 3:
  - With `v` prefix: `git tag --list "v${DATE}*"`
  - With no prefix: `git tag --list "${DATE}*"`
  - With custom prefix: `git tag --list "<prefix>${DATE}*"`
- **Monolithic autolabeler (if user chose monolithic):** Add `pull_request: types: [opened, reopened, synchronize]` to the `on:` block. Add `disable-releaser: ${{ github.event_name == 'pull_request' }}` and `disable-autolabeler: ${{ github.event_name == 'push' }}` inputs to the release-drafter step. Change `pull-requests: read` to `pull-requests: write` on the job permissions (labeling requires write).

**`.github/workflows/autolabeler.yml` (if user chose separate workflow):**

Read section `## v7 Autolabeler Workflow Template` from `reference/config-reference.md`. Use that template as-is.

**`.github/workflows/release.yml` (if user opted in):**

Generate a minimal workflow skeleton based on the user's description from Step 5. Use `on: release: types: [published]` as the trigger. Structure the job steps according to what the user described (deploy, publish, notify, etc.). This is LLM-generated — tailor it to their actual use case.

Write all files using the Write tool.

### Step 8: Commit Files

Stage all generated files:

```
mcp__git__git_add([".github/release-drafter.yml", ".github/workflows/release-drafter.yml"])
```

Add `.github/workflows/autolabeler.yml` and `.github/workflows/release.yml` to the list if they were created.

Propose a plain-English commit message (no conventional prefixes). Examples:
- "Add release-drafter v7 configuration with semver versioning"
- "Add release-drafter v7 with CalVer date-based versioning and split autolabeler"

Confirm the message with the user via AskUserQuestion, then commit:

```
mcp__git__git_commit(message)
```

If `mcp__git__git_commit` fails, fall back to:

```bash
git add .github/release-drafter.yml .github/workflows/release-drafter.yml \
  .github/workflows/autolabeler.yml .github/workflows/release.yml
git commit -m "Add release-drafter v7 configuration"
```

### Step 9: Report Summary

Present a final summary showing:
- Which files were created
- Versioning strategy and tag prefix chosen
- Autolabeler approach
- Whether a post-release workflow was included
- Next steps

Include: "Use `/github:release` to publish draft releases after PRs are merged to main."

---

## Upgrade Flow

Branched from Step 1 when `release-drafter/release-drafter@v6` is detected in the existing workflow.

### Upgrade Step U1: Show Detected Setup

Display what was found in the existing files:
- Action version (`@v6`)
- Token handling style (`env: GITHUB_TOKEN` vs `with: token`)
- Whether autolabeler is embedded in the monolithic workflow (look for `pull_request` trigger and `disable-releaser` / `disable-autolabeler` flags)
- Current categories and labels from `.github/release-drafter.yml`

### Upgrade Step U2: Ask Autolabeler Preference

If the existing v6 workflow embeds autolabeler (has both `push` and `pull_request` triggers), ask via AskUserQuestion:

- **Keep monolithic (minimal change)** — update action version and token handling only. Keep autolabeler in the same workflow using v7's `disable-releaser` / `disable-autolabeler` flags. Lowest-effort migration.
- **Split to separate workflow (recommended)** — extract autolabeler to its own `.github/workflows/autolabeler.yml`. The main drafter workflow becomes push-only. Cleaner architecture.

Read section `## Autolabeler Migration` from `reference/migration-checklist.md` for the exact before/after snippets for each option.

If the existing v6 workflow does NOT embed autolabeler (push-only trigger), skip this question — the upgrade is purely version and token updates.

### Upgrade Step U3: Show Migration Summary and Confirm

Present a summary table via AskUserQuestion before making any edits:

| File | Change | What stays the same |
|------|--------|---------------------|
| `.github/workflows/release-drafter.yml` | Update action to @v7; update token handling; update permissions | All triggers, job names, all other inputs and steps |
| `.github/workflows/autolabeler.yml` | CREATE new file (if split chosen) | — |
| `.github/release-drafter.yml` | No changes | All categories, labels, autolabeler rules, templates |

Ask: "Apply these changes?" — Proceed / Cancel

### Upgrade Step U4: Apply Migration

Read section `## Migration Checklist` from `reference/migration-checklist.md` for the ordered steps.

Use **Edit** (not Write) for all changes to the existing workflow file. Preserve everything not explicitly listed below:

1. Change `release-drafter/release-drafter@v6` to `release-drafter/release-drafter@v7`
2. Replace the `env:` block (`env: GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}`) with `with: token: ${{ github.token }}`
3. Change `pull-requests: write` to `pull-requests: read` on the drafter job (write is no longer required for changelog generation)
4. **If user chose split:** Remove the `pull_request` trigger from the main workflow. Remove `disable-releaser` and `disable-autolabeler` inputs. Create `.github/workflows/autolabeler.yml` using the `## v7 Autolabeler Workflow Template` section from `reference/config-reference.md`.
5. **If user chose monolithic:** Update the action version and token only. Keep `pull_request` trigger and `disable-releaser` / `disable-autolabeler` flags. Update permissions to `pull-requests: write` on the job (monolithic still requires write for labeling).

**CRITICAL: Do NOT modify `.github/release-drafter.yml`** during the upgrade. The v6 and v7 config structures are identical — the config file requires no changes. Only modify the config if the user explicitly requests category or label changes.

### Upgrade Step U5: Commit and Report

Stage and commit the changed files:

```
mcp__git__git_add([".github/workflows/release-drafter.yml"])
```

Add `.github/workflows/autolabeler.yml` to the list if it was created.

Propose a plain-English commit message. Example: "Upgrade release-drafter from v6 to v7 with split autolabeler workflow"

Report:
- Which files were modified and how
- What was preserved (config, categories, labels)
- Verification instructions: "Run `gh run list --workflow release-drafter.yml` after merging to verify the v7 workflow works. Open a test PR to verify autolabeler applies labels correctly."

---

## Error Handling

| Situation | Action |
|-----------|--------|
| `.github/` directory does not exist | Create it with `mkdir -p .github/workflows` before writing any files |
| Existing files found during fresh setup | Warn user, route to upgrade flow; if user insists on fresh start, confirm before overwriting |
| v6 detected but config is heavily customized | Preserve all existing config (use Edit not Write); only change what v7 requires; inform user what was kept |
| `mcp__git__git_commit` fails | Fall back to `Bash(git add ... && git commit -m "...")` |
| User cancels at confirmation step | Abort gracefully; no files written or edited |
| Workflow file has non-standard structure | Warn user; apply changes best-effort; suggest manual review after committing |
| CalVer + custom tag prefix | Adapt the `git tag --list` pattern: use `"<prefix>${DATE}*"` instead of `"v${DATE}*"` |
| Already on v7 | Inform user v7 is already configured; show detected settings; offer reconfiguration or exit |
| Partial setup (config exists, workflow missing) | Offer to create the missing workflow; skip re-creating the config |
| Post-release workflow generation is unclear | Ask the user to describe the trigger condition and desired action in more detail before generating |
| `.github/release-drafter.yml` modified during upgrade (mistake) | Restore from git: `git checkout HEAD -- .github/release-drafter.yml` |

## Related Skills

- **`/github:release`** — Publish draft releases created by Release Drafter
- **`/github:setup`** — Verify prerequisites (gh CLI, authentication, MCP token)
- **`/github:feature`** — Create a branch, commit, push, and open a pull request

## Reference Files

- `reference/config-reference.md` — Complete YAML templates for v6 and v7 workflows and config
- `reference/migration-checklist.md` — v6-to-v7 migration steps and before/after snippets
- `reference/date-based-versioning.md` — CalVer format, collision handling, and inline bash computation script
