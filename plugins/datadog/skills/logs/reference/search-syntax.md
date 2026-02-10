# Datadog Log Search Syntax Reference

Quick reference for constructing Datadog log search queries used by the `search-logs` and `aggregate-logs` MCP tools.

## Basic Search

| Syntax | Description | Example |
|--------|-------------|---------|
| `free text` | Matches against log message body | `payment failed` |
| `@attribute:value` | Matches a structured (faceted) field | `@http.status_code:500` |
| `service:name` | Filter by service | `service:backend-api` |
| `source:name` | Filter by log source | `source:ruby` |
| `status:level` | Filter by log level | `status:error` |
| `host:name` | Filter by hostname | `host:web-01` |
| `tag:key:value` | Filter by tag | `tag:env:production` |

## Boolean Operators

| Operator | Syntax | Example |
|----------|--------|---------|
| AND (default) | space between terms | `service:api status:error` |
| OR | `OR` keyword or parentheses with commas | `status:(error OR warn)` |
| NOT / Exclude | `-` prefix | `-status:info` |
| Grouping | parentheses | `(service:api OR service:worker) status:error` |

## Status Filters

```
status:emergency
status:alert
status:critical
status:error
status:warn
status:notice
status:info
status:debug
```

Combine with OR: `status:(error OR critical OR alert)`

## Wildcards

| Pattern | Description | Example |
|---------|-------------|---------|
| `*` in values | Glob-style wildcard | `@http.url:*/api/v2/*` |
| `*` in attributes | Match any attribute value | `@user.email:*@example.com` |
| `service:back*` | Prefix matching | Matches `backend`, `back-office` |

## Numeric Ranges

| Syntax | Description | Example |
|--------|-------------|---------|
| `[min TO max]` | Inclusive range | `@http.status_code:[400 TO 499]` |
| `{min TO max}` | Exclusive range | `@duration:{0 TO 1000000000}` |
| `>value` | Greater than | `@duration:>1000000000` |
| `>=value` | Greater than or equal | `@http.status_code:>=400` |
| `<value` | Less than | `@response_time:<100` |
| `<=value` | Less than or equal | `@bytes:<=1024` |

**Note:** Duration values are in nanoseconds. 1 second = 1,000,000,000 ns.

## Escaping Special Characters

These characters must be escaped with `\` or the term must be quoted:

```
+ - = && || > < ! ( ) { } [ ] ^ " ~ * ? : \ /
```

Example: `"payment failed: timeout"` or `payment\ failed\:\ timeout`

## Time Expressions

Used in `filter.from` and `filter.to` parameters (not in the query string itself):

| Expression | Description |
|------------|-------------|
| `now` | Current time |
| `now-15m` | 15 minutes ago |
| `now-1h` | 1 hour ago |
| `now-4h` | 4 hours ago |
| `now-1d` | 1 day ago |
| `now-7d` | 7 days ago |
| `now-30d` | 30 days ago |
| ISO 8601 | Absolute timestamp, e.g. `2024-01-15T10:00:00Z` |

## Common Query Patterns

| Goal | Query |
|------|-------|
| All errors for a service | `service:my-app status:error` |
| HTTP 5xx responses | `@http.status_code:[500 TO 599]` |
| Specific error message | `service:my-app "Connection refused"` |
| Errors excluding health checks | `service:my-app status:error -@http.url:*/health*` |
| Slow requests (>1s) | `service:my-app @duration:>1000000000` |
| Specific user activity | `service:my-app @usr.id:12345` |
| Errors in production only | `service:my-app status:error env:production` |
| Multiple services | `(service:api OR service:worker) status:error` |
| Kubernetes pod logs | `kube_namespace:production kube_container_name:my-app` |
| Logs with a specific trace | `trace_id:abc123def456` |

## Aggregation Fields

When using `aggregate-logs`, common compute operations:

| Operation | Description | Example |
|-----------|-------------|---------|
| `count` | Count of matching logs | Count errors per minute |
| `avg` | Average of a numeric field | `avg:@duration` |
| `sum` | Sum of a numeric field | `sum:@bytes` |
| `min` / `max` | Min/max of a numeric field | `max:@response_time` |
| `pc75` / `pc90` / `pc95` / `pc99` | Percentiles | `pc99:@duration` |

Common `groupBy` facets: `service`, `status`, `@http.status_code`, `@http.method`, `host`, `@error.kind`, `env`, `kube_namespace`

## MCP Tool Parameters

### search-logs

```json
{
  "filter": {
    "query": "service:my-app status:error",
    "from": "now-1h",
    "to": "now"
  },
  "sort": "-timestamp",
  "page": {
    "limit": 25
  }
}
```

### aggregate-logs

```json
{
  "filter": {
    "query": "service:my-app status:error",
    "from": "now-1h",
    "to": "now"
  },
  "compute": [
    { "aggregation": "count" }
  ],
  "group_by": [
    {
      "facet": "@http.status_code",
      "limit": 10,
      "sort": { "aggregation": "count", "order": "desc" }
    }
  ]
}
```
