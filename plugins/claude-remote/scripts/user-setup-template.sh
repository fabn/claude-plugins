#!/usr/bin/env bash
set -euo pipefail

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
# settings), then delegates to the repository's own .claude/scripts/setup.sh
# for repo-specific setup (bundle install, npm install, service startup, etc.).
#
# Logs everything to /tmp/claude-user-setup.log; the repo-level setup script
# tees to the same file so /claude-remote:debug has a single source of truth.
# =============================================================================

LOG="/tmp/claude-user-setup.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== User setup started at $(date -Iseconds) ==="

# ── Permissive settings for sandboxed environment ────────────────
echo "[1/3] Installing permissive settings..."

# The project .claude/settings.json has restrictive permissions for local
# interactive use. In the sandboxed web environment there's no risk,
# so we install settings.local.json (higher precedence) that allow everything.
# This MUST run first so that env vars (e.g. DB credentials)
# are available to MCP servers even if later steps fail.
REPO_SETUP="$(find /home/user -maxdepth 4 -path '*/.claude/scripts/setup.sh' 2>/dev/null | head -1)"

if [ -n "$REPO_SETUP" ]; then
  REPO_DIR="$(dirname "$(dirname "$(dirname "$REPO_SETUP")")")"
  if [ -f "$REPO_DIR/.claude/settings.remote.json" ]; then
    cp "$REPO_DIR/.claude/settings.remote.json" "$REPO_DIR/.claude/settings.local.json"
    echo "  Installed .claude/settings.local.json from settings.remote.json"
  fi
fi

# ── mise ──────────────────────────────────────────────────────────
echo "[2/3] Installing mise..."
if ! command -v mise >/dev/null 2>&1; then
  curl -fsSL https://mise.run | sh

  export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

  # Symlink mise into /usr/local/bin so it's available in all shells
  # (non-interactive shells don't read .bashrc or BASH_ENV)
  ln -sf ~/.local/bin/mise /usr/local/bin/mise

  # Activate for interactive sessions
  echo 'eval "$(mise activate bash)"' >> ~/.bashrc

  echo "  mise $(mise --version) installed"
else
  echo "  mise already installed: $(mise --version)"
fi

# Prefer precompiled Ruby (no build toolchain needed)
mise settings ruby.compile=false
# Skip GitHub attestation verification (rate-limited without auth token)
mise settings ruby.github_attestations=false

# ── Delegate to repository setup ─────────────────────────────────
echo "[3/3] Delegating to repository setup..."

if [ -x "$REPO_SETUP" ]; then
  echo "  Running $REPO_SETUP ..."
  "$REPO_SETUP"
else
  echo "  No repo setup script found under /home/user/, skipping"
fi

echo "=== User setup complete at $(date -Iseconds) ==="
echo "Log: $LOG"
