---
name: rails:test
description: |
  This skill should be used when the user wants to write, scaffold, or improve
  tests in a Ruby on Rails application. Covers RSpec organization, FactoryBot
  patterns, request/model/service specs, VCR setup for HTTP stubbing, and
  test-driven development workflows.
  Activates on: "write tests", "add specs", "rspec", "factory bot", "test this",
  "spec for", "scaffold test", "write spec", "missing tests", "test coverage",
  "VCR cassette", "stub http", "testing strategy", "TDD", "test driven",
  "rails test", "how to test", "scrivere test", "aggiungere spec".
---

# Rails Testing Skill

Scaffold and write tests for Rails applications using RSpec, FactoryBot, shoulda-matchers, and VCR. Follows project conventions for test organization and patterns.

**Reference files:** Consult `reference/patterns.md` for complete RSpec examples, FactoryBot patterns, and VCR configuration.

## Tools Used

- **Read**: Examine source code to understand what needs testing
- **Grep/Glob**: Find existing specs, factories, and test helpers
- **Write/Edit**: Create or update spec files and factories

## Workflow

### Step 1: Detect Project Conventions

Before writing any test, discover the project's testing setup:

1. **Test framework**: Check `Gemfile` for `rspec-rails` vs `minitest`
2. **Factory library**: `factory_bot_rails` (standard) or `fabrication`
3. **HTTP stubbing**: `vcr` + `webmock`, or `webmock` alone
4. **Matchers**: `shoulda-matchers`, `rspec-its`
5. **Test runner**: `bin/rspec` wrapper or plain `bundle exec rspec`
6. **Support files**: Read `spec/support/` for shared contexts, custom matchers, and helpers
7. **Rails helper**: Check `spec/rails_helper.rb` for included modules and configuration

Also check the project's `CLAUDE.md` for testing conventions.

### Step 2: Determine What to Test

Based on the user's request, identify:

| Source Code | Spec Type | Spec Location |
|-------------|-----------|---------------|
| `app/models/` | Model spec | `spec/models/` |
| `app/services/` | Service spec | `spec/services/` |
| `app/controllers/api/` | Request spec | `spec/api/` or `spec/requests/` |
| `app/graphql/mutations/` | GraphQL spec | `spec/graphql/mutations/` |
| `app/graphql/queries/` | GraphQL spec | `spec/graphql/queries/` |
| `app/jobs/` | Job spec | `spec/jobs/` |
| `app/policies/` | Policy spec | `spec/policies/` |
| `app/controllers/` | Request spec | `spec/requests/` |

Read the source file to understand:
- Public methods to test
- Edge cases and error paths
- External dependencies to mock
- Associations and validations (for models)

### Step 3: Check for Existing Specs and Factories

1. **Existing spec**: Search for a spec file matching the source:
   ```
   Glob: spec/**/*<model_name>*_spec.rb
   ```

2. **Existing factory**: Search for the factory:
   ```
   Glob: spec/factories/*<model_name>*.rb
   ```

3. **Related specs**: Find specs that test similar patterns in the project to match style:
   ```
   Glob: spec/<type>/*_spec.rb (read 1-2 examples)
   ```

If a spec exists, read it first and add to it rather than creating a new file.

### Step 4: Create or Update Factory

If the model doesn't have a factory yet, create one:

1. **Place in** `spec/factories/<plural_model_name>.rb`
2. **Include**:
   - Required attributes with sensible defaults
   - `sequence` for unique fields
   - `association` for belongs_to
   - `trait` blocks for variations (states, roles, edge cases)

Follow the project's existing factory style. See `reference/patterns.md` for examples.

### Step 5: Write the Spec

Write the spec following these principles:

**Structure:**
- Use `describe` for the class/method being tested
- Use `context` for different scenarios ("when valid", "when unauthorized")
- Use `it` with descriptive strings (not `it { should ... }` for complex behavior)
- One assertion per example where practical

**For model specs:**
- Associations with shoulda-matchers: `it { is_expected.to belong_to(:user) }`
- Validations with shoulda-matchers: `it { is_expected.to validate_presence_of(:name) }`
- Scopes: test return values
- Instance methods: test behavior with different inputs
- State machines: test transitions and guards

**For service specs:**
- Instantiate with `described_class.new(args)`
- Test the public interface (usually `.call` or the primary method)
- Mock external dependencies (HTTP, email, etc.)
- Test success and failure paths
- Test side effects (database changes, jobs enqueued, emails sent)

**For request specs:**
- Test HTTP status codes
- Test response body structure
- Test authentication/authorization
- Test error responses (422, 404, 403)
- Use `let` for setup, avoid `before` blocks when `let` suffices

**For job specs:**
- Test `perform` directly
- Test enqueue behavior if relevant
- Test idempotency for critical jobs
- Mock external services

### Step 6: Handle External Dependencies

When the code under test makes HTTP calls:

1. **Check for VCR**: If the project uses VCR, record cassettes:
   ```ruby
   it "fetches data", :vcr do
     result = service.call
     expect(result).to be_success
   end
   ```
   Cassettes are stored in `spec/cassettes/` (or `spec/fixtures/vcr_cassettes/`)

2. **If no VCR**: Use webmock stubs:
   ```ruby
   stub_request(:get, "https://api.example.com/data")
     .to_return(status: 200, body: { result: "ok" }.to_json)
   ```

3. **For Sidekiq jobs**: Use `have_enqueued_sidekiq_job` or test inline with `Sidekiq::Testing.inline!`

4. **For email**: Use `ActionMailer::Base.deliveries` or `have_enqueued_mail`

### Step 7: Run and Verify

After writing the spec:

1. **Run the specific spec**:
   ```bash
   bundle exec rspec spec/path/to/new_spec.rb
   ```

2. **Check for failures** and fix:
   - Missing factories -> create them
   - Database state issues -> check `let`/`let!` ordering
   - Flaky time-dependent tests -> use `travel_to` or `freeze_time`

3. **Run RuboCop on the spec**:
   ```bash
   bundle exec rubocop spec/path/to/new_spec.rb
   ```

4. **Suggest next steps**:
   - "Want me to add more edge case tests?"
   - "Should I check test coverage for this module?"
   - "Want me to write specs for related files?"

## Error Handling

| Situation | Action |
|-----------|--------|
| No RSpec in project | Check for Minitest, suggest setup if neither exists |
| Factory not found | Create it based on model schema (`db/schema.rb`) |
| VCR cassette expired | Suggest re-recording with `VCR_RECORD=all bundle exec rspec spec/path` |
| Database schema mismatch | Suggest `RAILS_ENV=test rails db:drop db:create db:schema:load` |
| Flaky test (time-dependent) | Use `travel_to(Time.zone.parse("2024-01-15 10:00"))` block |
| Missing test database | Suggest `RAILS_ENV=test rails db:prepare` |

## Reference Files

- **`reference/patterns.md`** — Complete RSpec examples for models, services, requests, jobs, and policies with FactoryBot and VCR patterns
