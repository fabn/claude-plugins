---
name: rails:upgrade
description: |
  This skill should be used when upgrading a Rails application from one minor
  version to the next. Guides the full upgrade process: updating gems, running
  app:update, booting the app, fixing deprecation warnings, running tests, and
  progressively enabling new framework defaults. Enforces one minor version per
  invocation following Rails' official recommendation.
  Activates on: "upgrade rails", "upgrade to Rails", "rails upgrade",
  "update rails version", "bump rails", "next rails version",
  "rails version upgrade", "upgrade my rails app", "move to Rails",
  "rails upgrade path", "aggiornare rails", "aggiornamento rails".
---

# Rails Upgrade Skill

Upgrade a Rails application one minor version at a time, following the official
Rails upgrade guide. Each invocation handles a single version bump (e.g., 7.1→7.2,
not 7.1→8.0). For multi-version jumps, run this skill repeatedly.

**Reference files:** Consult `reference/version-changes.md` for breaking changes
and common gotchas per Rails version.

## Tools Used

- **Read**: Examine Gemfile, config files, initializers, deprecation output
- **Grep/Glob**: Find version references, deprecated API usage, config files
- **Bash**: Run bundle, rails tasks, test suite, console boot checks
- **Edit/Write**: Update Gemfile, config files, application code
- **AskUserQuestion**: Confirm file-by-file config decisions and risky defaults

## Workflow

### Step 1: Pre-flight Check

Establish the starting state before making any changes.

1. **Detect current Rails version**:
   ```bash
   bundle exec rails runner "puts Rails.version"
   ```

2. **Determine target version**: Ask the user which version to upgrade to, or
   default to the next minor version. Validate it's exactly one minor version
   ahead. If the user wants to skip versions, explain they should upgrade
   incrementally and offer to start with the next minor.

3. **Verify clean git state**:
   ```bash
   git status --porcelain
   ```
   If there are uncommitted changes, ask the user to commit or stash first.

4. **Run the test suite** to establish baseline health:
   ```bash
   bundle exec rspec --format progress
   ```
   Record the result. If tests are already failing, warn the user — it's best
   to start an upgrade from a green test suite. Ask if they want to proceed.

5. **Verify the app boots**:
   ```bash
   bin/rails runner "puts 'Boot OK: Rails ' + Rails.version"
   ```

6. **Capture existing deprecation warnings** (for comparison later):
   ```bash
   RUBYOPT="-W:deprecated" bin/rails runner "puts 'done'" 2>&1 | grep -i deprec
   ```
   Note these — some may already exist and should not be confused with
   upgrade-introduced warnings.

### Step 2: Update Gemfile

1. **Change the Rails gem version** in `Gemfile`:
   ```ruby
   gem 'rails', '~> X.Y.0'
   ```
   Where X.Y is the target version.

2. **Run bundle update**:
   ```bash
   bundle update rails
   ```

3. **Handle dependency conflicts**: If bundle update fails, read the error and
   resolve iteratively:
   - Identify conflicting gems from the error output
   - Update them alongside rails: `bundle update rails gem_a gem_b`
   - If a gem is incompatible with the target Rails, check for a newer version
     or alternative, and ask the user before making substitutions

4. **Verify the bundle resolves**:
   ```bash
   bundle check
   ```

5. **Commit the gem update**:
   ```bash
   git add Gemfile Gemfile.lock
   git commit -m "Update Rails to X.Y"
   ```

### Step 3: Run `app:update` Task

The `app:update` task updates config files, binstubs, and generates new
framework defaults.

```bash
bin/rails app:update
```

This produces file-by-file conflicts. Handle them as follows:

1. **Auto-revert `config/application.rb`**: This file almost never needs
   changes from the update task. Before reverting, check if `app:update`
   changed the `load_defaults` line — if so, keep the old `load_defaults`
   value (Step 9 handles that transition). Then revert:
   ```bash
   git checkout config/application.rb
   ```

2. **For each changed config file**, examine the diff:
   ```bash
   git diff config/
   ```

   For each file, use AskUserQuestion to present the diff and ask the user
   whether to:
   - **Accept** — keep the update's changes
   - **Reject** — revert to the previous version
   - **Merge** — keep specific parts (you'll need to edit manually)

   Guidelines for common files:
   - `config/environments/*.rb`: Review carefully. New settings are usually
     safe to accept. Removed settings may indicate deprecated config.
   - `config/initializers/`: Accept new initializers. Be cautious with changes
     to existing ones.
   - `bin/*`: Usually safe to accept (binstub updates).
   - `config/boot.rb`, `config/environment.rb`: Rarely change. Accept if
     they do.

3. **Accept whitespace-only or comment-only changes** unless they break
   linting. Don't bother the user with these.

4. **Commit accepted changes**:
   ```bash
   git add config/ bin/
   git commit -m "Update config files for Rails X.Y"
   ```

### Step 4: Boot Verification

Verify the application boots after the config changes:

```bash
bin/rails runner "puts 'Boot OK: Rails ' + Rails.version"
```

If it fails:
1. Read the error carefully
2. Common boot failures:
   - Missing gem (add to Gemfile, bundle install)
   - Removed config option (delete the line)
   - Changed initializer API (update to new syntax)
3. Fix the error, verify boot again, commit the fix:
   ```bash
   git add -A && git commit -m "Fix boot after Rails X.Y upgrade"
   ```
4. Repeat until the app boots cleanly

### Step 5: Run New Migrations

Check if the update task installed any new migrations:

```bash
bin/rails db:migrate:status | grep down
```

If there are pending migrations, invoke the `rails:migrate` skill workflow
to run them with a clean schema diff. Do not duplicate that workflow here —
reference it by name.

If no migrations are pending, skip this step.

### Step 6: Remove Deprecation Warnings

Capture deprecation warnings introduced by the upgrade:

```bash
RUBYOPT="-W:deprecated" bin/rails runner "puts 'done'" 2>&1 | grep -i deprec
```

Also run a quick test pass to surface runtime deprecations:

```bash
bundle exec rspec --format progress 2>&1 | grep -i deprec
```

Compare against the pre-upgrade warnings from Step 1. For each **new** warning:
1. Read the deprecation message — it usually tells you exactly what to change
2. Find the affected code with Grep
3. Apply the fix
4. Verify the warning is gone

Commit deprecation fixes as a group:
```bash
git add -A && git commit -m "Remove deprecation warnings for Rails X.Y"
```

### Step 7: Version-Specific Changes

Consult `reference/version-changes.md` for breaking changes specific to the
target version. Cross-reference with the project:

1. **Search for affected APIs**:
   ```bash
   # Example: if the upgrade guide says `before_filter` is removed
   grep -r "before_filter" app/
   ```

2. **Apply necessary changes** based on the reference file's guidance for this
   version pair

3. **Commit version-specific fixes**:
   ```bash
   git add -A && git commit -m "Apply version-specific changes for Rails X.Y"
   ```

If no version-specific changes affect the project, skip this step.

### Step 8: Run Test Suite

Run the full test suite, excluding slow JavaScript/system tests:

```bash
bundle exec rspec --format progress --tag ~js --tag ~system
```

If the project uses a different exclusion method (e.g., `--exclude-pattern`),
adapt accordingly:

```bash
bundle exec rspec --format progress --exclude-pattern "**/system/**"
```

For failures:
1. Group related failures (same root cause)
2. Fix one group at a time
3. Re-run affected specs to verify the fix
4. Commit each logical group of fixes:
   ```bash
   git add -A && git commit -m "Fix test failures after Rails X.Y upgrade"
   ```

If the system/JS tests were skipped, mention this to the user and suggest
running them separately after the upgrade is stable.

### Step 9: Configure Framework Defaults

The `app:update` task in Step 3 generated a file like
`config/initializers/new_framework_defaults_X_Y.rb`. This file contains all
new defaults commented out.

The goal is to enable each default, verify nothing breaks, and eventually
update `config.load_defaults` to the new version.

1. **Read the defaults file**:
   ```bash
   cat config/initializers/new_framework_defaults_X_Y.rb
   ```

2. **For each default setting**:
   a. Uncomment it (enable it)
   b. Check if the app boots: `bin/rails runner "puts 'OK'"`
   c. Run the test suite (or relevant subset)
   d. If tests pass → keep it enabled
   e. If tests fail → assess whether the failure is a real bug or expected
      behavior change. Use AskUserQuestion to ask the user about risky ones
      (e.g., encryption changes, cookie format changes, cache format changes)
   f. If the user defers a default, re-comment it with a `# TODO:` note

   **Batching tip:** Low-risk defaults (naming conventions, log formatting,
   whitespace behavior) can be enabled in batches. High-risk defaults
   (serialization formats, encryption, cache format versions) should be
   enabled one at a time with full test runs.

3. **After all safe defaults are enabled**, check if all settings are
   uncommented. If yes:
   - Delete the `new_framework_defaults_X_Y.rb` file
   - Update `config/application.rb`:
     ```ruby
     config.load_defaults X.Y
     ```
   - If some defaults were deferred, leave the file with only the deferred
     settings and keep `config.load_defaults` at the old version. Add a
     comment explaining why.

4. **Commit**:
   ```bash
   git add config/
   git commit -m "Enable Rails X.Y framework defaults"
   ```

## Error Handling

| Situation | Action |
|-----------|--------|
| Bundle update fails with conflicts | Identify conflicting gems, update them alongside rails, ask user about substitutions |
| App doesn't boot after gem update | Check error, fix missing/renamed gems or config, iterate |
| `app:update` overwrites custom config | Revert the file, apply only specific needed changes manually |
| Tests fail with unclear errors | Consult `reference/version-changes.md` for known breaking changes in the target version |
| Framework default breaks tests | Re-comment it, add TODO note, ask user about the expected behavior change |
| User wants to skip multiple versions | Explain incremental upgrade is safer, offer to start with the next minor |
| `rails:migrate` skill not available | Run migrations manually: `RAILS_ENV=test bin/rails db:migrate` and verify schema diff |
| Pre-existing test failures | Warn user, record baseline failures, distinguish them from upgrade-caused failures |

## Post-Upgrade Checklist

After completing all steps, summarize for the user:

- [ ] Rails version updated from A.B to X.Y
- [ ] All config files reviewed and committed
- [ ] App boots successfully
- [ ] Deprecation warnings resolved
- [ ] Test suite passing (note any skipped test categories)
- [ ] Framework defaults: all enabled / N deferred (list them)
- [ ] Commits are clean and logically grouped

## Reference Files

- **`reference/version-changes.md`** — Breaking changes and common gotchas per Rails version (7.0→7.1, 7.1→7.2, 7.2→8.0, 8.0→8.1)
