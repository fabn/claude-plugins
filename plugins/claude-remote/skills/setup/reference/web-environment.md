# Configuring the Claude Code web environment

Reference: https://code.claude.com/docs/en/claude-code-on-the-web

After `/claude-remote:setup` has generated the per-repo files, the web-side
configuration has to be done **once per environment** in the Claude Code web
UI at https://claude.ai/code.

## 1. Open the environment editor

In the web UI, click the current environment name (top bar) → **Add
environment** (or edit an existing one).

## 2. Paste the canonical user-setup script

The **Setup script** field must contain the canonical user-level bootstrap
script. The source of truth is:

```
${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh
```

From a local Claude Code session with the `claude-remote` plugin enabled, you
can print it with:

```bash
cat "$(claude plugin path claude-remote)/scripts/user-setup-template.sh"
```

Copy the entire contents (including the shebang) and paste into the **Setup
script** field.

One copy serves every repository: the script runs the
`.claude/scripts/setup.sh` of each repo cloned under `/home/user/` (each in
its own repo root, in sorted order), so an environment whose sessions clone
several repos needs nothing extra. A failing step or repo setup does not stop
the others; the script always exits 0 so the session starts and can diagnose
itself. It also registers a user-level SessionStart hook in
`~/.claude/settings.json` that trusts every repo's `mise.toml` and puts every
repo's mise tools on PATH — needed because a session opened on `/home/user`
runs no repo's own `session-start.sh`.

If the environment already holds a copy older than 0.5.0, re-paste it: older
copies delegate only to the first repo setup found and abort at the first
failing command.

**Do NOT edit the script in the web UI.** If something needs to change, edit
`plugins/claude-remote/scripts/user-setup-template.sh` in this marketplace
repo first, then re-paste. `/claude-remote:debug` diffs deployed copies
against this canonical file to detect drift.

## 3. Environment variables

The web UI's **Environment variables** section is the only place to put
secrets (DB passwords, API tokens, etc.) since no secrets store exists yet.
Format is `.env`-style, one `KEY=value` per line, no quotes.

Add DB credentials, API keys, and any other secrets the repo needs here.

> **Do not set `CLAUDE_CODE_REMOTE` yourself.** It is a Claude Code
> built-in, automatically set to `true` inside the SessionStart hook
> context in cloud sessions. The `session-start.sh` gate
> `[ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && exit 0` relies on that
> built-in to skip local execution — no manual configuration required.

## 4. Network access

Default **Trusted** covers npm, PyPI, RubyGems, GitHub, Docker Hub, and the
package managers the user-setup script uses (`mise.run`, etc.). If your repo
pulls from a private registry, add it under **Custom** with the default list
kept enabled.

## 5. Push and launch

1. Commit `.claude/scripts/setup.sh`, `.claude/scripts/session-start.sh`, and
   `.claude/settings.json` to the repo and push.
2. From the repo root locally:
   ```bash
   claude --remote "check-tools"
   ```
   or start a session directly from the web UI.
3. Check the end of `/tmp/claude-user-setup.log` inside the session: the
   `=== Setup summary ===` block lists every step and repo as `OK` or
   `FAILED`, and the final `=== User setup complete at ... (exit: ok) ===`
   line gives the overall status. Run `/claude-remote:debug` if anything is
   `FAILED`.
