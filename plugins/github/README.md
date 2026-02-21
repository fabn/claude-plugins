# GitHub Plugin

GitHub workflows: feature development with branch/commit/PR flow, addressing PR review comments, issue and project board management (Epics, sub-issues, triage), release management with Release Drafter, CI verification, and interactive setup for GitHub MCP server and gh CLI.

## Skills

| Skill | Description |
|-------|-------------|
| `/github:setup` | Interactive setup wizard — verifies gh CLI, authentication, MCP token, connectivity, permissions config, project defaults, and optional project board (8 steps) |
| `/github:release` | Publish draft releases created by Release Drafter with CI verification |
| `/github:feature` | Full feature workflow — create branch, stage files, commit, push, open a PR, and optionally move linked issues to "In review" |
| `/github:address-review` | Address PR review comments — read, categorize, implement code changes, reply to threads, push, and optionally resolve threads and update the PR description |
| `/github:pm` | Issue and project board management — create issues (Epic/Feature/Task/Bug), expand Epics into sub-issues, triage missing fields, and list board items |

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

### `uvx` (for git MCP server)

The `git` MCP server requires `uvx` (part of [uv](https://github.com/astral-sh/uv)):

```bash
brew install uv
```

### `npx` (for filesystem MCP server)

The `filesystem` MCP server requires Node.js and npm. Install via [nodejs.org](https://nodejs.org/) or:

```bash
brew install node
```

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

## MCP Servers

The plugin bundles three MCP servers:

| Server | Type | Purpose |
|--------|------|---------|
| `github` | HTTP | GitHub API access — repositories, releases, issues, PRs, actions, projects, labels |
| `git` | stdio (`uvx`) | Local git operations — branch, status, diff, log, add, commit, create branch, checkout |
| `filesystem` | stdio (`npx`) | Local file reads — used to read CLAUDE.md for project config |

The `github` server connects to `https://api.githubcopilot.com/mcp/` with configurable [toolsets](https://github.com/github/github-mcp-server?tab=readme-ov-file#default-toolset) via the `X-MCP-Toolsets` header. Default toolsets: `default`, `projects`, `actions`, `labels`.

## Skill Details

### `/github:setup`

Interactive setup wizard:
1. Checks `gh` CLI installation
2. Verifies `gh` authentication status
3. Checks `GITHUB_MCP_TOKEN` availability via MCP tool discovery
4. Tests MCP connectivity with a lightweight API call
5. Configures project permissions (three-tier allow/ask/deny model)
6. Writes project defaults to CLAUDE.md (main branch, branch prefix)
7. Optionally configures a GitHub project board (`github_project_number`, `github_project_owner`)
8. Reports status summary with next steps

### `/github:release`

Publish draft releases created by Release Drafter:
1. Detects repository context via `gh repo view`
2. Finds draft releases via GitHub MCP `list_releases`
3. Checks CI status on main — waits for in-progress runs, stops on failures
4. Confirms with user before publishing (mandatory)
5. Publishes with `gh release edit --draft=false`
6. Reports summary with tag, URL, and changelog

### `/github:feature`

Full feature development workflow:
1. Reads project config from CLAUDE.md (`github_main_branch`, `github_branch_prefix`, `github_project_number`)
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

## Project Config

Per-project defaults are stored in the project's `CLAUDE.md` as HTML comments (invisible when rendered):

```markdown
<!-- github-plugin-config -->
<!-- github_main_branch: main -->
<!-- github_branch_prefix: feature -->
<!-- github_project_number: 2 -->
<!-- github_project_owner: fabn -->
```

| Key | Written by | Read by |
|-----|-----------|---------|
| `github_main_branch` | `github:setup` Step 6 | `github:feature` Step 1 |
| `github_branch_prefix` | `github:setup` Step 6 | `github:feature` Step 1 |
| `github_project_number` | `github:setup` Step 7 | `github:pm`, `github:feature` Step 8a |
| `github_project_owner` | `github:setup` Step 7 | `github:pm`, `github:feature` Step 8a |

Field IDs (Priority, Size, Status) are discovered at runtime via `list_project_fields` — not cached — to avoid stale IDs if the project is recreated.
