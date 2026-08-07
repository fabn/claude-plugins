#!/usr/bin/env bash
#
# Move this plugin's project configuration out of the deprecated CLAUDE.md
# comment block and into `.claude/github.json`.
#
# Usage:
#   migrate-config.sh [<project-dir>] [--dry-run]
#
# Writes `.claude/github.json` and removes the `<!-- github-plugin-config -->`
# block, its keys, and one blank line left behind. Prints a summary to stderr and
# the resulting JSON to stdout.
#
# Refuses to overwrite an existing `.claude/github.json` — if both exist, the
# JSON is authoritative and the markdown block is leftovers to delete by hand,
# which is a decision for the user rather than for this script.
#
# --dry-run prints what would be written and touches nothing.
#
# Requires: jq

set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required but not installed" >&2; exit 69; }

dir="."
dry_run=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    *) dir="$arg" ;;
  esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
md_path="$dir/CLAUDE.md"
json_path="$dir/.claude/github.json"

if [ -f "$json_path" ]; then
  echo "error: $json_path already exists — nothing to migrate into." >&2
  echo "       If CLAUDE.md still carries a config block, remove it by hand." >&2
  exit 65
fi

resolved=$("$here/read-config.sh" "$dir") || exit $?
source_kind=$(jq -r '.source' <<<"$resolved")

if [ "$source_kind" != "claude-md" ]; then
  echo "error: no deprecated config block found in $md_path (source: $source_kind)" >&2
  exit 65
fi

config=$(jq '.config' <<<"$resolved")

if [ "$dry_run" -eq 1 ]; then
  echo "would write $json_path:" >&2
  printf '%s\n' "$config"
  echo "would strip the <!-- github-plugin-config --> block from $md_path" >&2
  exit 0
fi

mkdir -p "$dir/.claude"
printf '%s\n' "$config" > "$json_path"

# Strip the marker, every github_* key comment, and a blank line left in their place.
tmp=$(mktemp)
sed -E '/<!-- *github-plugin-config *-->/d; /<!-- *github_[a-z_]+ *:[^>]*-->/d' "$md_path" \
  | cat -s > "$tmp"
mv "$tmp" "$md_path"

echo "wrote $json_path" >&2
echo "stripped the config block from $md_path" >&2
printf '%s\n' "$config"
