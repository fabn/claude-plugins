# Claude Code Plugin Marketplace

This repository is a Claude Code plugin marketplace. It hosts reusable plugins that bundle skills, MCP server configurations, and reference documentation.

## Repository Structure

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json       # Marketplace catalog (lists all plugins)
├── plugins/
│   └── <plugin-name>/         # One directory per plugin
│       ├── .claude-plugin/
│       │   └── plugin.json    # Plugin manifest (name, description, version, author)
│       ├── .mcp.json          # Bundled MCP servers (optional)
│       └── skills/
│           └── <skill-name>/  # One directory per skill
│               ├── SKILL.md   # Skill definition (frontmatter + workflow)
│               └── reference/ # Supporting reference files (optional)
```

## Adding a New Plugin

1. Create `plugins/<name>/` directory
2. Create `plugins/<name>/.claude-plugin/plugin.json` with name, description, version, author, keywords
3. Optionally add `.mcp.json` for bundled MCP servers
4. Add skills under `plugins/<name>/skills/<skill-name>/SKILL.md`
5. Update `.claude-plugin/marketplace.json` to include the new plugin in the `plugins` array

## Adding a New Skill to an Existing Plugin

1. Create `plugins/<plugin>/skills/<skill-name>/SKILL.md`
2. Add a `reference/` subdirectory if the skill needs supporting documentation
3. The skill will be invocable as `/<plugin>:<skill-name>`
4. Update the plugin's `README.md` (table, getting started, skill details section)
5. Add new keywords to both `plugins/<plugin>/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
6. Keep `description` fields in sync between plugin.json and marketplace.json
7. Bump `version` in both `plugin.json` and `marketplace.json` (patch for fixes, minor for new skills)

## Testing

- Note: `gh` CLI has no `-C` flag (unlike `git -C`); run `gh` commands from the repo directory
- Test a single plugin: `claude --plugin-dir ./plugins/<name>`
- Add marketplace locally: `/plugin marketplace add /absolute/path/to/claude-plugins`
- Install a plugin: `/plugin install <name>@fabn-claude-plugins`
- Validate structure: `claude plugin validate .`

## Conventions

- Plugin names should be lowercase, hyphen-separated (e.g., `datadog`, `aws-ecs`)
- Skill names should describe the action (e.g., `dashboard`, `deploy`, `migrate`)
- SKILL.md frontmatter uses third-person description ("This skill should be used when...") with an "Activates on:" block listing trigger phrases (include Italian variants)
- SKILL.md body follows: intro → reference pointer → tools used → numbered workflow steps → error handling table → reference files section
- MCP server names in `.mcp.json` should be namespaced to avoid collision (e.g., `datadog.datadog-mcp`)
- All env vars required by MCP servers should be documented in the README

## Documentation

- [Claude Code Plugins](https://code.claude.com/docs/en/plugins)
- [Plugin Reference](https://code.claude.com/docs/en/plugins-reference)
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
