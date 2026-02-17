---
name: rails:migrate
description: |
  This skill should be used when running Rails database migrations and committing
  the resulting schema changes. Ensures a clean schema diff by running migrations
  against the test database reset from main, not the potentially dirty development
  database. Activates on: "run migration", "run migrations", "migrate database",
  "commit migration", "db:migrate", "schema change", "clean schema diff",
  "migration workflow", "eseguire migrazione", "lanciare migrazione".
---

# Run Migration Skill

Run Rails database migrations with a clean schema diff by using the test database
as the source of truth, avoiding dirty development database artifacts.

## Why This Workflow

The development database schema (`db/schema.rb`) often drifts from `main` due to
experimental migrations, manual changes, or out-of-order branch switches. Running
`db:migrate` against development produces a noisy schema diff that includes
unrelated changes. This workflow uses the test database to produce a minimal,
correct schema diff containing only the migration's changes.

## Workflow

### Step 1: Identify Pending Migrations

List migration files not yet committed or recently created:

```bash
git status db/migrate/
git diff --name-only main -- db/migrate/
```

If no pending migrations exist, inform the user and stop.

### Step 2: Reset Test Database from Main Schema

Restore `db/schema.rb` from `main` and rebuild the test database from scratch:

```bash
git restore --source=main --worktree db/schema.rb
RAILS_ENV=test bin/rails db:drop db:create db:schema:load
```

This ensures the test database matches the production schema before applying
the new migration.

### Step 3: Run Migration Against Test

```bash
RAILS_ENV=test bin/rails db:migrate
```

### Step 4: Verify Schema Diff

Check that the schema diff contains only the expected changes:

```bash
git diff db/schema.rb
```

Verify:
- The `version` timestamp matches the new migration
- Only the intended table/index/column changes appear
- No unrelated changes leaked in

If the diff looks wrong, stop and report to the user.

### Step 5: Test Reversibility

If the migration uses `change` (reversible), verify it can be rolled back and
re-applied cleanly:

```bash
RAILS_ENV=test bin/rails db:migrate:redo
```

Then re-check the schema diff — it should be identical to Step 4:

```bash
git diff db/schema.rb
```

If the migration uses `up`/`down` explicitly, skip this step unless the user
requests it.

### Step 6: Commit

Stage and commit only the migration file(s) and `db/schema.rb`:

```bash
git add db/migrate/<migration_file> db/schema.rb
git commit -m "<message>"
```

Do not stage other files. The commit message should describe what the migration
does (not that a migration was run).

### Step 7: Optionally Run in Development

Ask the user if they want to also run the migration in the development
environment. If yes:

```bash
bin/rails db:migrate
```

Then discard any development-specific schema changes that differ from the
already-committed clean schema:

```bash
git checkout db/schema.rb
```

This keeps the committed schema clean while ensuring the development database
is up to date.

## Error Handling

| Situation | Action |
|-----------|--------|
| Test DB drop fails (connections) | Run `RAILS_ENV=test bin/rails db:drop DISABLE_DATABASE_ENVIRONMENT_CHECK=1` |
| Schema load fails | Check for missing extensions or dependencies, report to user |
| Migration fails | Report the error, do not commit, leave test DB in failed state for debugging |
| Redo produces different diff | Migration is not cleanly reversible — warn the user |
| Unrelated schema changes appear | The main branch schema may have diverged — suggest rebasing first |
