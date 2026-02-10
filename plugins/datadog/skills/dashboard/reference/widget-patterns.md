# Datadog Dashboard Widget Patterns - Terraform HCL Reference

Copy-paste-ready HCL blocks for every common widget type. All patterns follow the 12-column ordered layout with fixed reflow.

---

## Dashboard Resource Skeleton

```hcl
resource "datadog_dashboard" "<topic>_monitoring" {
  title       = "<Title> Monitoring"
  description = "<Description of the dashboard>"
  layout_type = "ordered"
  reflow_type = "fixed"
  tags        = ["team:<handle>"]

  # Template Variables
  template_variable {
    name     = "env"
    prefix   = "env"
    defaults = ["prod"]
  }

  template_variable {
    name     = "service"
    prefix   = "service"
    defaults = ["*"]
  }

  # ... widgets go here ...
}

output "dashboard_id" {
  description = "The ID of the created dashboard"
  value       = datadog_dashboard.<topic>_monitoring.id
}

output "dashboard_url" {
  description = "The URL to access the dashboard"
  value       = datadog_dashboard.<topic>_monitoring.url
}
```

---

## Template Variables

Standard patterns for dynamic filtering. Always include `env` first.

```hcl
# Required: environment filter (always first)
template_variable {
  name     = "env"
  prefix   = "env"
  defaults = ["prod"]  # Project-specific default
}

# Common: service filter
template_variable {
  name     = "service"
  prefix   = "service"
  defaults = ["*"]
}

# Kubernetes: namespace filter
template_variable {
  name     = "kube_namespace"
  prefix   = "kube_namespace"
  defaults = ["*"]
}

# Kubernetes: cluster filter
template_variable {
  name     = "kube_cluster_name"
  prefix   = "kube_cluster_name"
  defaults = ["example-project-prod"]
}

# Integration-specific: use the tag key as prefix
template_variable {
  name     = "proxy"       # HAProxy example
  prefix   = "proxy"
  defaults = ["*"]
}
```

**Reference in queries:** Use `$variable_name` syntax, e.g.:
- `sum:metric{$env,$service,$kube_namespace}`
- Combine with static tags: `sum:metric{$env,$service,code:5*}`

---

## Widget Layout (12-Column Grid)

All widgets use `widget_layout` with `x` (0-11), `y`, `width` (1-12), `height`.

**Standard sizes:**

| Widget Type    | Typical Size (WxH) | Notes                          |
|----------------|--------------------:|--------------------------------|
| query_value    | 2x2, 3x2, 4x2      | KPI cards at top of groups     |
| timeseries     | 6x3, 6x4, 12x4     | Charts, half or full width     |
| sunburst       | 3x3, 4x4            | Breakdowns by category         |
| query_table    | 3x2, 6x3, 12x4     | Tabular data                   |
| toplist        | 3x3, 4x4            | Rankings                       |
| heatmap        | 6x3, 12x4           | Distributions                  |
| change         | 2x4, 2x5            | Narrow column, vertical        |
| list_stream    | 5x3, 6x4            | Log streams                    |
| event_timeline | 6x3                 | Event timelines                |
| check_status   | 3x3                 | Service health checks          |
| note           | 12x1                | Full-width section headers     |
| manage_status  | 3x4                 | Monitor status panels          |
| slo_list       | 4x4                 | SLO summaries                  |

```hcl
widget_layout {
  height = 2
  width  = 4
  x      = 0   # Column position (0-11)
  y      = 0   # Row position (auto-increments)
}
```

---

## Group Definition

ALL widgets MUST be wrapped in groups. Each group has a title, background color, and contains child widgets.

```hcl
widget {
  group_definition {
    title            = "Overview KPIs"
    show_title       = true
    layout_type      = "ordered"
    background_color = "vivid_blue"

    # Child widgets go here (same widget {} syntax, without widget_layout)
    widget {
      query_value_definition {
        # ...
      }
    }

    widget {
      timeseries_definition {
        # ...
      }
    }
  }
  # Group-level layout positions the entire group on the grid
  widget_layout {
    height = 6
    width  = 12
    x      = 0
    y      = 0
  }
}
```

**Background color palette** (use semantically):
- `vivid_blue` - Overview, KPIs, general info
- `vivid_green` - Health, success, availability
- `vivid_orange` - Warnings, degradation
- `vivid_pink` - Errors, failures
- `vivid_purple` - Performance, latency
- `vivid_yellow` - Alerts, attention needed
- `gray` - Logs, events, auxiliary info
- `white` - Neutral, documentation

---

## Query Value Definition

KPI cards with at-a-glance status via conditional formatting and optional trend sparkline.

```hcl
widget {
  query_value_definition {
    autoscale   = true
    precision   = 0            # 0 for counts, 2-3 for decimals
    text_align  = "center"
    title       = "Total Requests (last 1h)"
    title_align = "left"
    title_size  = "16"
    live_span   = "1h"         # "5m", "1h", "1d", "1w"
    # custom_unit = "req"      # Set when unit is not auto-detected

    request {
      formula {
        formula_expression = "query1"
        # alias = "Requests"   # Optional display name
      }
      query {
        metric_query {
          aggregator  = "sum"   # "sum", "avg", "max", "min", "last"
          data_source = "metrics"
          name        = "query1"
          query       = "sum:my.metric{$env,$service}.as_count()"
        }
      }

      # MUST HAVE: conditional formats for status coloring
      # Order: best case first, then warning, then worst case
      conditional_formats {
        comparator = ">"
        palette    = "white_on_green"
        value      = 10000
      }
      conditional_formats {
        comparator = "<="
        palette    = "white_on_yellow"
        value      = 10000
      }
      conditional_formats {
        comparator = "<"
        palette    = "white_on_red"
        value      = 5000
      }
    }

    # RECOMMENDED: sparkline background for trend context
    timeseries_background {
      type = "bars"    # "bars" for counts/rates, "area" for continuous
    }
  }
  widget_layout {
    height = 2
    width  = 4
    x      = 0
    y      = 0
  }
}
```

**Conditional format palettes:**
- `white_on_green` - Good / healthy
- `white_on_yellow` - Warning / degraded
- `white_on_red` - Critical / failing
- `green_on_white`, `yellow_on_white`, `red_on_white` - Inverted variants

**For error metrics** (lower is better), reverse the logic:
```hcl
conditional_formats {
  comparator = "<"
  palette    = "white_on_green"
  value      = 10
}
conditional_formats {
  comparator = "<="
  palette    = "white_on_yellow"
  value      = 50
}
conditional_formats {
  comparator = ">"
  palette    = "white_on_red"
  value      = 50
}
```

**For boolean/status metrics** (1=UP, 0=DOWN):
```hcl
conditional_formats {
  comparator = ">"
  palette    = "white_on_green"
  value      = 0.9
}
conditional_formats {
  comparator = "<="
  palette    = "white_on_red"
  value      = 0.9
}
```

---

## Timeseries Definition

Charts with legends, multiple series, and formula aliases.

```hcl
widget {
  timeseries_definition {
    title          = "HTTP Response Codes Over Time"
    title_align    = "left"
    title_size     = "16"
    show_legend    = true          # MUST be true for multi-series
    legend_layout  = "auto"        # "auto" or "horizontal"
    legend_columns = ["avg", "max", "value"]  # Columns shown in legend

    # Series 1: Success
    request {
      display_type = "bars"        # "line", "bars", "area"
      formula {
        formula_expression = "query_2xx"
        alias              = "2xx Success"    # SHOULD have alias for readability
      }
      query {
        metric_query {
          data_source = "metrics"
          name        = "query_2xx"
          query       = "sum:http.responses{$env,$service,code:2*} by {code}.as_count()"
        }
      }
      style {
        palette    = "green"       # Semantic color for success
        line_type  = "solid"       # "solid", "dashed", "dotted"
        line_width = "normal"      # "thin", "normal", "thick"
      }
    }

    # Series 2: Errors
    request {
      display_type = "bars"
      formula {
        formula_expression = "query_5xx"
        alias              = "5xx Server Error"
      }
      query {
        metric_query {
          data_source = "metrics"
          name        = "query_5xx"
          query       = "sum:http.responses{$env,$service,code:5*} by {code}.as_count()"
        }
      }
      style {
        palette    = "red"         # Semantic color for errors
        line_type  = "solid"
        line_width = "normal"
      }
    }
  }
  widget_layout {
    height = 4
    width  = 8
    x      = 0
    y      = 2
  }
}
```

**Display type guidance:**
- `line` - Continuous metrics (latency, CPU, memory)
- `bars` - Counts, rates, discrete events (requests, errors)
- `area` - Cumulative metrics, stacked compositions

**Style palette options:**
- Semantic: `green`, `red`, `blue`, `orange`, `purple`, `yellow`
- Gradients: `warm` (red-orange), `cool` (blue-green)
- Multi-color: `dog_classic`, `dog_classic_area`, `datadog16`

**Formula functions** commonly used:
```hcl
formula {
  formula_expression = "per_second(query1)"        # Rate conversion
  alias              = "Requests/sec"
}
formula {
  formula_expression = "forecast(query1, 'seasonal', 1)"  # Prediction
  alias              = "Predicted"
}
formula {
  formula_expression = "week_before(query1)"       # Week-over-week comparison
  alias              = "Last Week"
}
formula {
  formula_expression = "query1 * -1"               # Invert for stacked up/down charts
  alias              = "Refunded"
}
```

**Rollup for time bucketing:**
```hcl
query = "sum:metric{*}.as_count().rollup(sum, daily, 'Europe/Rome')"  # Daily buckets in timezone
query = "sum:metric{*}.as_count().rollup(count, 3600)"                # Hourly buckets
```

---

## Sunburst Definition

Breakdown visualization grouped by tags.

```hcl
widget {
  sunburst_definition {
    title       = "Payments by Type"
    title_align = "left"
    title_size  = "16"
    hide_total  = false

    legend_table {
      type = "table"      # Shows detailed breakdown table alongside chart
    }

    request {
      formula {
        formula_expression = "query1"
      }
      query {
        metric_query {
          aggregator  = "sum"
          data_source = "metrics"
          name        = "query1"
          query       = "sum:my.metric{$env,$service} by {type_tag}.as_count()"
        }
      }
      style {
        palette = "datadog16"    # Good for many categories
        # Other options: "dog_classic_area", "cool", "warm"
      }
    }
  }
  widget_layout {
    height = 3
    width  = 3
    x      = 6
    y      = 0
  }
}
```

---

## Toplist Definition

Ranking metrics by dimension.

```hcl
widget {
  toplist_definition {
    title       = "Top Services by Error Rate"
    title_align = "left"
    title_size  = "16"
    live_span   = "1h"

    request {
      formula {
        formula_expression = "query1"
        alias              = "Error Count"
      }
      query {
        metric_query {
          aggregator  = "sum"
          data_source = "metrics"
          name        = "query1"
          query       = "sum:trace.http.request.errors{$env} by {service}.as_count()"
        }
      }
      conditional_formats {
        comparator = ">"
        palette    = "white_on_red"
        value      = 100
      }
      conditional_formats {
        comparator = "<="
        palette    = "white_on_green"
        value      = 100
      }
    }
  }
  widget_layout {
    height = 4
    width  = 4
    x      = 0
    y      = 0
  }
}
```

---

## Query Table Definition

Tabular data with multiple formulas and cell display modes.

```hcl
widget {
  query_table_definition {
    title       = "Pod Status Summary"
    title_align = "left"
    title_size  = "16"
    live_span   = "5m"

    request {
      formula {
        alias              = "Running"
        formula_expression = "query_running"
        cell_display_mode  = "bar"    # "number", "bar"
      }
      formula {
        alias              = "Pending"
        formula_expression = "query_pending"
        cell_display_mode  = "bar"
      }
      formula {
        alias              = "Failed"
        formula_expression = "query_failed"
        cell_display_mode  = "bar"
      }

      query {
        metric_query {
          aggregator  = "sum"
          data_source = "metrics"
          name        = "query_running"
          query       = "sum:kubernetes_state.pod.status_phase{$env,phase:running} by {pod_name}"
        }
      }
      query {
        metric_query {
          aggregator  = "sum"
          data_source = "metrics"
          name        = "query_pending"
          query       = "sum:kubernetes_state.pod.status_phase{$env,phase:pending} by {pod_name}"
        }
      }
      query {
        metric_query {
          aggregator  = "sum"
          data_source = "metrics"
          name        = "query_failed"
          query       = "sum:kubernetes_state.pod.status_phase{$env,phase:failed} by {pod_name}"
        }
      }
    }
  }
  widget_layout {
    height = 3
    width  = 6
    x      = 0
    y      = 0
  }
}
```

---

## Change Definition

Shows metric changes over time periods, useful for week-over-week comparisons.

```hcl
widget {
  change_definition {
    title       = "Failed Charges by Reason"
    title_align = "left"
    title_size  = "16"

    request {
      change_type   = "absolute"    # "absolute" or "percent"
      increase_good = false         # false when metric represents errors
      order_by      = "change"      # "change", "name", "present", "past"
      order_dir     = "desc"
      show_present  = true

      formula {
        formula_expression = "week_before(query1)"
      }
      formula {
        formula_expression = "query1"
      }

      query {
        event_query {
          data_source = "logs"
          indexes     = ["*"]
          name        = "query1"
          storage     = "hot"
          compute {
            aggregation = "count"
          }
          group_by {
            facet = "@failure_code"
            limit = 10
            sort {
              aggregation = "count"
              metric      = "count"
              order       = "desc"
            }
          }
          search {
            query = "source:myservice status:error $env"
          }
        }
      }
    }
  }
  widget_layout {
    height = 5
    width  = 2
    x      = 10
    y      = 0
  }
}
```

---

## Heatmap Definition

Distribution visualization for latency, sizes, or other continuous metrics.

```hcl
widget {
  heatmap_definition {
    title       = "Request Latency Distribution"
    title_align = "left"
    title_size  = "16"
    show_legend = true

    request {
      query {
        metric_query {
          data_source = "metrics"
          name        = "query1"
          query       = "avg:trace.http.request.duration{$env,$service} by {resource_name}"
        }
      }
      style {
        palette = "dog_classic"
      }
    }
  }
  widget_layout {
    height = 4
    width  = 12
    x      = 0
    y      = 0
  }
}
```

---

## Note Definition

Dashboard documentation / section headers.

```hcl
widget {
  note_definition {
    content          = "## Performance Metrics\nThis section tracks response times and throughput."
    background_color = "transparent"
    font_size        = "14"
    has_padding      = true
    show_tick        = false
    text_align       = "left"
    tick_edge        = "left"
    tick_pos         = "50%"
    vertical_align   = "top"
  }
  widget_layout {
    height = 1
    width  = 12
    x      = 0
    y      = 0
  }
}
```

---

## List Stream Definition

Log streams for real-time event monitoring.

```hcl
widget {
  list_stream_definition {
    title       = "Error Logs"
    title_align = "left"
    title_size  = "16"

    request {
      response_format = "event_list"

      columns {
        field = "status_line"
        width = "auto"
      }
      columns {
        field = "timestamp"
        width = "auto"
      }
      columns {
        field = "content"
        width = "auto"
      }
      columns {
        field = "service"
        width = "auto"
      }

      query {
        data_source  = "logs_stream"
        query_string = "source:myservice status:(warn OR error) $env"
        storage      = "hot"
        sort {
          column = "timestamp"
          order  = "desc"
        }
      }
    }
  }
  widget_layout {
    height = 3
    width  = 6
    x      = 0
    y      = 0
  }
}
```

---

## Event Timeline Definition

Timeline of infrastructure events.

```hcl
widget {
  event_timeline_definition {
    title       = "State Changes"
    title_align = "left"
    title_size  = "16"
    live_span   = "1d"

    query          = "source:myservice $env (\"error\" OR \"restart\" OR \"deploy\")"
    tags_execution = "and"
  }
  widget_layout {
    height = 3
    width  = 6
    x      = 6
    y      = 0
  }
}
```

---

## Check Status Definition

Service health check visualization.

```hcl
widget {
  check_status_definition {
    title       = "Service Health Checks"
    title_align = "left"
    title_size  = "16"
    check       = "myservice.openmetrics.health"
    grouping    = "cluster"      # "check", "cluster"
    group_by    = ["service", "host"]
    tags        = ["$env", "$service"]
  }
  widget_layout {
    height = 3
    width  = 3
    x      = 0
    y      = 0
  }
}
```

---

## Manage Status Definition

Monitor status overview panel.

```hcl
widget {
  manage_status_definition {
    color_preference    = "text"
    display_format      = "countsAndList"     # "counts", "countsAndList", "list"
    hide_zero_counts    = true
    query               = "tag:(integration:myservice)"
    show_last_triggered = false
    show_priority       = true
    sort                = "status,asc"
    summary_type        = "monitors"
    title               = "Service Monitors"
  }
  widget_layout {
    height = 4
    width  = 3
    x      = 0
    y      = 0
  }
}
```

---

## SLO List Definition

SLO summary widget.

```hcl
widget {
  slo_list_definition {
    title       = "Service SLOs"
    title_align = "left"
    title_size  = "16"

    request {
      request_type = "slo_list"
      query {
        limit        = 100
        query_string = "tags:\"integration:myservice\""
      }
    }
  }
  widget_layout {
    height = 4
    width  = 4
    x      = 0
    y      = 0
  }
}
```

---

## Log-Based Queries (Event Query)

For widgets querying logs instead of metrics:

```hcl
query {
  event_query {
    data_source = "logs"
    indexes     = ["*"]
    name        = "query1"
    storage     = "hot"         # "hot" for recent, "warm" for archived
    compute {
      aggregation = "count"     # "count", "sum", "avg", "min", "max"
      # metric    = "@duration" # Required for sum/avg/min/max
    }
    group_by {
      facet = "@service"
      limit = 10
      sort {
        aggregation = "count"
        metric      = "count"
        order       = "desc"
      }
    }
    search {
      query = "source:myservice status:error $env"
    }
  }
}
```

---

## Common Kubernetes Metrics Reference

Frequently used in Kubernetes-aware dashboards:

```hcl
# Pods running
"avg:kubernetes.pods.running{$kube_namespace,$kube_cluster_name,pod_name:*myapp*}"

# Container restarts
"sum:kubernetes.containers.restarts{$kube_namespace,$kube_cluster_name,container_name:*myapp*} by {pod_name}.as_count()"

# OOM kills
"sum:kubernetes_state.container.status_report.count.oomkilled{$kube_namespace,$kube_cluster_name,container:*myapp*}.as_count()"

# Pod status phases
"sum:kubernetes_state.pod.status_phase{$kube_namespace,$kube_cluster_name,pod_name:*myapp*,phase:running} by {pod_name}"

# CPU usage
"avg:kubernetes.cpu.usage.total{$kube_namespace,$kube_cluster_name,pod_name:*myapp*} by {pod_name}"

# Memory usage
"avg:kubernetes.memory.usage{$kube_namespace,$kube_cluster_name,pod_name:*myapp*} by {pod_name}"
```
