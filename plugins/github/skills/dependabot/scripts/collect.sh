#!/usr/bin/env bash
#
# List the open Dependabot pull requests of a repository, one JSON object per line.
#
# Usage:
#   collect.sh [<owner/repo>]        # defaults to the repository of the current directory
#
# Output (stdout), one line per PR:
#   {
#     "number", "title", "url", "createdAt", "head", "headRefName", "labels",
#     "ecosystem":  "bundler" | "npm_and_yarn" | "github_actions" | ...   (from the branch)
#     "group":      "<name>" | null      (group PRs: "Bump the <name> group ...")
#     "deps":       [ { "name", "from", "to", "bump" } ],
#     "majors":     true when any dep is a major,
#     "ours":       true when a commit is not authored by Dependabot (or the PR has
#                   more than 30 commits, which only we would add),
#     "mergeable":  "MERGEABLE" | "CONFLICTING" | "UNKNOWN",
#     "checks":     { "state": "success" | "failure" | "pending" | "none",
#                     "failed", "pending", "skipped": [names], "all": [ { "name", "state" } ] }
#                   For lane planning only: a skipped check does not make the state
#                   red, and required checks are not known here. The auto-merge gate
#                   decides with `gh pr checks`.
#   }
#
# `bump` is major / minor / patch, "unknown" when a side is not a version (a SHA,
# a date). A 0.x minor counts as major: semver allows breaking changes there.
#
# deps come from the body's "Updates `x` from a to b" lines when present (group
# PRs and multi-dependency PRs), otherwise from the title.
#
# Requires: gh (authenticated), jq

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' is required but not installed" >&2; exit 69; }

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

owner="${repo%/*}" name="${repo#*/}"

# A hand-written query: `gh pr list --json commits` asks for every author of
# every commit and trips GraphQL's 500k node limit on a large backlog.
# shellcheck disable=SC2016
gh api graphql --paginate -F owner="$owner" -F name="$name" -f query='
  query($owner: String!, $name: String!, $endCursor: String) {
    repository(owner: $owner, name: $name) {
      pullRequests(states: OPEN, first: 50, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          number title body url createdAt headRefName headRefOid mergeable
          author { login }
          labels(first: 20) { nodes { name } }
          commits(last: 30) { totalCount nodes { commit { authors(first: 5) { nodes { email } } } } }
          statusCheckRollup: commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 100) { nodes {
            __typename
            ... on CheckRun { name status conclusion }
            ... on StatusContext { context state }
          } } } } } }
        }
      }
    }
  }' --jq '.data.repository.pullRequests.nodes[] | select(.author.login == "dependabot")' \
| jq -c '
  def ver: ltrimstr("v") | [scan("[0-9]+") | tonumber];
  def bump($f; $t):
    if ($f | test("^[0-9a-f]{7,40}$")) or ($t | test("^[0-9a-f]{7,40}$")) then "unknown"
    else ($f | ver) as $a | ($t | ver) as $b
    | if ($a | length) == 0 or ($b | length) == 0 then "unknown"
      elif $a[0] != $b[0] then "major"
      elif $a[0] == 0 and ($a[1] // 0) != ($b[1] // 0) then "major"
      elif ($a[1] // 0) != ($b[1] // 0) then "minor"
      else "patch" end
    end;
  def dep($n; $f; $t): ($f | rtrimstr(".")) as $f | ($t | rtrimstr(".")) as $t
    | { name: $n, from: $f, to: $t, bump: bump($f; $t) };
  def check_state: (.conclusion // .state // .status // "" | ascii_downcase)
    | if . == "" or . == "in_progress" or . == "queued" or . == "pending" or . == "expected" or . == "waiting" then "pending"
      elif . == "success" or . == "neutral" then "success"
      elif . == "skipped" then "skipped"
      else "failure" end;

  (.body // "") as $body
  | ([ $body | scan("Updates `([^`]+)` from ([^ \n]+) to ([^ \n]+)") | dep(.[0]; .[1]; .[2]) ]) as $from_body
  | ([ .title | capture("(?i)(?:bump|update) (?<n>\\S+)(?: requirement)? from (?<f>.+?) to (?<t>.+?)(?: in /\\S*)?$")? | dep(.n; .f; .t) ]) as $from_title
  | ([ .statusCheckRollup.nodes[0].commit.statusCheckRollup.contexts.nodes[]? | { name: (.name // .context), state: check_state } ]) as $checks
  | {
      number, title, url, createdAt,
      head: .headRefOid, headRefName,
      labels: [ .labels.nodes[].name ],
      ecosystem: (.headRefName | split("/")[1]),
      group: (.title | capture("(?i)bump the (?<g>\\S+) group").g? // null),
      deps: (if ($from_body | length) > 0 then $from_body else $from_title end | unique_by(.name)),
      ours: (.commits.totalCount > 30 or any(.commits.nodes[].commit.authors.nodes[].email; test("dependabot") | not)),
      mergeable,
      checks: {
        state: (if ($checks | length) == 0 then "none"
                elif any($checks[]; .state == "failure") then "failure"
                elif any($checks[]; .state == "pending") then "pending"
                else "success" end),
        failed: [ $checks[] | select(.state == "failure") | .name ],
        pending: [ $checks[] | select(.state == "pending") | .name ],
        skipped: [ $checks[] | select(.state == "skipped") | .name ],
        all: $checks
      }
    }
  | .majors = any(.deps[]; .bump == "major")
'
