---
name: datadog:logs
description: |
  This skill should be used when the user wants to search, analyze, or investigate
  Datadog logs. Translates natural language or code snippets into Datadog log
  queries, executes via search-logs and aggregate-logs MCP tools, and presents
  structured results with follow-up suggestions.
  Activates on: "search logs", "find logs", "datadog logs", "log search",
  "check logs", "query logs", "analyze logs", "show me errors", "recent errors",
  "find 5xx", "investigate logs", "debug with logs", "log analysis",
  "count errors by", "group logs by", "error breakdown",
  "cercare log", "cerca nei log", "log datadog", "analizzare log".
---

# Datadog Logs Skill

Search and analyze Datadog logs using MCP tools. Supports natural language queries, code-snippet-based log discovery, and automatic scoping by a configured default service.

## Tools Used

- **Datadog MCP**: `search-logs` for log retrieval, `aggregate-logs` for analytics
- **Read**: Local CLAUDE.md for default service/filter configuration
- **ToolSearch**: Discover available Datadog MCP tools

## Workflow

### Step 1: Detect Context

Read the project's local `CLAUDE.md` (in current working directory) for plugin configuration:

```markdown
<!-- datadog_default_service: my-service-name -->
<!-- datadog_default_filter: env:production -->
```

- If `datadog_default_service` is set, auto-scope all queries with `service:<name>`
- If `datadog_default_filter` is set, prepend it to all queries
- If neither is set, proceed without defaults and ask the user for a service name if the query is ambiguous

### Step 2: Build Query

Determine query mode from user input:

#### Mode A: Natural Language / Direct Request

Parse the user's intent to extract:
- **Service**: explicit service name or use default
- **Time range**: "last hour", "today", "last 15 minutes" → map to `filter.from`/`filter.to`
- **Status/level**: "errors", "warnings", "critical" → `status:(error)`, `status:(warn)`, etc.
- **Keywords**: error messages, endpoint paths, user IDs
- **Structured fields**: HTTP status codes, durations, custom attributes

Translate to Datadog search syntax using `reference/search-syntax.md`. Apply this template:

```
<default_filter> service:<default_or_specified> <status_filter> <user_keywords> <field_filters>
```

**Examples:**
| User says | Query built |
|-----------|-------------|
| "show me recent errors" | `service:my-app status:error` |
| "find 5xx responses in the last 30min" | `service:my-app @http.status_code:[500 TO 599]` |
| "check warnings for the worker service" | `service:worker status:warn` |
| "logs about payment timeout" | `service:my-app "payment timeout"` |

#### Mode B: Code Snippet

When the user points to code containing logging statements:

1. Read the referenced code file/lines
2. Extract log message patterns, log level, and structured fields:
   - `Rails.logger.error("Payment failed for order #{order_id}")` → `status:error "Payment failed for order"`
   - `logger.warn("Retrying request", extra: { attempt: n })` → `status:warn "Retrying request"`
   - `console.error('API timeout', { endpoint })` → `status:error "API timeout"`
3. Derive search query matching on message content, source, and log level
4. Present the derived query to the user for confirmation before executing

### Step 3: Execute Search

If Datadog MCP tools are not already available, discover them first:
```
ToolSearch("datadog")
```

**For log retrieval** — use `search-logs`:
- `filter.query`: the constructed query string
- `filter.from`: start of time range (default: `now-1h`)
- `filter.to`: end of time range (default: `now`)
- `sort`: `-timestamp` (newest first)
- `page.limit`: 25 (default, adjustable by user)

**For analytics/aggregation** — use `aggregate-logs`:
- `filter.query`: same query
- `compute`: appropriate aggregation (`count`, `avg`, `sum`, percentiles on a field)
- `group_by`: relevant facets (e.g., `status`, `@http.status_code`, `service`, `host`)

Use aggregation when the user asks for:
- Counts, totals, averages, percentiles
- "How many errors...", "group by...", "breakdown of..."
- Patterns, trends, distributions

### Step 4: Present Results

**For log entries:**
- Format as a readable list with: timestamp, status, service, message (truncated if long)
- Highlight error/warning entries
- Show total count of matching logs
- If results are truncated, note how many more exist

**For aggregations:**
- Present as summary with counts, percentages, or computed values
- Use tables for grouped results
- Highlight patterns: top error types, status code distribution, error spikes

**Always suggest follow-ups** when results are interesting:
- "Want to see these grouped by status code?"
- "Should I narrow to the last 5 minutes?"
- "Want to aggregate by host to find which server is affected?"

### Step 5: Iterate

Support query refinement without starting from scratch:
- "show me more" → increase `page.limit` or use the cursor from the previous `search-logs` response to fetch the next page
- "narrow to last 5 minutes" → adjust `filter.from` to `now-5m`
- "group by host" → switch to `aggregate-logs` with `group_by: host`
- "exclude health checks" → append `-@http.url:*/health*` to query
- "only 500s" → replace status filter with `@http.status_code:500`

Each refinement modifies the previous query context.

## Error Handling

| Situation | Action |
|-----------|--------|
| MCP tools not available | Tell user to run `/datadog:setup` to configure the Datadog plugin |
| No results returned | Suggest broadening the query: wider time range, fewer filters, check service name spelling |
| Authentication error | Suggest checking API key scopes — `logs_read_data` permission is required |
| Rate limiting | Wait and retry, inform user of the delay |
| Malformed query | Validate query syntax against `reference/search-syntax.md`, fix and retry |
| Service name unknown | Ask user to specify or run `/datadog:setup` to configure a default |

## Reference Files

- **`reference/search-syntax.md`** — Complete Datadog log search syntax with examples, operators, and MCP tool parameter formats
