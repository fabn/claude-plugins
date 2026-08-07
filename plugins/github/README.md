# GitHub Plugin

GitHub workflows: feature development with branch/commit/PR flow, addressing PR review comments, issue and project board management (Epics, sub-issues, triage), cross-repository roadmap and dependency mapping, release management with Release Drafter (setup, upgrade, and publishing), actionlint CI for workflow linting, and interactive setup for GitHub MCP server and gh CLI.

## Skills

| Skill | Description |
|-------|-------------|
| `/github:setup` | Interactive setup wizard — verifies gh CLI, authentication, MCP token, connectivity, permissions config, project defaults, and optional project board (8 steps) |
| `/github:release` | Publish draft releases created by Release Drafter with CI verification |
| `/github:release-drafter` | Set up or upgrade release-drafter — versioning strategy, autolabeler, post-release workflow |
| `/github:feature` | Full feature workflow — create branch, stage files, commit, push, open a PR, and optionally move linked issues to "In review" |
| `/github:address-review` | Address PR review comments — read, categorize, implement code changes, reply to threads, push, and optionally resolve threads and update the PR description |
| `/github:actionlint` | Set up actionlint CI — lint GitHub Actions workflow files on push and PR using reviewdog/action-actionlint |
| `/github:pm` | Issue and project board management — create issues (Epic/Feature/Task/Bug), expand Epics into sub-issues, triage missing fields, and list board items |
| `/github:roadmap` | Cross-repository dependency map — what is blocked, by what, and what is actionable now, generated on demand from GitHub's own issue graph |

## Prerequisites

### `gh` CLI

The [GitHub CLI](https://cli.github.com/) must be installed and authenticated:

```bash
brew install gh
gh auth login --web
```

The `gh project` subcommand is part of the standard `gh` CLI — no extra install needed.

### `GITHUB_MCP_TOKEN`

The plugin's MCP server requires a GitHub token. Generate one following the [GitHub MCP Server documentation](https://github.com/github/github-mcp-server?tab=readme-ov-file#default-toolset).

Make the token available to Claude's environment using any of these methods:

- **Shell environment**: `export GITHUB_MCP_TOKEN=your-token` in `.bashrc`/`.zshrc`
- **Global Claude settings**: Add to `~/.claude/settings.local.json`:
  ```json
  {
    "env": {
      "GITHUB_MCP_TOKEN": "your-token-here"
    }
  }
  ```
- **Project Claude settings**: Add to `.claude/settings.local.json` in the project root

> **Note:** OAuth flow support may remove the token requirement in the future.

### `jq` (for `/github:roadmap`)

The roadmap skill's `fetch-graph.sh` normalizes the GraphQL response with `jq`.

```bash
jq --version   # any 1.6+
```

Install with `brew install jq` (macOS) or your distribution's package manager. The script exits with a clear message if it is missing.

### `uvx` (for git MCP server)

The `git` MCP server requires `uvx` (part of [uv](https://github.com/astral-sh/uv)):

```bash
brew install uv
```

#### Why the `git` server pins `mcp<2`

`mcp-server-git` (latest release `2026.7.10`) is built against the low-level decorator API of the MCP Python SDK — `@server.list_tools()`. **SDK 2.0.0 removed it**, and an unpinned `uvx mcp-server-git` resolves to that SDK, so the server dies at startup with:

```
AttributeError: 'Server' object has no attribute 'list_tools'
```

Claude Code reports this as a connection failure (`-32000`) with no hint of the cause, because the process is gone before the handshake. `--with "mcp<2"` holds the SDK on the 1.x line, where the server initializes normally (verified: it reports `mcp-git 1.29.0`).

Tracked upstream as [modelcontextprotocol/servers#4580](https://github.com/modelcontextprotocol/servers/issues/4580) — the root cause there is the unbounded `mcp>=1.0.0` constraint in `mcp-server-git`'s own dependencies. **Remove the pin when that issue closes**, either because upstream adds the constraint or because `server.py` migrates to the SDK 2.x API. Four skills call `mcp__git__*` and the recommended permissions block denies the Bash equivalents, so this server failing silently is worse than it looks.

## Getting Started

Run the setup wizard after installing:

```
/github:setup
```

This walks through 8 steps: verifies all prerequisites, configures project permissions, writes project defaults to CLAUDE.md, and optionally links a GitHub project board. Add `enableAllProjectMcpServers: true` to your project's `.claude/settings.json` so all three MCP servers start automatically.

To manage issues and the project board:

```
/github:pm
```

After opening a PR with `/github:feature` and receiving review comments:

```
/github:address-review
```

To set up or upgrade release-drafter on your repository:

```
/github:release-drafter
```

To add actionlint CI for linting GitHub Actions workflows:

```
/github:actionlint
```

## MCP Servers

The plugin bundles two MCP servers:

| Server | Type | Purpose |
|--------|------|---------|
| `github` | HTTP | GitHub API access — repositories, releases, issues, PRs, actions, projects, labels |
| `git` | stdio (`uvx`) | Local git operations — branch, status, diff, log, add, commit, create branch, checkout |

The `github` server connects to `https://api.githubcopilot.com/mcp/` with configurable [toolsets](https://github.com/github/github-mcp-server?tab=readme-ov-file#default-toolset) via the `X-MCP-Toolsets` header. Default toolsets: `default`, `projects`, `actions`, `labels`.

> 0.7.0 removed a third bundled server, `filesystem` (stdio, `npx`). No skill ever called its tools — it appeared only as an allowlist entry — and it duplicated Claude Code's native Read/Write/Edit while adding a Node.js runtime dependency. The `git` server stays: four skills call `mcp__git__*` directly, and the permissions block this plugin recommends *denies* Bash `git add` / `git commit` precisely so that local git goes through it consistently.

## Skill Details

### `/github:setup`

Interactive setup wizard:
1. Checks `gh` CLI installation
2. Verifies `gh` authentication status
3. Checks `GITHUB_MCP_TOKEN` availability via MCP tool discovery
4. Tests MCP connectivity with a lightweight API call
5. Configures project permissions (three-tier allow/ask/deny model)
6. Writes project defaults to CLAUDE.md (main branch, branch prefix)
7. Optionally configures a GitHub project board (`project.number`, `project.owner`)
8. Reports status summary with next steps

### `/github:release`

Publish draft releases created by Release Drafter:
1. Detects repository context via `gh repo view`
2. Finds draft releases via GitHub MCP `list_releases`
3. Checks CI status on main — waits for in-progress runs, stops on failures
4. Confirms with user before publishing (mandatory)
5. Publishes with `gh release edit --draft=false`
6. Reports summary with tag, URL, and changelog

### `/github:release-drafter`

Set up or upgrade release-drafter on any repository:
1. Detects existing release-drafter setup (none, v6, or v7)
2. Fresh setup: asks versioning strategy (semver or CalVer), tag prefix, autolabeler opt-in, post-release actions
3. Shows a summary of files to create and asks for confirmation
4. Generates config and workflow files from reference templates
5. Commits all generated files
6. Upgrade path: detects v6, migrates to v7 (token handling, permissions), preserves existing config

### `/github:actionlint`

Set up actionlint CI on any repository:
1. Detects existing actionlint workflow (none or already configured)
2. Asks target branch and fail level (error or warning)
3. Shows summary and confirms before writing
4. Generates `.github/workflows/actionlint.yml` using reviewdog/action-actionlint with auto-detecting reporter
5. Commits the workflow file

### `/github:feature`

Full feature development workflow:
1. Reads project config via `scripts/read-config.sh` (`mainBranch`, `branchPrefix`, `project`)
2. Detects current branch and working tree state via Git MCP
3. Creates or checks out a feature branch (suggests name from description)
4. Reviews unstaged and staged changes, asks which files to include
5. Stages selected files and proposes a plain-English commit message
6. Pushes branch to remote via `git push -u origin <branch>`
7. Optionally links related GitHub issues
8. Creates a pull request with a concise title and body
9. If a project board is configured and issues were linked, offers to move them to "In review"
10. Reports branch, commit, PR URL, linked issues, and board updates

### `/github:address-review`

Address open review comments on a pull request:
1. Detects the PR for the current branch (or asks for a PR number)
2. Reads all unresolved review threads and categorizes each as Actionable, Question, Suggestion, or Inaccurate
3. Presents a table of comments with proposed actions and asks for confirmation before proceeding
4. Implements code changes (Edit/MultiEdit), stages, and commits with a plain-English message; skips commit if no code changes are needed
5. Pushes the commit, posts a reply to every comment thread, and optionally resolves threads via GraphQL and updates the PR description

### `/github:pm`

Issue and project board management — four operations:

**Create Issue:**
1. Reads project config (board optional)
2. Detects repo via `gh repo view`
3. Chooses issue type: Epic / Feature / Task / Bug
4. Searches for duplicates before proceeding
5. Collects Title, Body, Priority (required), Size (required), and optional fields
6. Confirms before creating
7. Creates issue via GitHub MCP
8. Adds to project board and sets Priority / Size (if board configured)
9. Links to parent issue as sub-issue (if provided)
10. Reports issue URL and board status

**Expand Epic:**
1. Identifies the Epic by number or search
2. Reads Epic title, body, and existing sub-issues
3. Suggests a task breakdown; user confirms, adds, or removes
4. Previews all sub-issues before creating anything
5. Creates each sub-issue, links it to the Epic, adds it to the board

**Triage / Fix:**
1. Fetches open issues
2. Checks each for missing Priority, Size, parent link, or board membership
3. Reports a table of findings
4. Applies fixes after user confirmation

**List / Explore Board:**
1. Fetches project items (or falls back to `list_issues` if no board configured)
2. Filters by Status, Priority, assignee, or type (optional)
3. Presents a table with #, Title, Type, Status, Priority, Size
4. Offers follow-up actions

### `/github:roadmap`

Cross-repository dependency map, regenerated on every run:

1. Reads `roadmap.repos` from project config (falls back to the current repository, and says so)
2. Fetches each repository's issue graph via the bundled `scripts/fetch-graph.sh` — hierarchy, `blockedBy` and `blocking`, paginated and deduplicated
3. Merges any declared cross-organization edges, which GitHub's dependencies cannot express
4. Reports what the data cannot tell you: isolated issues, dangling config entries, repositories that failed to fetch
5. Renders the tree — `✅` done, `▶` actionable now, `⏸` blocked (naming the blocker), `⚠` blocked across an organization boundary
6. Closes with an "Actionable now" list, ordered by how much each item unblocks

No roadmap file is written. A checked-in roadmap is a copy of state GitHub already holds, and it starts lying the first time an issue is closed without it being updated.

## Project Config

Per-project defaults live in `.claude/github.json`:

```json
{
  "mainBranch": "main",
  "branchPrefix": "feature",
  "project": { "number": 2, "owner": "acme" },
  "roadmap": {
    "repos": ["acme-corp/platform", "acme-corp/app", "acme-labs/shared-modules"],
    "externalEdges": [
      { "blocked": "acme-corp/app#310", "by": "acme-labs/shared-modules#15" }
    ]
  }
}
```

| Key | Written by | Read by |
|-----|-----------|---------|
| `mainBranch` | `github:setup` Step 6 | `github:feature`, `github:address-review` |
| `branchPrefix` | `github:setup` Step 6 | `github:feature` |
| `project.number` / `project.owner` | `github:setup` Step 7 | `github:pm`, `github:feature` Step 8a |
| `roadmap.repos` | manually | `github:roadmap` |
| `roadmap.externalEdges` | manually | `github:roadmap` |

Every key is optional. Omitting one is what selects its default, which is why `github:setup` does not write defaults the user did not change.

Field IDs (Priority, Size, Status) are discovered at runtime via `list_project_fields` — not cached — to avoid stale IDs if the project is recreated.

### Resolution

Skills never parse config themselves. They run:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh" [project-dir]
```

which returns `{ "source", "path", "config" }` with `config` normalized to the shape above regardless of where it was found.

### Migrating from the CLAUDE.md block

Before 0.7.0 the config lived in `CLAUDE.md` as `<!-- github_key: value -->` HTML comments. That format could not hold structured values, and it grew a file that is loaded into context every session with data no model needs to read.

The old location is still read, and reported as `source: "claude-md"`. Skills that see it stop and offer:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/migrate-config.sh"          # --dry-run to preview
```

which writes `.claude/github.json`, strips the block from `CLAUDE.md`, and leaves the surrounding prose intact.

**The fallback is removed in 0.8.0.** It exists because several skills degrade quietly without config rather than failing — `github:pm` skips board steps without erroring — so a hard cutover would have looked exactly like a silent bug.
