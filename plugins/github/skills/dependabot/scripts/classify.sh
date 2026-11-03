#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq programs are single-quoted on purpose
#
# Classify open Dependabot PRs against what the default branch locks today.
#
# Usage:
#   collect.sh [<owner/repo>] | classify.sh [<owner/repo>]
#
# Run from a checkout of the repository with the default branch fetched: GitHub
# Actions are read from `.github/` on origin/<default>.
#
# Output (stdout), one line per PR:
#   { "number", "verdict", "deps": [ { "name", "from", "to", "locked": [versions], "verdict" } ] }
#
# Dependency verdicts:
#   GONE          not locked on the default branch any more
#   SUPERSEDED    the default branch already locks the target or higher
#   DUPLICATE     another open PR moves the same dependency higher on the same major
#                 ("of": its number). Never across majors: a patch on the current line
#                 (often a security fix) is not a duplicate of a major.
#   PENDING       still to do
#   UNKNOWN       this script cannot tell (ecosystem absent from the SBOM, a SHA pin
#                 without a version comment): use the ecosystem adapter
#
# A PR is PENDING when any dep is, UNKNOWN when any dep is and none is PENDING,
# otherwise GONE / SUPERSEDED / DUPLICATE from the mix of its deps.
#
# Locked versions come from the dependency-graph SBOM, which lags a few minutes
# behind a push to the default branch. A package can be locked at several
# versions (npm): only the instances on the target's major count for SUPERSEDED.
#
# Requires: gh (authenticated), jq, git

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required but not installed" >&2; exit 69; }

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
default=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/prs.jsonl"

gh api "repos/$repo/dependency-graph/sbom" --jq '
  [ .sbom.packages[]
    | (.externalRefs // [] | map(.referenceLocator | select(startswith("pkg:"))) | first) as $purl
    | select($purl != null)
    | { type: ($purl | capture("^pkg:(?<t>[^/]+)/").t), name, version: .versionInfo } ]' \
  > "$tmp/sbom.json" 2>"$tmp/sbom.err" || {
  echo "warning: SBOM unavailable ($(head -1 "$tmp/sbom.err")); every non-Actions dep is UNKNOWN" >&2
  echo '[]' > "$tmp/sbom.json"
}

# `uses: owner/action[/path]@ref  # vX.Y.Z` in workflows and local composite actions.
if jq -s -e 'any(.[]; .ecosystem == "github_actions")' "$tmp/prs.jsonl" >/dev/null; then
  here=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
  if [ "$here" != "$repo" ]; then
    echo "warning: the current directory is not a checkout of $repo; GitHub Actions deps are UNKNOWN" >&2
    echo null > "$tmp/actions.json"
  elif git rev-parse --verify -q "origin/$default" >/dev/null; then
    git grep -h -E 'uses:[[:space:]]*[^ .][^ ]*@' "origin/$default" -- .github \
      | sed -E 's/^.*uses:[[:space:]]*//; s/["'\'']//g' \
      | jq -R -s '
          split("\n") | map(select(length > 0)
          | capture("^(?<name>[^@ ]+)@(?<ref>[^ #]+)[[:space:]]*(#[[:space:]]*(?<comment>\\S+))?")?)' \
      > "$tmp/actions.json"
  else
    echo "warning: origin/$default not fetched; GitHub Actions deps are UNKNOWN (git fetch origin $default)" >&2
    echo null > "$tmp/actions.json"
  fi
else
  echo '[]' > "$tmp/actions.json"
fi

jq -c -s --slurpfile sbom "$tmp/sbom.json" --slurpfile actions "$tmp/actions.json" '
  def ver: ltrimstr("v") | [scan("[0-9]+") | tonumber];
  def purl_type:
    { bundler: "gem", npm_and_yarn: "npm", bun: "npm", pip: "pypi", uv: "pypi", poetry: "pypi",
      go_modules: "golang", cargo: "cargo", composer: "composer", maven: "maven", gradle: "maven",
      nuget: "nuget", pub: "pub", mix: "hex", swift: "swift" }[.];
  ($sbom[0]) as $sbom | ($actions[0]) as $actions
  | ([ $sbom[].type ] | unique) as $covered

  | def locked($eco; $name):
      if $eco == "github_actions" then
        if $actions == null then null
        else [ $actions[] | select(.name == $name or (.name | startswith($name + "/")))
               | if (.ref | test("^[0-9a-f]{40}$")) then (.comment // "sha") else .ref end
               | ltrimstr("v") ] | unique
        end
      else ($eco | purl_type) as $t
        | if $t == null or ($covered | index($t) | not) then null
          else [ $sbom[] | select(.type == $t and .name == $name) | .version ] | unique end
      end;

    def dep_verdict:
      . as $d
      | if .locked == null then "UNKNOWN"
      elif (.locked | length) == 0 then "GONE"
      elif (.from | test("[~^<>=*]")) then "PENDING"
      elif any(.locked[]; . == ($d.from | ltrimstr("v")) or . == "sha") then "PENDING"
      else (.to | ver) as $to
        | [ .locked[] | ver | select(length > 0 and .[0] == $to[0]) ] as $same
        | if ($same | length) > 0 and all($same[]; . >= $to) then "SUPERSEDED" else "PENDING" end
      end;

    [ .[] | . as $pr
      | { number, ecosystem,
          deps: [ .deps[] | . + { locked: locked($pr.ecosystem; .name) } | . + { verdict: dep_verdict } ] } ]

  # A pending dep that another PR moves higher is a duplicate of that PR.
  | . as $all
  | [ .[] | .ecosystem as $eco | .number as $n
      | .deps |= map(
          if .verdict != "PENDING" then .
          else . as $d
            | [ $all[] | select(.number != $n and .ecosystem == $eco) | .number as $m
                | .deps[] | select(.name == $d.name and (.to | ver) > ($d.to | ver) and (.to | ver)[0] == ($d.to | ver)[0])
                | $m ] as $higher
            | if ($higher | length) > 0 then . + { verdict: "DUPLICATE", of: ($higher | max) } else . end
          end) ]

  | .[]
  | [ .deps[].verdict ] as $v
  | { number,
      verdict: (if ($v | length) == 0 then "UNKNOWN"
                elif ($v | index("PENDING")) then "PENDING"
                elif ($v | index("UNKNOWN")) then "UNKNOWN"
                elif all($v[]; . == "GONE") then "GONE"
                elif ($v | index("DUPLICATE")) then "DUPLICATE"
                else "SUPERSEDED" end),
      deps: [ .deps[] | del(.bump) ] }
' "$tmp/prs.jsonl"
