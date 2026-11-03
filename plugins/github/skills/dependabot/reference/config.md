# Configuration

The skill reads the `dependabot` key of `.claude/github.json`, resolved with the
plugin's shared script:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh" | jq '.config.dependabot // {}'
```

Every key is optional; a missing key selects its default.

```json
{
  "dependabot": {
    "maintainer": "octocat",
    "ready_label": "ready-to-merge",
    "required_checks": ["test", "lint"],
    "auto_merge": {
      "enabled": true,
      "update_types": ["patch", "minor"],
      "ecosystems": ["npm_and_yarn", "github_actions"],
      "dependency_scope": ["development", "runtime"],
      "method": "squash"
    },
    "max_deps_per_pr": 6,
    "max_deep_work_per_run": 5,
    "local_checks": ["npm run lint", "npm run typecheck"],
    "warnings_check": { "check": "test", "pattern": "warn|deprecat" },
    "release_check": false
  }
}
```

| Key | Default | Meaning |
|---|---|---|
| `maintainer` | the authenticated `gh` user | Requested as reviewer on every ready PR |
| `ready_label` | `ready-to-merge` | Label of PRs that only wait on the maintainer's click; created on first use |
| `required_checks` | the branch protection's required checks, else every check on the head | Checks that must be completed and successful before a PR is ready or auto-merged |
| `auto_merge.enabled` | `false` | Turns on the auto-merge gate ([auto-merge.md](auto-merge.md)) |
| `auto_merge.update_types` | `["patch", "minor"]` | Bump types the gate admits. `major` is never admitted, whatever this says |
| `auto_merge.ecosystems` | `["*"]` | Dependabot ecosystems (the `dependabot/<ecosystem>/` branch segment) the gate admits |
| `auto_merge.dependency_scope` | `["development", "runtime"]` | Use `["development"]` to auto-merge only what never reaches production |
| `auto_merge.method` | `squash` | `merge`, `squash` or `rebase`, passed to `gh pr merge` |
| `max_deps_per_pr` | `6` | A PR moving more direct dependencies is split, not audited as it is |
| `max_deep_work_per_run` | `5` | PRs taken through audit + fix in one run; the rest only get the cheap passes (see SKILL.md Step 5) |
| `local_checks` | the adapter's smoke checks | Commands run locally before pushing a fix |
| `warnings_check` | none | CI job whose log is diffed against the default branch for new warning lines |
| `release_check` | `false` | Compare advisories in the latest published release against the default branch |

Read the required checks from branch protection when `required_checks` is absent:

```bash
gh api "repos/{owner}/{repo}/branches/<default>/protection/required_status_checks" --jq '.contexts[]' 2>/dev/null
```

No protection (or no permission to read it) means every check on the head counts.

## First run in a repository

When the key is absent, proceed with the defaults (auto-merge off) and, at the
end of the run, offer once with `AskUserQuestion` to write the key: the
maintainer, the auto-merge choice and the `local_checks` the run discovered.
Write only the keys the user changed from their defaults.
