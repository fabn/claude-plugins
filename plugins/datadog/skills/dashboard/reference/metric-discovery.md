# Datadog Metric Discovery Workflow

Systematic process for discovering available metrics, their tags, units, and descriptions before building a dashboard. Use all applicable strategies in parallel for best results.

---

## Strategy 1: Datadog MCP (Preferred)

The Datadog MCP server provides direct access to metric data from the Datadog API.

### Discovery Steps

1. **Find available tools:**
   ```
   ToolSearch("datadog")
   ```
   Look for tools like `list_metrics`, `get_metric_metadata`, `get_metric_tags`, `search_metrics`, etc.

2. **List metrics matching integration prefix:**
   - Search for metrics with the integration name prefix (e.g., `puma.*`, `sidekiq.*`, `redis.*`)
   - Note the metric names, types, and available tags

3. **Inspect individual metrics:**
   - Get metadata for each metric (unit, type, description)
   - Get available tag keys for filtering and grouping
   - Check recent values to understand scale and ranges

4. **Discover custom metrics:**
   - Search for project-specific prefixes (e.g., `custom.*`, `ecommerce.*`)
   - Check for log-based metrics that may supplement integration metrics

### If MCP is Not Available

Warn the user:
> "Datadog MCP is not configured in this session. Metric discovery will rely on documentation and integrations-core metadata. For more accurate results, configure the Datadog MCP server."

Proceed with strategies 2 and 3 below.

---

## Strategy 2: Datadog Documentation

Official Datadog integration docs list all collected metrics with descriptions.

### URL Pattern
```
https://docs.datadoghq.com/integrations/<integration>/?tab=host
```

### Examples
- Redis: `https://docs.datadoghq.com/integrations/redisdb/?tab=host`
- Sidekiq: `https://docs.datadoghq.com/integrations/sidekiq/?tab=host`
- Puma: `https://docs.datadoghq.com/integrations/puma/?tab=host`
- Nginx: `https://docs.datadoghq.com/integrations/nginx/?tab=host`
- PostgreSQL: `https://docs.datadoghq.com/integrations/postgres/?tab=host`
- HAProxy: `https://docs.datadoghq.com/integrations/haproxy/?tab=host`

### What to Extract
Look for the **"Data Collected"** section, specifically:
- **Metrics** table: metric name, type (gauge/rate/count), unit, description
- **Service Checks**: health check names for `check_status_definition` widgets
- **Events**: event sources for `event_timeline_definition` widgets

### Usage
```
WebFetch the integration docs page, extract the metrics table from "Data Collected" section.
```

---

## Strategy 3: GitHub integrations-core CSV

The `DataDog/integrations-core` repository contains authoritative metric metadata as CSV files.

### URL Pattern
```
https://raw.githubusercontent.com/DataDog/integrations-core/master/<integration>/metadata.csv
```

### CSV Columns
| Column | Description | Use For |
|--------|-------------|---------|
| `metric_name` | Full metric name (e.g., `redis.net.clients`) | Query construction |
| `metric_type` | `gauge`, `rate`, `count` | Widget type selection |
| `unit_name` | Unit (e.g., `byte`, `second`, `millisecond`, `connection`) | `custom_unit` setting |
| `per_unit_name` | Per-unit (e.g., `second` for rates) | Display formatting |
| `description` | Human-readable description | Widget titles |
| `orientation` | `0` (higher is better), `1` (lower is better), `-1` (neither) | `conditional_formats` direction |
| `integration` | Integration name | Grouping |
| `short_name` | Abbreviated name | Legend aliases |

### Examples
```
# Redis
https://raw.githubusercontent.com/DataDog/integrations-core/master/redisdb/metadata.csv

# Sidekiq
https://raw.githubusercontent.com/DataDog/integrations-core/master/sidekiq/metadata.csv

# Nginx
https://raw.githubusercontent.com/DataDog/integrations-core/master/nginx/metadata.csv

# PostgreSQL
https://raw.githubusercontent.com/DataDog/integrations-core/master/postgres/metadata.csv

# HAProxy
https://raw.githubusercontent.com/DataDog/integrations-core/master/haproxy/metadata.csv
```

### Note on Integration Names
Some integrations use different directory names than you might expect:
- Redis: `redisdb` (not `redis`)
- PostgreSQL: `postgres` (not `postgresql`)
- Elasticsearch: `elastic` (not `elasticsearch`)

If a 404 is returned, try alternate names or search the repository.

### For Integrations Not in integrations-core
Check `DataDog/integrations-extras`:
```
https://raw.githubusercontent.com/DataDog/integrations-extras/master/<integration>/metadata.csv
```

---

## Strategy 4: Datadog AWS Documentation MCP

If the `awslabs.aws-documentation-mcp-server` is available, use it for AWS-specific metrics:

```
search_documentation("datadog <integration> metrics")
```

This can surface additional context about AWS integration metrics (CloudWatch, ECS, Lambda, etc.).

---

## Strategy 5: User-Provided Metrics (Fallback)

When automated discovery fails or for custom application metrics:

1. Ask the user to provide:
   - Metric names they want to monitor
   - Units for each metric
   - Tag keys available for filtering/grouping
   - Threshold values for conditional formatting (green/yellow/red)

2. Suggest checking Datadog Metrics Explorer:
   > "You can find available metrics in Datadog Metrics Explorer. Search for your integration prefix and note the metric names, tags, and units."

---

## Metric Analysis Workflow

After discovering metrics, organize them for dashboard design:

### 1. Categorize by Purpose

| Category | Metric Pattern | Widget Type | Example |
|----------|---------------|-------------|---------|
| KPI / Health | Single aggregate value | `query_value` | Total requests, Error rate |
| Trend | Value over time | `timeseries` | Request rate, Latency |
| Breakdown | Distribution by tag | `sunburst`, `toplist` | Errors by code, Traffic by source |
| Comparison | Multiple related values | `query_table` | Pod status by phase |
| Change | Period-over-period | `change` | Week-over-week failures |

### 2. Determine Units

Priority order for unit determination:
1. **integrations-core CSV** `unit_name` column (most reliable)
2. **Datadog MCP** metric metadata
3. **Metric name inference:**
   - `.seconds`, `.duration` -> `second`
   - `.bytes`, `.memory` -> `byte`
   - `.count`, `.total` -> (none, use `autoscale`)
   - `.percent`, `.ratio` -> `percent`
   - `.connections` -> `connection`
   - `.requests` -> `request`
4. **Ask user** when none of the above works

### 3. Determine Conditional Format Thresholds

For `query_value` widgets, determine red/yellow/green thresholds:

1. **Check `orientation` field** in CSV metadata:
   - `0` (higher is better): green > threshold > yellow > threshold > red
   - `1` (lower is better): green < threshold < yellow < threshold < red
   - `-1` (neither): skip or ask user

2. **For unknown thresholds:** Ask the user what constitutes good, warning, and critical values

3. **Common patterns:**
   - Error counts: `< 10` green, `<= 50` yellow, `> 50` red
   - Availability: `> 0.99` green, `> 0.95` yellow, `<= 0.95` red
   - Latency (seconds): `< 0.5` green, `<= 2` yellow, `> 2` red
   - Queue depth: `< 100` green, `<= 500` yellow, `> 500` red

### 4. Suggest Groupings

Propose logical widget groups based on metric categories:
- **Overview / KPIs**: Top-level aggregate numbers (query_value widgets)
- **Traffic / Throughput**: Request rates, connections, data volume
- **Errors / Failures**: Error rates, failed jobs, 5xx responses
- **Performance / Latency**: Response times, processing duration
- **Resource Utilization**: CPU, memory, connections, queue depth
- **Kubernetes Health**: Pod status, restarts, OOM kills (if k8s-deployed)
- **Logs & Events**: Recent errors, state changes, deployments

### 5. Propose Template Variables

Based on discovered tag keys, suggest filters:
- **Always**: `env` (with production default)
- **If k8s**: `kube_namespace`, `kube_cluster_name`
- **If service-based**: `service`
- **Integration-specific**: e.g., `queue` for Sidekiq, `db` for Redis, `proxy` for HAProxy
