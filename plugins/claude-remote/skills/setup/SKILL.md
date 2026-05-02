---
name: claude-remote:setup
description: |
  This skill should be used when the user wants to prepare a repository for
  Claude Code on the web (cloud sessions), or to upgrade an existing
  claude-remote setup to the latest template (e.g. to enable mise lockfile
  usage and avoid GitHub API rate limits). Detects the project stack
  (Ruby/Rails, Node, Python, Go, PHP, mise, databases), generates a
  per-repo bootstrap script, a SessionStart hook, walks the user through
  generating mise.lock for cloud platforms, optionally adds a mise bundler
  deps provider for Ruby projects, and wires everything into
  .claude/settings.json with the claude-remote plugin enabled from the
  fabn-claude-plugins marketplace. On re-run with existing scripts, saves
  .bak files and regenerates from the latest template. Also prints the next
  steps for pasting the canonical user-level setup script into the web UI
  environment.
  Activates on: "setup claude remote", "configure claude remote",
  "prepare repo for claude web", "prepare repo for cloud", "claude on the
  web setup", "cloud session bootstrap", "remote bootstrap", "web session
  setup", "upgrade claude remote", "update claude remote setup",
  "regenerate setup scripts", "fix mise rate limit", "add mise lockfile",
  "configura claude remote", "prepara repo per claude web",
  "setup sessione cloud", "aggiorna claude remote", "rigenera script claude remote".
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

### Step 1: Detect project stack and prior setup

Run these detections in parallel:

- **Runtimes**:
  - `Gemfile` + `Gemfile.lock` → Ruby
  - `package.json` → Node; lockfile picks pm: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb` → bun, else npm
  - `pyproject.toml` / `requirements.txt` → Python (prefer `uv` if `uv.lock` present)
  - `go.mod` → Go
  - `composer.json` → PHP
- **Version manager**: `mise.toml` or `.tool-versions` → mise block included
- **mise lockfile**: presence of `mise.lock` (matters for cloud rate-limit avoidance — see Step 5)
- **mise bundler provider**: grep `mise.toml` for `[deps.bundler]` (matters for Step 6 proposal)
- **Services** — look at `config/database.yml`, `docker-compose.yml`, `docker-compose.*.yml`, `.env.example`:
  - `adapter: mysql2` or `mysql:` image → MySQL
  - `adapter: postgresql` or `postgres:` image → PostgreSQL
  - `redis:` image or `REDIS_URL` → Redis
  - `elasticsearch:` / `opensearch:` → flag and ask (not auto-configured)
- **Prior setup** (upgrade-mode detection):
  - `.claude/scripts/setup.sh` exists → upgrade scenario
  - `.claude/scripts/session-start.sh` exists → upgrade scenario
  - Read the existing `setup.sh` and check whether it contains `mise install --locked` (new) or only `mise install` (legacy). The legacy pattern is the main reason a user re-runs this skill.

Do NOT write anything yet.

### Step 2: Confirm detection

Use `AskUserQuestion` to present the detected stack and let the user correct it:

- Runtimes detected (checkboxes, pre-selected)
- Services detected (checkboxes, pre-selected)
- Services the user wants to add manually
- Whether to create `.claude/settings.remote.json` (permissive fallback for the sandbox)
- **If upgrade-mode (Step 1 found existing scripts)**: confirm "Regenerate `.claude/scripts/setup.sh` and `.claude/scripts/session-start.sh` from the latest template?" with the explanation: the skill saves a `.bak` of each existing file before overwriting. If the user declines, skip Steps 3–4 and continue with the lockfile / bundler / settings steps so they still benefit from the parts of the upgrade that don't touch the scripts.

### Step 3: Generate `.claude/scripts/setup.sh`

Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/reference/repo-setup-template.sh`.
Strip the `__SECTION:foo__` ... `__END:foo__` blocks for runtimes/services
that were NOT selected in Step 2. Keep them for selected ones. Remove the
sentinel comment lines themselves.

If the file already exists (upgrade mode), copy it to
`.claude/scripts/setup.sh.bak` first. Then write the new version,
`chmod +x`, and run `bash -n` on it. Abort and show the error if the
syntax check fails — restore from `.bak` if needed.

### Step 4: Generate `.claude/scripts/session-start.sh`

Same procedure with `session-start-template.sh`. Keep:

- The `CLAUDE_CODE_REMOTE` gate at the top (always).
- The `$CLAUDE_ENV_FILE` PATH persistence block (always).
- Only service blocks and healthcheck blocks for selected services/runtimes.

If the file already exists, save a `.bak` first. Then `chmod +x` and `bash -n`.

### Step 5: mise lockfile (skip if no `mise.toml` and no `.tool-versions`)

The `__SECTION:mise__` block in the generated `setup.sh` calls
`mise install --locked` when `mise.lock` is present. Without the lockfile,
`mise install` falls back to GitHub API calls for `latest` resolution and
GitHub-backed backends — cloud sessions are unauthenticated and frequently
hit the rate limit. So if Step 1 detected a mise config but **no
`mise.lock`**, walk the user through generating one:

1. Tell the user: cloud sessions run on `linux-x64`; the lockfile must
   contain URLs for that platform. If the user develops on macOS,
   pre-populating both platforms is required.
2. Offer (`AskUserQuestion`) to run the generator now via Bash:
   ```bash
   mise lock --platform linux-x64,macos-arm64
   ```
   - If `mise` is on PATH locally and the user accepts → run it, then
     verify `mise.lock` exists and `bash -n`-equivalent for TOML via
     `mise lockfile-status` (best effort) or just `[ -s mise.lock ]`.
   - If `mise` is missing locally or the user declines → print the exact
     command and tell them to run it before pushing. Do NOT block the
     rest of the workflow.
3. **Do not recommend `[settings] locked = true` inside `mise.toml`.** That
   flag enables strict mode at *global* scope (it applies to the user's
   `~/.config/mise/config.toml` too) and breaks tools outside this repo.
   The skill's generated `setup.sh` already passes `--locked` per-command,
   which is the correct scope.
4. If `mise.lock` already exists, just confirm it's committed (warn if
   `git ls-files --error-unmatch mise.lock` fails) and move on.

### Step 6: mise bundler deps provider (Ruby + `mise.toml` only)

If the repo has `Gemfile` AND `mise.toml` AND Step 1 did not find an
existing `[deps.bundler]` section, propose adding:

```toml
[deps.bundler]
auto = true
```

Use `AskUserQuestion` — this is opt-in. Benefit: when the user later runs
`mise run <task>` after a `Gemfile.lock` change, mise reinstalls
bundler dependencies automatically. It is harmless to add even for
projects that never use `mise run`.

If the user accepts, append the snippet to `mise.toml` using `Edit`
(not `Write` — we must not clobber existing content). Run `bash -n`
equivalent for TOML by parsing it via `mise config --json` (best effort)
or just visually verifying via Read.

### Step 7: Merge `.claude/settings.json`

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

### Step 8: Optional `settings.remote.json`

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

### Step 9: Offer to write CLAUDE.md verify hint (optional)

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

### Step 10: Print next steps

Tell the user:

1. Commit and push the new files: `.claude/scripts/setup.sh`,
   `.claude/scripts/session-start.sh`, `.claude/settings.json`,
   `mise.lock` (if Step 5 generated it), `mise.toml` (if Step 6
   added the bundler provider), `CLAUDE.md` (if updated in Step 9),
   and (if created) `.claude/settings.remote.json`.
   Delete any `.bak` files left from upgrade mode once the new scripts
   are verified working in a cloud session.
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

### Step 11: Local verification

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
| `mise lock` not on PATH locally during Step 5 | Print the command and ask the user to install mise locally first, or skip lockfile generation and continue (cloud sessions will still work but may rate-limit) |
| `mise.lock` exists but only contains macOS URLs | Tell the user to re-run `mise lock --platform linux-x64,macos-arm64` so the cloud session can use `--locked` strict mode |
| Existing `setup.sh.bak` already present (second upgrade run) | Overwrite it without asking — it's a transient artifact |
