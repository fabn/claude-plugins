---
name: github:roadmap
description: |
  This skill should be used when the user wants to see how work is sequenced
  across several GitHub repositories: what is blocked by what, what is ready to
  start now, and where an Epic stands. Renders a dependency tree on demand from
  GitHub's own issue hierarchy and dependency graph — it does not maintain a
  roadmap document.
  Activates on: "roadmap", "what is blocked", "what can I start", "what is next",
  "dependency tree", "issue dependencies", "blocked by", "unblocked work",
  "where are we", "epic status", "cross-repo dependencies", "show the plan",
  "roadmap", "cosa è bloccato", "cosa posso iniziare", "cosa viene dopo",
  "albero delle dipendenze", "dipendenze issue", "a che punto siamo",
  "stato epic", "dipendenze tra repo", "mostrami il piano".
---

# GitHub Roadmap Skill

Render the current dependency map across one or more repositories: issue hierarchy (Epics and sub-issues), blocking relationships, and what is actionable right now.

**This skill deliberately does not write a roadmap file.** A checked-in roadmap is a copy of state that already lives in GitHub, and it starts lying the first time an issue is closed without it being updated. The graph is regenerated on every invocation instead, so it cannot go stale — if it is wrong, GitHub is wrong, and that is where the fix belongs.

For the GraphQL queries and the reasoning behind them, see [reference/graphql-queries.md](reference/graphql-queries.md).

## What GitHub already knows, and the one thing it does not

Almost the entire map is data the user maintains simply by opening and closing issues:

| Relationship | Source | Crosses repositories? |
|---|---|---|
| Parent / sub-issue | `parent`, `subIssues` | Yes |
| Blocked by / blocking | `blockedBy`, `blocking` | Yes, **within limits** |
| Open / closed state | `state` | — |

The exception is **cross-organization** links. GitHub's issue dependencies do not span organizations — selecting an issue outside the current organization fails with a `FORBIDDEN` GraphQL error ([docs](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/creating-issue-dependencies), [changelog](https://github.blog/changelog/2025-08-21-dependencies-on-issues/)). Sub-issues have the same practical ceiling.

So a project spanning two organizations has edges that exist only in prose. Those — and only those — are declared in config. Everything else is derived.

**Do not ask the user to declare edges GitHub can already express.** If a dependency is between two repositories in the same organization, the right answer is to record it on the issue, not in a config file.

## Config

Read from the project's `CLAUDE.md` `<!-- github-plugin-config -->` block, the same block `github:pm` and `github:feature` use:

```markdown
<!-- github-plugin-config -->
<!-- github_roadmap_repos: acme-corp/platform, acme-corp/app, acme-labs/shared-modules -->
<!-- github_roadmap_external_edges: acme-corp/app#310 <- acme-labs/shared-modules#15; acme-corp/app#306 <- acme-corp/platform#404 -->
```

| Key | Meaning |
|---|---|
| `github_roadmap_repos` | Comma-separated `owner/repo` list to include. If absent, use the current repository only. |
| `github_roadmap_external_edges` | Semicolon-separated `<blocked> <- <blocker>` pairs, each a fully qualified `owner/repo#number`. Optional. Only for links GitHub cannot express. |

Keep `github_roadmap_external_edges` short. If it grows past a handful of entries, that is a signal the repositories belong in one organization, not that the list needs a better format.

## Tools Used

- **Bash**: `gh api graphql` — the only source that returns dependency *edges*. The GitHub MCP returns `blocked_by` / `blocking` as **counts only**, which is enough to verify a result but not to build a graph.
- **Bash**: `gh repo view --json owner,name` to detect the current repository when config is absent.
- **Read**: the project's `CLAUDE.md` for the config block.
- **GitHub MCP** (optional): `issue_read` when the user drills into a single issue after seeing the map.

## Workflow

### Step 1: Resolve Configuration

Read `CLAUDE.md` and parse the `<!-- github-plugin-config -->` block.

- **`github_roadmap_repos` present**: use it.
- **Absent**: run `gh repo view --json owner,name` and use the current repository alone. Say so explicitly in the output — a single-repo map from a multi-repo project looks complete and is not. Offer to add the key.
- **Not in a git repository and no config**: stop, and ask which repositories to map.

Parse `github_roadmap_external_edges` if present. Ignore malformed entries rather than failing, but list them in the output so a typo is visible instead of silently dropping an edge.

### Step 2: Fetch Each Repository's Graph

One GraphQL call per repository — see [reference/graphql-queries.md](reference/graphql-queries.md) for the query.

Request open issues with `number`, `title`, `state`, `issueType`, `parent`, `subIssues`, `blockedBy` and `blocking`. Every edge node carries `repository { nameWithOwner }`, so cross-repository edges are identified without a second lookup.

Paginate when a repository returns a full page. Never silently truncate: if pagination is stopped early for any reason, say how many issues were skipped.

Closed issues are not fetched, but they appear as edge nodes (a closed blocker is still returned by `blockedBy`) — which is exactly what is needed to tell "blocked" from "was blocked".

### Step 3: Merge and Resolve

Build one graph across all repositories:

1. Add every hierarchy edge (`parent` / `subIssues`).
2. Add every dependency edge (`blockedBy` / `blocking`), deduplicating — a single relationship is reported from both ends.
3. Add the configured external edges, marking them as declared rather than derived.
4. Compute, for each open issue: **blocked** if any blocker is open, **unblocked** otherwise.

### Step 4: Report What the Data Cannot Tell You

Before rendering, surface the gaps. This step is what separates a map that is trusted from one that is merely drawn:

- **Isolated issues** — open issues with no parent, no sub-issues and no dependency edges. They are invisible in a tree and are usually either genuinely standalone or a missing link nobody recorded. List them separately rather than omitting them.
- **Dangling external edges** — a configured edge naming an issue that does not exist or is already closed. A closed one is a config entry to delete.
- **Repositories that failed to fetch** — never render a partial map as if it were whole.

### Step 5: Render the Map

Group by top-level item (Epic, or any issue with no open parent). Within each group, order by dependency depth. Collapse completed work to a single line — the interesting part is the frontier, not the history.

Mark each node:

- `✅` closed
- `▶` open and unblocked — actionable now
- `⏸` open and blocked, naming the blocker
- `⚠` blocked across an organization boundary via a declared edge

Qualify a cross-repository reference with its `owner/repo` and leave same-repository ones bare, so the eye catches the boundary crossings.

Close with a short **"Actionable now"** list: every `▶` node, ordered by how much it unblocks. That list is the reason to run this skill.

### Step 6: Offer Follow-ups

Depending on what the map shows:

- An isolated issue that clearly belongs under an Epic → offer to link it (`/github:pm`).
- A dependency described in an issue body but absent from the graph → offer to record it on the issue, so the next run derives it instead of needing config.
- A closed external edge → offer to remove the config entry.

## Error Handling

| Situation | Action |
|-----------|--------|
| `gh` CLI not installed or not authenticated | Stop, tell user to run `/github:setup` |
| No config and not in a git repository | Ask which repositories to map |
| Config lists a repository the token cannot read | Report it by name, render the rest, do **not** fail the whole run |
| GraphQL returns `FORBIDDEN` on a dependency field | The repository is on a plan or preview that lacks it — render hierarchy only and say dependencies were unavailable |
| A repository returns more issues than one page | Paginate; if stopped early, report how many were skipped |
| External edge references a non-existent issue | List it as dangling config, keep going |
| External edge references a closed issue | Render it satisfied, suggest deleting the entry |
| No open issues anywhere | Say so plainly — an empty map and a failed fetch must not look alike |

## Reference Files

- [reference/graphql-queries.md](reference/graphql-queries.md) — the queries, pagination, and why the GitHub MCP cannot replace them

## Related Skills

- **`/github:pm`** — create issues, expand Epics into sub-issues, link parents, triage missing fields
- **`/github:setup`** — verify `gh` CLI, authentication and the MCP token
