# GitHub Plugin

GitHub workflows: feature development with branch/commit/PR flow, release management with Release Drafter, CI verification, and interactive setup for GitHub MCP server and gh CLI.

## Skills

| Skill | Description |
|-------|-------------|
| `/github:setup` | Interactive setup wizard — verifies gh CLI, authentication, MCP token, connectivity, permissions config, and project defaults (7 steps) |
| `/github:release` | Publish draft releases created by Release Drafter with CI verification |
| `/github:feature` | Full feature workflow — create branch, stage files, commit, push, and open a PR |

## Prerequisites

### `gh` CLI

The [GitHub CLI](https://cli.github.com/) must be installed and authenticated:

```bash
brew install gh
gh auth login --web
```

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

This walks through 7 steps: verifies all prerequisites, configures project permissions, and writes project defaults to CLAUDE.md. Add `enableAllProjectMcpServers: true` to your project's `.claude/settings.json` so all three MCP servers start automatically.

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
7. Reports status summary with next steps

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
1. Reads project config from CLAUDE.md (`github_main_branch`, `github_branch_prefix`)
2. Detects current branch and working tree state via Git MCP
3. Creates or checks out a feature branch (suggests name from description)
4. Reviews unstaged and staged changes, asks which files to include
5. Stages selected files and proposes a plain-English commit message
6. Pushes branch to remote via `git push -u origin <branch>`
7. Optionally links related GitHub issues
8. Creates a pull request with a concise title and body
9. Reports branch, commit, PR URL, and linked issues

## Project Config

Per-project defaults are stored in the project's `CLAUDE.md` as HTML comments (invisible when rendered):

```markdown
<!-- github-plugin-config -->
<!-- github_main_branch: main -->
<!-- github_branch_prefix: feature -->
```

Written by `/github:setup` (Step 6), read by `/github:feature` (Step 1).
