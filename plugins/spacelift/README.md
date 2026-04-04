# Spacelift Plugin

Spacelift CI/CD workflows for Terraform infrastructure management.

## Skills

| Skill | Description |
|-------|-------------|
| `/spacelift:status` | List stacks, check status, view dependencies and resources |
| `/spacelift:logs` | Read run logs, inspect runs, view resource changes |
| `/spacelift:debug` | Debug failed runs with structured error analysis |
| `/spacelift:preview` | Run local previews to test changes before pushing |
| `/spacelift:manage` | Confirm, discard, trigger, retry, and cancel runs |

## Prerequisites

- `spacectl` CLI installed and available in PATH ([installation guide](https://github.com/spacelift-io/spacectl#installation))
- Environment variables configured:

| Variable | Description |
|----------|-------------|
| `SPACELIFT_API_KEY_ENDPOINT` | Spacelift instance URL (e.g. `https://mycompany.app.spacelift.io`) |
| `SPACELIFT_API_GITHUB_TOKEN` | GitHub token for Spacelift API authentication |

## Getting Started

```bash
# Install the plugin
/plugin install spacelift@fabn-claude-plugins

# Then just ask
> check spacelift status for my stack
> show me the logs for the last run
> why did spacelift fail on this PR?
> run a local preview for stack X
> confirm the pending run on my-stack
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

When MCP tools are unavailable, skills fall back to `spacectl` CLI commands.

## Skill Details

### `/spacelift:status`

Lists stacks, shows details, checks stack status after push, and views dependencies. Can also browse resources, contexts, and spaces.

### `/spacelift:logs`

Reads run logs for any run (tracked or proposed). Can find runs by stack, branch, or PR. Shows resource changes and supports pagination for large logs.

### `/spacelift:debug`

Structured debugging workflow for failed runs: identifies the failure, determines which phase failed, fetches logs, parses Terraform errors, and suggests fixes.

### `/spacelift:preview`

Runs local previews: packages local files, uploads to Spacelift, and executes a plan. Supports targeting specific resources and custom environment variables.

### `/spacelift:manage`

Run lifecycle management: confirm pending runs, discard unwanted runs, trigger new deployments, retry failures, and cancel queued runs. Always confirms with user before acting.

## Environment Setup

Add to your shell profile or `.env`:

```bash
export SPACELIFT_API_KEY_ENDPOINT=https://mycompany.app.spacelift.io
export SPACELIFT_API_GITHUB_TOKEN=ghp_your_token_here
```

Or configure in Claude Code settings (`~/.claude/settings.local.json`):

```json
{
  "env": {
    "SPACELIFT_API_KEY_ENDPOINT": "https://mycompany.app.spacelift.io",
    "SPACELIFT_API_GITHUB_TOKEN": "ghp_your_token_here"
  }
}
```
