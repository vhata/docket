# Codebase reviews: ledger, findings, closure, cadence

PR review checks one change. A codebase review checks the properties no single change shows: duplicated rules drifting apart, helpers gone dead, documented controls with no code behind them, invariants that hold only by accident. A **full review** reads everything and resets the baseline. An **incremental review** starts from the previous reviewed commit, re-checks every standing finding, reads the delta, and runs cheap whole-repository checks. Incremental is the default; full is a periodic reset. The rule text lives in the repository's `docs/CODE_REVIEW_GUIDE.md` (template in `templates/docs/CODE_REVIEW_GUIDE.md`).

## Artifacts

- `review/README.md`: index, newest first, with type, reviewed commit and open count at close. The top row is the baseline for the next incremental review; the newest Full row is the baseline for cumulative churn, so a run of small incrementals cannot hide a large total change. Below the table, a short **Pending reconciliation** list: findings whose fix PR has landed with independent verification but whose closure the next review has not yet recorded (finding, fix PR and commit, reviewer, evidence). An empty index means no review has happened, not that nothing is wrong.
- `review/YYYY-MM-DD-HHMM-{full,incremental}.md`: one immutable snapshot per review, UTC timestamp. Edited after merge only to correct a factual error in the review itself. Status changes belong to the next snapshot, never to the PR that fixes a finding.
- `review/BACKLOG.md`: the mutable queue of findings promoted into work (see queues.md).

**Record the reviewed commit as a commit on the default branch.** Reviews of unmerged branches get squashed away on merge, after which the exact delta since the review cannot be read from history; `bash scripts/review-due.sh` then reports the baseline as lost and gives merge-base figures as approximations only. Never treat a merge-base diff as complete coverage. If the review must happen on a branch before landing (a release review of a stack), keep the reviewed tree retrievable (`git bundle create review/<stamp>.bundle <commit>`, or the PR's head), record the branch commit in the snapshot, and in the next PR touching the index record the squash commit on main it corresponds to, after comparing the two trees exactly (`git diff <reviewed-commit> <squash-commit>`).

## Snapshot structure

1. Header table: type, reviewed commit, previous review and its commit (or None), reviewers (which agents inspected what), baseline commands and their exact results, coverage or other measured figures if the repository has them.
2. Summary: a few sentences on where the problems concentrate.
3. Invariants: properties the codebase must keep, carried forward and amended. Derived from this codebase (recorded when the same class of problem appears twice, or when a decision holds only while code keeps an unenforced rule), not copied from another project.
4. Findings, grouped by kind.
5. Mapping table: backlog slug to finding slugs, plus explicit inventory-only decisions.
6. Suggested order of work and verification limits.

## Findings

```md
- `immutable-finding-slug` — **One-sentence title.** Kind · Status · Verification.
  - Where: `path:line` (`symbol`) at the reviewed commit; more locations as needed.
  - Severity: P0..P3.
  - Failure scenario, evidence (reproduction or inspection) and suggested correction in one to four sentences.
  - Review backlog: `mapped-backlog-slug` (only when mapped)
```

Kinds: Bug, Design, Duplication, Performance, Test, Style, Tooling, Docs, Security. Verification: **Verified** (executed or reproduced) or **Read** (inspection only). One finding is one independently fixable, independently verifiable thing; many sites of the same smell are one finding listing the sites.

Statuses: **Open**; **Moved** (open at a new location, counts as open); **Fixed** (PR or commit, location at the reviewed commit, and how it was confirmed); **Accepted** (reason, who decided, and when to reconsider; an agent can show a finding invalid but accepting a real correctness or security risk is the user's call); **Invalid** (evidence the finding was wrong); **Superseded** (replacement slug). Closed entries keep all three parts in one line:

```md
- `finding-slug` — Fixed in #45 (f10a8e2). `path:line` (`symbol`): what the code now does. Original reproduction rerun; no longer reproduces.
```

A PR link alone is not a closure. Historical locations are read with `git show <reviewed-commit>:<path>`.

## Performing a full review

1. Record the reviewed commit. Run the repository's baseline checks (the check entrypoint, the end-to-end suite, any headless or smoke run) at that commit and record exact results; a check that passed last review and fails now is itself a finding.
2. Read all maintained source, tests and configuration. List vendored and generated paths as exclusions with the reason. Delegate independent areas to parallel agents, but confirm every claim against the source before recording it; every maintained area has a reviewer or an explicit coverage gap in the snapshot. Never record a finding you could not confirm and never invent findings to fill a quota.
3. Reproduce the serious bugs and mark them Verified; the rest stay Read.
4. Review-close triage (below) for every Open or Moved finding.
5. Write the snapshot, amend the invariants, add the index row.
6. Land the review as its own PR. A review PR never carries a code fix. Small factual documentation fixes found during the review may be separate commits on the review branch, each recorded as Fixed with its commit.

## Performing an incremental review

Inputs: the guide, the newest snapshot, the repository. Base is the previous reviewed commit; the new reviewed commit is current main.

1. Baseline checks, as above, recorded in the header.
2. Re-check every standing finding by reading the current code. Do not infer status from PR titles. Scan merged PRs since base for `Resolves review finding:` markers and verify each: inspect the code at the new commit, record the new `Where`, rerun the original reproduction for Verified findings, repeat the inspection for Read ones. Confirmed closures go to the closed list; unconfirmed ones stay Open or Moved and get their backlog mapping restored.
3. Read the whole delta (`git log --oneline <base>..HEAD`, `git diff --stat <base>..HEAD`, then every hunk) against the invariants and the standing findings. A hunk that adds another copy of an already-listed duplication is a finding even though it is locally fine.
4. Run the whole-repository mechanical checks (below), compare the numbers with the previous snapshot, and record them even when unchanged.
5. Re-read hot files: any file touched by most PRs in the delta gets a full read, because interaction bugs form where changes concentrate.
6. Review-close triage, snapshot, index row, review PR.

Starting prompt that works: "Read docs/CODE_REVIEW_GUIDE.md and the most recent file in review/, then do an incremental review."

### Mechanical checks (language-neutral set)

Keep to checks that need only git, the shell and the repository's own tooling.

```bash
git diff --stat <base>..HEAD | tail -1                     # size of the delta
git ls-files | xargs wc -l | sort -rn | head               # largest files, compare with last review
grep -rnE 'TODO|FIXME|HACK|XXX' <source dirs>              # deferred work hiding in code instead of the queue
grep -rnE '<lint-suppression-pattern>' <source dirs>       # #[allow(, eslint-disable, noqa, nolint: count must not drift up unexplained
git ls-files | grep -vE '<expected extensions and paths>'   # stray files committed by accident (one repo shipped a shell error log)
bash scripts/check-links.sh                                 # documentation link rot
bash scripts/check-queues.sh --strict                       # queue hygiene
```

Add the repository's own drift checks: documented CLI flags against the parser, documented controls against the handlers, a features list against the code, plan status against what has merged, the quality doc against what hooks and CI actually run. Each is a Docs finding when it disagrees, fixed on the spot when it is a small edit.

## Review-close triage

Once, at close, for every Open or Moved finding, make exactly one decision and record it in the mapping table:

1. **Map** to an existing backlog entry that already covers it.
2. **Promote** into a new, coherent, ready backlog entry with a `Findings:` line, when the finding is a verified or user-visible bug, a structural change that unblocks other work, or a batch of small defects in one area worth a branch.
3. **Inventory only**, with the reason, when it does not justify a branch or belongs to a refactor not yet scheduled. Reconsidered at every later review while it stays open.
4. **Fix now**: Docs findings whose fix is a small edit (stale number, retired name, dangling slug, broken link) are fixed in their own commit on the review branch.

Promotion is not authorisation. Review completion never licenses fixing all the findings; work comes from the backlog by priority or from an explicit assignment, and a separately shippable raw finding discovered during ordinary work is filed, not fixed.

## Fix PRs and closure

A PR resolving a finding claims its backlog slug and each finding slug in scope, opens with `## Why`, and includes a human-runnable validation scenario in `## Validation`: setup, actions, the old failure, the expected corrected result. For tooling or documentation findings, give the command or inspection and define success. "Tests pass" or a CI link is not a scenario; the marker validator fails a `Resolves review finding` without a Validation section. The independent reviewer verifies the fix against the original failure before the PR is ready.

When the fix PR lands, add the finding to the index's Pending reconciliation list with the fix commit, the reviewer and the evidence, so verified work is visible between reviews. Closure itself is recorded by the next incremental review, as above, which also clears the pending list. When tools prevent re-running the original reproduction, say so in the snapshot rather than treating the merged fix as verified.

## When a review is due

`bash scripts/review-due.sh --paths "<source dirs>"` reports commits and days since the latest review, source churn since the latest full review, and a verdict. Defaults: incremental after 25 commits or 21 days or when merged PRs claim finding closures; full when inserted source lines since the last full review exceed a third of the current source; "baseline lost" when a reviewed commit is missing or no longer on main. Also reset with a full review after a large refactor, when a hot file was substantially rewritten, when most standing findings are closed and a clean baseline is wanted, or when two consecutive incremental reviews each added many findings.

Two of the studied repositories had let reviews lapse past every one of these triggers, with 95 commits and more than half the source added since the only review in one case. Put the review-due script in the scheduled main-validation workflow so the lapse is reported, and treat its verdict as a prompt for a review PR, never as licence to start fixing.
