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
#     "failed": [ { "repo", "error" } ],
#     "resolved": [ { "ref", "kind", "state", "title" } ]     # only with --resolve
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
#   --resolve <owner/repo#N> [...]
#
# Looks up arbitrary references and reports what they actually are. Needed for
# two things the issue sweep above structurally cannot see:
#
#   * Declared cross-organization edges. Only OPEN issues are swept, so an edge
#     naming an issue that has since been closed has nothing to be checked
#     against — it would be rendered as a live blocker for ever.
#   * Pull requests. `issues()` excludes them, so work in flight as a PR looks
#     like work not started.
#
# `kind` is "issue", "pull_request" or "missing"; `state` is OPEN, CLOSED or
# MERGED.
#
# Requires: gh (authenticated), jq

set -uo pipefail

repos=()
refs=()
mode="repos"
for arg in "$@"; do
  case "$arg" in
    --resolve) mode="refs"; continue ;;
  esac
  if [ "$mode" = "refs" ]; then refs+=("$arg"); else repos+=("$arg"); fi
done

if [ "${#repos[@]}" -eq 0 ] && [ "${#refs[@]}" -eq 0 ]; then
  echo "usage: $(basename "$0") <owner/repo> [...] [--resolve <owner/repo#N> ...]" >&2
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

for slug in ${repos[@]+"${repos[@]}"}; do
  owner="${slug%%/*}"
  name="${slug##*/}"

  # Reject anything that is not exactly one owner/repo pair. Whitespace is the
  # case worth naming: a caller that passes "a/b c/d" as a single argument (easy
  # in zsh, where unquoted expansion does not word-split) would otherwise be
  # queried as owner "a", name "d" and come back as a confusing NOT_FOUND.
  case "$slug" in
    *[[:space:]]*)
      failed=$(jq -c --arg r "$slug" '. + [{repo: $r, error: "contains whitespace — pass each owner/repo as its own argument"}]' <<<"$failed")
      continue ;;
  esac

  if [ -z "$owner" ] || [ -z "$name" ] || [ "$owner" = "$slug" ] || [ "$owner/$name" != "$slug" ]; then
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

# --- resolve explicit references ------------------------------------------
# One call per ref, asking for both shapes: a number is an issue or a PR and
# nothing tells them apart in advance. Whichever comes back non-null is the answer.
resolved="[]"
for ref in ${refs[@]+"${refs[@]}"}; do
  slug="${ref%%#*}"
  num="${ref##*#}"
  owner="${slug%%/*}"
  name="${slug##*/}"

  if [ "$slug" = "$ref" ] || [ -z "$num" ] || [ "$owner" = "$slug" ] || ! [ "$num" -eq "$num" ] 2>/dev/null; then
    resolved=$(jq -c --arg r "$ref" '. + [{ref: $r, kind: "missing", state: null, title: "not in owner/repo#number form"}]' <<<"$resolved")
    continue
  fi

  # Asking for both shapes means one alias is ALWAYS null, and GraphQL reports
  # that as a NOT_FOUND error alongside perfectly good data — which makes gh
  # exit non-zero on every successful lookup. So the exit code says nothing
  # here; what decides is whether the body parses and carries a node.
  out=$(gh api graphql \
        -f query='query($owner:String!,$name:String!,$number:Int!){
          repository(owner:$owner,name:$name){
            issue(number:$number){ state title }
            pullRequest(number:$number){ state title }
          }
        }' -F owner="$owner" -F name="$name" -F number="$num" 2>/dev/null)

  if ! jq -e '.data' >/dev/null 2>&1 <<<"$out"; then
    resolved=$(jq -c --arg r "$ref" '. + [{ref: $r, kind: "missing", state: null, title: "lookup failed"}]' <<<"$resolved")
    continue
  fi

  resolved=$(jq -c --arg r "$ref" --argjson o "$out" '
    ($o.data.repository // {}) as $d
    | . + [ if   $d.issue       then {ref: $r, kind: "issue",        state: $d.issue.state,       title: $d.issue.title}
            elif $d.pullRequest then {ref: $r, kind: "pull_request", state: (if $d.pullRequest.state == "MERGED" then "MERGED" else $d.pullRequest.state end), title: $d.pullRequest.title}
            else {ref: $r, kind: "missing", state: null, title: "no issue or pull request with that number"} end ]
  ' <<<"$resolved")
done

printf '%s' "$raw_pages" | jq -s --argjson failed "$failed" --argjson resolved "$resolved" '
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

      failed: $failed,
      resolved: $resolved
    }
'
