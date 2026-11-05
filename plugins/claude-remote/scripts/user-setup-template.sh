#!/usr/bin/env bash
# NOTE: deliberately no `set -e` at the top level. Every step runs isolated in
# its own subshell (with `set -euo pipefail` inside) so that one failing step
# or one failing repository setup never stops the remaining ones. The script
# always exits 0 so the environment comes up and the session can diagnose
# itself from the summary at the end of the log.
set -o pipefail

# =============================================================================
# Canonical user-level Claude Code web setup script
#
# SOURCE OF TRUTH: this file, inside the claude-remote plugin.
# Any change to the web-UI setup script MUST be made here first, then
# redeployed by copy-pasting this file's contents into:
#   - the Claude Code web environment "Setup script" field, and
#   - (optionally) ~/.claude/scripts/setup.sh on local machines
#
# The script handles minimal cross-project bootstrapping (mise + permissive
# settings + the Claude Code plugins the repos declare), then delegates to
# EVERY repository's own .claude/scripts/setup.sh for repo-specific setup
# (bundle install, npm install, service startup, etc.). A session can clone
# several repositories side by side under /home/user/; each one is set up in
# its own repo root, in a deterministic (sorted) order.
#
# Logs everything to /tmp/claude-user-setup.log; the repo-level setup scripts
# tee to the same file so /claude-remote:debug has a single source of truth.
# The log ends with a "=== Setup summary ===" block (one OK/FAILED line per
# step and per repo) and the "=== User setup complete at ... ===" marker,
# which carries the overall status: "(exit: ok)" or "(exit: N failure[s])".
#
# Testing overrides (leave unset in the web UI):
#   CLAUDE_SETUP_SEARCH_ROOT  where repos are discovered (default /home/user)
#   CLAUDE_SETUP_LOG          log file (default /tmp/claude-user-setup.log)
# =============================================================================

LOG="${CLAUDE_SETUP_LOG:-/tmp/claude-user-setup.log}"
SEARCH_ROOT="${CLAUDE_SETUP_SEARCH_ROOT:-/home/user}"
exec > >(tee -a "$LOG") 2>&1
echo "=== User setup started at $(date -Iseconds) ==="

# ── VM fingerprint (cheap diagnostic, one-time) ──────────────────
echo "  host: $(uname -srm) | user: $(whoami) | home: $HOME | cwd: $PWD"
[ -f /etc/os-release ] && . /etc/os-release && echo "  os: ${PRETTY_NAME:-unknown}"

# mise and its shims must be on PATH for every step and every repo setup,
# whether mise was just installed or was already there.
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# ── Step runner ──────────────────────────────────────────────────
# run_step <label> <command...>: runs the command in a subshell with
# `set -euo pipefail` (the step stops at its own first error), records
# OK/FAILED with the exit code, and always returns 0 so the caller carries on.
SUMMARY=()
FAILURES=0
run_step() {
  local label="$1"; shift
  local rc
  ( set -euo pipefail; "$@" )
  rc=$?
  if [ "$rc" -eq 0 ]; then
    SUMMARY+=("  OK      $label")
  else
    FAILURES=$((FAILURES + 1))
    SUMMARY+=("  FAILED  $label (exit $rc)")
    echo "  ERROR: step '$label' failed with exit $rc — continuing"
  fi
  return 0
}

# ── Repository discovery ─────────────────────────────────────────
# Every <root>/*/.claude/scripts/setup.sh, plus the working directory (and
# $CLAUDE_PROJECT_DIR) when it is itself a repo with a setup script — the
# single-repo layout. Deduplicated by real path and sorted for a
# deterministic order.
REPO_DIRS=()
discover_repos() {
  local candidate real
  local -A seen=()
  local -a found=()
  for candidate in "$PWD" "${CLAUDE_PROJECT_DIR:-}" "$SEARCH_ROOT"/*/; do
    [ -n "$candidate" ] || continue
    candidate="${candidate%/}"
    [ -f "$candidate/.claude/scripts/setup.sh" ] || continue
    real="$(cd "$candidate" 2>/dev/null && pwd -P)" || continue
    [ -n "${seen[$real]:-}" ] && continue
    seen[$real]=1
    found+=("$real")
  done
  [ ${#found[@]} -gt 0 ] && mapfile -t REPO_DIRS < <(printf '%s\n' "${found[@]}" | LC_ALL=C sort)
  return 0
}
discover_repos

# ── Permissive settings for sandboxed environment ────────────────
echo "[1/5] Installing permissive settings..."

# The project .claude/settings.json has restrictive permissions for local
# interactive use. In the sandboxed web environment there's no risk,
# so we install settings.local.json (higher precedence) that allow everything.
# This MUST run first so that env vars (e.g. DB credentials)
# are available to MCP servers even if later steps fail.
install_settings() {
  local repo failed=0
  for repo in "${REPO_DIRS[@]}"; do
    if [ -f "$repo/.claude/settings.remote.json" ]; then
      if cp "$repo/.claude/settings.remote.json" "$repo/.claude/settings.local.json"; then
        echo "  [$(basename "$repo")] installed .claude/settings.local.json from settings.remote.json"
      else
        echo "  [$(basename "$repo")] ERROR: could not install settings.local.json"
        failed=1
      fi
    fi
  done
  return "$failed"
}

if [ ${#REPO_DIRS[@]} -gt 0 ]; then
  for repo in "${REPO_DIRS[@]}"; do
    echo "  Found repo setup: $repo/.claude/scripts/setup.sh"
  done
  run_step "settings" install_settings
else
  # Diagnostic: if no repo setup script was discovered, dump the top of
  # the search root so /claude-remote:debug can see where the repo actually
  # landed (common failure: cloned under /home/user/workspace/<repo>).
  echo "  WARN: no .claude/scripts/setup.sh found in $PWD or $SEARCH_ROOT/*/"
  echo "  $SEARCH_ROOT directory tree (depth 4):"
  find "$SEARCH_ROOT" -maxdepth 4 -type d 2>/dev/null | head -20 | sed 's/^/    /'
fi

# ── mise ──────────────────────────────────────────────────────────
echo "[2/5] Installing mise..."
install_mise() {
  if ! command -v mise >/dev/null 2>&1; then
    # Retry on transient failures (mise.run has returned 503 during bootstrap).
    # --retry-all-errors covers HTTP 5xx; default curl --retry only covers
    # transport-level errors.
    curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors https://mise.run | sh

    # Symlink mise into /usr/local/bin so it's available in all shells
    # (non-interactive shells don't read .bashrc or BASH_ENV)
    ln -sf ~/.local/bin/mise /usr/local/bin/mise

    # Activate for interactive sessions
    grep -qF 'mise activate bash' ~/.bashrc 2>/dev/null ||
      echo 'eval "$(mise activate bash)"' >> ~/.bashrc

    echo "  mise $(mise --version) installed"
  else
    echo "  mise already installed: $(mise --version)"
  fi

  # Prefer precompiled Ruby (no build toolchain needed)
  mise settings ruby.compile=false
  # Skip GitHub attestation verification (rate-limited without auth token)
  mise settings ruby.github_attestations=false
}
run_step "mise" install_mise

# ── Common CLI tools (gh, jq) ────────────────────────────────────
# gh is NOT pre-installed on Claude web VMs; jq IS pre-installed. apt-get
# is idempotent so we just ask for both — already-installed is a no-op.
echo "[3/5] Installing common CLI tools (gh, jq)..."
install_cli_tools() {
  # --allow-releaseinfo-change: a third-party apt source on the base image can
  # change its Release metadata (Origin/Label/Suite) between image builds, and
  # plain `apt-get update` then refuses the repository and fails the step.
  apt-get update -qq --allow-releaseinfo-change
  apt-get install -y -qq gh jq
}
run_step "cli-tools" install_cli_tools

# ── Claude Code plugins declared by the repositories ─────────────
# Locally Claude Code asks to trust the marketplaces in the project's
# .claude/settings.json (extraKnownMarketplaces) when the repo is opened. A
# cloud session asks nobody, so the marketplaces are never registered and
# every enabledPlugins entry is dropped at startup ("Skipping orphaned
# enabledPlugins entry ...: marketplace not registered"). Registering the
# marketplace alone is not enough either: a headless session does not fetch
# enabled plugins, it reports them as a plugin-cache-miss and loads no skills.
# So register and install here, reading each repo's own settings file so the
# plugin list has a single source. Marketplaces and plugins declared by
# several repos are handled once. Both commands are idempotent; a failing
# entry is reported and the remaining ones are still processed.
echo "[4/5] Installing Claude Code plugins..."
install_plugins() {
  local -a settings_files=()
  local repo f item failed=0
  for repo in "${REPO_DIRS[@]}"; do
    [ -f "$repo/.claude/settings.json" ] && settings_files+=("$repo/.claude/settings.json")
  done
  if [ ${#settings_files[@]} -eq 0 ]; then
    echo "  No repo .claude/settings.json found, skipping"
    return 0
  fi
  if ! command -v claude >/dev/null 2>&1; then
    echo "  WARNING: claude CLI not on PATH, plugins not installed"
    return 0
  fi
  local -a marketplaces=() plugins=()
  for f in "${settings_files[@]}"; do
    # A malformed settings file fails only its own parsing, not the step.
    mapfile -t -O "${#marketplaces[@]}" marketplaces < <(jq -r '.extraKnownMarketplaces // {} | .[].source
         | if .source == "github" then .repo elif .source == "git" then .url else empty end' "$f" ||
      echo "  WARNING: could not parse $f" >&2)
    mapfile -t -O "${#plugins[@]}" plugins < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$f" 2>/dev/null)
  done
  while read -r item; do
    [ -n "$item" ] || continue
    claude plugin marketplace add "$item" || { echo "  WARNING: could not add marketplace $item"; failed=1; }
  done < <(printf '%s\n' "${marketplaces[@]}" | LC_ALL=C sort -u)
  while read -r item; do
    [ -n "$item" ] || continue
    claude plugin install "$item" || { echo "  WARNING: could not install $item"; failed=1; }
  done < <(printf '%s\n' "${plugins[@]}" | LC_ALL=C sort -u)
  return "$failed"
}
run_step "plugins" install_plugins

# ── Delegate to every repository setup ───────────────────────────
echo "[5/5] Delegating to repository setup..."

run_repo_setup() {
  local repo="$1"
  local setup="$repo/.claude/scripts/setup.sh"
  cd "$repo"
  # Child stdout/stderr inherit the exec-tee redirect at the top of this
  # script, so everything the repo script emits lands in $LOG automatically.
  if [ -x "$setup" ]; then
    "$setup"
  else
    echo "  WARN: $setup is not executable, running it with bash"
    bash "$setup"
  fi
}

if [ ${#REPO_DIRS[@]} -gt 0 ]; then
  for repo in "${REPO_DIRS[@]}"; do
    echo "  Running $repo/.claude/scripts/setup.sh ..."
    run_step "repo $(basename "$repo")" run_repo_setup "$repo"
  done
else
  echo "  No repo setup script found in $PWD or $SEARCH_ROOT/*/, skipping"
fi

# ── Summary ──────────────────────────────────────────────────────
echo "=== Setup summary ==="
printf '%s\n' "${SUMMARY[@]}"
if [ "$FAILURES" -eq 0 ]; then
  STATUS="ok"
elif [ "$FAILURES" -eq 1 ]; then
  STATUS="1 failure"
else
  STATUS="$FAILURES failures"
fi
echo "=== User setup complete at $(date -Iseconds) (exit: $STATUS) ==="
echo "Log: $LOG"
exit 0
