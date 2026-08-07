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

Fetching is done by a bundled script, not by hand-written queries at runtime — see [reference/graph-data.md](reference/graph-data.md) for its contract and the reasoning behind it.

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

Resolved by the shared script, never by parsing files inline:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh"
```

It returns `{ "source", "path", "config" }`. **Act on `source` before using `config`:**

| `source` | Meaning | What to do |
|---|---|---|
| `json` | `.claude/github.json` — the current location | Nothing, proceed |
| `claude-md` | the deprecated `<!-- github-plugin-config -->` block | Stop and offer migration (below) |
| `none` | no configuration anywhere | Proceed with this skill's defaults |

The `config` object is normalized to the same shape either way:

```json
{
  "mainBranch": "main",
  "branchPrefix": "feature",
  "project": { "number": 2, "owner": "acme" },
  "roadmap": { "repos": ["acme/platform"], "externalEdges": [] }
}
```

### On `source: "claude-md"`

Tell the user their config is in the deprecated location and offer to move it:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-config.sh"          # add --dry-run to preview
```

It writes `.claude/github.json`, strips the block from `CLAUDE.md` and leaves the surrounding prose intact. If they decline, continue with the values returned — the fallback is removed in 0.8.0, and saying so now is the point of the prompt.

**Do not skip the prompt.** Several skills here degrade quietly without config rather than failing, so once the fallback is gone a silent fallback today and a silent failure tomorrow look identical to the user.

This skill reads `config.roadmap`:

```json
{
  "roadmap": {
    "repos": ["acme-corp/platform", "acme-corp/app", "acme-labs/shared-modules"],
    "externalEdges": [
      { "blocked": "acme-corp/app#310", "by": "acme-labs/shared-modules#15" }
    ]
  }
}
```

| Key | Meaning |
|---|---|
| `repos` | `owner/repo` list to include. If absent, use the current repository only. |
| `externalEdges` | `{blocked, by}` pairs, each side a fully qualified `owner/repo#number`. Optional. Only for links GitHub cannot express. |

Keep `externalEdges` short. If it grows past a handful of entries, that is a signal the repositories belong in one organization, not that the list needs a better format.

## Tools Used

- **Bash**: `${CLAUDE_PLUGIN_ROOT}/skills/roadmap/scripts/fetch-graph.sh` — fetches and normalizes the graph. Requires `gh` (authenticated) and `jq`.
- **Bash**: `gh repo view --json owner,name` to detect the current repository when config is absent.
- **Bash**: `${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh` for the project config.
- **GitHub MCP** (optional): `issue_read` when the user drills into a single issue after seeing the map.

## Workflow

### Step 1: Resolve Configuration

Run `read-config.sh` and act on `source` before anything else (see [Config](#config)).

- **`config.roadmap.repos` present**: use it.
- **Absent**: run `gh repo view --json owner,name` and use the current repository alone. Say so explicitly in the output — a single-repo map from a multi-repo project looks complete and is not. Offer to add the key.
- **Not in a git repository and no config**: stop, and ask which repositories to map.

Take `config.roadmap.externalEdges` if present. Ignore malformed entries rather than failing, but list them in the output so a typo is visible instead of silently dropping an edge.

### Step 2: Fetch the Graph

Run the bundled script with every configured repository as an argument:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/roadmap/scripts/fetch-graph.sh" owner/repo-a owner/repo-b
```

It emits one JSON object on stdout: `issues`, `edges`, `counts`, `failed`. Pagination, the both-ends deduplication of dependencies, and per-repository error isolation all happen inside it.

**Do not hand-write GraphQL for this.** The query has several details that are easy to get subtly wrong and that fail silently when they are — the cursor variable must be named `$endCursor` for `--paginate` to work, the same relationship is reported from both ends and must be deduplicated, and closed issues must be kept when they appear as edge nodes. A script gets them right identically on every run.

Read `failed` before anything else. Never render a partial map as if it were whole.

Then resolve, in a second pass, every reference the sweep structurally cannot see — each configured external edge, plus any number an issue body leans on:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/roadmap/scripts/fetch-graph.sh" \
  --resolve owner/repo-a#15 owner/repo-b#320
```

This is not optional tidiness, it closes two blind spots:

- **The sweep fetches only OPEN issues.** A declared external edge naming an issue that has since been **closed** has nothing in the data to be checked against, so without this it renders as a live blocker for ever. This has happened.
- **`issues()` excludes pull requests.** Work in flight as a PR is invisible, so an item actively being implemented looks like an item nobody has started.

`resolved[]` gives `kind` (`issue` / `pull_request` / `missing`) and `state` (`OPEN` / `CLOSED` / `MERGED`).

### Step 3: Merge and Resolve

Build one graph across all repositories:

1. Take the hierarchy from each issue's `parent` and `children`.
2. Take the dependency edges from `edges` — already deduplicated by the script.
3. Add the configured external edges, marking them as declared rather than derived — **using the state from `resolved`, never assuming they are open.**
4. Compute, for each open issue: **blocked** if any blocker has `byState = OPEN`, **unblocked** otherwise. A closed blocker is satisfied, not a block.

### Step 4: Report What the Data Cannot Tell You

Before rendering, surface the gaps. This step is what separates a map that is trusted from one that is merely drawn:

- **Isolated issues** — open issues with no parent, no sub-issues and no dependency edges. They are invisible in a tree and are usually either genuinely standalone or a missing link nobody recorded. List them separately rather than omitting them.
- **Dangling external edges** — from `resolved`: `kind: "missing"` is a typo or a deleted issue, `state: "CLOSED"` or `"MERGED"` is a satisfied blocker and a config entry to delete. Say which, and offer to remove it.
- **Work in flight as a pull request** — a `resolved` entry with `kind: "pull_request"` and `state: "OPEN"` means the item is being implemented right now. An issue whose PR is open is not "not started", and rendering it as blocked-and-idle is the most misleading thing this skill can do.
- **Repositories that failed to fetch** — from `failed`. Never render a partial map as if it were whole.
- **Checksum mismatches** — for each entry in `counts`, compare `blockedBy` against the number of edges resolved for that issue. A shortfall means an edge was dropped somewhere, and the tree below is incomplete. Say so; do not quietly render it.

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
| `jq` not installed | The script exits 69 naming it; tell the user to install `jq` |
| An external edge resolves to `CLOSED`/`MERGED` | The blocker is satisfied — render it so, and offer to delete the config entry |
| A referenced number resolves to an open PR | Render the item as in progress, not as blocked |
| No config and not in a git repository | Ask which repositories to map |
| Config lists a repository the token cannot read | It appears in `failed` with its error; report it by name, render the rest |
| GraphQL returns `FORBIDDEN` on a dependency field | The repository is on a plan or preview that lacks it — render hierarchy only and say dependencies were unavailable |
| A repository returns more issues than one page | Handled by the script's `--paginate`; nothing to do |
| External edge references a non-existent issue | List it as dangling config, keep going |
| External edge references a closed issue | Render it satisfied, suggest deleting the entry |
| No open issues anywhere | Say so plainly — an empty map and a failed fetch must not look alike |

## Reference Files

- [reference/graph-data.md](reference/graph-data.md) — the script's output contract, the query it runs, and why the GitHub MCP cannot replace it
- `scripts/fetch-graph.sh` — fetches and normalizes the graph; run it, do not reimplement it

## Related Skills

- **`/github:pm`** — create issues, expand Epics into sub-issues, link parents, triage missing fields
- **`/github:setup`** — verify `gh` CLI, authentication and the MCP token
