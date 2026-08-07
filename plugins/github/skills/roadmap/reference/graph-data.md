# Where the Roadmap Graph Comes From

The skill does not query GitHub directly. It runs `scripts/fetch-graph.sh`, which owns every detail below. This file documents the contract so the output can be consumed confidently — not so the script can be reimplemented inline.

## Output contract

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/roadmap/scripts/fetch-graph.sh" owner/repo-a owner/repo-b
```

One JSON object on stdout:

| Key | Contents |
|---|---|
| `issues` | Open issues: `repo`, `number`, `id` (`owner/repo#N`), `title`, `type`, `parent`, `children[]` |
| `edges` | Deduplicated dependencies: `blocked`, `by`, `blockedState`, `byState`, `crossRepo` |
| `counts` | Per issue, the dependency counts GitHub reports — a checksum, see below |
| `failed` | Repositories that could not be read, with the error |

Every issue reference is the string `owner/repo#number`, so cross-repository edges need no second lookup and no disambiguation.

Exit codes: `64` no arguments, `69` a required binary (`gh`, `jq`) is missing. A repository that fails to fetch is **not** an error exit — it lands in `failed` and the run continues, because a partial map is useful as long as it announces that it is partial.

## Why a script and not a query in the skill

Four details are easy to get wrong when writing the query by hand, and each one fails quietly:

1. **`--paginate` requires the cursor variable to be named `$endCursor`.** Any other name and only the first 100 issues are ever returned — with no error, and a plausible-looking map.
2. **Dependencies are reported from both ends.** If A blocks B, A lists B under `blocking` *and* B lists A under `blockedBy`. Without deduplication on the ordered pair every edge is drawn twice.
3. **Closed issues must be kept when they appear as edge nodes.** Only open issues are fetched, but a blocker may well be closed — and a closed blocker is precisely how "blocked" is told apart from "was blocked". Filtering edge nodes by state inverts the meaning of the whole map.
4. **One unreadable repository must not abort the run.** Failing the whole invocation because one token lacks one scope turns a useful partial answer into no answer.

## Why not the GitHub MCP

`issue_read` returns dependency information as counts:

```json
{ "blocked_by": 1, "blocking": 2, "total_blocked_by": 1, "total_blocking": 2 }
```

Enough to answer "is this blocked?", not "by what?" — so it cannot build a graph.

It does have one good use, and the script preserves it in `counts`: a **checksum**. If an issue reports `blockedBy: 2` but only one edge was resolved for it, an edge was dropped and the tree is incomplete. Reporting that beats rendering a quietly wrong map.

## The query

Run by the script; reproduced here for review, not for copying into a skill.

```graphql
query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $endCursor, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number title state
        issueType { name }
        repository { nameWithOwner }
        parent    { number state repository { nameWithOwner } }
        subIssues(first: 50) { nodes { number state repository { nameWithOwner } } }
        blockedBy(first: 50) { nodes { number state repository { nameWithOwner } } }
        blocking(first: 50)  { nodes { number state repository { nameWithOwner } } }
      }
    }
  }
}
```

`issueType` is null on repositories without issue types enabled — treat it as cosmetic and never branch behaviour on it.

### Drilling into a single issue

When the user asks about one issue after seeing the map, this is small enough to run inline:

```bash
gh api graphql -f query='
query($owner:String!,$name:String!,$number:Int!) {
  repository(owner:$owner,name:$name) {
    issue(number:$number) {
      number title state
      blockedBy(first:50) { nodes { number title state repository { nameWithOwner } } }
      blocking(first:50)  { nodes { number title state repository { nameWithOwner } } }
    }
  }
}' -F owner=<owner> -F name=<repo> -F number=<n>
```

## The cross-organization limitation

GitHub issue dependencies span repositories but **not organizations**. Submitting one across an organization boundary returns `FORBIDDEN: Unauthorized`. Sub-issues hit the same practical ceiling.

This is the only reason the skill accepts a declared edge list. It is a workaround for a platform limit, not a general-purpose way to describe dependencies — anything GitHub can express should be recorded on the issue, where it stays correct with nobody maintaining it.

Sources:

- [Creating issue dependencies — GitHub Docs](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies)
- [Dependencies on issues — GitHub Changelog](https://github.blog/changelog/2025-08-21-dependencies-on-issues/)
- [Adding sub-issues — GitHub Docs](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)

## Cost

GraphQL is scored per call on nodes returned, not pages requested. One call per repository at 100 issues a page is inexpensive. A project large enough to paginate many times per repository should lower `first:` rather than add calls.
