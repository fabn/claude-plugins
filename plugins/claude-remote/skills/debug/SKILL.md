---
name: claude-remote:debug
description: |
  This skill should be used when a Claude Code web (cloud) session is not
  working correctly after /claude-remote:setup was run, or when the user
  suspects the web-UI Setup script is misconfigured. Reads
  /tmp/claude-user-setup.log, verifies repo-side files
  (.claude/scripts/setup.sh, .claude/scripts/session-start.sh,
  .claude/settings.json), checks the web-UI script against the canonical
  reference bundled with this plugin, matches log patterns to known failure
  modes, and prints a concrete fix.
  Activates on: "debug claude remote", "claude remote broken",
  "claude web session broken", "setup script failed", "remote session not
  working", "diagnose cloud session", "why is my remote session failing",
  "debug /tmp/claude-user-setup.log", "diagnostica claude remote",
  "sessione cloud rotta".
---

# Claude Remote Debug Skill

Diagnose why a Claude Code web (cloud) session isn't working. The user-level
setup script, the per-repo setup script, and the SessionStart hook all log
to a single file — `/tmp/claude-user-setup.log` — which makes this a
log-first workflow.

## Reference files

- `${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh` — canonical
  user-level script. Any deployed copy is compared against this.
- `${CLAUDE_PLUGIN_ROOT}/skills/debug/reference/troubleshooting.md` —
  pattern → diagnosis → fix table. **Read this early.**
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/session-start-template.sh`
  and `repo-setup-template.sh` — reference templates for what the repo
  files should look like.

## Tools Used

- **Read**: `/tmp/claude-user-setup.log`, repo settings/scripts, reference files
- **Grep**: pattern-match log lines against known failure modes
- **Bash**: `diff` against canonical script, `jq` on settings.json, runtime health checks
- **Glob**: verify repo files exist

## Workflow

### Step 1: Load the troubleshooting reference

Read `${CLAUDE_PLUGIN_ROOT}/skills/debug/reference/troubleshooting.md` in
full. The log patterns + fixes table guides the rest of this workflow.

### Step 2: Read the log

```bash
tail -n 500 /tmp/claude-user-setup.log 2>&1 || echo "LOG_MISSING"
```

- **If `LOG_MISSING`**: either the user never started a remote session, or
  the web UI "Setup script" field is empty. Show them
  `${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh` and point them at
  `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/web-environment.md` for
  paste instructions. Stop here.
- **If present**: continue.

### Step 3: Verify phase markers

Grep for the canonical marker lines:

- `=== User setup started at`
- `[1/4] Installing permissive settings`
- `[2/4] Installing mise`
- `[3/4] Installing common CLI tools`
- `[4/4] Delegating to repository setup`
- `=== User setup complete at`
- `=== Repo setup started at`
- `=== Repo setup complete at`

Determine the furthest marker reached. If any marker is missing, the
script aborted between that marker and the previous one. Show the last
30 lines above the point of failure.

### Step 4: Pattern-match against troubleshooting.md

For each log pattern in `troubleshooting.md`, grep the log. Collect every
match with its diagnosis and fix. Don't stop at the first hit — there may
be multiple independent failures.

### Step 5: Repo-state audit

Run these checks in the current working directory:

- `Glob(".claude/scripts/setup.sh")` — exists? executable?
- `Glob(".claude/scripts/session-start.sh")` — exists? executable?
- `Read(".claude/settings.json")` and verify:
  - `enabledPlugins["claude-remote@fabn-claude-plugins"] === true`
  - `extraKnownMarketplaces["fabn-claude-plugins"]` present
  - At least one `hooks.SessionStart[].hooks[].command` matches
    `.claude/scripts/session-start.sh`
- `jq . .claude/settings.json` to confirm valid JSON

Report each failing check with a concrete remediation (usually: re-run
`/claude-remote:setup`).

### Step 6: Canonical drift check (optional, user-assisted)

Ask the user (via `AskUserQuestion`) whether they still have a local copy
of the script they pasted into the web UI. Common locations:

- `~/.claude/scripts/setup.sh`
- A pasted block in notes / clipboard manager

If they provide one, `diff` it against
`${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh` and report any
drift. The canonical file is authoritative — any difference means the web
UI is stale and needs re-pasting.

### Step 7: Live health check (only if inside a remote session)

If `CLAUDE_CODE_REMOTE=true` in the current environment, re-run the
health checks that `session-start.sh` performs:

```bash
command -v mise ruby bundle node npm
mysqladmin ping --silent 2>&1 || echo "mysql down"
pg_isready -q 2>&1 || echo "postgres down"
redis-cli ping 2>&1 || echo "redis down"
```

Compare to what `session-start.sh` last reported (`SETUP INCOMPLETE: ...`
line in the log). If anything regressed since session start, that's a
mid-session service crash — not a setup bug.

### Step 8: Full environment dump (optional, only when earlier steps are inconclusive)

If Steps 3–7 haven't pinpointed the root cause — e.g. the log shows all
markers but something still doesn't work, or the failure mode doesn't
match any pattern in `troubleshooting.md` — run the bundled environment
dump script for a comprehensive snapshot:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/debug-environment.sh"
```

This tees a full report to `/tmp/claude-env-debug.log` covering identity,
PATH, tool versions, running services, listening ports, `CLAUDE_ENV_FILE`
contents, `mise ls`/`mise settings`, shell init files, and the tail of
`/tmp/claude-user-setup.log`. Read the output and look for:

- Missing runtimes that should have been installed in the setup phase
- Services listed in the expected ports list but not present
- `CLAUDE_ENV_FILE` unset or empty (PATH persistence block of
  `session-start.sh` didn't run)
- `mise ls` showing versions different from `mise.toml`
- Shell init files missing the `mise activate bash` line

Skip this step on quick/obvious failures — it produces ~200 lines of
output and should only be invoked when the cheap pattern-matching above
hasn't been enough.

### Step 9: Summarize

Produce a structured report:

```
## Status
- Furthest phase reached: [marker]
- Detected failures: N

## Root cause
[the single most likely cause, drawn from Step 4 / Step 5]

## Fix
[specific file + edit, or specific command to run]

## Validate
[command to re-run locally or in a new remote session to confirm]
```

## Error handling

| Symptom | Action |
|---|---|
| `/tmp/claude-user-setup.log` exists but is empty | User-level script started then was killed before any output; check web UI logs for OOM / timeout |
| Log shows repeated `[1/3]...[2/3]...[3/3]` cycles | Session is being resumed and the setup script isn't actually being re-run — that's expected; only the SessionStart hook runs on resume. Look for hook output below the last repo-setup block. |
| Repo files look fine but session-start hook never runs | `.claude/settings.json` likely has a syntax error; `jq .` will catch it. Fall back to reading raw bytes. |
