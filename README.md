# Claude Code Plugin Marketplace

A collection of Claude Code plugins for monitoring, infrastructure, and development workflows.

## Available Plugins

| Plugin | Description | Skills |
|--------|-------------|--------|
| [**claude-remote**](plugins/claude-remote/) | Configure, verify, and diagnose Claude Code on the web (cloud sessions) | `setup`, `verify`, `debug` |
| [**datadog**](plugins/datadog/) | Datadog monitoring: dashboards, logs, APM traces, metric discovery | `setup`, `dashboard`, `logs`, `traces` |
| [**github**](plugins/github/) | GitHub workflows: issues, PRs, releases, project boards, code review | `setup`, `release`, `feature`, `pm`, `address-review` |
| [**rails**](plugins/rails/) | Ruby on Rails development: debugging, testing, refactoring, migrations | `debug`, `test`, `refactor`, `migrate`, `upgrade` |
| [**spacelift**](plugins/spacelift/) | Spacelift CI/CD for Terraform: stack management, run inspection, debugging, previews | `manage`, `status`, `logs`, `debug`, `preview` |
| [**terraform**](plugins/terraform/) | Terraform infrastructure: plan, drift detection, apply with safety gates | `plan`, `drift`, `apply` |

## Installation

### Interactive (from Claude Code)

```
/plugin marketplace add fabn/claude-plugins
/plugin install github@fabn-claude-plugins
```

### Via settings.json

Add to your `~/.claude/settings.json` (user-level) or `.claude/settings.json` (project-level):

```json
{
  "enabledPlugins": {
    "github@fabn-claude-plugins": true,
    "terraform@fabn-claude-plugins": true
  },
  "extraKnownMarketplaces": {
    "fabn-claude-plugins": {
      "source": {
        "source": "github",
        "repo": "fabn/claude-plugins"
      }
    }
  },
  "enableAllProjectMcpServers": true
}
```

### Local (for development)

```
/plugin marketplace add /absolute/path/to/claude-plugins
```

### Test a single plugin

```bash
claude --plugin-dir ./plugins/datadog
claude --plugin-dir ./plugins/rails
```

## Documentation

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins)
- [Plugin Reference](https://code.claude.com/docs/en/plugins-reference)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
