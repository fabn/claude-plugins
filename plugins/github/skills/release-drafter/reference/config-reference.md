# Config Reference: release-drafter

Complete, copy-pasteable YAML templates for release-drafter workflows and configuration files. Each H2 section is a lookup unit read independently by the skill.

For v6-to-v7 migration differences, see `migration-checklist.md`.
For CalVer date-based versioning patterns, see `date-based-versioning.md`.

---

## v7 Workflow Template

Complete release-drafter workflow for v7. Triggers on push to main and creates or updates the draft release.

```yaml
# .github/workflows/release-drafter.yml
name: Release Drafter

on:
  push:
    branches:
      - main

permissions:
  contents: write       # required: create and update draft releases
  pull-requests: read   # required: read PR titles, labels, and authors for changelog

jobs:
  update_release_draft:
    runs-on: ubuntu-latest
    steps:
      - uses: release-drafter/release-drafter@v7
        with:
          token: ${{ github.token }}
```

---

## v7 Autolabeler Workflow Template

Separate autolabeler workflow for v7 (recommended split approach). Triggers on PR events and applies labels based on the `autolabeler:` stanza in `.github/release-drafter.yml`.

```yaml
# .github/workflows/autolabeler.yml
name: Auto Label

on:
  pull_request:
    types: [opened, reopened, synchronize]

permissions:
  contents: read   # workflow level: minimal footprint

jobs:
  auto_label:
    runs-on: ubuntu-latest
    permissions:
      contents: read         # job level: required to read config from .github/release-drafter.yml
      pull-requests: write   # job level: required to apply labels
    steps:
      - uses: release-drafter/release-drafter/autolabeler@v7
        with:
          token: ${{ github.token }}
          # config-name defaults to release-drafter.yml — reads autolabeler: stanza
          # from .github/release-drafter.yml (same file as the main drafter config)
```

---

## v7 Config Template

Complete `.github/release-drafter.yml` configuration file for v7. Works with semver version resolution. For CalVer (date-based versioning), see `date-based-versioning.md`.

v7 expresses matching through `when` and does everything with categories. The v6 spellings still parse as compatibility shorthands, so a v6 config keeps working — but write new configs this way, and see `## Deprecated v6 Config Fields` for the mapping when migrating one.

```yaml
# .github/release-drafter.yml
name-template: 'v$RESOLVED_VERSION'   # release name shown on GitHub
tag-template: 'v$RESOLVED_VERSION'    # git tag created when draft is published

categories:
  - title: '🚀 Features'
    when:
      labels:
        - 'feature'
        - 'enhancement'
  - title: '🐛 Bug Fixes'
    when:
      labels:
        - 'fix'
        - 'bugfix'
        - 'bug'
  - title: '🛠️ Maintenance'
    when:
      label: 'chore'
  - title: '🤖 Dependencies'
    when:
      label: 'dependencies'

  # Drops matching changes before categorization. A non-changelog category
  # needs no title: it renders nothing.
  - type: pre-exclude
    when:
      labels:
        - 'skip-changelog'

  # Version resolution, kept separate from changelog inclusion. Do NOT use
  # with CalVer — see date-based-versioning.md. When several categories
  # contribute, the most severe increment wins.
  - type: version-resolver
    semver-increment: major
    when:
      labels: ['major']
  - type: version-resolver
    semver-increment: minor
    when:
      labels: ['minor']
  # No `when`: the fallback when no other version-resolver category matches.
  - type: version-resolver
    semver-increment: patch

change-template: '- $TITLE @$AUTHOR (#$NUMBER)'
change-title-escapes: '\<*_&'   # escape special markdown chars in PR titles

template: |
  ## Changes

  $CHANGES

autolabeler:
  # Rules that automatically apply labels to PRs based on branch name,
  # file paths, or PR title. This stanza is read by BOTH the monolithic
  # action and the separate autolabeler@v7 action.
  - label: 'chore'
    files:
      - '*.md'
    branch:
      - '/docs{0,1}\/.+/'
      - '/chore\/.+/'
  - label: 'bug'
    branch:
      - '/fix\/.+/'
    title:
      - '/fix/i'
  - label: 'enhancement'
    branch:
      - '/feature\/.+/'
```

---

## v6 Workflow Template

Complete v6 monolithic workflow. Handles both release drafting and autolabeling in a single workflow using conditional disable flags.

```yaml
# .github/workflows/release-drafter.yml (v6)
name: Release Drafter

on:
  push:
    branches:
      - main
  pull_request:
    types: [opened, reopened, synchronize]

permissions:
  contents: read   # workflow level default

jobs:
  update_release_draft:
    name: Release Drafter
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write   # v6 requires write for autolabeler in same job
    steps:
      - uses: release-drafter/release-drafter@v6
        with:
          # Conditional flags: run only the relevant function for each event type
          disable-releaser: ${{ github.event_name == 'pull_request' }}
          disable-autolabeler: ${{ github.event_name == 'push' }}
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

---

## v6 Config Template

Complete `.github/release-drafter.yml` configuration for v6. A v6 config still parses under v7 and keeps working, so an upgrade is not blocked on rewriting it — but v7 deprecates most of what it uses. See `## Deprecated v6 Config Fields`.

```yaml
# .github/release-drafter.yml (v6)
name-template: 'v$RESOLVED_VERSION'
tag-template: 'v$RESOLVED_VERSION'

categories:
  - title: '🚀 Features'
    labels:
      - 'feature'
      - 'enhancement'
  - title: '🐛 Bug Fixes'
    labels:
      - 'fix'
      - 'bugfix'
      - 'bug'
  - title: '🛠️ Maintenance'
    label: 'chore'
  - title: '🤖 Dependencies'
    label: 'dependencies'

change-template: '- $TITLE @$AUTHOR (#$NUMBER)'
change-title-escapes: '\<*_&'

exclude-labels:
  - 'skip-changelog'

version-resolver:
  major:
    labels: ['major']
  minor:
    labels: ['minor']
  patch:
    labels: ['patch']
  default: patch

template: |
  ## Changes

  $CHANGES

autolabeler:
  - label: 'chore'
    files:
      - '*.md'
    branch:
      - '/docs{0,1}\/.+/'
      - '/chore\/.+/'
  - label: 'bug'
    branch:
      - '/fix\/.+/'
    title:
      - '/fix/i'
  - label: 'enhancement'
    branch:
      - '/feature\/.+/'
```

---

## Config Customization Notes

**Tag prefix:** The templates above use `v$RESOLVED_VERSION` which produces tags like `v1.2.3` or `v2026.04.02`. For no `v` prefix, use `$RESOLVED_VERSION` directly:

```yaml
name-template: '$RESOLVED_VERSION'
tag-template: '$RESOLVED_VERSION'
```

**Categories:** Add or remove category blocks as needed. A `type: changelog` category (the default) requires a `title`; the other types render nothing and do not. Matching goes under `when`, which takes either a single condition or a list of conditions combined with OR. PRs that match no category appear under an uncategorized group.

**Autolabeler rules:** Each rule under `autolabeler:` supports `branch` (regex list), `files` (glob list), and `title` (regex list). A PR matches a label rule if ANY of the listed patterns match. Multiple rules can apply to the same PR.

**Version resolution:** `type: version-resolver` categories decide the semver bump, and a `semver-increment` on a `type: changelog` category works too when one category should both appear in the notes and drive the bump. Do NOT use either with CalVer — when the `version:` action input injects a date-based version, resolution is meaningless and only causes confusion. See `date-based-versioning.md` for the CalVer setup.

**`$RESOLVED_VERSION` with `version:` input override:** When the `version:` input is provided to the action (e.g., for CalVer injection), `$RESOLVED_VERSION` reflects the injected value. This means `name-template: 'v$RESOLVED_VERSION'` will produce `v2026.04.02` when `version: 2026.04.02` is passed as input.

---

## Deprecated v6 Config Fields

Every field below still parses under v7 as a compatibility shorthand, so a v6 config keeps drafting releases correctly. They are marked `@deprecated` in v7's schema (`src/actions/drafter/config/schemas/config.schema.ts`), so treat a config using them as legacy rather than current.

| v6 field | v7 replacement |
|---|---|
| `categories[].labels` | `categories[].when.labels` |
| `categories[].label` | `categories[].when.label` |
| `exclude-labels` | a category with `type: pre-exclude` and `when.labels` |
| `include-labels` | a category with `type: pre-include` and `when.labels` |
| `exclude-paths` | a category with `type: pre-exclude` and `when.paths` |
| `include-paths` | a category with `type: pre-include` and `when.paths` |
| `version-resolver` | categories with `type: version-resolver` and `semver-increment` |

Two things to get right when translating `version-resolver`:

- `default:` becomes a `type: version-resolver` category with **no `when`**, which the schema treats as the fallback when no other version-resolver category matches. A `patch: labels: ['patch']` entry alongside `default: patch` is redundant and can be dropped.
- `title` is required only for `type: changelog` categories. Omit it on `pre-include`, `pre-exclude` and `version-resolver` categories: they render nothing.

The `autolabeler:` stanza is unchanged in v7 — `label`, `files`, `branch`, `title` and `body`, with no deprecations.
