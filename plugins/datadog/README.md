# Datadog Plugin

Datadog monitoring workflows for Terraform-managed infrastructure. Includes dashboard creation with metric discovery and HCL generation, log search and analysis, APM trace investigation, and interactive setup.

## Skills

| Skill | Description |
|-------|-------------|
| `/datadog:setup` | Interactive setup wizard — verifies API credentials, tests MCP connectivity, configures project defaults |
| `/datadog:dashboard` | Create Datadog dashboards as Terraform HCL with metric discovery and grouped widget layouts |
| `/datadog:logs` | Search and analyze logs using natural language or code snippets |
| `/datadog:traces` | Search and analyze APM traces by query, trace ID, or Datadog URL |

## Prerequisites

The plugin requires Datadog API credentials. Set these in `~/.claude/settings.local.json`:

```json
{
  "env": {
    "DD_API_KEY": "your-api-key",
    "DD_APP_KEY": "your-app-key",
    "DD_SITE": "datadoghq.eu"
  }
}
```

| Variable | Required | Description |
|----------|----------|-------------|
| `DD_API_KEY` | Yes | Datadog API key (Organization Settings > API Keys) |
| `DD_APP_KEY` | Yes | Datadog Application key (scopes: `logs_read_data`, `dashboards_read`, `metrics_read`) |
| `DD_SITE` | Yes | Datadog site region (`datadoghq.eu`, `datadoghq.com`, `us5.datadoghq.com`, etc.) |

## Getting Started

Run the setup wizard after installing:

```
/datadog:setup
```

This verifies credentials, tests MCP connectivity, and optionally configures project-level defaults for log and trace queries.

## MCP Servers

The plugin bundles two MCP servers:

| Server | Package | Purpose |
|--------|---------|---------|
| `datadog.datadog-mcp` | `datadog-mcp-server` | Metrics, dashboards, monitors, log search, log aggregation |
| `datadog.datadog-apm` | `@winor30/mcp-server-datadog` | APM trace search and retrieval |

Both servers are driven by the same three `DD_*` environment variables. The `datadog-apm` server uses `DATADOG_*` variable names internally, but the plugin's `.mcp.json` maps these automatically — you only need to set `DD_API_KEY`, `DD_APP_KEY`, and `DD_SITE`.

| You set | Used by `datadog.datadog-mcp` | Used by `datadog.datadog-apm` (mapped internally) |
|---------|-------------------------------|--------------------------------------------------|
| `DD_API_KEY` | `DD_API_KEY` | → `DATADOG_API_KEY` |
| `DD_APP_KEY` | `DD_APP_KEY` | → `DATADOG_APP_KEY` |
| `DD_SITE` | `DD_SITE` | → `DATADOG_SITE` |

## Project Configuration

The `logs` and `traces` skills read default settings from your project's `CLAUDE.md`. These are set automatically by `/datadog:setup` or can be added manually:

```markdown
<!-- datadog-plugin-config -->
<!-- datadog_default_service: my-service-name -->
<!-- datadog_default_filter: env:production -->
```

- `datadog_default_service` — auto-scopes log and trace queries to this service
- `datadog_default_filter` — prepended to all queries (e.g., `env:production`)

## Skill Details

### `/datadog:setup`

Interactive setup wizard:
1. Checks environment variables in `~/.claude/settings.local.json`
2. Verifies MCP server connectivity
3. Optionally configures default service and search filter
4. Writes configuration to project's `CLAUDE.md`

### `/datadog:dashboard`

Creates production-quality Datadog dashboards as Terraform HCL:
1. Gathers requirements (integration, metrics, concerns)
2. Discovers metrics via MCP, Datadog docs, and integrations-core CSV
3. Assigns team tags and designs template variables
4. Designs grouped widget layout with user approval
5. Generates Terraform HCL with conditional formats, legends, and units
6. Validates with `terraform fmt`

### `/datadog:logs`

Searches and analyzes logs via MCP tools:
1. Reads project defaults (service, filter) from `CLAUDE.md`
2. Translates natural language or code snippets into Datadog query syntax
3. Executes via `search-logs` or `aggregate-logs` MCP tools
4. Presents structured results with follow-up suggestions

Supports natural language ("show me recent errors") and code-based discovery (point to logging statements to find matching logs).

### `/datadog:traces`

Searches and analyzes APM traces:
1. Reads project defaults from `CLAUDE.md`
2. Builds queries from natural language, trace IDs, or Datadog URLs
3. Executes via `list_traces` MCP tool
4. Parses large trace responses (~100KB) into concise summaries
5. Supports query refinement and cross-referencing with `/datadog:logs`
