---
name: rails:refactor
description: |
  This skill should be used when the user wants to refactor Ruby on Rails code
  by extracting service objects, concerns, query objects, form objects, or
  DelegateClass wrappers. Identifies code smells and applies established Rails
  refactoring patterns.
  Activates on: "refactor", "extract service", "extract concern", "fat model",
  "fat controller", "code smell", "service object", "query object", "form object",
  "too complex", "simplify", "extract class", "single responsibility",
  "rails refactor", "clean up code", "rifattorizzare", "estrarre servizio".
---

# Rails Refactoring Skill

Identify code smells in Rails applications and apply established refactoring patterns. Extracts service objects, concerns, query objects, form objects, and DelegateClass wrappers following project conventions.

**Reference files:** Consult `reference/patterns.md` for complete code examples of each extraction pattern.

## Tools Used

- **Read**: Examine the code to refactor and existing patterns in the project
- **Grep/Glob**: Find existing services, concerns, and patterns to match style
- **Write/Edit**: Create new files and update existing ones

## Workflow

### Step 1: Analyze the Code

Read the code the user wants to refactor and identify the smell:

| Code Smell | Indicator | Extraction Target |
|------------|-----------|-------------------|
| Fat controller | Controller action > 15 lines, business logic in controller | Service object |
| Fat model | Model file > 200 lines, mixed responsibilities | Concern or service |
| Repeated query patterns | Same `.where().order().limit()` chain in multiple places | Query object / scope |
| Complex form handling | Multi-model form, conditional validations | Form object |
| Decorator logic | Display formatting, computed properties in model | DelegateClass wrapper |
| Callback chains | Long `before_save` / `after_create` chains with side effects | Service object |
| God service | Service > 100 lines, doing too many things | Split into focused services |

### Step 2: Discover Project Conventions

Before creating any new files, find existing patterns:

1. **Service objects**: Check `app/services/` for naming and structure
   ```
   Glob: app/services/**/*.rb
   ```
   Look for:
   - Initialization pattern: `initialize` with kwargs? Positional args?
   - Call pattern: `.call` class method? Instance `#call`? Custom method names?
   - Return pattern: Plain value? Result/Data object? Boolean?
   - Logging: `SemanticLogger::Loggable`? `Rails.logger`?
   - Error handling: Custom exceptions? `ActiveRecord::RecordInvalid`?

2. **Concerns**: Check `app/models/concerns/` for naming and style
   ```
   Glob: app/models/concerns/**/*.rb
   ```

3. **Namespacing**: Check if services are namespaced by domain
   ```
   ls app/services/  (look for subdirectories)
   ```

4. **Read project CLAUDE.md** for explicit style conventions

### Step 3: Plan the Extraction

Present the refactoring plan to the user before making changes:

```
## Refactoring Plan

**Current**: OrdersController#create (45 lines, handles validation, payment, notification)

**Proposed**:
1. Extract `OrderCreationService` to `app/services/order_creation_service.rb`
   - Handles: validation, payment processing, order creation
   - Returns: the created Order or raises on failure
2. Slim controller to: instantiate service, call, respond

**Files to create:**
- app/services/order_creation_service.rb
- spec/services/order_creation_service_spec.rb

**Files to modify:**
- app/controllers/api/orders_controller.rb (slim down #create)
```

Wait for user approval before proceeding.

### Step 4: Extract the Code

Apply the appropriate pattern from `reference/patterns.md`:

#### For Service Object Extraction:

1. Create the service file following project conventions
2. Move business logic from controller/model into the service
3. Keep the service focused on one responsibility
4. Add proper error handling (raise on failure, or return result)
5. Update the original file to delegate to the service
6. Ensure all associations and queries are properly scoped

#### For Concern Extraction:

1. Identify the cohesive group of methods to extract
2. Create the concern with `extend ActiveSupport::Concern`
3. Move methods, validations, associations, callbacks, and scopes
4. Use `included` block for class-level declarations
5. Include the concern in the original model
6. Verify no hidden dependencies on methods remaining in the model

#### For Query Object Extraction:

1. Create a query class that wraps an ActiveRecord scope
2. Initialize with a base relation (default to `.all`)
3. Add chainable filter methods
4. Return an ActiveRecord::Relation (not arrays)
5. Replace inline query chains with query object calls

#### For DelegateClass Wrapper:

1. Use `DelegateClass(ModelName)` to wrap the model
2. Add computed properties and display logic
3. Do NOT add persistence logic (no `save`, `update`)
4. Initialize by passing the model instance

### Step 5: Update Tests

After extracting code:

1. **Create specs for the new class** following the project's test patterns
2. **Update existing specs** that tested the behavior in its old location
3. **Ensure coverage**: The extracted code should have at least:
   - Success path test
   - Failure/error path test
   - Edge cases relevant to the business logic
4. **Run the full test suite** for the affected area

### Step 6: Verify the Refactoring

After applying changes:

1. **Run affected specs**:
   ```bash
   bundle exec rspec spec/services/new_service_spec.rb spec/controllers/affected_controller_spec.rb
   ```

2. **Run RuboCop** on new and changed files:
   ```bash
   bundle exec rubocop app/services/new_service.rb app/controllers/affected_controller.rb
   ```

3. **Check for loose ends**:
   - Are there other callers of the extracted code?
   - Did we leave any dead code behind?
   - Do all tests still pass?

4. **Suggest next steps**:
   - "Want me to check for similar patterns elsewhere?"
   - "Should I add more tests for edge cases?"
   - "This model still has X responsibilities — want to extract more?"

## Error Handling

| Situation | Action |
|-----------|--------|
| No existing service pattern in project | Use the standard `initialize` + method pattern, explain the convention |
| Mixed concerns hard to separate | Suggest incremental extraction — start with the most cohesive group |
| Circular dependencies after extraction | Suggest dependency injection or event-driven approach |
| Tests break after extraction | Check for missing `let` definitions, factory changes, or mock updates |
| RuboCop violations in new code | Fix before presenting to user |
| User disagrees with extraction boundary | Discuss trade-offs, adjust the plan |

## Reference Files

- **`reference/patterns.md`** — Complete code examples for service objects, concerns, query objects, form objects, and DelegateClass wrappers with before/after comparisons
