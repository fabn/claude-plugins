---
name: claude-remote:setup
description: |
  This skill should be used when the user wants to prepare a repository for
  Claude Code on the web (cloud sessions). Detects the project stack
  (Ruby/Rails, Node, Python, Go, PHP, mise, databases), generates a
  per-repo bootstrap script, a SessionStart hook, and wires everything into
  .claude/settings.json with the claude-remote plugin enabled from the
  fabn-claude-plugins marketplace. Also prints the next steps for pasting
  the canonical user-level setup script into the web UI environment.
  Activates on: "setup claude remote", "configure claude remote",
  "prepare repo for claude web", "prepare repo for cloud", "claude on the
  web setup", "cloud session bootstrap", "remote bootstrap", "web session
  setup", "configura claude remote", "prepara repo per claude web",
  "setup sessione cloud".
---

# Claude Remote Setup Skill

Generates everything a repository needs to run correctly inside a Claude
Code web (cloud) session: a per-repo setup script, a SessionStart hook, and
the `.claude/settings.json` wiring that enables this plugin from the
`fabn-claude-plugins` marketplace.

Reference doc: https://code.claude.com/docs/en/claude-code-on-the-web

## Reference files

- `${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh` — canonical
  user-level script that must be pasted into the web UI "Setup script"
  field. Source of truth; never edit in the web UI.
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/repo-setup-template.sh` —
  parametric template for the per-repo `.claude/scripts/setup.sh`.
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/session-start-template.sh` —
  parametric template for `.claude/scripts/session-start.sh`.
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/settings-snippet.json` —
  canonical JSON to merge into the repo's `.claude/settings.json`.
- `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/web-environment.md` —
  web-UI configuration instructions (shown to user at the end).

## Tools Used

- **Glob**: detect project manifests (`Gemfile`, `package.json`, `mise.toml`, etc.)
- **Read**: read detected manifests, existing `.claude/settings.json`, reference templates
- **Grep**: detect services from `config/database.yml`, `docker-compose.yml`
- **AskUserQuestion**: confirm detected stack and optional settings
- **Write / Edit**: create scripts and settings
- **Bash**: `chmod +x`, `bash -n`, `jq .` for verification

## Workflow

### Step 1: Detect project stack

Run these detections in parallel:

- **Runtimes**:
  - `Gemfile` + `Gemfile.lock` → Ruby
  - `package.json` → Node; lockfile picks pm: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, else npm
  - `pyproject.toml` / `requirements.txt` → Python (prefer `uv` if `uv.lock` present)
  - `go.mod` → Go
  - `composer.json` → PHP
- **Version manager**: `mise.toml` or `.tool-versions` → mise block included
- **Services** — look at `config/database.yml`, `docker-compose.yml`, `docker-compose.*.yml`, `.env.example`:
  - `adapter: mysql2` or `mysql:` image → MySQL
  - `adapter: postgresql` or `postgres:` image → PostgreSQL
  - `redis:` image or `REDIS_URL` → Redis
  - `elasticsearch:` / `opensearch:` → flag and ask (not auto-configured)

Do NOT write anything yet.

### Step 2: Confirm detection

Use `AskUserQuestion` to present the detected stack and let the user correct it:

- Runtimes detected (checkboxes, pre-selected)
- Services detected (checkboxes, pre-selected)
- Services the user wants to add manually
- Whether to create `.claude/settings.remote.json` (permissive fallback for the sandbox)

### Step 3: Generate `.claude/scripts/setup.sh`

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/repo-setup-template.sh`.
Strip the `__SECTION:foo__` ... `__END:foo__` blocks for runtimes/services
that were NOT selected in Step 2. Keep them for selected ones. Remove the
sentinel comment lines themselves.

Create the file, `chmod +x`, and run `bash -n` on it. Abort and show the
error if the syntax check fails.

### Step 4: Generate `.claude/scripts/session-start.sh`

Same procedure with `session-start-template.sh`. Keep:

- The `CLAUDE_CODE_REMOTE` gate at the top (always).
- The `$CLAUDE_ENV_FILE` PATH persistence block (always).
- Only service blocks and healthcheck blocks for selected services/runtimes.

`chmod +x` and `bash -n`.

### Step 5: Merge `.claude/settings.json`

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/settings-snippet.json`.
Read the target repo's `.claude/settings.json` (create `{}` if missing).

Deep-merge the two with these rules:

- **`extraKnownMarketplaces`**: add `fabn-claude-plugins` if absent; never
  overwrite an existing entry under the same name — ask instead.
- **`enabledPlugins`**: add `claude-remote@fabn-claude-plugins: true`;
  leave other enabled plugins alone.
- **`hooks.SessionStart`**: if the array already exists, **append** the new
  entry only if no existing entry already points to
  `.claude/scripts/session-start.sh` (idempotent).

Write the result back with 2-space indentation. Validate with `jq .`.

Before composing the SessionStart hook block, **consult the
`plugin-dev:hook-development` skill** if available (use the Skill tool) so
the hook syntax matches current Claude Code conventions. If that skill
isn't available, fall back to the snippet in the reference file.

### Step 6: Optional `settings.remote.json`

This file is only useful when the repo's committed `.claude/settings.json`
contains restrictive entries (`permissions.deny` or `permissions.ask`) that
would block unattended operation in the sandbox. Check for those first:

1. `Read` the repo's `.claude/settings.json`.
2. Inspect `permissions.deny` and `permissions.ask`. If **both are empty or
   absent**, the sandbox can already run unattended — skip this step and do
   NOT create `settings.remote.json`.
3. Otherwise, and only if the user opted in during Step 2 and the file does
   not already exist, create `.claude/settings.remote.json` with a
   permissive baseline for unattended remote sessions:

   ```json
   {
     "permissions": {
       "allow": ["*"],
       "deny": [],
       "ask": []
     }
   }
   ```

   **Important caveat to communicate to the user:** specific `deny` or
   `ask` entries in the repo's committed `settings.json` are NOT overridden
   by `"allow": ["*"]`. If a tool is explicitly denied or gated in
   `settings.json` (e.g. `deny: ["node"]`), it stays denied/gated in the
   sandbox unless you add an explicit `allow` entry for that exact tool in
   `settings.remote.json`. Inspect the repo's settings and, for each
   deny/ask entry, ask the user whether to add a matching explicit allow
   entry in `settings.remote.json`.

The user-setup script copies this to `settings.local.json` at session
start, giving the sandbox permissive defaults without touching the
locally-restrictive `settings.json`.

### Step 7: Offer to write CLAUDE.md verify hint (optional)

Ask the user via `AskUserQuestion` whether to add a short instruction
to the repo's `CLAUDE.md` telling Claude to run `/claude-remote:verify`
at the start of every cloud session. This is **opt-in** — do NOT write
it without confirmation.

If the user agrees:

1. Read the repo's `CLAUDE.md` (create it if it doesn't exist).
2. Check whether a `<!-- claude-remote-plugin -->` marker is already
   present. If yes, leave the file alone — it's already configured.
3. Otherwise append this block at the end of the file:

   ```markdown
   <!-- claude-remote-plugin -->
   ## Claude Code on the web

   When running inside a Claude Code web (cloud) session (`CLAUDE_CODE_REMOTE=true`),
   before acting on the user's first request, run `/claude-remote:verify` to
   confirm the environment is ready (runtimes installed, services up). If
   verify reports failures, do not proceed with the task — follow its
   recommendation to run `/claude-remote:debug` for a full diagnosis.
   ```

4. Tell the user what was added and remind them to commit `CLAUDE.md`
   together with the other generated files.

If the user declines: skip silently.

### Step 8: Print next steps

Tell the user:

1. Commit and push the new files: `.claude/scripts/setup.sh`,
   `.claude/scripts/session-start.sh`, `.claude/settings.json`,
   `CLAUDE.md` (if updated in Step 7), and (if created)
   `.claude/settings.remote.json`.
2. Paste the contents of `${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh`
   into the Claude Code web UI's **Setup script** field for the target
   environment. Reference the web-environment doc for full instructions:
   Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/web-environment.md`
   and show the relevant excerpt.
3. Add any secrets the repo needs (DB credentials, API tokens, etc.) to
   the web UI **Environment variables** section. Do NOT set
   `CLAUDE_CODE_REMOTE` — it is a Claude Code built-in and is
   automatically set inside the SessionStart hook context.
4. Start a session: `claude --remote "check-tools"` from the repo root.
5. At the start of the session, run `/claude-remote:verify` to confirm
   the environment is ready. If anything fails, run `/claude-remote:debug`
   for a full diagnosis.

### Step 9: Local verification

Run:

```bash
bash -n .claude/scripts/setup.sh
bash -n .claude/scripts/session-start.sh
jq . .claude/settings.json > /dev/null
```

Report all green or the first failure.

## Error handling

| Symptom | Action |
|---|---|
| `bash -n` fails on a generated script | Show the error, re-emit the section from template without mangling, retry once, else leave the file for user to inspect |
| `jq .` fails on merged settings.json | Roll back to pre-edit contents (keep a backup in `.claude/settings.json.bak`), report the diff, ask the user to resolve manually |
| Existing `extraKnownMarketplaces.fabn-claude-plugins` entry with different config | `AskUserQuestion` whether to overwrite |
| `mise.toml` present but no runtime detected | Warn that mise will still install but nothing is tied to it; proceed |
| MySQL detected | Warn that MySQL isn't pre-installed on the web VM; the generated setup.sh will `apt-get install mysql-server`, which adds startup time |
