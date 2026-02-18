# Rails Plugin

Ruby on Rails development workflows. Includes debugging and performance profiling, test scaffolding with RSpec and FactoryBot, refactoring patterns for service objects and concerns, a clean migration workflow, and guided Rails version upgrades.

## Skills

| Skill | Description |
|-------|-------------|
| `/rails:debug` | N+1 query detection, query analysis, memory profiling, index analysis |
| `/rails:test` | RSpec scaffolding, FactoryBot patterns, VCR setup, test organization |
| `/rails:refactor` | Extract service objects, concerns, query objects, form objects, DelegateClass wrappers |
| `/rails:migrate` | Run migrations with clean schema diffs using test database as source of truth |
| `/rails:upgrade` | Guided Rails version upgrade, one minor version at a time |

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
/rails:upgrade upgrade to Rails 7.2
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

### `/rails:upgrade`

Guides a Rails version upgrade one minor version at a time:
1. Pre-flight check — detect versions, verify clean git state and green tests
2. Update Gemfile and resolve dependency conflicts
3. Run `app:update`, review config changes file-by-file with user
4. Verify the app boots
5. Run new migrations (delegates to `rails:migrate`)
6. Fix deprecation warnings introduced by the upgrade
7. Apply version-specific breaking changes from reference guide
8. Run test suite (skipping JS/system tests), fix failures
9. Enable new framework defaults one at a time, update `config.load_defaults`

Each logical group of changes gets its own commit. Includes reference documentation covering breaking changes for Rails 7.0→7.1, 7.1→7.2, 7.2→8.0, and 8.0→8.1.
