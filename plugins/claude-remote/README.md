# Claude Remote Plugin

Configure and diagnose [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) cloud sessions. Generates a per-repo bootstrap script, a SessionStart hook, and the `.claude/settings.json` wiring needed to take a repository from "fresh clone" to "working cloud session", then provides a log-driven debug workflow when something goes wrong.

## Skills

| Skill | Description |
|-------|-------------|
| `/claude-remote:setup` | Detect the project stack (Ruby/Rails, Node, Python, mise, databases), generate `.claude/scripts/setup.sh` and `.claude/scripts/session-start.sh`, and merge the claude-remote marketplace + plugin + SessionStart hook into `.claude/settings.json`. Optionally proposes a `CLAUDE.md` snippet that tells Claude to run `/claude-remote:verify` at the start of every cloud session. Prints next-step instructions for pasting the canonical user-level script into the web UI. |
| `/claude-remote:verify` | Quick happy-path check at the start of a cloud session. Parses the generated `setup.sh` and `session-start.sh` to derive the expected toolset dynamically (runtimes, services, package managers), runs a fast battery of health probes, and offers to chain into `/claude-remote:debug` on failure. Read-only — never modifies files. |
| `/claude-remote:debug` | Read `/tmp/claude-user-setup.log`, audit repo-side files, compare deployed user-setup script against the canonical version bundled with this plugin, match log patterns to known failure modes, and print a concrete fix. Can optionally invoke the bundled `debug-environment.sh` script for a full environment dump when cheap pattern-matching is inconclusive. |

## How it works

A working cloud session needs three cooperating pieces:

1. **User-level setup script** pasted into the Claude Code web UI environment's "Setup script" field. It installs cross-project tooling (mise, `gh`, `jq`), writes permissive sandbox settings, logs a VM fingerprint for diagnostics, then discovers the per-repo script and delegates to it. The canonical version lives at `plugins/claude-remote/scripts/user-setup-template.sh` inside this plugin — **this file is the source of truth**, any future changes are made here first, then re-pasted into the web UI.
2. **Per-repo `.claude/scripts/setup.sh`** — runs on new sessions, installs repo-specific deps (`bundle install`, `npm ci`, etc.) and starts required services.
3. **Per-repo `.claude/scripts/session-start.sh`** — runs on every session (including resumes) via a `SessionStart` hook. Keeps services up and persists mise-managed `PATH` to `$CLAUDE_ENV_FILE` so every Bash tool call inherits the right environment.

All three log to `/tmp/claude-user-setup.log` so `/claude-remote:debug` has a single source of truth to diagnose either layer. A separate `debug-environment.sh` script bundled with the plugin can be invoked on demand for a full environment snapshot (identity, PATH, tool versions, services, mise state, shell init files) — output goes to `/tmp/claude-env-debug.log`.

## Enabling the plugin

### Option A — add the marketplace and enable this plugin in your repo

Commit a `.claude/settings.json` to the repo with:

```json
{
  "extraKnownMarketplaces": {
    "fabn-claude-plugins": {
      "source": {
        "source": "github",
        "repo": "fabn/claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "claude-remote@fabn-claude-plugins": true
  }
}
```

This is exactly what `/claude-remote:setup` generates for you automatically — along with the SessionStart hook, the scripts, and (optionally) a permissive `settings.remote.json`.

### Option B — install interactively

```
/plugin marketplace add fabn/claude-plugins
/plugin install claude-remote@fabn-claude-plugins
```

Then run `/claude-remote:setup` inside any repo you want to prepare for Claude Code on the web.

## Getting started

1. Enable the plugin in a local Claude Code session (Option A or B above).
2. Inside the repository you want to prepare, run:
   ```
   /claude-remote:setup
   ```
3. Answer the detection confirmation prompts. The skill will create `.claude/scripts/setup.sh`, `.claude/scripts/session-start.sh`, and update `.claude/settings.json`.
4. Commit and push the generated files.
5. In the Claude Code web UI at https://claude.ai/code, open your environment settings and paste the contents of `plugins/claude-remote/scripts/user-setup-template.sh` into the **Setup script** field. Add any secrets (DB passwords, API tokens, etc.) the repo needs under **Environment variables** — `CLAUDE_CODE_REMOTE` is a built-in and is automatically set inside SessionStart hooks, so you do not need to set it yourself.
6. From the repo root locally:
   ```bash
   claude --remote "check-tools"
   ```
7. At the start of the cloud session, run:
   ```
   /claude-remote:verify
   ```
   to confirm the environment is ready. If any check fails, verify will
   offer to chain into `/claude-remote:debug` automatically. You can also
   let `/claude-remote:setup` write a `CLAUDE.md` snippet that tells
   Claude to invoke verify at the start of every cloud session.
8. If anything goes wrong, inside the session run:
   ```
   /claude-remote:debug
   ```

## Prerequisites

- A Claude Code subscription with [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) access (Pro, Max, Team, or Enterprise).
- A GitHub-connected repo (cloud sessions clone from GitHub).
- `jq` available locally for the setup skill's JSON validation step.
- `bash` 4+ locally for syntax-checking generated scripts.

## The canonical user-setup script

The user-level setup script lives at:

```
plugins/claude-remote/scripts/user-setup-template.sh
```

**This is the source of truth.** If it needs to change:

1. Edit it here in this repo.
2. Bump the plugin version in `plugin.json` and `marketplace.json`.
3. Re-paste the new contents into the Claude Code web UI Setup script field for each environment that uses it.

`/claude-remote:debug` can diff a user-provided copy of the deployed script against this canonical file to detect drift.

## Reference

- [Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) — primary documentation for the cloud environment, setup scripts, and SessionStart hooks.
- [SessionStart hook reference](https://code.claude.com/docs/en/hooks#sessionstart)
- [`.claude/settings.json` schema](https://code.claude.com/docs/en/settings)
