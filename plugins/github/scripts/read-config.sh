#!/usr/bin/env bash
#
# Resolve this plugin's project configuration, from either the current location
# or the deprecated one, and say which was used.
#
# Usage:
#   read-config.sh [<project-dir>]        # defaults to the current directory
#
# Output (stdout): a single JSON object
#   {
#     "source": "json" | "claude-md" | "none",
#     "path":   "<file that was read>" | null,
#     "config": { ... }
#   }
#
# `source` is the part callers must act on:
#   json      — current location, nothing to do
#   claude-md — the deprecated `<!-- github-plugin-config -->` block in CLAUDE.md.
#               Tell the user and offer `migrate-config.sh`. Do NOT proceed
#               silently: several skills degrade quietly without config (pm skips
#               board steps without erroring), so a silent fallback would look
#               identical to a silent failure once the fallback is removed.
#   none      — no configuration anywhere; use each skill's own defaults
#
# `config` is normalized to the JSON shape either way, so callers read one shape
# and never parse markdown themselves.
#
# Requires: jq

set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required but not installed" >&2; exit 69; }

dir="${1:-.}"
json_path="$dir/.claude/github.json"
md_path="$dir/CLAUDE.md"

# --- current location -------------------------------------------------------
if [ -f "$json_path" ]; then
  if ! cfg=$(jq -e '.' "$json_path" 2>&1); then
    echo "error: $json_path is not valid JSON: $cfg" >&2
    exit 65
  fi
  jq -n --argjson c "$cfg" --arg p "$json_path" '{source: "json", path: $p, config: $c}'
  exit 0
fi

# --- deprecated location ----------------------------------------------------
if [ -f "$md_path" ] && grep -q '<!-- *github-plugin-config *-->' "$md_path"; then
  # Each key is its own `<!-- key: value -->` comment. Collect them into an
  # object, then reshape to match the JSON layout.
  flat=$(grep -oE '<!-- *github_[a-z_]+ *:[^>]*-->' "$md_path" \
    | sed -E 's/^<!-- *//; s/ *-->$//' \
    | jq -R -s '
        split("\n") | map(select(length > 0)) | map(
          (index(":")) as $i
          | { key:   (.[0:$i] | gsub("^\\s+|\\s+$"; "")),
              value: (.[$i+1:] | gsub("^\\s+|\\s+$"; "")) }
        ) | from_entries')

  jq -n --argjson f "$flat" --arg p "$md_path" '
    def num($v): if $v == null then null elif ($v | test("^[0-9]+$")) then ($v | tonumber) else $v end;
    # Split a comma-separated scalar; the deprecated format could hold nothing richer.
    def list($v): if $v == null or $v == "" then null
                  else ($v | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))) end;
    # "a#1 <- b#2; c#3 <- d#4"  ->  [{blocked, by}, ...]
    def edges($v): if $v == null or $v == "" then null
                   else ($v | split(";") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))
                         | map(split("<-") | map(gsub("^\\s+|\\s+$"; "")))
                         | map(select(length == 2))
                         | map({blocked: .[0], by: .[1]})) end;
    {
      source: "claude-md",
      path: $p,
      config: ({
        mainBranch:   $f.github_main_branch,
        branchPrefix: $f.github_branch_prefix,
        project: (
          if ($f.github_project_number // $f.github_project_owner) then
            { number: num($f.github_project_number), owner: $f.github_project_owner }
          else null end
        ),
        roadmap: (
          if ($f.github_roadmap_repos // $f.github_roadmap_external_edges) then
            { repos: list($f.github_roadmap_repos), externalEdges: edges($f.github_roadmap_external_edges) }
          else null end
        )
      } | with_entries(select(.value != null)))
    }'
  exit 0
fi

# --- nothing ----------------------------------------------------------------
jq -n '{source: "none", path: null, config: {}}'
