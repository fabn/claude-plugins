---
name: datadog:traces
description: |
  This skill should be used when the user wants to search, analyze, or investigate
  Datadog APM traces. Finds recent traces by query or looks up specific traces by
  ID or Datadog URL. Translates natural language into APM query syntax, executes
  via the list_traces MCP tool, and parses large trace responses into concise
  summaries with error details and Datadog links.
  Activates on: "search traces", "find traces", "datadog traces", "trace search",
  "analyze trace", "trace lookup", "APM traces", "slow requests",
  "error traces", "trace ID", "investigate trace", "request performance",
  "tracciare errori", "cercare trace", "trace datadog".
---

# Datadog Traces Skill

Analyze APM traces from Datadog to investigate errors, performance issues, and request flows. Supports searching recent traces by criteria and looking up specific traces by ID or URL.

**Scope:** This skill handles APM trace search and analysis only. For log search use `/datadog:logs`, for dashboard creation use `/datadog:dashboard`.

**Reference files:** Consult `reference/query-syntax.md` for the full APM query syntax, timestamp format, and MCP tool parameters.

## Tools Used

- **Datadog APM MCP** (`datadog.datadog-apm`): `list_traces` for trace retrieval
- **Bash**: `scripts/parse-traces.js` to reduce large trace responses to concise summaries
- **Read**: Local CLAUDE.md for default service/filter configuration
- **ToolSearch**: Discover available Datadog MCP tools

## Workflow

### Step 1: Detect Context

Read the project's local `CLAUDE.md` (in current working directory) for plugin configuration:

```markdown
<!-- datadog_default_service: my-service-name -->
<!-- datadog_default_filter: env:production -->
```

- If `datadog_default_service` is set, use it as the default `service:` filter
- If `datadog_default_filter` is set, prepend it to all queries (typically `env:production`)
- If neither is set, ask the user for a service name

> **Note:** This configuration is written by `datadog:setup` (Step 5). Changes to the
> format must be synchronized across setup, logs, and traces skills.

### Step 2: Determine Query Mode

Detect how the user wants to search:

#### Mode A: Natural Language / Search

Parse the user's intent to extract:
- **Service**: explicit service name or use default
- **Time range**: "last hour", "today", "last 15 minutes" (default: 7 days)
- **Status**: "errors", "failing" -> `status:error`
- **Endpoint/resource**: controller names, URL paths -> `resource_name:*Pattern*`
- **Duration**: "slow", "over 1 second" -> `@duration:>1s`
- **HTTP status**: "5xx", "500 errors" -> `@http.status_code:[500 TO 599]`

Build the query using `reference/query-syntax.md`. Apply this template:

```
<env_filter> service:<default_or_specified> <status_filter> <resource_filter> <duration_filter>
```

**Examples:**
| User says | Query built |
|-----------|-------------|
| "show recent errors" | `env:production service:my-app status:error` |
| "find slow requests to /api/orders" | `env:production service:my-app resource_name:*orders* @duration:>1s` |
| "5xx responses in the last hour" | `env:production service:my-app @http.status_code:[500 TO 599]` |
| "traces for the UsersController" | `env:production service:my-app resource_name:*UsersController*` |

#### Mode B: Trace ID Lookup

When the user provides a specific trace:
- **URL pattern**: Extract ID from `https://app.datadoghq.com/apm/trace/(\d+)`
- **Direct ID**: Numeric string

Build query: `trace_id:<id>`

Use an extended time range of 30 days (old traces may still be relevant).

#### Mode C: Code-Based Investigation

When the user points to code with controller actions or endpoint definitions:
1. Read the referenced code to extract endpoint/controller names
2. Build a `resource_name:*Pattern*` query matching the code
3. Present the derived query to the user for confirmation

### Step 3: Execute Search

If Datadog MCP tools are not already available, discover them first:
```
ToolSearch("datadog")
```

**Calculate time range** in epoch seconds (the API requires seconds, not milliseconds):
```bash
now=$(date +%s)
from=$((now - 604800))  # 7 days ago (default)
```

Adjust `from` based on user request:
- "last hour" -> `now - 3600`
- "today" -> `now - 86400`
- "last 30 minutes" -> `now - 1800`
- Trace ID lookup -> `now - 2592000` (30 days)

**Execute:**
```
list_traces(
  query: "<built query>",
  start_time: <epoch seconds>,
  end_time: <epoch seconds>,
  limit: 5,
  sort: "desc"
)
```

Keep `limit` at 5 by default to manage context size. Trace responses can be 100KB+ per trace.

### Step 4: Parse Response

Trace responses are very large. **Always** pipe through the parse script to reduce them:

```bash
echo '<raw_json_response>' | node ${CLAUDE_PLUGIN_ROOT}/skills/traces/scripts/parse-traces.js
```

The script:
- Handles both list format (`{ traces: [...] }`) and spans format (`{ data: [...] }`)
- Deduplicates by trace ID
- Extracts: endpoint, status, HTTP status, duration, error type/message/stack, Datadog URL
- Reduces 100KB+ responses to ~2KB of structured data

If the parse script fails, show raw trace data as a fallback but warn the user about the large output.

### Step 5: Present Results

**For search results:**

```
## Trace Results (N found)

| # | Endpoint | Status | Duration | Time |
|---|----------|--------|----------|------|
| 1 | GET /api/v1/orders | error | 2.3s | 2h ago |
| 2 | POST /api/v1/items | ok | 150ms | 3h ago |

### Trace 1 - Error Details
**Error:** ActiveRecord::RecordNotFound
**Message:** Couldn't find Order with 'id'=999
[View in Datadog](https://app.datadoghq.com/apm/trace/123456)
```

**For single trace lookup:**

```
## Trace Analysis

**Trace ID:** 1978608689310201934
**Endpoint:** GET /api/v1/orders/123
**Status:** error (500)
**Duration:** 2.34s

### Error
**Type:** ActiveRecord::RecordNotFound
**Message:** Couldn't find Order with 'id'=123

### Stack Trace (first 10 lines)
app/controllers/api/v1/orders_controller.rb:15:in `show'
...

[View in Datadog](https://app.datadoghq.com/apm/trace/1978608689310201934)
```

**Always suggest follow-ups** when results are interesting:
- "Want to see more traces for this endpoint?"
- "Should I narrow to just 5xx errors?"
- "Want to check the logs around this time? (use `/datadog:logs`)"

### Step 6: Iterate

Support query refinement without starting from scratch:
- "show me more" -> increase `limit` to 10 or 20
- "only errors" -> add `status:error` to query
- "last hour only" -> narrow `start_time` to `now - 3600`
- "for a different service" -> replace `service:` filter
- "show me the logs" -> suggest switching to `/datadog:logs` with the same time range and service

Each refinement modifies the previous query context.

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP tools not available | Tell user to run `/datadog:setup` to configure the Datadog plugin |
| No traces found | Suggest broadening time range, removing status filter, or checking service name spelling |
| Authentication error | Suggest checking API key scopes — APM read permissions are required |
| Timestamp parse error | Verify epoch seconds (10 digits), not milliseconds (13 digits) |
| Parse script fails | Fall back to showing raw trace data with a warning about large output |
| Service name unknown | Ask user to specify or run `/datadog:setup` to configure a default |
| Trace response too large | Reduce `limit`, always use parse script, summarize instead of showing full output |

## Reference Files

- **`reference/query-syntax.md`** — Complete Datadog APM trace query syntax with filters, operators, timestamp format, and MCP tool parameters
- **`scripts/parse-traces.js`** — Node.js script that reduces large trace responses to concise structured summaries
