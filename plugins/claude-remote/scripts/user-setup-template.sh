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

# ── VM fingerprint (cheap diagnostic, one-time) ──────────────────
echo "  host: $(uname -srm) | user: $(whoami) | home: $HOME"
[ -f /etc/os-release ] && . /etc/os-release && echo "  os: ${PRETTY_NAME:-unknown}"

# ── Permissive settings for sandboxed environment ────────────────
echo "[1/4] Installing permissive settings..."

# The project .claude/settings.json has restrictive permissions for local
# interactive use. In the sandboxed web environment there's no risk,
# so we install settings.local.json (higher precedence) that allow everything.
# This MUST run first so that env vars (e.g. DB credentials)
# are available to MCP servers even if later steps fail.
REPO_SETUP="$(find /home/user -maxdepth 4 -path '*/.claude/scripts/setup.sh' 2>/dev/null | head -1)"

if [ -n "$REPO_SETUP" ]; then
  REPO_DIR="$(dirname "$(dirname "$(dirname "$REPO_SETUP")")")"
  echo "  Found repo setup: $REPO_SETUP"
  if [ -f "$REPO_DIR/.claude/settings.remote.json" ]; then
    cp "$REPO_DIR/.claude/settings.remote.json" "$REPO_DIR/.claude/settings.local.json"
    echo "  Installed .claude/settings.local.json from settings.remote.json"
  fi
else
  # Diagnostic: if no repo setup script was discovered, dump the top of
  # /home/user so /claude-remote:debug can see where the repo actually
  # landed (common failure: cloned under /home/user/workspace/<repo>).
  echo "  WARN: no .claude/scripts/setup.sh found under /home/user (maxdepth 4)"
  echo "  /home/user directory tree (depth 4):"
  find /home/user -maxdepth 4 -type d 2>/dev/null | head -20 | sed 's/^/    /'
fi

# ── mise ──────────────────────────────────────────────────────────
echo "[2/4] Installing mise..."
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

# ── Common CLI tools (gh, jq) ────────────────────────────────────
# gh is NOT pre-installed on Claude web VMs; jq IS pre-installed. apt-get
# is idempotent so we just ask for both — already-installed is a no-op.
echo "[3/4] Installing common CLI tools (gh, jq)..."
apt-get update -qq
apt-get install -y -qq gh jq

# ── Delegate to repository setup ─────────────────────────────────
echo "[4/4] Delegating to repository setup..."

if [ -x "$REPO_SETUP" ]; then
  echo "  Running $REPO_SETUP ..."
  # Child stdout/stderr inherit the exec-tee redirect at the top of this
  # script, so everything the repo script emits lands in $LOG automatically.
  "$REPO_SETUP"
else
  echo "  No repo setup script found under /home/user/, skipping"
fi

echo "=== User setup complete at $(date -Iseconds) ==="
echo "Log: $LOG"
