---
name: github:dependabot
description: |
  This skill should be used when the user wants to triage the open Dependabot
  PRs of a repository, in any ecosystem: close the dead ones, fix and review
  the rest, give majors a verdict, optionally auto-merge safe patch/minor.
  Activates on: "dependabot", "dependabot PRs", "triage dependabot",
  "merge dependabot PRs", "dependabot backlog", "clean up dependabot",
  "dependabot alerts", "vulnerable dependencies", "PR di dependabot",
  "PR dependabot aperte", "smaltire dependabot", "pulizia dependabot",
  "aggiornamenti dipendenze dependabot".
---

# Dependabot

Takes every open Dependabot PR of the current repository to one of four ends:

- **Closed** — no longer needed (gone, superseded, duplicate).
- **Auto-merged** — a patch or minor that passed every item of the auto-merge
  gate, only in repositories that enable it.
- **Ready to merge** — green, reviewed with a TLDR, labelled and handed to the
  maintainer, whose only job left is to read and click.
- **Postponed with a reason** — a major with its assessment, an `ignore` entry
  with the condition that lifts it, or a decision asked to the user.

Whatever a PR needs to get there (a regenerated lockfile, a deprecation fix, a
held-back package, a rebase) is this skill's to do, on the Dependabot branch.

Ecosystem specifics live in [reference/ecosystems.md](reference/ecosystems.md);
this file says "the adapter's X" and the adapter says how. The auto-merge gate
is in [reference/auto-merge.md](reference/auto-merge.md), comment and report
templates in [reference/review-template.md](reference/review-template.md),
config keys in [reference/config.md](reference/config.md).

## Modes

The mode comes only from the arguments, never from the wording of the request.

| Arguments | Mode |
|---|---|
| none | **Interactive**: present the plan, act, ask decisions with `AskUserQuestion` |
| `--dry-run` | Every step up to the plan, then the report with what would be done: nothing is closed, pushed, labelled or merged in any step (Steps 1 and 4 list their actions instead of taking them) |
| `--unattended` | Nobody is watching (a Routine, `claude -p`, a schedule): act without pausing, decisions go to the tracking issue. Combined with `--dry-run`, only the issue is written |

**Unattended** changes only these points; everything else, the gate included,
is the same:

- No `AskUserQuestion` and no pause after the plan (Step 5). Every decision
  becomes an entry in the **tracking issue** (Step 11), and the run goes on
  with what does not depend on it.
- The answers are read at the start of the next run (Step 0): the
  maintainer's comments on the issue after the last report. An answer that
  does not match an option is followed if it is clear, asked again otherwise.
- Nothing the user alone can decide is done: no *Not wanted* verdict, no
  *Upgrade now* other than security majors and size S majors (both still end
  in the maintainer's review), no Decision acted on, and no config key
  written. *Blocked* `ignore` entries still go into the config PR: merging
  it is the confirmation.
- Wait in the foreground, never with a background shell: a `claude -p` or
  Routine session can end with the turn and drop it. Checks after a push get
  at most 30 minutes (`timeout 1800 gh pr checks <n> --watch`); what is still
  pending is left to Step 1 of the next run.

## Tools Used

- **Bash** — the bundled scripts (require `gh` authenticated and `jq`):
  - `${CLAUDE_PLUGIN_ROOT}/skills/dependabot/scripts/collect.sh` — open Dependabot PRs as JSON lines: ecosystem, group, deps with bump type, `ours`, mergeable, checks
  - `${CLAUDE_PLUGIN_ROOT}/skills/dependabot/scripts/classify.sh` — GONE / SUPERSEDED / DUPLICATE / PENDING / UNKNOWN per PR, from the dependency-graph SBOM and the workflows
  - `${CLAUDE_PLUGIN_ROOT}/skills/dependabot/scripts/advisories.sh` — open advisories (Dependabot alerts, `osv-scanner` fallback); exit 3 means unknown
  - `${CLAUDE_PLUGIN_ROOT}/scripts/read-config.sh` — the `dependabot` key of `.claude/github.json`
  - `gh pr merge|checks|view|edit|close`, `git`, and the ecosystem's own tools per the adapter
- **GitHub MCP** — `pull_request_read`, `pull_request_review_write` (reviews), `update_pull_request` (reviewers, close), `add_issue_comment`, `issue_write` (labels), `get_job_logs`
- **AskUserQuestion** — every decision; **PushNotification** first when running unattended
- **Agent** — one read-only subagent per PR for changelog audits when several are audited in the same run

## Hard rules

- **Merge only through the gate.** Claude merges nothing that fails or skips
  one item of [auto-merge.md](reference/auto-merge.md), never pushes to the
  default branch, never uses `--admin` or bypasses branch protection.
- **Work on the Dependabot branch itself**, single PR or group: lock fixes,
  held-back packages, parent bumps and code fixes are commits on
  `dependabot/*`. Only an update with no Dependabot PR at all (a vulnerable
  package Dependabot did not open, or the split of an oversized PR) gets a
  branch of ours.
- **Never merge the default branch into a Dependabot branch.** A PR that is
  only behind is left alone. A PR in conflict and untouched by us: Dependabot
  rebases it by itself, wait. A PR in conflict carrying our commits: rebase it
  onto `origin/<default>` and push with
  `git push --force-with-lease=<branch>:<sha we fetched> origin <branch>`.
  Lockfile conflicts are never resolved by hand: take the default branch's
  lockfile and re-run the command that produced our commit (adapter:
  regenerate from default).
- **Closing a single Dependabot PR is not "later".** Dependabot answers a close
  with "I won't notify you again about this release": it skips that version,
  opens a new PR at the next release of the same major, and the analysis on the
  closed PR is lost. Close only GONE / SUPERSEDED / DUPLICATE PRs and PRs an
  `ignore` entry on the default branch now covers, plus PRs too large to audit,
  which are split into PRs of ours (Step 6). Postponing is done with a verdict
  (Step 9), not a close.
- **Every push gets a PR comment** saying what changed and why, and the review
  is updated to match.
- **Dependabot regenerates group PRs** when the default branch moves: it may
  close a group PR we pushed to and open a new one. The review lists our
  commits; re-apply them on the new PR (cherry-pick or re-run the same lock
  command), carry the review over, close nothing by hand.
- **`@dependabot` commands** (`rebase`, `recreate`, `ignore`) work from a local
  session, where they are posted as the maintainer. A cloud session's GitHub
  proxy rewrites them so they never reach Dependabot: there, do the work
  directly (rebase here, close via the API, `ignore` entries in config).
- Never skip, disable or loosen a test to get green.
- A command that changes directory stops when the `cd` fails (`cd <dir> &&
  …`, or `git -C`): after a failed `git worktree add`, a bare `cd` runs the
  update in the main checkout.
- Re-list the PRs before acting on a plan written earlier in the run: right
  after a `dependabot.yml` change merges, Dependabot runs at once, closes
  single PRs a group now covers and opens new ones.

## Workflow

### Step 0 — Preflight

1. `gh auth status`; `gh repo view --json nameWithOwner,defaultBranchRef`. Work
   from a checkout of that repository (the scripts read `origin/<default>`):
   `git fetch -q origin <default>`, and `git fetch --unshallow` on a shallow
   clone.
2. Config: `read-config.sh`, then `.config.dependabot // {}` with the defaults
   of [config.md](reference/config.md). On `source: "claude-md"` follow the
   plugin's migration prompt (as `github:pm` does) before going on.
3. Read `.github/dependabot.yml`: ecosystems and directories, groups,
   `open-pull-requests-limit` per ecosystem (default 5), existing `ignore`
   entries. No file and still Dependabot PRs: security updates only; say so.
4. Set `S` to a scratch directory for the JSON the steps share (the
   session's scratchpad when it has one).
5. The tracking issue (open, label `dependabot-triage`, created by Step 11):
   read the maintainer's comments after our last report. Each one answers a
   decision listed there; act on it in this run, in any mode. Interactive,
   ask the decisions still unanswered with `AskUserQuestion` now, and record
   the answers as a comment on the issue so the next run sees them.

### Step 1 — Keep last run's PRs ready

Before anything new, the PRs carrying `ready_label` or one of our reviews
(`--dry-run`: list the actions only):

| State | Action |
|---|---|
| Merged or closed by the maintainer | Leaves the queue |
| New head from Dependabot | Fresh look (Steps 6–8) and an updated review |
| Conflicting | Untouched by us: wait for Dependabot. Ours: rebase (Hard rules) |
| Required check turned red | Remove the label, take it to the Fix lane |
| Closed by Dependabot and regenerated | Re-apply our commits on the new PR, carry review and label over |
| Waiting in the merge plan on a PR now merged | Ours: regenerate the lock from default, push, comment, label. Dependabot's: `@dependabot rebase` |

### Step 2 — Collect

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/dependabot/scripts/collect.sh" > "$S/prs.jsonl"
```

`ours: true` means a head commit was not authored by Dependabot (us, or the
maintainer). `checks` is a summary of all checks for planning; whether a PR is
green is decided on its required checks with `gh pr checks` (Step 8). `mergeable`
`UNKNOWN` is computed lazily: ask again later, then test locally:
`git merge-tree --write-tree origin/<default> FETCH_HEAD` after fetching the
head. `--write-tree` needs git 2.38 or later: an older git reports a conflict
on every PR, so check `git --version` first and treat the result as unknown
when it is older. Exit 1 is a conflict; any other non-zero exit is an error.

**Stale CI.** A run older than the last lockfile change on the default branch
says nothing about the PR today, the normal state of a backlog. For the PRs
taken this run that carry no commit of ours, ask Dependabot for a fresh head:
`gh pr comment <n> --body "@dependabot rebase"` from a local session (the
cloud proxy mangles it, Hard rules). There, rebase the branch ourselves only
when the PR goes to the Fix lane anyway: a branch we pushed to is one
Dependabot stops maintaining.

Dependabot sometimes ignores the command. With no new head after 20 minutes,
rebase it ourselves only when the PR moves a single lockfile entry (nothing to
maintain after it merges), and say so in the push comment; any other PR stays
under "Next run".

### Step 3 — Urgency

```bash
if "${CLAUDE_PLUGIN_ROOT}/skills/dependabot/scripts/advisories.sh" > "$S/advisories.jsonl"; then
  jq -c --slurpfile adv "$S/advisories.jsonl" '. as $pr | .advisories = [ $adv[]
    | select(.package as $p | any($pr.deps[]; .name == $p)) | {ghsa, severity, scope, patched} ]' \
    "$S/prs.jsonl" > "$S/prs-adv.jsonl"
else
  jq -c '.advisories = null' "$S/prs.jsonl" > "$S/prs-adv.jsonl"   # unknown, not none
fi
```

`advisories: null` (the script exited 3) means **unknown**: say so on the first
line of the report, never treat it as "none". For every update record:

1. **Severity and fix**: highest severity; the lowest patched version on the
   package's current major (an advisory can be patched on several lines).
2. **Exposure**: `scope` runtime or development. Read the advisory's own text
   for its preconditions (a configuration, an optional package present in the
   lock, a platform, a feature turned on) and check each in the repository,
   then whether our code calls the vulnerable API. A call with a precondition
   unmet is not reachable. Say "reachable", "not reachable" or "unknown", with
   the precondition that decided it — never guess.
3. **Pins**: does our manifest constraint admit the fix? A pin never outranks
   an advisory; a pin that blocks a fix is a top item.

**Queue order**: critical/high reachable advisories → other advisories → PRs
blocking others (a red group PR, the open-PR limit full of majors) → majors →
the rest, oldest first. Vulnerable packages with **no** PR go into the plan as
Batch lane items (Step 5).

### Step 4 — Close the dead

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/dependabot/scripts/classify.sh" < "$S/prs.jsonl" > "$S/classified.jsonl"
```

| Verdict | Action (no confirmation needed; `--dry-run`: list only) |
|---|---|
| GONE | close with the template comment |
| SUPERSEDED | close with the template comment |
| DUPLICATE | close, linking the PR in `deps[].of` (same major only: a patch is never a duplicate of a major) |
| UNKNOWN | the adapter's "locked version" decides, then as above |
| PENDING | Step 5 |

The SBOM lags a few minutes behind a push to the default branch: a PR the
maintainer merged moments ago can make another look PENDING; it will be
caught at the next run. A group PR with some packages already on the default
branch is still PENDING: Dependabot regenerates it.

### Step 5 — Plan the lanes

Every remaining PR, and every vulnerable package with no PR, gets one lane:

| Lane | Goes there | How |
|---|---|---|
| **Auto-merge candidate** | Patch/minor admitted by the config, checks green, `ours: false` | Audit (Step 6), then the gate (Step 8) |
| **Ready** | Patch/minor PRs and groups that are green and not auto-merge candidates, or that failed the gate | Audit, review, label |
| **Fix** | Red CI; changelog ACTION; parent-blocked updates (with their parent bump); majors with verdict *Upgrade now* | On the Dependabot branch (Step 7) |
| **Batch** | Vulnerable packages with no PR whose fix is on the current major | One PR of ours from the default branch, the adapter's conservative update (Step 7) |
| **Major** | Every major PR, and vulnerable packages whose only fix is a major | A verdict (Step 9) |
| **Decision** | A choice no code change can make (dropping a package, a product trade-off), toolchain upgrades (a dev tool dragging its core across many minors) | Asked (Step 11) |

**Parents.** Before planning a bump, check that every package requiring it
admits the target (adapter: parents). A parent that does not makes it
parent-blocked: find the first parent release that admits it, follow the
chain, and if it resolves it goes to Fix with its parents; if no release
admits it, Major lane *Blocked* or Decision.

**Families.** Packages released together and pinned to the same exact version
(a framework's `@scope/*` packages, a monorepo's crates) cannot move one at a
time: each single PR is red by construction. Recognise them by a shared
scope or prefix and the same exact `from` in the manifest. Their open PRs are
one Fix item: on the PR carrying most of them, bring the other members to the
same version (adapter: regenerate), close the others as superseded by it, and
propose a `groups` entry for the family in the Step 9 config PR.

**Backlog cap.** Deep work (audit + fix + review) is limited to
`max_deep_work_per_run` PRs, taken in queue order. Every other PR still gets
the cheap passes — closed if dead, and listed under "Next run" in the report —
so a large backlog drains across several runs instead of one session that
never ends. Auto-merge candidates count toward the cap: the audit is the
expensive part of the gate.

Present the plan (lane counts, the PRs taken this run, the decisions to ask)
before acting on it. In `--dry-run`, stop here and print the report;
`--unattended` puts it in the report and goes on.

### Step 6 — Changelog audit (every PR, every package)

Green CI proves the tests pass, not that nothing changed: a renamed module, a
new default or a new deprecation warning can ship without a failing test. No
PR is reviewed, marked ready or auto-merged before this is done for each
package it moves, direct ones and transitive ones that cross a minor or are
new.

**At most `max_deps_per_pr` direct packages per PR.** A larger PR (a backlog,
a busy week in a group) is not audited as it is: close it with a link and split
its packages into PRs of ours, grouped by domain, each carrying the code
changes its own packages need.

1. **Read the changes between the two versions** (adapter: changelog), not the
   PR body's truncated excerpt. A changelog that cannot be read is said so in
   the review, never assumed empty.
2. **Grep the code** for every API, option or default the changelog touches,
   and note the hits.
3. **Verdict per package**: **NONE** (nothing reaches us), **CHECK**
   (behaviour that reaches us changes with no code change needed: say what),
   **ACTION** (a code or config change is needed, or a new deprecation warning
   is emitted: make it on the branch).
   - **A renamed or moved serialized type is always ACTION**: background job
     classes, message or event names, cache keys, anything one deploy writes
     and another reads. When an environment running the new code shares a
     queue or store with one running the old code, the old one fails on the
     new name until it is released. Say in the review that the PR must be
     released right after merge, or that the new name must first ship on the
     old version; check that names written by the old version still resolve
     on the new one.
4. **Diff the CI warnings** when `warnings_check` is configured: download the
   job log of the PR head and of the latest green default-branch run,
   normalise timestamps and paths, diff the lines matching `pattern`. A line
   only in the PR is ACTION. Service-container noise is not ours.
5. **One subagent per PR** when several PRs are audited in the same run: give
   each this procedure, the adapter section and its package list
   (`from → to`), read-only on the repository, run them in parallel.

### Step 7 — Fix lane

One PR at a time:

1. Check out the Dependabot branch. **A single-package PR can drag unrelated
   packages**: diff the lock (adapter); when it moves anything the update does
   not need, regenerate it from the default branch (adapter) and say so on the
   PR. Add missing parent bumps there too.
2. **Turn the changelog into a grep**: the removals and renames between the two
   versions, each grepped across the source and test trees. Report every hit,
   including "no hit".
3. **Reproduce before fixing**: run the tests of the call sites on the bare
   upgrade first; the failures are the evidence of what actually breaks.
4. **Trace each failure to a real caller.** A newer package can expose a latent
   test bug (stricter argument validation, a fixed edge case). Fix the test
   when production is right, the code when it is not, and say which.
5. Fix every breaking change and every new deprecation warning. A new runtime
   dependency in the lock diff is a finding: justify it in the review or avoid
   it by moving fewer packages.
6. **Exercise hooks the tests do not assert** when the package sits under one
   (a mailer filter, a build plugin): run it once and look at the output.
7. Run `local_checks` (or the adapter's smoke checks) and the affected tests;
   compare any local failure with the default branch's lockfile before
   trusting it. Push, comment.
8. Red twice on the same cause: stop, move it to Decision with what was learned
   (a major goes back to Awaiting review with that added to its assessment).

**Group PR red**: find the package that breaks (failing tests, then the
changelogs of what they touch). A small fix in our code goes on the group
branch. Anything bigger: hold that package back in the group's lock (adapter:
hold back) and take it to the Fix lane at the group's target; if it does not
land this run, it goes to Decision (fix it, or an `ignore` entry for that
minor line). Never wait for Dependabot to drop the package.

**Batch PR** (only for what no Dependabot PR carries): branch
`deps/batch-<date>` from `origin/<default>`, the adapter's conservative update
for the named packages only, check that the lock diff moves nothing else.
At most `max_deps_per_pr` packages per batch PR: more become several batch
PRs, grouped by domain. Commit `Batch dependency update <date>` with every
package `from → to` and its advisory in the body, push, open the PR.

### Step 8 — Review, then auto-merge or mark ready

**Do not wait for the next run.** After a push, wait for the required checks
in the background (`gh pr checks <n> --required --watch`, run in the
background) and continue with other PRs meanwhile. Wait on checks, never on a
bot comment: status bots edit their comment several times while checks run.

1. Candidate for auto-merge and every gate item holds: merge as
   [auto-merge.md](reference/auto-merge.md) says, one at a time, and post the
   review once merged.
2. Every other PR gets the review ([template](reference/review-template.md)),
   one per PR, a new one whenever the PR changes.
3. **Ready** means: audit complete (a row per package, every ACTION
   fixed), no new warning, required checks green on the head, `mergeable`
   clean, review posted. Then add `ready_label` (create it on first use) and
   request the maintainer (`update_pull_request reviewers`), unless the
   maintainer authored the PR (a batch or config PR opened with their
   account): GitHub refuses an author as reviewer, the label is enough. The
   maintainer's queue is `is:open label:<ready_label>`.
4. **Merge plan.** PRs that are green one by one can break together without a
   text conflict: two changes to the same lockfile whose union is not a valid
   resolution (one adds an entry the other's version no longer satisfies).
   When two or more PRs delivered this run touch the same lockfile, merge them
   one after another into a scratch worktree from `origin/<default>` and run
   the adapter's lock check after each; on a failure, find the PR it clashes
   with. The report gives the order: Dependabot's PRs first, ours touching the
   lock last. A PR that breaks after another gets "regenerate after #n" in its
   review and no `ready_label` until then (Step 1 of a later run).
   Do not stack them with `gh stack`: stacking rebases Dependabot branches onto
   each other (Dependabot stops maintaining them), its cascading rebase is
   textual and regenerates no lockfile, and merging a mid-stack PR merges
   everything below it.

### Step 9 — Postpone: the Major lane and `ignore` entries

A major is never left open without a verdict, and never closed "to revisit
later". Collect the Step 3 facts, the removals turned into a grep (Step 7
point 2) and a size: **S** (no hit, or a one-line change), **M** (a few call
sites, one area), **L** (many call sites, a parent chain, or behaviour the tests
do not pin). Then exactly one verdict:

| Verdict | When | What happens |
|---|---|---|
| **Upgrade now** | A security major with no fix on the current line (always first); otherwise parents admit it and it is the best value for its size. At most two per run, and only ones this run takes to green | Fix lane |
| **Awaiting review** | Upgradable, not taken this run | Stays open with the assessment review, maintainer requested, **without** the ready label |
| **Blocked** | A parent or our constraints admit no release of the target | `ignore` entry; the PR closes once the entry is on the default branch |
| **Not wanted** | The user said so (a package being dropped, a product trade-off) | `ignore` entry; the PR closes once the entry is on the default branch |

Framework majors (the application framework itself, a language runtime) go to
Decision: they deserve their own session.

**Slots.** Majors left open count toward `open-pull-requests-limit`; once it is
full, Dependabot stops opening new PRs for that ecosystem, groups included.
When majors fill the limit, say so on the first line of the report.

**When Dependabot replaces a major PR** with a newer (or, after a cooldown, an
older) target of the same major, carry the verdict and the assessment over and
re-check only the delta.

**The `ignore` entry** goes under the ecosystem's entry in
`.github/dependabot.yml`, always with the reason and the lift condition:

```yaml
    ignore:
      - dependency-name: "<package>"
        update-types: ["version-update:semver-major"]
        # Blocked: <parent> <version> requires <package> < <major>.
        # Lift when a <parent> release admits <package> <major>.
```

All entries of a run go into **one** PR (`deps/dependabot-config-<date>`), its
body carrying the same table as the report. The user confirms its entries
(Step 11); it is then reviewed and marked ready like any other PR. Once merged,
close each covered PR with the template comment.

**Revisit every entry at every run**, before new verdicts: an ignored major
never shows up as a PR, so find its latest version with the ecosystem's
registry or `outdated` command. Blocked: re-check the parents; once nothing
blocks, drop the entry. Not wanted: report it with its lift condition, drop it
only on the user's answer. An advisory fixed only in an ignored major drops the
entry and makes that major *Upgrade now* (or Decision while still blocked):
`ignore` entries can suppress security updates too.

### Step 10 — Release check (only with `release_check`)

Find the latest published release (`gh release list --exclude-drafts
--exclude-pre-releases --limit 1`), list the advisories its lockfile carries
(`osv-scanner` on a checkout of the tag, when installed) and compare with
Step 3. Advisories fixed on the default branch but present in the release are
**awaiting release**: high or critical ones go on the first line of the
report, and publishing is the user's call (`github:release`).

### Step 11 — Questions and report

Decisions are asked, not written into the report as questions:

- **`AskUserQuestion`**, one question per decision, at most four per call; with
  more, the most blocking first and the rest after acting on the answers.
- Two to four options each, the recommended one first with "(Recommended)";
  each description says what Claude does next if it is picked.
- The question carries the facts (package, versions, size, what breaks, PR
  number) so it can be answered without scrolling back.
- A free-text answer may describe a way none of the options offered: follow it.
Then the report ([template](reference/review-template.md)): what was done and
what waits on the maintainer, counts by default, rows only where the user is
needed.

**Unattended**: the report and the decisions go to the tracking issue instead,
one per repository (`Dependabot triage`, label `dependabot-triage`, created on
first use). Its body is replaced with the latest report; each run adds one
comment with that run's decisions in the issue template, so the maintainer
answers there and is notified by GitHub. A decision answered meanwhile
disappears from the next one. Send a `PushNotification` when the tool exists,
one line: how many decisions, the most urgent, the issue link. Its wording
matches the report: an advisory found not reachable is not called urgent.

## Error Handling

| Situation | What to do |
|---|---|
| `advisories.sh` exits 3 | Advisories unknown: first line of the report; offer to install `osv-scanner` or enable Dependabot alerts |
| `classify.sh` says the SBOM is unavailable (dependency graph off) | Every non-Actions dep is UNKNOWN: use the adapter's locked version |
| `classify.sh` says the directory is not a checkout of the repo | Run it from the right checkout; Actions deps are UNKNOWN until then |
| `collect.sh` returns nothing but the PR list shows Dependabot PRs | Check `gh auth status` scopes and that the PRs' author is `dependabot` (not a fork bot) |
| CI log expired (410) or the run predates the last lockfile change on default | CI unknown: re-run the checks before calling the PR green or red |
| Red job with no test failure in its log | Compare with the same job on the default branch first: a failure main does not have, on a PR behind main, is drift (schema, generated files) and goes with a rebase. Only one main shares, or the runner's own, is infrastructure: report once |
| Push rejected by `--force-with-lease` | Someone pushed meanwhile: fetch, look at what changed, redo; never plain `--force` |
| Ecosystem missing from the adapters | Work the fields out from the repository; say which were improvised |

## Reference Files

- [reference/ecosystems.md](reference/ecosystems.md) — per-ecosystem commands: locked version, lock diff, regenerate, parents, hold back, changelog, smoke checks
- [reference/auto-merge.md](reference/auto-merge.md) — the auto-merge gate and how to merge
- [reference/review-template.md](reference/review-template.md) — review, assessment, close and push comments; the report
- [reference/config.md](reference/config.md) — `dependabot` keys of `.claude/github.json` and their defaults
