# Auto-merge gate

Claude merges a Dependabot PR only when **every** item below holds, all checked
in this run against **one** head sha, recorded before the first item. One item
that fails, or that cannot be checked, sends the PR down the ready flow
(review + label + maintainer) instead.
The gate is for updates that are boring by evidence, not by hope.

| # | Condition | How to check |
|---|---|---|
| 1 | `auto_merge.enabled` is `true` (the default), and the PR's ecosystem and dependency scope are in the config | `config.md`; scope from the advisory or the manifest (dev group, `devDependencies`, `[dev-dependencies]` …) |
| 2 | `deps` is non-empty, names every direct package the PR changes, and each is a `patch` or `minor` admitted by `auto_merge.update_types` | `collect.sh` `deps[].bump` (`unknown` fails), compared with the manifest/lock diff (adapter): a package in the diff and not in `deps` fails |
| 3 | No `0.x` minor, no transitive dependency crossing a major, no new runtime dependency | `collect.sh` counts `0.x` minors as major; the lock diff (adapter) for the transitive ones |
| 4 | Changelog audit verdict **NONE** for every dependency, direct and transitive ones crossing a minor | Step 6; each changelog actually read — unreadable is not NONE |
| 5 | The branch carries no commit of ours | `collect.sh` `ours: false`. A PR we had to fix is reviewed by the maintainer |
| 6 | At least one check is required, and every required check completed and successful on the recorded sha | `gh pr checks <n> --required`; with no `required_checks` and no branch protection, `gh pr checks <n>` (all checks). No check at all, pending, failed or skipped fails. `collect.sh`'s `checks` is for planning, not for this item |
| 7 | `mergeable` is `MERGEABLE` | `gh pr view <n> --json mergeable,mergeStateStatus`. Right after a merge GitHub reports `UNKNOWN` for a few seconds: ask again every 5 seconds for up to a minute; still `UNKNOWN` fails |
| 8 | No new warning against the default branch, when `warnings_check` is configured | Step 6 point 4 |

## Merging

The same procedure merges the ready PRs the maintainer told Claude to merge
(SKILL.md Step 11). Their answer stands in for items 1–5; items 6 and 7 are
checked again on the recorded sha, and the verdict line reads
`**Merged on <maintainer>'s answer** — required checks green on <sha>`.

1. Merge pinned to the recorded sha, so a push that landed since refuses the
   merge:

   ```bash
   gh pr merge <n> --<method> --match-head-commit <recorded sha>
   ```

   Never `--admin`, never bypass branch protection, never enable GitHub's
   own auto-merge (`--auto`): it would merge a head this run has not audited.
2. Only after the merge succeeded, post the review (same template as a ready
   PR) with the verdict line
   `**Auto-merged** — patch/minor, audit NONE, required checks green on <sha>`.
3. **One at a time.** A merge makes every other PR's `mergeable` and checks
   stale: re-read them for the next candidate. Dependabot rebases the others
   on its own; a candidate that turned `CONFLICTING` waits for that rebase and
   is not merged in this run. Candidates go in the merge plan's order
   (SKILL.md Step 8): one touching a lockfile a merge of this run changed is
   merged only if the plan's lock check passed with that merge applied.
   A candidate whose head moved is a new candidate:
   items 2, 3, 5, 6 and 7 are checked again on the new sha; item 4 carries over
   only if the lock diff is identical.
4. A refused merge (head moved, protection, a check that appeared) is not an
   error to work around: the PR goes to the ready flow with the reason in the
   review.

The report lists every auto-merged PR with its dependencies, so the maintainer
can see what landed without opening anything.
