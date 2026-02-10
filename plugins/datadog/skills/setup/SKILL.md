---
name: datadog:setup
description: |
  This skill should be used when the user wants to configure Datadog credentials,
  verify MCP server connectivity, or set project-level defaults (default service,
  search filters). Checks ~/.claude/settings.local.json for DD_API_KEY, DD_APP_KEY,
  and DD_SITE environment variables, tests MCP tool availability, and writes
  configuration to the project's CLAUDE.md.
  Activates on: "setup datadog", "configure datadog", "datadog setup",
  "install datadog", "connect to datadog", "datadog credentials",
  "datadog api key", "test datadog connection", "verify datadog",
  "datadog config", "initialize datadog", "configurare datadog",
  "configurazione datadog".
---

# Datadog Setup Skill

Interactive setup wizard for the Datadog plugin. Verifies API credentials, tests MCP connectivity, and configures project-level defaults for log queries and dashboards.

## Tools Used

- **Read**: Check `~/.claude/settings.local.json` for environment variables
- **ToolSearch**: Discover Datadog MCP tools and verify connectivity
- **AskUserQuestion**: Prompt for missing configuration and preferences
- **Edit**: Update project's `CLAUDE.md` with default settings

## Workflow

### Step 1: Check Environment Variables

Read `~/.claude/settings.local.json` and verify the presence of required Datadog credentials in the `env` object:

| Variable | Required | Description |
|----------|----------|-------------|
| `DD_API_KEY` | Yes | Datadog API key for authentication |
| `DD_APP_KEY` | Yes | Datadog Application key for API access |
| `DD_SITE` | Yes | Datadog site region endpoint |

**For each missing variable:**

1. Explain what it is and where to find it:
   - `DD_API_KEY`: Datadog → Organization Settings → API Keys
   - `DD_APP_KEY`: Datadog → Organization Settings → Application Keys (needs `logs_read_data`, `dashboards_read`, `metrics_read` scopes)
   - `DD_SITE`: The Datadog site for your organization

2. Show common `DD_SITE` values:
   | Site | Value |
   |------|-------|
   | EU | `datadoghq.eu` |
   | US1 | `datadoghq.com` |
   | US5 | `us5.datadoghq.com` |
   | US3 | `us3.datadoghq.com` |
   | AP1 | `ap1.datadoghq.com` |

**IMPORTANT:** Do NOT write credentials automatically. Only instruct the user on what to add and where. The user must edit the file themselves.

3. Show the exact JSON snippet to add to `~/.claude/settings.local.json`:
   ```json
   {
     "env": {
       "DD_API_KEY": "your-api-key-here",
       "DD_APP_KEY": "your-app-key-here",
       "DD_SITE": "datadoghq.eu"
     }
   }
   ```

If all variables are present, confirm with a checkmark and proceed to Step 2.

### Step 2: Verify Connection

Test that the Datadog MCP server is reachable and credentials are valid:

1. Use `ToolSearch("datadog")` to discover available MCP tools
2. Attempt a lightweight API call (e.g., `list-metrics` with a small limit or `get-metrics` with a known metric prefix) to verify credentials work
3. **If successful**: Report connected site and available tools
4. **If failed**: Diagnose the issue:
   - No MCP tools found → Plugin not installed correctly, suggest reinstalling
   - Authentication error → Wrong API key, expired key, or insufficient scopes
   - Connection error → Wrong `DD_SITE` value, network issues
   - Suggest specific fixes for each failure mode

### Step 3: Configure Default Service (Optional)

Ask the user if they want to configure a default Datadog service for this project:

> "Do you have a default Datadog service name for this project? This will be used to auto-scope log queries."

- **If yes**: Get the service name and write it to the project's `CLAUDE.md`
- **If no/skip**: Proceed without a default (queries will require explicit service specification)

The service name should match what appears in Datadog's Service Catalog (e.g., `backend-api`, `frontend-app`, `worker`).

### Step 4: Configure Default Search Filter (Optional)

Ask the user if they want a default search filter prepended to all log queries:

> "Do you want a default filter prepended to all log queries? Common examples: `env:production`, `team:backend`, `kube_namespace:production`"

- **If yes**: Get the filter expression and write it to the project's `CLAUDE.md`
- **If no/skip**: Proceed without a default filter

### Step 5: Write Configuration to CLAUDE.md

If the user configured any defaults (service or filter), append the configuration block to the project's local `CLAUDE.md` file in the current working directory.

**Format** (using HTML comments so it's invisible in rendered markdown but parseable):

```markdown
<!-- datadog-plugin-config -->
<!-- datadog_default_service: my-service-name -->
<!-- datadog_default_filter: env:production -->
```

Rules:
- If `CLAUDE.md` exists, append the config block at the end
- If `CLAUDE.md` does not exist, create it with only the config block
- If a `<!-- datadog-plugin-config -->` block already exists, replace it
- Only include lines for settings the user actually configured

> **Note:** This configuration format is read by `datadog:logs` (Step 1: Detect Context)
> to auto-scope queries. Changes to the format must be synchronized between both skills.

### Step 6: Summary

Print a configuration summary:

```
Datadog Plugin Configuration
-----------------------------
DD_SITE:          datadoghq.eu (configured)
DD_API_KEY:       configured
DD_APP_KEY:       configured
MCP Connection:   verified
Default service:  backend-api
Default filter:   env:production

Next steps:
- Search logs: /datadog:logs show me recent errors
- Create dashboard: /datadog:dashboard create a Redis dashboard
```

Adjust the summary based on what was actually configured. For missing items, show "not configured" and suggest running setup again.

## Error Handling

| Situation | Action |
|-----------|--------|
| `~/.claude/settings.local.json` doesn't exist | Tell user to create it with the required env vars |
| JSON parse error in settings file | Warn user about malformed JSON, suggest fixing |
| MCP server not responding | Check if plugin is installed, suggest `/plugin install datadog@fabn-claude-plugins` |
| API key has insufficient scopes | List required scopes: `logs_read_data`, `dashboards_read`, `metrics_read` |
| `CLAUDE.md` is read-only | Warn and print the config block for manual addition |

## Related Skills

- **`/datadog:logs`** — Search and analyze logs (reads configuration written by this skill)
- **`/datadog:dashboard`** — Create Terraform-based Datadog dashboards
