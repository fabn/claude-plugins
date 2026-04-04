# Spacelift Plugin

Spacelift CI/CD workflows for Terraform infrastructure management.

## Skills

| Skill | Description |
|-------|-------------|
| `/spacelift:spacelift` | Inspect stacks, read run logs, debug failures, run local previews, manage runs |

## Prerequisites

- `spacectl` CLI installed (via `mise install spacectl` or [direct download](https://github.com/spacelift-io/spacectl))
- Environment variables configured:

| Variable | Description |
|----------|-------------|
| `SPACELIFT_API_KEY_ENDPOINT` | Spacelift instance URL (e.g. `https://fabn-business.app.spacelift.io`) |
| `SPACELIFT_API_GITHUB_TOKEN` | GitHub token for Spacelift API authentication |

## Getting Started

```bash
# Install the plugin
/plugin install spacelift@fabn-claude-plugins

# Then just ask
> check spacelift status for my stack
> why did spacelift fail on this PR?
> run a local preview for stack X
> list all stacks
> show me the logs for the last run
```

## MCP Server

This plugin bundles the Spacelift MCP server (`spacelift.spacectl-mcp`) which provides direct tool access to the Spacelift API.

| Server | Command | Description |
|--------|---------|-------------|
| `spacelift.spacectl-mcp` | `spacectl mcp server` | Spacelift API via MCP protocol |

### MCP Tools Available

The MCP server exposes 38 tools covering:

- **Stacks**: list, search, and inspect stacks
- **Runs**: list tracked/proposed runs, get run details, logs, and changes
- **Run management**: trigger, confirm, discard runs
- **Local preview**: run local previews with optional targets and env vars
- **Resources**: list managed infrastructure resources
- **Contexts**: list, search, and inspect contexts
- **Policies**: list policies, get samples and evaluations
- **Modules**: list, search, and inspect private registry modules
- **GraphQL**: introspect schema, search fields, get type details
- **Other**: blueprints, spaces, worker pools, API keys

When MCP tools are unavailable, the skill falls back to `spacectl` CLI commands.

## Environment Setup

Add to your shell profile or `.env`:

```bash
export SPACELIFT_API_KEY_ENDPOINT=https://your-account.app.spacelift.io
export SPACELIFT_API_GITHUB_TOKEN=ghp_your_token_here
```

Or configure in Claude Code settings (`~/.claude/settings.local.json`):

```json
{
  "env": {
    "SPACELIFT_API_KEY_ENDPOINT": "https://your-account.app.spacelift.io",
    "SPACELIFT_API_GITHUB_TOKEN": "ghp_your_token_here"
  }
}
```
