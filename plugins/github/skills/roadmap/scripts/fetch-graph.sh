#!/usr/bin/env bash
#
# Fetch and normalize the issue graph for one or more GitHub repositories.
#
# Usage:
#   fetch-graph.sh <owner/repo> [<owner/repo> ...]
#
# Output (stdout): a single JSON object
#   {
#     "issues": [ { "repo", "number", "title", "type", "parent", "children" } ],
#     "edges":  [ { "blocked": "owner/repo#N", "by": "owner/repo#M",
#                   "blockedState", "byState", "crossRepo" } ],
#     "counts": [ { "id", "blockedBy", "blocking" } ],
#     "failed": [ { "repo", "error" } ]
#   }
#
# `issues` holds OPEN issues only. `edges` may reference closed issues — a closed
# blocker is exactly how "blocked" is told apart from "was blocked", so those
# nodes carry their state rather than being dropped.
#
# `counts` is the per-issue count of dependencies as GitHub reports them. Compare
# it against the edges actually resolved: a mismatch means an edge was missed and
# the rendered tree is incomplete. Reporting that beats drawing a quietly wrong map.
#
# Dependencies are reported from both ends (A blocking B is also B blocked-by A),
# so `edges` is deduplicated on the ordered pair.
#
# A repository that cannot be read is listed in `failed` and does not abort the
# run — a partial map is useful as long as it says it is partial.
#
# Requires: gh (authenticated), jq

set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $(basename "$0") <owner/repo> [<owner/repo> ...]" >&2
  exit 64
fi

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "error: '$bin' is required but not installed" >&2; exit 69; }
done

read -r -d '' QUERY <<'GRAPHQL' || true
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $endCursor, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        title
        state
        issueType { name }
        repository { nameWithOwner }
        parent { number state repository { nameWithOwner } }
        subIssues(first: 50) { nodes { number state repository { nameWithOwner } } }
        blockedBy(first: 50) { nodes { number state repository { nameWithOwner } } }
        blocking(first: 50)  { nodes { number state repository { nameWithOwner } } }
      }
    }
  }
}
GRAPHQL

raw_pages=""
failed="[]"

for slug in "$@"; do
  owner="${slug%%/*}"
  name="${slug##*/}"

  if [ -z "$owner" ] || [ -z "$name" ] || [ "$owner" = "$slug" ]; then
    failed=$(jq -c --arg r "$slug" '. + [{repo: $r, error: "not in owner/repo form"}]' <<<"$failed")
    continue
  fi

  # --paginate follows pageInfo.endCursor on its own, which is why the query
  # names the cursor variable $endCursor exactly.
  if ! page=$(gh api graphql --paginate \
        -f query="$QUERY" -F owner="$owner" -F name="$name" 2>&1); then
    err=$(printf '%s' "$page" | tr '\n' ' ' | cut -c1-200)
    failed=$(jq -c --arg r "$slug" --arg e "$err" '. + [{repo: $r, error: $e}]' <<<"$failed")
    continue
  fi

  raw_pages+="$page"$'\n'
done

printf '%s' "$raw_pages" | jq -s --argjson failed "$failed" '
  # gh --paginate emits one JSON document per page; collect every issue node.
  [ .[] | .data.repository.issues.nodes[]? ] as $nodes

  | def ref($n): ($n.repository.nameWithOwner + "#" + ($n.number | tostring));

    {
      issues: [ $nodes[] | {
        repo:     .repository.nameWithOwner,
        number:   .number,
        id:       ref(.),
        title:    .title,
        type:     (.issueType.name // null),
        parent:   (if .parent then { id: ref(.parent), state: .parent.state } else null end),
        children: [ .subIssues.nodes[] | { id: ref(.), state: .state } ]
      } ],

      edges: ( [
          # blocked-by, read from the blocked end
          ( $nodes[] | . as $i | .blockedBy.nodes[]
            | { blocked: ref($i), by: ref(.), blockedState: $i.state, byState: .state } ),
          # blocking, read from the blocker end — same relationship, other direction
          ( $nodes[] | . as $i | .blocking.nodes[]
            | { blocked: ref(.), by: ref($i), blockedState: .state, byState: $i.state } )
        ]
        | unique_by([.blocked, .by])
        | map(. + { crossRepo: ((.blocked | split("#")[0]) != (.by | split("#")[0])) })
      ),

      # Checksum against the edges above; see the header.
      counts: [ $nodes[] | {
        id:        ref(.),
        blockedBy: (.blockedBy.nodes | length),
        blocking:  (.blocking.nodes | length)
      } ],

      failed: $failed
    }
'
