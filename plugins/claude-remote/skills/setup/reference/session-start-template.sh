#!/usr/bin/env bash
# SessionStart hook — runs after Claude Code launches on every session
# (startup + resume). Keeps it light: ensure services are up and persist
# mise-managed PATH via $CLAUDE_ENV_FILE so every Bash tool call inherits it.
#
# Skips on local machines — only runs inside Claude Code web cloud sessions.

[ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && exit 0

# __SECTION:mysql__
if ! mysqladmin ping --silent 2>/dev/null; then
  service mysql start >/dev/null 2>&1 || true
  for i in $(seq 1 15); do
    mysqladmin ping --silent 2>/dev/null && break
    sleep 1
  done
fi
# __END:mysql__

# __SECTION:postgres__
if ! pg_isready -q 2>/dev/null; then
  service postgresql start >/dev/null 2>&1 || true
fi
# __END:postgres__

# __SECTION:redis__
if ! redis-cli ping >/dev/null 2>&1; then
  service redis-server start >/dev/null 2>&1 || true
fi
# __END:redis__

# --- Persist mise-managed PATH so every Bash tool call inherits it ---
# Claude Code's Bash tool uses non-interactive shells that skip .bashrc,
# so we must inject the mise-shimmed PATH via CLAUDE_ENV_FILE.
#
# A session can also open on a parent folder (e.g. /home/user) holding several
# cloned repos. In that case $CLAUDE_PROJECT_DIR has no mise.toml of its own,
# so trust every child repo's mise.toml and put each repo's tools on PATH.
if [ -n "${CLAUDE_ENV_FILE:-}" ] && command -v mise >/dev/null 2>&1; then
  PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
  if [ -d "$PROJECT_DIR/.git" ] || [ -f "$PROJECT_DIR/mise.toml" ]; then
    # Single repo: the project dir is the repo itself.
    mise trust "$PROJECT_DIR/mise.toml" 2>/dev/null || true
  else
    for repo in "$PROJECT_DIR"/*/; do
      repo="${repo%/}"
      [ -f "$repo/mise.toml" ] || [ -f "$repo/.tool-versions" ] || continue
      [ -f "$repo/mise.toml" ] && { mise trust "$repo/mise.toml" >/dev/null 2>&1 || true; }
      # Prepend this repo's tool bin dirs to PATH: shims resolve versions by
      # cwd, so from the parent folder they would find no version at all.
      while IFS= read -r bin_dir; do
        [ -n "$bin_dir" ] && case ":$PATH:" in *":$bin_dir:"*) ;; *) PATH="$bin_dir:$PATH" ;; esac
      done < <(cd "$repo" && mise bin-paths 2>/dev/null)
    done
    export PATH
  fi
  eval "$(mise activate bash 2>/dev/null)" || true
  echo "PATH=$PATH" >> "$CLAUDE_ENV_FILE"
fi

# --- Quick health check ---
ISSUES=()
# __SECTION:ruby_healthcheck__
command -v ruby >/dev/null 2>&1 || ISSUES+=("ruby missing")
command -v bundle >/dev/null 2>&1 || ISSUES+=("bundle missing")
# __END:ruby_healthcheck__
# __SECTION:node_healthcheck__
command -v node >/dev/null 2>&1 || ISSUES+=("node missing")
# __END:node_healthcheck__
# __SECTION:mysql_healthcheck__
mysqladmin ping --silent 2>/dev/null || ISSUES+=("mysql down")
# __END:mysql_healthcheck__
# __SECTION:postgres_healthcheck__
pg_isready -q 2>/dev/null || ISSUES+=("postgres down")
# __END:postgres_healthcheck__
# __SECTION:redis_healthcheck__
redis-cli ping >/dev/null 2>&1 || ISSUES+=("redis down")
# __END:redis_healthcheck__

if [ ${#ISSUES[@]} -gt 0 ]; then
  echo "SETUP INCOMPLETE: ${ISSUES[*]}. See /tmp/claude-user-setup.log"
else
  echo "Session ready"
fi
