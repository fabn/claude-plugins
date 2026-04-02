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

```yaml
# .github/release-drafter.yml
name-template: 'v$RESOLVED_VERSION'   # release name shown on GitHub
tag-template: 'v$RESOLVED_VERSION'    # git tag created when draft is published

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
change-title-escapes: '\<*_&'   # escape special markdown chars in PR titles

exclude-labels:
  - 'skip-changelog'   # PRs with this label are omitted from the changelog

version-resolver:
  # Determines which semver component to bump based on PR labels.
  # Do NOT use with CalVer — see date-based-versioning.md.
  major:
    labels: ['major']
  minor:
    labels: ['minor']
  patch:
    labels: ['patch']
  default: patch   # default bump when no version label is present

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

Complete `.github/release-drafter.yml` configuration for v6. Structurally identical to v7 config — the differences between v6 and v7 are in the workflow files, not the config file. Existing v6 configs do not need to change when upgrading to v7.

```yaml
# .github/release-drafter.yml (v6 — same structure as v7)
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

**Categories:** Add or remove category blocks as needed. Each category requires a `title` and either `label` (single string) or `labels` (list). PRs that match no category appear under an uncategorized group.

**Autolabeler rules:** Each rule under `autolabeler:` supports `branch` (regex list), `files` (glob list), and `title` (regex list). A PR matches a label rule if ANY of the listed patterns match. Multiple rules can apply to the same PR.

**`version-resolver`:** Controls semver bump when no explicit version label is on a PR. Do NOT use `version-resolver` with CalVer — when using the `version:` action input to inject a date-based version, the `version-resolver` section is meaningless and may cause confusion. See `date-based-versioning.md` for the CalVer setup.

**`$RESOLVED_VERSION` with `version:` input override:** When the `version:` input is provided to the action (e.g., for CalVer injection), `$RESOLVED_VERSION` reflects the injected value. This means `name-template: 'v$RESOLVED_VERSION'` will produce `v2026.04.02` when `version: 2026.04.02` is passed as input.
