---
name: rails:debug
description: |
  This skill should be used when the user wants to debug performance issues,
  investigate N+1 queries, analyze slow requests, profile memory usage, or
  understand query patterns in a Ruby on Rails application.
  Activates on: "debug performance", "N+1 queries", "slow request", "query analysis",
  "memory profiling", "rails performance", "find slow queries", "bullet",
  "why is this slow", "optimize queries", "eager loading", "database performance",
  "debug rails", "profile request", "analizzare performance", "query lente".
---

# Rails Debug & Profiling Skill

Investigate and resolve performance issues in Rails applications. Covers N+1 query detection, query analysis, memory profiling, and request performance investigation.

**Reference files:** Consult `reference/patterns.md` for detection techniques, profiling tools, and optimization patterns.

## Tools Used

- **Read**: Examine models, controllers, and query patterns
- **Grep/Glob**: Find eager loading gaps, query hotspots, and association chains
- **Bash**: Run profiling commands, query analysis, and benchmarks

## Workflow

### Step 1: Identify the Problem Type

Determine what kind of performance issue the user is investigating:

| Symptom | Problem Type | Investigation Path |
|---------|-------------|-------------------|
| Slow page/endpoint | Query N+1 or missing index | Step 2 |
| High memory usage | Object allocation or large dataset | Step 3 |
| Slow background job | Inefficient queries or external calls | Step 2 + Step 4 |
| General "it's slow" | Need profiling data first | Step 4 |

If the user describes a specific endpoint or action, read the relevant controller and model code first.

### Step 2: N+1 Query Detection

Analyze the code path for N+1 patterns:

1. **Read the controller action** to identify which models are loaded
2. **Trace the association chain**:
   - What associations does the view/serializer access?
   - Are collections iterated with nested association access?
   - Are there `has_many` through chains?

3. **Search for missing eager loads**:
   ```
   Grep for: .each, .map, .select, .find_each in the controller/service
   Then check: does each iteration access an association not in includes/preload?
   ```

4. **Check existing eager loading**:
   ```
   Grep for: .includes(, .preload(, .eager_load( in the relevant scope/controller
   ```

5. **Propose fix** with the appropriate loading strategy:
   - `includes` — lets Rails decide (usually preload, switches to eager_load if WHERE references the association)
   - `preload` — always separate queries (one per association), best for has_many
   - `eager_load` — LEFT OUTER JOIN, needed when filtering/sorting by association

6. **For GraphQL APIs**: Check for DataLoader/BatchLoader usage:
   - Look in `app/graphql/loaders/` for existing batch loaders
   - If missing, suggest creating one following the project's loader pattern
   - Check `GraphQL::Batch` or `dataloader` usage

### Step 3: Memory Investigation

When investigating memory issues:

1. **Identify large dataset loading**:
   ```
   Grep for: .all, .to_a, .load on large tables
   Grep for: .pluck vs .select (pluck avoids AR instantiation)
   ```

2. **Check for unbounded queries**:
   - Missing `.limit` on user-facing queries
   - `.find_each` / `.in_batches` not used for bulk operations
   - Large `includes` chains loading entire association trees

3. **Suggest memory-efficient alternatives**:
   - `.find_each(batch_size: 1000)` instead of `.each` for large sets
   - `.pluck(:id, :name)` instead of `.select(:id, :name).map { ... }`
   - `.in_batches.update_all(...)` instead of loading + iterating + saving
   - Streaming CSV/JSON responses for exports

4. **For background jobs**: Check if the job loads more data than needed. Suggest passing IDs and re-querying with scoped selects.

### Step 4: Request Profiling

When the user needs to profile a specific request:

1. **Check if profiling tools are available**:
   ```
   Grep Gemfile for: rack-mini-profiler, bullet, memory_profiler, benchmark-ips, stackprof
   ```

2. **If Bullet is configured**, guide the user to check Bullet output:
   - Look for `Bullet.enable` in development config
   - Check `log/bullet.log` for detected N+1s
   - Review `config/environments/development.rb` for Bullet settings

3. **If rack-mini-profiler is available**, suggest:
   - `?pp=flamegraph` for request flamegraph
   - `?pp=profile-gc` for GC profiling
   - `?pp=analyze-memory` for memory analysis

4. **For production issues** (no profiling tools):
   - Check Datadog APM traces if configured (suggest `/datadog:traces`)
   - Analyze `log/development.log` for query counts and timings
   - Use `ActiveSupport::Notifications` to instrument specific code paths

5. **Quick benchmarking** for isolated code:
   ```ruby
   # In rails console
   require 'benchmark'
   Benchmark.bm do |x|
     x.report("current") { current_implementation }
     x.report("optimized") { optimized_implementation }
   end
   ```

### Step 5: Index Analysis

When queries are slow due to missing indexes:

1. **Find the slow query** from logs or Datadog traces
2. **Check existing indexes**:
   ```
   Read db/schema.rb, search for the table name
   Look at add_index lines for the relevant columns
   ```
3. **Analyze query patterns**:
   - WHERE clauses need indexes on filtered columns
   - ORDER BY clauses benefit from indexes
   - JOIN conditions need indexes on foreign keys
   - Composite indexes: column order matters (most selective first)

4. **Generate migration** for missing indexes:
   ```ruby
   add_index :table_name, :column_name
   add_index :table_name, [:col1, :col2]  # composite covers col1 queries too
   ```

5. **Warn about redundant indexes** (per project conventions):
   - A composite index `[:email, :locale]` already covers queries on `email` alone
   - Don't add both `add_index :t, :email` and `add_index :t, [:email, :locale]`

### Step 6: Present Findings

Summarize the investigation with:
- **Root cause**: What's causing the performance issue
- **Impact**: How it affects response time / memory / database load
- **Fix**: Specific code changes with before/after
- **Verification**: How to confirm the fix works (query count, response time, memory)

Suggest follow-up actions:
- "Want me to implement the fix?"
- "Should I check for similar patterns elsewhere in the codebase?"
- "Want to profile after the fix to verify improvement?"

## Error Handling

| Situation | Action |
|-----------|--------|
| No profiling gems installed | Suggest adding bullet/rack-mini-profiler to Gemfile development group |
| Cannot reproduce in development | Suggest using Datadog APM traces from production (`/datadog:traces`) |
| Complex association chain | Draw the association path as a diagram before suggesting fixes |
| Multiple N+1s in same endpoint | Prioritize by frequency (most iterations first), fix in one `includes` chain |
| Schema file not found | Check for `db/structure.sql` as alternative to `db/schema.rb` |

## Reference Files

- **`reference/patterns.md`** — Common N+1 patterns, eager loading strategies, memory optimization techniques, and profiling tool configurations
