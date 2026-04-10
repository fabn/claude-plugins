#!/usr/bin/env bash
# =============================================================================
# Claude Code web environment debug dump.
#
# Run manually during a cloud session (or invoked by /claude-remote:debug)
# to gather diagnostic information about the VM, runtimes, services, and
# shell state. Output is teed to /tmp/claude-env-debug.log so it can be
# shared or attached to an issue.
#
# Safe to run anywhere — does not modify system state.
# =============================================================================

LOG="/tmp/claude-env-debug.log"

{
echo "============================================"
echo "Claude Code Environment Debug"
echo "Date: $(date -Iseconds)"
echo "============================================"

echo ""
echo "=== Identity ==="
echo "whoami: $(whoami)"
echo "id: $(id)"
echo "HOME: $HOME"
echo "SHELL: $SHELL"
echo "TERM: ${TERM:-unset}"

echo ""
echo "=== Working Directory ==="
echo "pwd: $(pwd)"
echo "ls -la:"
ls -la

echo ""
echo "=== Claude Environment Variables ==="
env | grep -i CLAUDE | sort

echo ""
echo "=== Key Paths ==="
echo "PATH: $PATH"
for bin in mise ruby bundle rails node npm pnpm yarn python uv go php gh jq mysql redis-cli psql pg_isready; do
  echo "which $bin: $(command -v "$bin" 2>/dev/null || echo 'not found')"
done

echo ""
echo "=== Tool Versions ==="
for cmd in "mise --version" "ruby --version" "bundle --version" "rails --version" "node --version" "npm --version" "python --version" "go version" "php --version" "gh --version" "jq --version" "mysql --version"; do
  printf "%-20s " "${cmd%% *}:"
  $cmd 2>/dev/null | head -1 || echo "not found"
done

echo ""
echo "=== OS Info ==="
echo "uname -a: $(uname -a)"
cat /etc/os-release 2>/dev/null || echo "/etc/os-release not found"

echo ""
echo "=== Filesystem ==="
echo "df -h /:"
df -h /
echo ""
echo "/home/user contents:"
ls -la /home/user/ 2>/dev/null || echo "  /home/user does not exist"
echo ""
echo "/home/claude contents (if exists):"
ls -la /home/claude/ 2>/dev/null || echo "  /home/claude does not exist"

echo ""
echo "=== Process Info ==="
echo "Running services (mysql/redis/postgres/ruby/node):"
ps aux | grep -E "(mysql|redis|postgres|ruby|node)" | grep -v grep || echo "  none running"

echo ""
echo "=== Network ==="
echo "Listening ports:"
ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || echo "  ss/netstat not available"

echo ""
echo "=== MySQL Status ==="
mysqladmin ping --silent 2>&1 || echo "MySQL not running"

echo ""
echo "=== PostgreSQL Status ==="
pg_isready 2>&1 || echo "PostgreSQL not running"

echo ""
echo "=== Redis Status ==="
redis-cli ping 2>/dev/null || echo "Redis not running"

echo ""
echo "=== .env File (current directory) ==="
if [ -f .env ]; then
  echo ".env exists, $(wc -l < .env) lines"
  echo "Keys present (values omitted):"
  grep -oE '^[A-Z_][A-Z0-9_]*=' .env | sort -u
else
  echo ".env does not exist in $(pwd)"
fi

echo ""
echo "=== CLAUDE_ENV_FILE ==="
echo "CLAUDE_ENV_FILE=${CLAUDE_ENV_FILE:-unset}"
if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -f "$CLAUDE_ENV_FILE" ]; then
  echo "Contents:"
  cat "$CLAUDE_ENV_FILE"
else
  echo "File does not exist or var unset"
fi

echo ""
echo "=== mise Status ==="
if command -v mise >/dev/null 2>&1; then
  echo "mise ls:"
  mise ls 2>&1
  echo ""
  echo "mise settings:"
  mise settings 2>&1
else
  echo "mise not installed"
fi

echo ""
echo "=== Shell Init Files ==="
for f in ~/.bashrc ~/.bash_profile ~/.profile /etc/profile; do
  if [ -f "$f" ]; then
    echo "--- $f (last 10 lines) ---"
    tail -10 "$f"
    echo ""
  fi
done

echo ""
echo "=== Recent Setup Log Tail ==="
if [ -f /tmp/claude-user-setup.log ]; then
  echo "/tmp/claude-user-setup.log (last 40 lines):"
  tail -40 /tmp/claude-user-setup.log
else
  echo "/tmp/claude-user-setup.log does not exist"
fi

echo ""
echo "============================================"
echo "Debug complete at $(date -Iseconds)"
echo "============================================"
} 2>&1 | tee "$LOG"

echo ""
echo "Full log saved to: $LOG"
