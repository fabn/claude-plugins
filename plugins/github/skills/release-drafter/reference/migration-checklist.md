# Migration Checklist: release-drafter v6 to v7

Reference document for the `github:release-drafter` skill. Each H2 section is a lookup unit read independently.

For complete YAML templates, see `config-reference.md`.

---

## v6 vs v7 Differences

Side-by-side comparison of the key changes between release-drafter v6 and v7.

| Feature | v6 | v7 |
|---------|----|----|
| Action reference | `release-drafter/release-drafter@v6` | `release-drafter/release-drafter@v7` |
| Token handling | `env: GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}` | `with: token: ${{ github.token }}` (defaults to `github.token`) |
| Autolabeler architecture | Embedded in monolithic action; controlled by `disable-releaser`/`disable-autolabeler` flags | Separate action path `release-drafter/release-drafter/autolabeler@v7` available (monolithic still valid) |
| Main drafter permissions | `pull-requests: write` | `pull-requests: read` (write only needed for autolabeler job) |
| `version` input | Not available | Available — overrides semver resolution (enables CalVer) |
| Node runtime | Node 16 | Node 24 |

**Token handling inline snippets:**

v6:
```yaml
- uses: release-drafter/release-drafter@v6
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

v7:
```yaml
- uses: release-drafter/release-drafter@v7
  with:
    token: ${{ github.token }}
```

**Action reference change:**
- v6: `uses: release-drafter/release-drafter@v6`
- v7: `uses: release-drafter/release-drafter@v7`

---

## Token Handling Migration

In v6, the token was passed as an environment variable:

```yaml
env:
  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

In v7, the token is a named action input:

```yaml
with:
  token: ${{ github.token }}
```

**Migration steps:**
1. Remove the `env:` block from the release-drafter step
2. Add `with: token: ${{ github.token }}` to the step

**Notes:**
- `env: GITHUB_TOKEN` still works in v7 as a fallback but is not the documented pattern; avoid it in new or migrated workflows
- The `with: token:` input is optional because the action defaults to `github.token`; explicit form is recommended for clarity
- `github.token` is equivalent to `secrets.GITHUB_TOKEN` for most operations; it is the short form available natively in GitHub Actions expressions

---

## Autolabeler Migration

### Architecture Overview

**v6:** The autolabeler runs inside the same `release-drafter/release-drafter@v6` action as the release drafter. A single workflow handles both release drafting (on push to main) and autolabeling (on PR events). The `disable-releaser` and `disable-autolabeler` inputs control which behavior runs per event.

**v7:** A separate action path `release-drafter/release-drafter/autolabeler@v7` is available for splitting autolabeler into its own workflow. The monolithic approach (single workflow, conditional flags) also continues to work because `disable-releaser` and `disable-autolabeler` are present in v7.

**CRITICAL:** The `autolabeler:` config stanza stays in `.github/release-drafter.yml` regardless of which approach you use. Only the workflow step and trigger change. Do NOT move or delete the `autolabeler:` stanza from your config file.

### Before (v6 — monolithic workflow)

Single workflow, both push and PR triggers, conditional disable flags:

```yaml
- uses: release-drafter/release-drafter@v6
  with:
    disable-releaser: ${{ github.event_name == 'pull_request' }}
    disable-autolabeler: ${{ github.event_name == 'push' }}
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### After: v7 Option A — monolithic (minimal migration)

The same pattern continues to work in v7. Update action version and token only:

```yaml
- uses: release-drafter/release-drafter@v7
  with:
    disable-releaser: ${{ github.event_name == 'pull_request' }}
    disable-autolabeler: ${{ github.event_name == 'push' }}
    token: ${{ github.token }}
```

This is the lowest-effort migration path. The `autolabeler:` stanza in `.github/release-drafter.yml` is unchanged.

### After: v7 Option B — split workflows (recommended)

Create a dedicated autolabeler workflow using the separate action path:

```yaml
# .github/workflows/autolabeler.yml
- uses: release-drafter/release-drafter/autolabeler@v7
  with:
    token: ${{ github.token }}
    config-name: release-drafter.yml  # reads autolabeler: stanza from .github/release-drafter.yml
```

The main release-drafter workflow no longer needs PR triggers or disable flags. See `config-reference.md` for complete workflow templates.

**Benefits of split approach:**
- Each workflow has a clear, single responsibility
- Autolabeler job gets only `pull-requests: write` — main drafter job gets only `pull-requests: read`
- Easier to disable or modify one without affecting the other

---

## Permissions Migration

### v6 Pattern

```yaml
# v6 — all permissions on one job
permissions:
  contents: read       # workflow level

jobs:
  update_release_draft:
    permissions:
      contents: write
      pull-requests: write   # both releaser and autolabeler needed write
```

### v7 — Drafter Job (write no longer needed for PR reading)

```yaml
# v7 — drafter job only needs read on pull-requests
permissions:
  contents: write
  pull-requests: read    # changelog generation only requires read
```

### v7 — Autolabeler Job (if split)

```yaml
# v7 — autolabeler workflow level
permissions:
  contents: read

jobs:
  auto_label:
    permissions:
      pull-requests: write   # write only where labels are applied
```

### Summary Table

| Job | v6 Permissions | v7 Permissions |
|-----|---------------|----------------|
| Drafter (main) | `contents: write`, `pull-requests: write` | `contents: write`, `pull-requests: read` |
| Autolabeler (split) | n/a (same job) | workflow: `contents: read`; job: `pull-requests: write` |
| Monolithic (Option A) | `contents: write`, `pull-requests: write` | `contents: write`, `pull-requests: write` (unchanged if keeping single job) |

---

## Migration Checklist

Step-by-step checklist for migrating from v6 to v7. Follow in order.

1. **Update action reference:** Change `release-drafter/release-drafter@v6` to `release-drafter/release-drafter@v7`

2. **Replace token handling:** Remove the `env:` block:
   ```yaml
   # Remove this:
   env:
     GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```
   Add `with: token:` input:
   ```yaml
   # Add this:
   with:
     token: ${{ github.token }}
   ```

3. **Update drafter job permissions:** Change `pull-requests: write` to `pull-requests: read` on the drafter job (write is no longer required for changelog generation)

4. **Choose autolabeler approach:**
   - **Option A (minimal change):** Keep the monolithic workflow, just apply steps 1-3. No further changes needed.
   - **Option B (recommended split):** Continue with steps 5-7.

5. **(Option B only) Create autolabeler workflow:** Create `.github/workflows/autolabeler.yml` with `pull_request` trigger and `release-drafter/release-drafter/autolabeler@v7` step. See `config-reference.md` for the complete template.

6. **(Option B only) Clean up main drafter workflow:** Remove the `pull_request` trigger and the `disable-releaser`/`disable-autolabeler` inputs from the main drafter workflow. The main workflow should only run on push to main.

7. **(Option B only) Update autolabeler workflow permissions:** Set workflow-level `contents: read` and job-level `pull-requests: write` on the autolabeler job.

8. **Verify config file is unchanged:** Confirm that the `autolabeler:` stanza still exists in `.github/release-drafter.yml`. Do NOT move or delete it — it is read by both the monolithic action and the separate `autolabeler@v7` action.

9. **Test:** Push a commit to main and verify the release draft is updated. Open a pull request and verify labels are applied automatically.
