# Claude Code Plugin Marketplace

A collection of Claude Code plugins for infrastructure, monitoring, and DevOps workflows.

## Available Plugins

| Plugin | Description | Skills | MCP Servers |
|--------|-------------|--------|-------------|
| **datadog** | Datadog monitoring workflows for Terraform-managed infrastructure | `/datadog:dashboard` - Dashboard creation with metric discovery and HCL generation | `datadog.datadog-mcp` |

## Installation

### Add the marketplace (local)

```
/plugin marketplace add /absolute/path/to/claude-plugins
```

### Add the marketplace (GitHub, future)

```
/plugin marketplace add fabn/claude-plugins
```

### Install a plugin

```
/plugin install datadog@fabn-claude-plugins
```

## Plugin: Datadog

### Prerequisites

The Datadog plugin requires API credentials to connect to the Datadog MCP server. Set the following environment variables in `~/.claude/settings.local.json` or your shell environment:

- `DD_API_KEY` - Datadog API key
- `DD_APP_KEY` - Datadog Application key
- `DD_SITE` - Datadog site (e.g., `datadoghq.eu`, `datadoghq.com`)

Example `~/.claude/settings.local.json`:

```json
{
  "env": {
    "DD_API_KEY": "your-api-key",
    "DD_APP_KEY": "your-app-key",
    "DD_SITE": "datadoghq.eu"
  }
}
```

### Skills

#### `/datadog:dashboard`

Creates production-quality Datadog dashboards as Terraform HCL. The workflow:

1. Gathers requirements (integration, metrics, concerns)
2. Discovers available metrics via MCP, docs, and integrations-core CSV
3. Designs template variables and widget layout
4. Generates formatted Terraform HCL with outputs
5. Validates with `terraform fmt`

## Documentation

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins)
- [Plugin Reference](https://code.claude.com/docs/en/plugins-reference)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
