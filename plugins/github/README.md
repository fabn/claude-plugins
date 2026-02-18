# GitHub Plugin

GitHub workflows: release management with Release Drafter, CI verification, and interactive setup for GitHub MCP server and gh CLI.

## Skills

| Skill | Description |
|-------|-------------|
| `/github:setup` | Interactive setup wizard — verifies gh CLI, authentication, MCP token, and connectivity |
| `/github:release` | Publish draft releases created by Release Drafter with CI verification |

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

## Getting Started

Run the setup wizard after installing:

```
/github:setup
```

This verifies all prerequisites and reports what needs to be fixed.

## MCP Servers

The plugin bundles one MCP server:

| Server | Type | Purpose |
|--------|------|---------|
| `github` | HTTP | GitHub API access — repositories, releases, issues, PRs, actions, projects, labels |

The server connects to `https://api.githubcopilot.com/mcp/` with configurable [toolsets](https://github.com/github/github-mcp-server?tab=readme-ov-file#default-toolset) via the `X-MCP-Toolsets` header. Default toolsets: `default`, `projects`, `actions`, `labels`.

## Skill Details

### `/github:setup`

Interactive setup wizard:
1. Checks `gh` CLI installation
2. Verifies `gh` authentication status
3. Checks `GITHUB_MCP_TOKEN` availability via MCP tool discovery
4. Tests MCP connectivity with a lightweight API call
5. Reports status summary with next steps

### `/github:release`

Publish draft releases created by Release Drafter:
1. Detects repository context via `gh repo view`
2. Finds draft releases via GitHub MCP `list_releases`
3. Checks CI status on main — waits for in-progress runs, stops on failures
4. Confirms with user before publishing (mandatory)
5. Publishes with `gh release edit --draft=false`
6. Reports summary with tag, URL, and changelog
