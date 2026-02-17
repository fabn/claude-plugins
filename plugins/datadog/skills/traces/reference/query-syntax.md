# Datadog APM Trace Query Syntax Reference

Quick reference for constructing Datadog APM trace queries used by the `list_traces` MCP tool.

## Basic Filters

| Filter | Example | Description |
|--------|---------|-------------|
| `env` | `env:production` | Environment |
| `service` | `service:my-app` | Service name |
| `status` | `status:error` | Trace status: `ok`, `error` |
| `resource_name` | `resource_name:UsersController#index` | Controller#action or endpoint |
| `operation_name` | `operation_name:rack.request` | Operation type |
| `trace_id` | `trace_id:1978608689310201934` | Specific trace ID |
| `@duration` | `@duration:>1s` | Duration filter |
| `@http.status_code` | `@http.status_code:500` | HTTP status code |
| `@http.method` | `@http.method:POST` | HTTP method |
| `@http.url` | `@http.url:*/api/v1/*` | URL path (supports wildcards) |

## Wildcards

Use `*` for partial matches:
- `resource_name:*Users*` — any resource containing "Users"
- `@http.url:*/api/*` — any URL containing "/api/"

## Duration Syntax

| Expression | Description |
|------------|-------------|
| `@duration:>1s` | Longer than 1 second |
| `@duration:>500ms` | Longer than 500 milliseconds |
| `@duration:[100ms TO 1s]` | Between 100ms and 1 second |
| `@duration:>5s` | Longer than 5 seconds (very slow) |

## Boolean Operators

| Operator | Syntax | Example |
|----------|--------|---------|
| AND (default) | space between terms | `service:api status:error` |
| OR | `OR` keyword | `status:error OR @http.status_code:429` |
| NOT / Exclude | `-` prefix | `-resource_name:*health*` |
| Grouping | parentheses | `(service:api OR service:worker) status:error` |

## Common Query Patterns

| Goal | Query |
|------|-------|
| All errors for a service | `env:production service:my-app status:error` |
| HTTP 5xx responses | `env:production service:my-app @http.status_code:[500 TO 599]` |
| Slow requests (>1s) | `env:production service:my-app @duration:>1s` |
| Specific endpoint errors | `env:production service:my-app resource_name:*Orders* status:error` |
| Specific trace by ID | `trace_id:1978608689310201934` |
| POST requests only | `env:production service:my-app @http.method:POST` |
| Exclude health checks | `env:production service:my-app -resource_name:*health*` |
| 429 rate limited | `env:production service:my-app @http.status_code:429` |

## Timestamp Format

The `list_traces` MCP tool expects timestamps in **epoch seconds** (10 digits), not milliseconds.

**Correct:** `1766943704` (seconds)
**Incorrect:** `1766943704000` (milliseconds — will cause parse error)

Note: Datadog UI URLs use milliseconds, but the API uses seconds.

**Quick reference for time ranges:**
- 1 hour = 3600 seconds
- 1 day = 86400 seconds
- 7 days = 604800 seconds
- 30 days = 2592000 seconds

**Example calculation:**
```bash
now=$(date +%s)
from=$((now - 604800))  # 7 days ago
```

## MCP Tool Parameters

### list_traces

```json
{
  "query": "env:production service:my-app status:error",
  "start_time": 1766339104,
  "end_time": 1766943904,
  "limit": 5,
  "sort": "desc"
}
```

- `query`: Datadog APM query string (see filters above)
- `start_time`: Start of time range in epoch seconds
- `end_time`: End of time range in epoch seconds
- `limit`: Maximum number of traces to return (default: 5, keep low to manage context size)
- `sort`: `"desc"` for newest first, `"asc"` for oldest first

## Trace URL Format

Datadog trace URLs follow this pattern:
```
https://app.datadoghq.com/apm/trace/<trace_id>
```

To extract a trace ID from a URL, match the numeric value after `/apm/trace/`.
