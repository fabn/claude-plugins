# Ecosystem adapters

SKILL.md is written once for every ecosystem and says "the adapter's X". This
file is where X is spelled out. The ecosystem is the second segment of the
Dependabot branch: `dependabot/<ecosystem>/…`.

Every adapter answers the same questions:

| Field | Used in |
|---|---|
| **Locked version** | Step 4, when `classify.sh` says UNKNOWN |
| **Lock diff** | Step 5 / 6: what a PR really moves, transitive included |
| **Regenerate from default** | Fix lane and lockfile conflicts: never resolve a lockfile by hand |
| **Parents** | Who requires the package, and whether they admit the target |
| **Hold back** | Keep one package of a group PR at the default branch's version |
| **Changelog** | Step 6 audit |
| **Smoke checks** | Before pushing; `local_checks` in config overrides them |

An ecosystem not listed here still goes through every step: work the fields
out from the repository, and say in the report which ones were improvised.

## bundler (Ruby)

- **Locked version**: `git show origin/<default>:Gemfile.lock | ruby -rbundler -e 'puts Bundler::LockfileParser.new($stdin.read).specs.select { _1.name == ARGV[0] }.map(&:version)' <gem>`
- **Lock diff**: `git diff origin/<default>...FETCH_HEAD -- Gemfile.lock | grep -E '^[-+]    [a-z]'` (four spaces: resolved specs, not dependency lines). Read the `Gemfile` diff too: Dependabot widens constraints in groups.
- **Regenerate from default**: `git checkout origin/<default> -- Gemfile.lock && bundle lock --update <gem> [<parents>…] --conservative`. For our own batch, `bundle update --conservative --minor --strict <gems>` keeps every gem inside its level.
- **Parents**: the lockfile lists them (indented under each spec); `gem dependency <parent> -v <v>` shows a release's requirements, `gem list <parent> --remote --all` the releases to try. Follow the chain: the first parent release that admits the target may need its own parents moved.
- **Hold back**: temporary exact pins in the `Gemfile` (`gem 'x', '= <default version>'`, plus its plugins), `bundle lock`, restore the `Gemfile`, `bundle lock` again: the versions stay.
- **Changelog**: `gem fetch <gem> -v <to>` and read `CHANGELOG*` from `<from>` up, else the GitHub releases of the gem's `source_code_uri`.
- **Smoke checks**: boot (`bundle exec ruby -e 'require "./config/environment"'` for Rails, `bundle exec rake -T` otherwise) and lint (`bundle exec rubocop`).
- **Trap**: in a `git worktree`, a `bin/bundle` binstub on `PATH` may set `BUNDLE_GEMFILE` to the main checkout's `Gemfile`, so `bundle lock` rewrites the wrong lockfile. Prefix every call with `BUNDLE_GEMFILE=$PWD/Gemfile`.

## npm_and_yarn (npm, Yarn, pnpm) and bun

Find the package manager from the lockfile on the default branch: `package-lock.json` (npm), `yarn.lock` (Yarn — `.yarnrc.yml` means Berry), `pnpm-lock.yaml` (pnpm), `bun.lock` (bun).

- **Locked version**: `npm ls <pkg> --all --json` / `yarn why <pkg>` / `pnpm why <pkg>` after an install from the lockfile; without one, read the lockfile entry directly (`jq '.packages | to_entries[] | select(.key | endswith("node_modules/<pkg>")) | .value.version' package-lock.json`). Several versions of one package are normal.
- **Lock diff**: `git diff origin/<default>...FETCH_HEAD --stat` first: a single-package PR that rewrites thousands of lockfile lines moved more than its package. For `package-lock.json`, compare `jq '.packages | map_values(.version)'` of both sides; for the others, the version lines of the lockfile diff.
- **Regenerate from default**: `git checkout origin/<default> -- <lockfile>` then `npm install <pkg>@<to> --package-lock-only` / `yarn up <pkg>@<to>` (Berry) or `yarn upgrade <pkg>@<to>` (classic) / `pnpm update <pkg>@<to> --lockfile-only`. For a transitive package, the manager's override (`overrides` / `resolutions` / `pnpm.overrides`) is a last resort, said in the review.
- **Parents**: `npm explain <pkg>` / `yarn why <pkg>` / `pnpm why <pkg>`; `npm view <parent>@<v> dependencies peerDependencies` for what a release requires. Peer dependency ranges are the usual blocker for majors (a UI kit pinning `react`).
- **Hold back**: in a group PR, set the package back to the default branch's range in `package.json` and regenerate; for a transitive one, a temporary override, removed before the review.
- **Changelog**: `npm view <pkg> repository.url` → the repository's releases or `CHANGELOG.md`; monorepos keep one per package (`packages/<name>/CHANGELOG.md`).
- **Smoke checks**: the `package.json` scripts that exist among `build`, `lint`, `typecheck`/`tsc --noEmit`, `test` (unit only: end-to-end suites are CI's job).

## pip, uv, poetry (Python)

- **Locked version**: `uv.lock` (`uv tree --package <pkg>`), `poetry.lock` (`poetry show <pkg>`), or the pinned `requirements*.txt` line.
- **Lock diff**: `git diff origin/<default>...FETCH_HEAD -- uv.lock poetry.lock 'requirements*.txt'`.
- **Regenerate from default**: `uv lock --upgrade-package <pkg>==<to>` / `poetry update <pkg> --lock` / `pip-compile --upgrade-package <pkg>==<to>`.
- **Parents**: `uv tree --invert --package <pkg>` / `poetry show --tree` / `pipdeptree -r -p <pkg>`.
- **Hold back**: constrain the package to the default branch's version in `pyproject.toml`, relock, restore the constraint, relock.
- **Changelog**: PyPI `project_urls` (`curl -s https://pypi.org/pypi/<pkg>/json | jq .info.project_urls`) → changelog or GitHub releases.
- **Smoke checks**: import the package's top module, the linter in use (`ruff check`, `flake8`), the type checker if configured.

## github_actions

- **Locked version**: `classify.sh` reads every `uses: <action>@<ref>` under `.github/` on the default branch; a SHA pin counts by its `# vX.Y.Z` comment.
- **Lock diff**: the PR diff itself; check every workflow file it touches, and the ones it does not (an action used in several files must move in all of them).
- **Regenerate from default**: not applicable; rebase or recreate the edit.
- **Parents**: none. Composite actions under `.github/actions/` and reusable workflows count as callers.
- **Hold back**: revert the line.
- **Changelog**: the action repository's releases; for a major, read its `action.yml` diff for removed inputs or outputs and a changed `runs.using` (Node runtime).
- **Smoke checks**: `actionlint` when installed.
- An action that disappeared from the workflows usually moved into a reusable workflow in another repository: the PR is GONE, do not re-add the action.

## docker

- **Locked version**: the `FROM` lines (and `image:` in compose files) on the default branch; a digest pin counts by its tag.
- **Regenerate from default**: not applicable.
- **Changelog**: the image's release notes; for a base OS image, the distribution's release notes. A tag that also changes the OS release (`-bookworm` → `-trixie`) is a major whatever the number says.
- **Smoke checks**: `docker build` of the changed Dockerfile when Docker is available, else CI.

## go_modules

- **Locked version**: `go list -m <module>` (or the `go.mod` / `go.sum` line).
- **Regenerate from default**: `git checkout origin/<default> -- go.mod go.sum && go get <module>@v<to> && go mod tidy`.
- **Parents**: `go mod why -m <module>`, `go mod graph | grep <module>`.
- **Hold back**: `go get <module>@<default version>`.
- **Changelog**: the module repository's releases. A new major is a new import path (`/v2`): Dependabot does not open those, so a major PR here is unusual.
- **Smoke checks**: `go build ./... && go vet ./...`.

## terraform

- **Locked version**: `.terraform.lock.hcl` for providers, the `version` argument of `module` blocks for registry modules.
- **Regenerate from default**: `terraform init -upgrade` with the new constraint, then `terraform providers lock` for every platform the lock file already lists.
- **Changelog**: the provider's `CHANGELOG.md`; a module's releases. Provider majors remove arguments and change defaults that only a `plan` shows.
- **Smoke checks**: `terraform fmt -check`, `terraform validate`. A `plan` needs credentials and belongs to the repository's CI or its own skill.

## Other ecosystems

cargo, composer, maven/gradle, nuget, pub, mix, swift: the same fields apply.
`classify.sh` maps them to the SBOM when the dependency graph covers them; the
lockfile and the manager's own "why"/"tree" command fill the rest.
