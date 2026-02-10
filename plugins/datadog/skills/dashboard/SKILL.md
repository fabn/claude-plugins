---
name: datadog-dashboard
description: |
  Create and manage Datadog monitoring dashboards via Terraform. Handles metric discovery
  using Datadog MCP, widget layout design, template variables, and team assignment.
  Activates on: "create dashboard", "datadog dashboard", "new dashboard", "add dashboard",
  "dashboard for", "monitor dashboard", "creare dashboard", "nuova dashboard".
---

# Datadog Dashboard Skill

Create production-quality Datadog dashboards as Terraform HCL. This skill discovers metrics, designs grouped widget layouts, and generates formatted Terraform code ready to plan and apply.

## Tools Used

- **Datadog MCP** (if configured): Metric listing, tag discovery, metadata inspection
- **WebFetch**: Datadog docs and integrations-core CSV for metric metadata
- **Grep/Glob**: Discover project conventions (file placement, teams, provider config)
- **Write/Edit**: Generate Terraform HCL files
- **Bash**: `terraform fmt` validation

## Workflow

### Step 1: Requirements Gathering

Parse the user's request to determine:
- **Integration/topic**: What to monitor (e.g., Redis, Sidekiq, Puma, custom app)
- **New or modify**: Creating a new dashboard or adding widgets to an existing one
- **Specific concerns**: Any particular metrics or failure modes the user cares about

If the request is vague, ask:
> "What specific aspects of [topic] do you want to monitor? For example: throughput, errors, latency, resource usage, queue depth?"

### Step 2: Team Assignment

Datadog dashboards only support `team:xxx` tags.

1. **Check project context**: Look for team definitions in the project's CLAUDE.md files or Terraform files (search for `datadog_team` resources)
2. **Present options**: List discovered teams and ask which to assign
3. **Support "skip"**: User can choose no team tag
4. **Format**: `tags = ["team:<handle>"]`

### Step 3: Metric Discovery

Run all applicable strategies **in parallel** for comprehensive coverage. See `reference/metric-discovery.md` for full details.

**Strategy A - Datadog MCP (preferred):**
```
ToolSearch("datadog")
```
Use available tools to list metrics matching the integration prefix, inspect tags and units.

**Strategy B - Datadog Documentation:**
```
WebFetch: https://docs.datadoghq.com/integrations/<integration>/?tab=host
```
Extract the "Data Collected" > "Metrics" section.

**Strategy C - integrations-core CSV:**
```
WebFetch: https://raw.githubusercontent.com/DataDog/integrations-core/master/<integration>/metadata.csv
```
Parse CSV for metric_name, unit_name, per_unit_name, description, orientation.

**After discovery**, present findings to user:
- List metrics grouped by category (throughput, errors, latency, resources)
- Include units and descriptions
- Suggest which metrics to include and which to skip
- Note any metrics that couldn't be found (may require custom instrumentation)

### Step 4: Template Variables (Filters)

Design dashboard filters based on discovered metric tags:

1. **ALWAYS include `env`** with production-like default (check project conventions - `prod` or `production`)
2. **Propose additional filters** based on tag keys found during discovery:
   - Kubernetes: `kube_namespace`, `kube_cluster_name`
   - Service: `service`
   - Integration-specific: varies (e.g., `queue` for Sidekiq, `db` for Redis)
3. **Present to user** for confirmation/modification

### Step 5: Widget Layout Design

Organize widgets following the design guidelines below:

1. **Group widgets logically** with `group_definition` using colored backgrounds
2. **Select widget types** per metric (see Widget Type Selection below)
3. **Present proposed layout** to user as a structured outline:
   ```
   Group: "Overview KPIs" (vivid_blue)
     - [query_value 3x2] Total Requests
     - [query_value 3x2] Error Rate
     - [query_value 3x2] Avg Latency

   Group: "Traffic" (vivid_green)
     - [timeseries 12x4] Requests Over Time

   Group: "Errors" (vivid_pink)
     - [timeseries 8x4] Errors by Type
     - [sunburst 4x4] Error Breakdown
   ```
4. **Get user approval** before generating code

### Step 6: Terraform Code Generation

1. **Discover file placement**: Search for existing Datadog dashboard files in the project, or check project CLAUDE.md for conventions
2. **Generate HCL** following patterns from `reference/widget-patterns.md`:
   - Ordered layout with fixed reflow
   - All widgets in groups
   - Conditional formats on all query_value widgets
   - Legends on all multi-series timeseries
   - Units on all metric widgets
   - Template variable references in all queries
3. **Include outputs**: `dashboard_id` and `dashboard_url`
4. **Write file** to the discovered/agreed location

### Step 7: Validation

1. Run `terraform fmt` on generated files
2. Suggest running project-specific plan command (e.g., `/terraform-plan datadog`)
3. Verify template variable references in queries match `template_variable` blocks
4. Check total widget count - warn if exceeding ~20 widgets

## Dashboard Design Guidelines

### Layout Rules

- `layout_type = "ordered"`, `reflow_type = "fixed"` (always)
- 12-column grid system
- Groups span full width (12 columns) unless intentionally side-by-side

### Widget Groups (REQUIRED)

ALL widgets MUST be organized in `group_definition` blocks:
- `show_title = true`, descriptive title
- `background_color` from the semantic palette:

| Color | Use For |
|-------|---------|
| `vivid_blue` | Overview, KPIs, general information |
| `vivid_green` | Health, success, availability |
| `vivid_orange` | Warnings, degradation |
| `vivid_pink` | Errors, failures |
| `vivid_purple` | Performance, latency |
| `vivid_yellow` | Alerts, attention items |
| `gray` | Logs, events, auxiliary data |
| `white` | Neutral, documentation notes |

### Widget Type Selection

| Metric Category | Widget Type | Key Config |
|-----------------|-------------|------------|
| Single KPI value | `query_value` | `conditional_formats` (MUST), `timeseries_background`, `autoscale` |
| Trend over time | `timeseries` | `show_legend = true` (MUST for multi-series), `legend_columns`, formula `alias` |
| Category breakdown | `sunburst` | `legend_table`, grouped by tags |
| Top N ranking | `toplist` | `conditional_formats`, limit |
| Tabular data | `query_table` | `cell_display_mode`, multiple formulas |
| Distribution | `heatmap` | For latency, size distributions |
| Period comparison | `change` | `week_before()`, `increase_good` |
| Log stream | `list_stream` | `data_source = "logs_stream"`, columns |
| Event timeline | `event_timeline` | `tags_execution = "and"` |
| Health check | `check_status` | `grouping = "cluster"` |
| Monitor overview | `manage_status` | `display_format = "countsAndList"` |
| SLO summary | `slo_list` | `request_type = "slo_list"` |

### Standard Widget Sizes

| Widget Type | Size (WxH) | Notes |
|-------------|------------|-------|
| `query_value` | 2x2, 3x2, 4x2 | KPI row at top of groups |
| `timeseries` | 6x3, 6x4, 12x4 | Half or full width |
| `sunburst` | 3x3, 4x4 | Alongside timeseries |
| `query_table` | 6x3, 12x4 | Tabular breakdowns |
| `toplist` | 3x3, 4x4 | Ranking panels |
| `change` | 2x4, 2x5 | Narrow vertical column |
| `list_stream` | 5x3, 6x4 | Log panels |
| `check_status` | 3x3 | Health indicators |

### Query Value Rules

- MUST have `conditional_formats` with green/yellow/red thresholds
- SHOULD have `timeseries_background` (`type = "bars"` for counts, `"area"` for continuous)
- SHOULD have `autoscale = true`
- Set `custom_unit` when auto-detection fails
- Use `precision = 0` for integers, `2-3` for decimals

### Timeseries Rules

- MUST have `show_legend = true` when displaying multiple series
- Use `legend_layout = "auto"`, `legend_columns = ["avg", "max", "value"]`
- Each request SHOULD have a formula with `alias` for readable legend labels
- `display_type`: `line` for continuous, `bars` for counts/rates, `area` for cumulative
- Semantic `style.palette`: `green` for success, `red` for errors, `blue`/`dog_classic` for neutral

### Units of Measure

ALL metric widgets MUST display correct units. Derive from (in priority order):
1. integrations-core `metadata.csv` `unit_name` column
2. Datadog MCP metric metadata
3. Metric name inference (`.seconds` -> second, `.bytes` -> byte, `.count` -> autoscale)
4. Ask user

### Template Variables

- ALWAYS include `env` filter with production default
- Add filters for core dimensions relevant to the topic
- Use `prefix` matching the tag key
- `defaults = ["*"]` for optional filters, specific value for required ones
- Reference in queries as `$variable_name`

### Dashboard Splitting

When a dashboard exceeds ~20 widgets or covers too many unrelated concerns:
- Suggest splitting into multiple focused dashboards
- Each sub-dashboard should be self-contained with its own template variables
- Consider using `datadog_dashboard_list` to group related dashboards

### Tags

- Datadog dashboards only support `team:xxx` tags
- Format: `tags = ["team:<handle>"]`
- Additional tags (integration, managed_by) are for monitors/SLOs, not dashboards

## Reference Files

- **`reference/widget-patterns.md`** - Complete HCL code patterns for every widget type with inline comments
- **`reference/metric-discovery.md`** - Detailed metric research workflow using MCP, docs, and CSV sources

## Error Handling

| Situation | Action |
|-----------|--------|
| Datadog MCP not available | Warn user, proceed with docs/CSV discovery only |
| No metrics found for integration | Ask user to provide metric names manually |
| Integration not in integrations-core | Try `integrations-extras` repo, then fall back to docs |
| Terraform not initialized | Suggest `terraform init -backend=false` in module directory |
| Dashboard >20 widgets | Warn and suggest splitting strategy |
| Template variable mismatch | Cross-check all `$var` references against `template_variable` blocks |
| `terraform fmt` fails | Fix formatting issues before presenting to user |
