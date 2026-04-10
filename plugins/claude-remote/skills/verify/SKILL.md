---
name: claude-remote:verify
description: |
  This skill should be used when the user wants to confirm a Claude Code
  web (cloud) session is ready to work — runtimes installed, services up,
  environment healthy — before acting on their request. Parses the
  generated .claude/scripts/setup.sh and .claude/scripts/session-start.sh
  to derive the expected toolset dynamically (instead of hardcoding), runs
  a deterministic battery of checks, reports PASS/FAIL, and offers to
  chain into /claude-remote:debug for a full diagnosis on failure.
  Activates on: "verify claude remote", "verify remote session",
  "check tools", "check environment", "am I ready", "ready to work",
  "are all tools installed", "session ready", "health check claude remote",
  "verifica claude remote", "verifica ambiente", "tutto a posto",
  "tutto installato", "pronti a lavorare", "verifica tool".
---

# Claude Remote Verify Skill

Quick happy-path confirmation that a Claude Code web (cloud) session is
ready to work. Derives the expected toolset by **parsing the generated
`.claude/scripts/setup.sh` and `.claude/scripts/session-start.sh`**
rather than hardcoding a list — so a Flutter repo is verified against
`fvm`/`flutter`, a Rails repo against `bundle`/`ruby`, without this skill
needing to know every stack.

This is the **fast proactive check** (run at session start). For deep
reactive diagnosis when something is broken, use `/claude-remote:debug` —
verify will offer to chain into it automatically on failure.

## Reference files

- `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/repo-setup-template.sh` —
  reference for the section markers and conventions used by generated
  setup scripts.
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/session-start-template.sh` —
  reference for the `ISSUES+=("...")` healthcheck pattern.
- `${CLAUDE_PLUGIN_ROOT}/skills/debug/reference/troubleshooting.md` —
  used when chaining into debug.

## Tools Used

- **Read**: `.claude/scripts/setup.sh`, `.claude/scripts/session-start.sh`,
  `.claude/settings.json`, `mise.toml` (if present)
- **Grep**: extract `ISSUES+=("...")` lines, `service X start` invocations,
  and package-manager install hints from the generated scripts
- **Bash**: `command -v`, `mise ls --current`, `pg_isready`, `mysqladmin ping`,
  `redis-cli ping`, and other fast service health probes
- **AskUserQuestion**: on failure, ask whether to chain into debug
- **Skill**: invoke `claude-remote:debug` when the user opts in

## Workflow

### Step 1: Guard — is this a configured repo?

Check that all three prerequisites exist:

- `.claude/scripts/setup.sh` is present and executable
- `.claude/scripts/session-start.sh` is present and executable
- `.claude/settings.json` contains a `hooks.SessionStart` entry pointing
  at `.claude/scripts/session-start.sh`

If any are missing, stop immediately and tell the user:

> This repo hasn't been configured for `claude-remote` yet. Run
> `/claude-remote:setup` first, then re-run `/claude-remote:verify`.

### Step 2: Derive the expected check set

Read the three generated files and build a list of `{label, check_cmd}`
entries. The derivation is authoritative in three layers, most-specific
first:

**Layer A — `session-start.sh` assertions (highest priority).**
Grep the session-start script for `ISSUES+=("... missing")` and
`ISSUES+=("... down")` lines. Each one is an explicit maintainer
assertion of a required tool or service. Convert:

- `ISSUES+=("ruby missing")` → `{label: "ruby", check: "command -v ruby"}`
- `ISSUES+=("bundle missing")` → `{label: "bundle", check: "command -v bundle"}`
- `ISSUES+=("mysql down")` → `{label: "mysql", check: "mysqladmin ping --silent"}`
- `ISSUES+=("redis down")` → `{label: "redis", check: "redis-cli ping"}`
- `ISSUES+=("postgres down")` → `{label: "postgres", check: "pg_isready -q"}`
- Unknown `ISSUES+=("X missing")` → default to `command -v X`
- Unknown `ISSUES+=("X down")` → ask the user for the probe command
  (or skip with a WARN note)

**Layer B — service startup calls in `setup.sh`.**
Grep for `service <name> start` invocations and add the corresponding
health probes if not already present from Layer A:

- `service postgresql start` → `pg_isready -q`
- `service mysql start` → `mysqladmin ping --silent`
- `service redis-server start` → `redis-cli ping`

**Layer C — runtime hints in `setup.sh`.**
Grep for install commands and add matching `command -v` checks:

- `bundle install` → ensure `ruby` + `bundle`
- `fvm install` → ensure `fvm`; also check `fvm flutter --version`
  succeeds, because `command -v fvm` being true doesn't mean Flutter
  was actually downloaded
- `npm ci|install`, `pnpm install`, `yarn install`, `bun install` →
  ensure `node` + the specific package manager
- `pip install`, `uv sync` → ensure `python` (and `uv` if the script uses it)
- `mise install` → ensure `mise` is on PATH AND, if `mise.toml` or
  `.tool-versions` exists in the repo, run `mise ls --current` and
  verify each listed runtime has a resolvable binary

**Deduplication**: if a tool appears in multiple layers, keep a single
entry; Layer A wins on label wording.

### Step 3: Run the checks

Execute each check with a short timeout (~3 seconds per probe). Collect
`{label, status, detail}` tuples where:

- **PASS**: check exit code 0, capture version output when cheap
  (`<tool> --version | head -1`)
- **FAIL**: non-zero exit; capture stderr or a one-line reason
- **SKIP**: user-declined or unknown probe

Run checks in parallel where possible (pure `command -v` probes can all
run together); services sequentially because pings are already fast.

### Step 4: Report

Print a single clean table:

```
Claude Remote Verify — <repo name>
===================================
  PASS  mise       2026.4.7
  PASS  ruby       3.4.9
  PASS  bundle     2.5.22
  PASS  fvm        4.0.5
  PASS  flutter    3.24.3 (via fvm)
  PASS  postgres   accepting connections
  FAIL  redis      Could not connect to Redis at 127.0.0.1:6379

5/6 checks passed
```

Append a last-run indicator from `/tmp/claude-user-setup.log`:

```
Last user-setup run: 2026-04-10T10:20:47Z  (exit: ok)
```

Extract the timestamp from the `=== User setup complete at ... ===` line,
or report `never / incomplete` if the marker is missing.

### Step 5: All green → done

If every check is PASS, print a one-line confirmation and exit:

> All checks passed — session ready to work on `<repo>`.

Do not invoke any further skill.

### Step 6: Any failures → offer to chain into debug

If one or more checks are FAIL, print the failing rows with a short
heuristic hint next to each (e.g. "redis not running — `service
redis-server start` is in setup.sh so this ran once but the service
crashed or the hook didn't restart it on resume").

Then ask via `AskUserQuestion`:

> N check(s) failed. Run `/claude-remote:debug` for a full diagnosis?

- **Yes**: use the Skill tool to invoke `claude-remote:debug`. Pass
  along the failing labels so debug can focus its pattern-matching.
- **No**: exit. Print a reminder that the user can invoke
  `/claude-remote:debug` later if needed.

## Error handling

| Symptom | Action |
|---|---|
| `.claude/scripts/setup.sh` missing | Stop with "run /claude-remote:setup first" |
| `session-start.sh` healthcheck block is empty (no `ISSUES+=`) | Fall back to Layer B+C only; print a WARN that the session-start hook isn't asserting anything |
| `mise ls --current` errors out | Treat as FAIL for `mise` itself; don't try to iterate runtimes |
| `fvm` present but `fvm flutter --version` fails | Report as FAIL with detail "fvm installed but Flutter SDK not downloaded — try `fvm install` manually in the repo root" |
| Running on a local (non-cloud) session — `CLAUDE_CODE_REMOTE` unset | Run anyway but note in the header "local session — session-start hook did not run" |
| User declines the debug chain | Print a one-line reminder: "Run `/claude-remote:debug` later to investigate" |

## Notes

- This skill is **read-only**: it never modifies files or installs tools.
  Remediation belongs to `setup` (regenerate scripts) or `debug` (diagnose
  and suggest fixes).
- Checks are fast by design: the whole flow should complete in under
  5 seconds on a healthy repo.
- If the user wants to include verify in their repo's default workflow,
  `/claude-remote:setup` offers to write a `CLAUDE.md` snippet that
  instructs Claude to run verify at the start of every cloud session.
