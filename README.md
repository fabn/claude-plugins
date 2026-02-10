# Claude Code Plugin Marketplace

A collection of Claude Code plugins for infrastructure, monitoring, and DevOps workflows.

## Available Plugins

| Plugin | Description | Skills | MCP Servers |
|--------|-------------|--------|-------------|
| **datadog** | Datadog monitoring workflows for Terraform-managed infrastructure | `/datadog:dashboard` - Dashboard creation with metric discovery and HCL generation | `datadog.datadog-mcp` |
| | | `/datadog:logs` - Log search and analysis with natural language queries | |
| | | `/datadog:setup` - Interactive setup wizard for credentials and project defaults | |

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

### Getting Started

The quickest way to set up the Datadog plugin is to run the setup wizard:

```
/datadog:setup
```

This will verify your API credentials, test MCP connectivity, and optionally configure project-level defaults for log queries.

### Prerequisites

The Datadog plugin requires API credentials to connect to the Datadog MCP server. Set the following environment variables in `~/.claude/settings.local.json` or your shell environment:

- `DD_API_KEY` - Datadog API key
- `DD_APP_KEY` - Datadog Application key (requires scopes: `logs_read_data`, `dashboards_read`, `metrics_read`)
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

### Project Configuration (Optional)

The `datadog:logs` skill can read default settings from your project's `CLAUDE.md` file. These are set automatically by `/datadog:setup` or can be added manually:

```markdown
<!-- datadog-plugin-config -->
<!-- datadog_default_service: my-service-name -->
<!-- datadog_default_filter: env:production -->
```

- `datadog_default_service`: Auto-scopes all log queries to this service
- `datadog_default_filter`: Prepended to all log queries (e.g., `env:production`)

### Skills

#### `/datadog:setup`

Interactive setup wizard that verifies API credentials, tests MCP connectivity, and configures project-level defaults. Run this first after installing the plugin.

#### `/datadog:dashboard`

Creates production-quality Datadog dashboards as Terraform HCL. The workflow:

1. Gathers requirements (integration, metrics, concerns)
2. Discovers available metrics via MCP, docs, and integrations-core CSV
3. Designs template variables and widget layout
4. Generates formatted Terraform HCL with outputs
5. Validates with `terraform fmt`

#### `/datadog:logs`

Search and analyze Datadog logs using natural language or code snippets. The workflow:

1. Reads project defaults (service, filter) from `CLAUDE.md`
2. Translates your request into a Datadog log search query
3. Executes via `search-logs` or `aggregate-logs` MCP tools
4. Presents structured results with follow-up suggestions

Supports two modes:
- **Natural language**: "show me recent errors", "find 5xx responses in the last 30 minutes"
- **Code snippet**: Point to code with logging statements to find matching logs in Datadog

## Documentation

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins)
- [Plugin Reference](https://code.claude.com/docs/en/plugins-reference)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
