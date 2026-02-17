# Rails Plugin

Ruby on Rails development workflows. Includes debugging and performance profiling, test scaffolding with RSpec and FactoryBot, refactoring patterns for service objects and concerns, and a clean migration workflow.

## Skills

| Skill | Description |
|-------|-------------|
| `/rails:debug` | N+1 query detection, query analysis, memory profiling, index analysis |
| `/rails:test` | RSpec scaffolding, FactoryBot patterns, VCR setup, test organization |
| `/rails:refactor` | Extract service objects, concerns, query objects, form objects, DelegateClass wrappers |
| `/rails:migrate` | Run migrations with clean schema diffs using test database as source of truth |

## Prerequisites

- A Ruby on Rails application
- RSpec and FactoryBot (for the test skill)
- No MCP servers or API keys required

## Getting Started

Install the plugin and invoke a skill:

```
/rails:debug find N+1 queries in the orders controller
/rails:test write specs for OrderCreationService
/rails:refactor extract a service from OrdersController#create
/rails:migrate
```

## Skill Details

### `/rails:debug`

Investigates performance issues in Rails applications:
1. Identifies the problem type (N+1, memory, slow query, general)
2. Traces association chains and finds missing eager loads
3. Analyzes memory usage patterns (unbounded queries, missing batching)
4. Guides profiling with Bullet, rack-mini-profiler, or Datadog APM
5. Checks for missing database indexes
6. Presents findings with before/after fixes

Includes reference patterns for eager loading strategies (`includes` vs `preload` vs `eager_load`), GraphQL DataLoader/BatchLoader, and Bullet configuration.

### `/rails:test`

Scaffolds and writes tests following project conventions:
1. Detects project testing setup (framework, factories, HTTP stubbing, matchers)
2. Determines spec type from source location (model, service, request, job, policy)
3. Finds existing specs and factories to match style
4. Creates or updates FactoryBot factories with traits
5. Writes specs with proper structure (describe/context/it)
6. Handles external dependencies (VCR cassettes, webmock stubs, Sidekiq testing)
7. Runs and verifies the new specs

Includes reference patterns for model, service, request, job, and policy specs, plus FactoryBot and VCR configuration.

### `/rails:refactor`

Identifies code smells and applies extraction patterns:
1. Analyzes code to identify the smell (fat controller, fat model, callback chains, etc.)
2. Discovers existing project conventions (service style, concern patterns, namespacing)
3. Plans the extraction with file list and presents for approval
4. Extracts code following the appropriate pattern
5. Updates tests for the new and modified code
6. Runs specs and RuboCop to verify

Supported extractions:
- **Service objects** — from fat controllers or callback chains
- **Concerns** — from fat models with mixed responsibilities
- **Query objects** — from repeated query chains
- **Form objects** — from multi-model form handling
- **DelegateClass wrappers** — from display/decorator logic in models

### `/rails:migrate`

Runs migrations with a clean schema diff:
1. Identifies pending migrations
2. Resets test database from main's `db/schema.rb`
3. Runs migration against test (not development)
4. Verifies the schema diff contains only expected changes
5. Tests reversibility with `db:migrate:redo`
6. Commits only migration files and `db/schema.rb`
7. Optionally runs in development and discards schema noise

This avoids the common problem of development database drift producing noisy, unrelated changes in `db/schema.rb`.
