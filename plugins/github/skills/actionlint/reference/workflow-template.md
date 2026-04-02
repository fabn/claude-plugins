# Actionlint Workflow Reference

## Workflow Template

```yaml
name: Lint Actions

on:
  push:
    branches:
      - main
    paths:
      - '.github/workflows/**.*'
  pull_request:
    branches:
      - main
    paths:
      - '.github/workflows/**.*'

jobs:
  actionlint:
    name: Lint Github Actions
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: reviewdog/action-actionlint@v1
        with:
          reporter: ${{ github.event_name == 'pull_request' && 'github-pr-check' || 'github-check' }}
          fail_level: error
```

## Configuration Notes

**`reporter` auto-detection:**
The `reporter` input uses a GitHub Actions expression to choose the reporting method at runtime:
- On `pull_request` events: uses `github-pr-check`, which posts inline annotations on the PR diff
- On `push` events: uses `github-check`, which creates a check run with annotations visible in the commit status

This is the recommended approach — do not hardcode a single reporter value.

**`fail_level` options:**
- `error` (recommended) — only actionlint errors cause the check to fail; warnings are reported but non-blocking
- `warning` — both errors and warnings cause the check to fail; stricter but may be noisy on existing repos with many warnings

**`paths` filter:**
The `paths: ['.github/workflows/**.*']` filter ensures the workflow only runs when workflow files change. This avoids unnecessary CI runs on unrelated commits. The `**.*` glob matches all files recursively under `.github/workflows/`.

**`actions/checkout` version:**
Uses `actions/checkout@v6` (latest major). Actionlint needs the workflow files checked out locally to lint them.

**`reviewdog/action-actionlint` version:**
Uses `@v1` (latest v1.x). This action bundles actionlint and reviewdog, so no separate installation is needed. It automatically downloads the latest actionlint binary.

## Local Usage

To run actionlint locally before pushing:

**Install:**
```bash
# macOS
brew install actionlint

# Go
go install github.com/rhysd/actionlint/cmd/actionlint@latest
```

**Run:**
```bash
# Lint all workflow files
actionlint

# Lint a specific file
actionlint .github/workflows/ci.yml
```

**VS Code integration:**
The [actionlint VS Code extension](https://marketplace.visualstudio.com/items?itemName=arahata.linter-actionlint) provides real-time linting in the editor. Install it and ensure `actionlint` is on your PATH.
