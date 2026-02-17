# Claude Code Plugin Marketplace

A collection of Claude Code plugins for monitoring, infrastructure, and development workflows.

## Available Plugins

| Plugin | Description | Skills |
|--------|-------------|--------|
| [**datadog**](plugins/datadog/) | Datadog monitoring: dashboards, logs, APM traces, metric discovery | `setup`, `dashboard`, `logs`, `traces` |
| [**rails**](plugins/rails/) | Ruby on Rails development: debugging, testing, refactoring, migrations | `debug`, `test`, `refactor`, `migrate` |

## Installation

### From GitHub

```
/plugin marketplace add fabn/claude-plugins
/plugin install datadog@fabn-claude-plugins
/plugin install rails@fabn-claude-plugins
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
