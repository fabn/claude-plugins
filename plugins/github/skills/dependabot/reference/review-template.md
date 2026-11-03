# Templates

Every comment and review starts with a `<!-- github:dependabot … -->` marker, so
the next run finds its own work and nobody mistakes it for a human's.

## Review (every PR that is ready, auto-merged, or not to merge)

Posted with `pull_request_review_write` (`event: COMMENT`). Claude acts with the
maintainer's own account, so an `APPROVE` would read as theirs. A new review
replaces the old one whenever the PR changes.

```markdown
<!-- github:dependabot review -->
**Ready to merge** | **Ready, read the impact** | **Auto-merged** | **Do not merge**

**TLDR** — what changes, in one or two lines (packages `from → to`, the
constraint or major that matters).
**Urgency** — advisory id and severity, runtime or development, reachable /
not reachable / unknown; or "routine".
**Impact on us** — what our code calls that changed, behaviour that changes
(defaults, messages, new runtime dependencies, transitive majors), or "none
found" with what was checked.
**Changes on this branch** — each commit of ours and why (lock regenerated,
package held back, deprecation fixed, test adapted to new wording), or "none".
**Verified** — required checks on `<sha>`, local checks run, smoke checks,
warnings compared with the default branch.

<details><summary>Changelog audit — <n> packages</summary>

| Package | From → To | What changed that matters | Our hits | Verdict |
|---|---|---|---|---|
| one row per package, transitive ones that cross a minor included | | | | NONE / CHECK / ACTION |
</details>
```

## Major assessment (Major lane, verdict other than Upgrade now)

```markdown
<!-- github:dependabot major -->
**<package> <from> → <to>** · size S | M | L · verdict: Awaiting review | Blocked | Not wanted
Breaking changes that reach us: <grep hits per removal, or "none">.
Parents: <admit | blocked by <parent> <version> requiring <range>>. Advisory: <id | none>.
To take it: <the Fix lane steps it needs, one line>.
Lifted when: <condition> (Blocked / Not wanted only).
```

## Close (GONE / SUPERSEDED / DUPLICATE)

```markdown
<!-- github:dependabot -->
Closing: the default branch already locks `<pkg>` <version> (≥ <target>).
```

Variants: "`<pkg>` is no longer a dependency." / "Superseded by #<n>, which
moves `<pkg>` to <higher target>." / "Not taken: <reason>. Recorded as an
`ignore` entry in `.github/dependabot.yml` (#<config PR>), lifted when <condition>."

## Push comment (every push to a Dependabot branch)

```markdown
<!-- github:dependabot -->
Pushed <short sha>: <what changed and why — lock regenerated from the default
branch and what it no longer moves / packages held back / the fix and the
failure it answers>. Review updated.
```

## Report

Short by default: counts per section and only the rows that need the user.
The Majors table is always shown in full, every row in it needs the user.

```markdown
## Dependabot — <owner/repo> — <date>

**Needs you:** <decisions asked · PRs ready to merge (count + filter link) · a release — or "nothing">

### Auto-merged — <n>
| PR | Packages | Bump |

### Closed — <n>
<count by reason>

### Ready for you — <n>
`is:pr is:open label:<ready_label>`
| PR | TLDR | Impact |   ("read the impact" rows only)
Merge order (only when the merge plan found a clash): #a, #b, then #c once regenerated after #b.

### Fixed on the branch
| PR | What broke | Change made | CI | Ready |

### Majors — <n> open of <limit> slots
| PR / package | From → To | Size | Verdict | Why / lifted when |
Ignore entries revisited: <n kept, n dropped (package: why)> · Config PR: #<n> | none

### Security without a PR
| Package | Severity | Patched | Scope | Plan |

### Next run — <n>
<PRs beyond max_deep_work_per_run, oldest first>

### Awaiting a release   (release_check only)
| Package | Advisory | Severity | Fixed on default in |

### Infrastructure
<CI failures not caused by dependencies, or omit>
```

Every PR number is a link. When nothing is open and nothing is vulnerable, say
so in one line and stop.
