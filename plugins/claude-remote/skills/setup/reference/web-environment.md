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

**Do NOT edit the script in the web UI.** If something needs to change, edit
`plugins/claude-remote/scripts/user-setup-template.sh` in this marketplace
repo first, then re-paste. `/claude-remote:debug` diffs deployed copies
against this canonical file to detect drift.

## 3. Environment variables

The web UI's **Environment variables** section is the only place to put
secrets (DB passwords, API tokens, etc.) since no secrets store exists yet.
Format is `.env`-style, one `KEY=value` per line, no quotes.

Minimum variables you typically need:

```
CLAUDE_CODE_REMOTE=true
```

`CLAUDE_CODE_REMOTE=true` is what gates `session-start.sh` so it only runs
in cloud sessions, not locally.

Add DB credentials, API keys, and any other secrets here as needed.

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
3. Watch `/tmp/claude-user-setup.log` inside the session to confirm all
   phases completed. Run `/claude-remote:debug` if anything looks off.
