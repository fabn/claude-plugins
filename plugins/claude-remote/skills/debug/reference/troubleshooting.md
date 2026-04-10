# Claude Remote troubleshooting reference

Keyed to log patterns found in `/tmp/claude-user-setup.log` and repo state.
Used by `/claude-remote:debug` to match symptoms to fixes.

## Log-line patterns

| Pattern in log | Diagnosis | Fix |
|---|---|---|
| Log file does not exist at all | User-level setup script never ran. The "Setup script" field in the web UI environment is empty or contains a broken script. | Paste `${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh` into the web UI's Setup script field and restart the session. |
| `=== User setup started at` present, `[1/4]` missing | Script aborted immediately — typically a `set -e` failure on the very first line or a pasted script with trailing carriage returns (Windows line endings). | Re-copy the canonical script; ensure no CRLF. `file` should report `ASCII text`, not `ASCII text, with CRLF line terminators`. |
| `[1/4]` present, `[2/4]` missing | `find` command or `cp settings.remote.json` failed. Usually means the repo wasn't cloned to `/home/user/<repo>/` at the expected depth. | Verify the repo actually lands under `/home/user/` and that `.claude/scripts/setup.sh` exists in the repo (run `/claude-remote:setup` if not). |
| `[2/4]` present, `mise` install failed | Network policy blocks `mise.run` or `curl` proxy misbehaving. | Confirm the environment's network access is **Trusted** or **Full**. `mise.run` is reachable through the Trusted allowlist. |
| `[2/4]` followed by `mise: command not found` later | mise was installed but not placed on PATH for the child shell. | The canonical script symlinks mise into `/usr/local/bin`; if missing, the script was edited. Re-paste the canonical. |
| `[4/4] Delegating to repository setup` then `No repo setup script found under /home/user/` | The repo's `.claude/scripts/setup.sh` is missing, not executable, or deeper than `maxdepth 4`. | Run `/claude-remote:setup` in the repo root; confirm the file exists and is executable (`chmod +x .claude/scripts/setup.sh`). |
| `=== Repo setup started` present, `=== Repo setup complete` missing | Repo setup aborted mid-run — inspect last 30 lines above for the failing command. | Fix the failing step in `.claude/scripts/setup.sh` and re-run. |
| `bundle: command not found` (during repo setup) | mise-managed Ruby shims not on PATH in the non-interactive child shell. | Ensure `export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"` is at the top of `.claude/scripts/setup.sh` and that `mise install` ran first. |
| `mysql: unable to connect` / `Can't connect to local MySQL server` | MySQL not installed on web VM. | The generated setup.sh must `apt-get install -y mysql-server` before `service mysql start`. |
| `ECONNREFUSED` / `403` on npm | Network proxy issue or private registry blocked. | Check environment network access level; add registry domain under Custom network access. |
| `SETUP INCOMPLETE: ...` emitted by session-start hook | Runtime was installed at setup time but is not reachable now. Usually because `$CLAUDE_ENV_FILE` PATH injection block is missing from `session-start.sh`. | Confirm the PATH persistence block is present and `mise activate bash` is eval'd. |
| No `=== User setup complete` line | User-level script crashed before the final `echo`. Tail the log for the actual error. | Show last 40 lines of `/tmp/claude-user-setup.log`. |

## Repo-state checks

| Check | What's wrong if it fails | Fix |
|---|---|---|
| `.claude/scripts/setup.sh` missing | Repo never went through `/claude-remote:setup` | Run `/claude-remote:setup` |
| `.claude/scripts/session-start.sh` missing | Same | Run `/claude-remote:setup` |
| `.claude/scripts/setup.sh` not executable | `chmod +x` step skipped | `chmod +x .claude/scripts/setup.sh` |
| `.claude/settings.json` lacks `claude-remote@fabn-claude-plugins` in `enabledPlugins` | Plugin not enabled in the cloned repo → skills unavailable in cloud session | Re-run `/claude-remote:setup` or add manually |
| `.claude/settings.json` lacks SessionStart hook pointing to `.claude/scripts/session-start.sh` | Services will not start on session resume | Re-run `/claude-remote:setup` |
| Script doesn't tee to `/tmp/claude-user-setup.log` | Debug skill cannot find logs | Ensure `exec > >(tee -a "$LOG") 2>&1` at the top of both scripts |

## Canonical drift

If the script pasted into the web UI differs from
`${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh`, the deployed copy
is stale. Remediate by re-pasting the canonical file. Do not edit inside
the web UI.
