# Date-Based Versioning with release-drafter

Reference document for the `github:release-drafter` skill. Covers CalVer implementation using release-drafter's `version` input to bypass semver resolution.

For the base workflow template to build on, see `config-reference.md`.

---

## CalVer Format

**Format:** `YYYY.MM.DD` — e.g., `2026.04.02`

Calendar Versioning (CalVer) uses the release date as the version string. Each component is zero-padded:
- `YYYY` — four-digit year
- `MM` — two-digit month
- `DD` — two-digit day

**Use cases:** Projects where semantic versioning does not apply — infrastructure repos, config-driven repositories, continuous delivery pipelines, or any project where "what changed" is more meaningful than "how big was the change."

**How it works with release-drafter:** release-drafter v7 exposes a `version` input that overrides the built-in semver version calculation entirely. When `version: 2026.04.02` is passed to the action, `$RESOLVED_VERSION` in your config templates (e.g., `name-template`, `tag-template`) reflects that value. Release-drafter still handles draft creation, PR categorization, and changelog generation — only the version number source changes.

---

## Same-Day Collision Handling

**WARNING:** If multiple releases are triggered on the same calendar day, the computed `YYYY.MM.DD` version collides with the tag that already exists.

**Solution:** Count existing tags for the current date and append a numeric suffix starting from `.2` for the second release.

| Release | Tag |
|---------|-----|
| First of the day | `2026.04.02` |
| Second of the day | `2026.04.02.2` |
| Third of the day | `2026.04.02.3` |

The suffix starts at `.2` (not `.1`) because the first release carries no suffix. This makes `2026.04.02.2` the natural reading of "second release on 2026-04-02."

---

## CalVer Version Computation

Inline bash script for computing the CalVer version with same-day collision handling. Place this in a workflow step's `run:` block.

```bash
DATE=$(date +'%Y.%m.%d')
COUNT=$(git tag --list "${DATE}*" | wc -l | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then
  VERSION="$DATE"
else
  VERSION="${DATE}.$(( COUNT + 1 ))"
fi
echo "version=$VERSION" >> $GITHUB_OUTPUT
```

**Line-by-line explanation:**
1. `DATE=$(date +'%Y.%m.%d')` — compute today's date in YYYY.MM.DD format
2. `COUNT=$(git tag --list "${DATE}*" | wc -l | tr -d ' ')` — count git tags that start with today's date (e.g., `2026.04.02`, `2026.04.02.2`); `tr -d ' '` removes whitespace from `wc -l` output
3. `if [ "$COUNT" -eq 0 ]` — if no tags exist for today, use the bare date
4. `VERSION="${DATE}.$(( COUNT + 1 ))"` — otherwise append `.(count + 1)`; when COUNT=1 (one existing tag `2026.04.02`), this produces `2026.04.02.2`
5. `echo "version=$VERSION" >> $GITHUB_OUTPUT` — write the version to the GitHub Actions step output for use in later steps

**Note:** Requires repository checkout with full tag history before this step runs. See the Prerequisites section.

---

## Prerequisites

The `git tag --list` command requires the repository to be checked out with all tags fetched. Without this, the command returns nothing and `COUNT` is always 0, meaning all releases on the same day would collide on the same tag.

**Required checkout step (must run before CalVer computation):**

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0    # fetch full history and all tags
```

**Why `fetch-depth: 0`:** GitHub Actions runners start with no repository content. By default, `actions/checkout` performs a shallow clone. `fetch-depth: 0` fetches the full history including all git tags, which is required for `git tag --list` to return existing tags.

**Warning signs if checkout is misconfigured:** All releases on the same day will receive the bare date version (e.g., `2026.04.02`) even when a tag with that name already exists. The second push of the day will fail when release-drafter tries to create a tag that already exists.

---

## CalVer Workflow Integration

Complete step sequence for a release-drafter workflow using CalVer versioning. Combines checkout, CalVer computation, and release-drafter steps.

```yaml
# Steps to include in your release-drafter workflow job:

- uses: actions/checkout@v4
  with:
    fetch-depth: 0       # must fetch all tags for collision detection

- name: Compute CalVer
  id: calver
  run: |
    DATE=$(date +'%Y.%m.%d')
    COUNT=$(git tag --list "${DATE}*" | wc -l | tr -d ' ')
    if [ "$COUNT" -eq 0 ]; then
      VERSION="$DATE"
    else
      VERSION="${DATE}.$(( COUNT + 1 ))"
    fi
    echo "version=$VERSION" >> $GITHUB_OUTPUT

- uses: release-drafter/release-drafter@v7
  with:
    version: ${{ steps.calver.outputs.version }}
    token: ${{ github.token }}
```

**Tag prefix note:** If your config uses `tag-template: 'v$RESOLVED_VERSION'`, the created tag will be `v2026.04.02`. Adjust the `git tag --list` pattern to match your prefix:

```bash
# For tag-template: 'v$RESOLVED_VERSION' (produces v-prefixed tags):
COUNT=$(git tag --list "v${DATE}*" | wc -l | tr -d ' ')

# For tag-template: '$RESOLVED_VERSION' (no prefix):
COUNT=$(git tag --list "${DATE}*" | wc -l | tr -d ' ')
```

For the full workflow file including triggers and permissions, use the v7 workflow template in `config-reference.md` as the base and insert these steps.

---

## CalVer Compatibility Warnings

**WARNING: Do not use `version-resolver` labels with CalVer.**

The `version-resolver` section in `.github/release-drafter.yml` controls semver bump behavior (major/minor/patch labels). When the `version:` action input is provided, it overrides `$RESOLVED_VERSION` directly, making label-based version bumping meaningless. Leaving `version-resolver` in the config while using CalVer causes confusion: contributors may add major/minor/patch labels expecting them to affect the release version, but they will have no effect.

**Recommendation:** When using CalVer, remove or omit the `version-resolver` section from your release-drafter config.

**WARNING: Mixing CalVer tags with semver resolution corrupts future versions.**

`semver.coerce("2026.04.02")` produces `2026.4.2`. If the `version:` input is NOT provided on a subsequent run, release-drafter falls back to semver resolution based on the previous tag. It will parse the last CalVer tag as `2026.4.2` and attempt a semver patch bump, producing `2026.4.3` instead of the next expected CalVer version.

**Recommendation:** When using CalVer, always provide the `version:` input on every release-drafter run. Never rely on the fallback semver resolution path. Never mix CalVer and semver strategies in the same repository's release-drafter config.
