# GraphQL Queries for the Roadmap Skill

## Why GraphQL and not the GitHub MCP

The GitHub MCP's `issue_read` returns dependency information as an **`issue_dependencies_summary`** object:

```json
{ "blocked_by": 1, "blocking": 2, "total_blocked_by": 1, "total_blocking": 2 }
```

Counts, not edges. That is enough to answer "is this blocked?" but not "by what?", so it cannot build a graph. It has one good use: as a **checksum**. If the resolved graph produces fewer blockers for an issue than `total_blocked_by` reports, an edge was missed — say so rather than rendering a tree that is quietly incomplete.

GraphQL returns the edges themselves, and each node carries its repository, so one call per repository is enough.

## The main query

One call per repository. Verified against the public schema.

```graphql
query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $after, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        title
        state
        issueType { name }
        parent {
          number
          state
          repository { nameWithOwner }
        }
        subIssues(first: 50) {
          nodes { number state title repository { nameWithOwner } }
        }
        blockedBy(first: 50) {
          nodes { number state title repository { nameWithOwner } }
        }
        blocking(first: 50) {
          nodes { number state title repository { nameWithOwner } }
        }
      }
    }
  }
}
```

Invocation:

```bash
gh api graphql -f query="$QUERY" -F owner=<owner> -F name=<repo>
```

Add `-F after=<cursor>` to paginate. Use `-F` (not `-f`) for the cursor so a `null` first page is handled correctly.

### Notes on the fields

- **`state` on edge nodes is essential.** Only open issues are fetched, but a blocker may well be closed — a closed blocker returned by `blockedBy` is precisely how "blocked" is distinguished from "was blocked".
- **`repository { nameWithOwner }` on every edge node** is what makes cross-repository edges resolvable without a second lookup, and what lets the renderer mark organization boundaries.
- **`issueType` is null** on repositories without issue types enabled. Treat it as cosmetic — never branch behaviour on it.
- **Dependencies are reported from both ends.** If A blocks B, A lists B under `blocking` and B lists A under `blockedBy`. Deduplicate on the ordered pair.

## Drilling into a single issue

When the user asks about one issue after seeing the map:

```graphql
query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      number
      title
      state
      blockedBy(first: 50) { nodes { number title state repository { nameWithOwner } } }
      blocking(first: 50)  { nodes { number title state repository { nameWithOwner } } }
    }
  }
}
```

## The cross-organization limitation

GitHub issue dependencies span repositories but **not organizations**. Selecting an issue outside the current organization returns `FORBIDDEN: Unauthorized` when the relationship is submitted. Sub-issues hit the same practical ceiling.

This is why the skill accepts a declared edge list at all. It is a workaround for a platform limit, not a general-purpose way to describe dependencies — anything GitHub can express should be recorded on the issue, where it stays correct without anyone maintaining it.

Sources:

- [Creating issue dependencies — GitHub Docs](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies)
- [Dependencies on issues — GitHub Changelog](https://github.blog/changelog/2025-08-21-dependencies-on-issues/)
- [Adding sub-issues — GitHub Docs](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)

## Rate limiting

GraphQL costs are scored per call, and one call per repository with a page of 100 issues is inexpensive. A project large enough to paginate several times per repository should be queried with a smaller `first:` rather than more calls — the cost scales with nodes returned, not with pages requested.
