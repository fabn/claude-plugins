#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Repo-level setup script — runs inside Claude Code web cloud sessions only.
#
# Invoked by the user-level setup script (pasted into the web environment
# "Setup script" field) which discovers this file via:
#   find /home/user -maxdepth 4 -path '*/.claude/scripts/setup.sh'
#
# Canonical reference for the user-level script:
#   ${CLAUDE_PLUGIN_ROOT}/scripts/user-setup-template.sh
#
# When invoked by the user-level script, stdout/stderr are already captured
# to /tmp/claude-user-setup.log via that script's exec-tee (inherited fds).
# If you run this script standalone for debugging, pipe it yourself:
#   bash .claude/scripts/setup.sh 2>&1 | tee -a /tmp/claude-user-setup.log
# =============================================================================

# The user-level setup script invokes this file without cd-ing into the repo,
# so $PWD is whatever the caller had (typically /home/user). Without moving
# into the repo root, mise cannot see the repo's mise.toml and silently
# reports "all tools are installed" while actually installing nothing, which
# then cascades into every subsequent step being a no-op or failing because
# the expected runtimes are not on PATH. Always cd first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

echo "=== Repo setup started at $(date -Iseconds) ==="
echo "  repo: $REPO_ROOT"

# Ensure mise shims are on PATH for this non-interactive shell.
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

# __SECTION:mise__
# Runtime versions from mise.toml / .tool-versions
if command -v mise >/dev/null 2>&1; then
  echo "[repo 1] mise install..."
  mise trust "$REPO_ROOT" 2>/dev/null || true
  mise install
  # Reshim so any newly-installed mise-managed binaries (fvm, lefthook,
  # typst, etc.) land on PATH for the subsequent steps.
  mise reshim || true
fi
# __END:mise__

# __SECTION:ruby__
# Ruby / Bundler
if [ -f Gemfile ]; then
  echo "[repo] bundle install..."
  bundle config set --local path vendor/bundle
  bundle install --jobs=4 --retry=3
  # Reshim so new gem-provided binaries (e.g. rails, rspec) are on PATH
  command -v mise >/dev/null 2>&1 && mise reshim || true
fi
# __END:ruby__

# __SECTION:node__
# Node.js — detect package manager from lockfile
if [ -f package.json ]; then
  if [ -f pnpm-lock.yaml ]; then
    echo "[repo] pnpm install..."
    corepack enable >/dev/null 2>&1 || true
    pnpm install --frozen-lockfile
  elif [ -f yarn.lock ]; then
    echo "[repo] yarn install..."
    corepack enable >/dev/null 2>&1 || true
    yarn install --frozen-lockfile
  elif [ -f bun.lockb ]; then
    echo "[repo] bun install..."
    bun install --frozen-lockfile
  else
    echo "[repo] npm ci..."
    npm ci
  fi
  # Reshim so new npm-provided binaries are on PATH
  command -v mise >/dev/null 2>&1 && mise reshim || true
fi
# __END:node__

# __SECTION:python__
# Python
if [ -f pyproject.toml ] && command -v uv >/dev/null 2>&1; then
  echo "[repo] uv sync..."
  uv sync
elif [ -f requirements.txt ]; then
  echo "[repo] pip install..."
  pip install -r requirements.txt
fi
# __END:python__

# __SECTION:postgres__
# PostgreSQL
if ! pg_isready -q 2>/dev/null; then
  echo "[repo] starting postgresql..."
  service postgresql start || true
fi
# __END:postgres__

# __SECTION:mysql__
# MySQL — NOT pre-installed on Claude web VMs; install then start.
if ! command -v mysqld >/dev/null 2>&1; then
  echo "[repo] installing mysql-server..."
  apt-get update -qq && apt-get install -y -qq mysql-server
fi
if ! mysqladmin ping --silent 2>/dev/null; then
  echo "[repo] starting mysql..."
  service mysql start || true
fi
# __END:mysql__

# __SECTION:redis__
# Redis
if ! redis-cli ping >/dev/null 2>&1; then
  echo "[repo] starting redis..."
  service redis-server start || true
fi
# __END:redis__

echo "=== Repo setup complete at $(date -Iseconds) ==="
