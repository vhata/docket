# Code review

Read when asked for a full or incremental codebase review, when a PR resolves a review finding, or when delegating and reviewing agent work. PR review checks one change; codebase review checks accumulated interactions and maintains the finding inventory in [review/](../review/). The project's review inputs (focus areas, baseline commands, drift checks, source paths) live under [Review inputs](../docs/QUALITY.md#review-inputs) in `docs/QUALITY.md`. That section is required; every pointer in this guide goes to it.

## PR review (every change)

Every PR that changes code is reviewed by an agent that did not write it, including the coordinator's own code and integration changes. Brief the reviewer with the intended behaviour, the base and head commits and the validation results; in a PR with several writers, keep each author's contribution identifiable. The reviewer reads the whole diff and surrounding code, independently reruns the decisive checks, reproduces claimed "before" behaviour, proves behaviour-neutral claims on an input the author did not use, and mutation-tests new tests. Review depth follows risk: a routine change gets one careful reviewer, not a stack of specialist passes. The reviewer reports findings with location, failure scenario and evidence, and does not invent findings to fill a review; it does not edit the branch. Authors fix; the reviewer confirms the fixes against the original failure. Checks that passed on isolated branches do not prove the combination works, so related PRs are checked together (rebased in merge order, or in a disposable integration worktree) before the set is marked ready. If a rebase or a fix leaves any gate incomplete again, the PR returns to draft. When no reviewer is available, say so in the PR and keep it pending review rather than marking it ready. A routine PR review creates no ledger snapshot; snapshots come from requested codebase reviews. The PR body then records:

```md
## Review
Independent review by <agent> at <commit>: <verdict>. Verified: <claims and how>. Findings: <n> (<fixed in <commit> | disposition>). Not checked: <gaps>.
```

The focus areas the reviewer concentrates on are listed under [Review inputs](../docs/QUALITY.md#review-inputs) in `docs/QUALITY.md`.

## Ledger

- `review/README.md` indexes snapshots newest first with type, reviewed commit (a commit on `main`) and open count at close. The top row is the next incremental review's baseline; the newest Full row is the baseline for cumulative churn.
- `review/YYYY-MM-DD-HHMM-full.md` / `-incremental.md` (UTC) are immutable once merged, except for factual corrections to the review itself. Status changes are recorded by the next snapshot, never by the PR that fixes a finding.
- `review/BACKLOG.md` is the mutable queue of findings promoted into separate work; see [TODO_GUIDE.md](TODO_GUIDE.md).
- The reviewed commit must be reachable from `main`, or the delta since the review cannot be read from history once the branch is squashed. When a review has to happen on a branch before it lands, preserve the reviewed tree (a bundle or the PR head), record the branch commit in the snapshot, and in the next PR that touches the index record the squash commit on `main` it corresponds to after comparing the two trees exactly. Until then `review-due.sh` reports the baseline as lost and its merge-base figures are approximations.

### Snapshot skeleton

```md
# <Full|Incremental> review, YYYY-MM-DD

| Field | Value |
| --- | --- |
| Type | Full / Incremental |
| Reviewed commit | `<sha>` on main |
| Previous review | <file> at `<sha>` / None |
| Reviewers | <coordinator; independent agents and the areas each covered> |
| Baseline | `bash scripts/check.sh`: <result>; <each baseline command from the Review inputs in `docs/QUALITY.md`>: <result> |

## Summary
## Invariants
## Findings
### Open and Moved
### Closed
## Backlog mapping
| Backlog entry | Findings | Decision |
## Suggested order of work
## Verification limits
```

### Finding format

```md
- `immutable-finding-slug` — **One-sentence title.** Kind · Status · Verification.
  - Where: `path:line` (`symbol`) at the reviewed commit.
  - Severity: P0..P3.
  - Failure scenario, evidence and suggested correction in one to four sentences.
  - Review backlog: `mapped-backlog-slug`
```

Kinds: Bug, Design, Duplication, Performance, Test, Style, Tooling, Docs, Security. Verification: **Verified** (executed or reproduced) or **Read** (inspection). Statuses: **Open**, **Moved** (open at a new location), **Fixed**, **Accepted** (reason, who decided and when to reconsider; an agent may show a finding Invalid with evidence, but accepting a correctness or security risk is the user's decision), **Invalid** (evidence), **Superseded** (replacement slug). Every non-open status carries evidence. Closed entries are one line each with reference, location at the reviewed commit, and confirmation:

```md
- `finding-slug` — Fixed in #45 (f10a8e2). `path:line` (`symbol`): what the code now does. Original reproduction rerun; no longer reproduces.
```

One finding is one independently fixable, verifiable problem; repeated instances of one smell are one finding listing every site. A `Where` from an older snapshot is read at that commit with `git show <reviewed-commit>:<path>`; `git blame -L <start>,<end> <path>` shows when the lines changed since.

## Baseline checks

Run `bash scripts/check.sh` and the baseline commands listed under [Review inputs](../docs/QUALITY.md#review-inputs) in `docs/QUALITY.md` at the reviewed commit, and record exact results in the header.

A check that passed at the previous review and fails now is a finding.

## Full review

1. Record the reviewed commit and run the baseline.
2. Read all maintained source, tests and configuration; delegate independent areas to parallel agents and confirm every claim against the source before recording it. Never record a finding you could not confirm, and never invent findings to fill a review.
3. Reproduce serious bugs (Verified); the rest stay Read.
4. Review-close triage (below).
5. Write the snapshot, amend the invariants, add the index row.
6. Open the review as its own PR from a `task/<slug>` branch (for example `task/review-2026-03-01`); a `review/` branch would claim a backlog entry. It carries no code fixes; small factual documentation fixes may be separate commits on the review branch, recorded as Fixed.

## Incremental review

Base is the newest snapshot's reviewed commit.

1. Baseline, recorded.
2. Re-check every standing finding by reading current code. For merged PRs carrying `Resolves review finding: <slug>`, inspect the code at the new commit, record the new location, rerun the original reproduction (Verified) or repeat the inspection (Read). Unconfirmed closures stay Open or Moved with their backlog mapping restored.
3. Read the whole delta against the invariants and standing findings; a new copy of a listed duplication is a finding.
4. Mechanical checks. The language-neutral set:

   ```sh
   bash docket/scripts/check-links.sh
   bash docket/scripts/check-queues.sh --strict
   git ls-files | xargs wc -l | sort -rn | head        # largest files, as evidence, not a threshold
   git grep -nE 'TODO|FIXME|HACK|XXX'                  # deferred work hiding in code instead of the queue
   git status --porcelain --ignored                    # stray files not yet committed, and ignored directories that should not be there
   git ls-files                                        # read for committed strays, against the extension list under Review inputs
   ```

   Language-specific checks (lint-suppression counts, documented flags or controls against the code, and the rest) are the drift checks listed under [Review inputs](../docs/QUALITY.md#review-inputs) in `docs/QUALITY.md`. Compare every number with the previous snapshot and record it even when unchanged.
5. Re-read files touched by most PRs in the delta.
6. Review-close triage, snapshot, index row, review PR (from a `task/` branch, as above).

A full review resets the baseline after a large refactor, when a hot file was rewritten, when most findings are closed and a clean baseline is wanted, when two consecutive incremental reviews each added many findings, or when `bash docket/scripts/review-due.sh`, run with the `--paths` the project records under Review inputs, reports source churn above a third of the codebase.

## Review-close triage

For every Open or Moved finding at close, exactly one decision, recorded in the mapping table: map to an existing backlog entry; promote into a new coherent ready entry (verified or user-visible bug, structural change that unblocks work, or a batch of small defects in one area); keep as inventory with a reason; or fix now when it is a small documentation edit. Promotion is not authorisation to implement.

## Fixing a finding

Select by explicit assignment first, otherwise from `review/BACKLOG.md` by priority. Raw findings without a backlog entry are inventory, not a queue. The fix PR claims its backlog slug and each finding in scope, opens with `## Why`, and includes in `## Validation` a human-runnable scenario: setup, actions, the old failure, the expected corrected result (or, for tooling and docs, the command or inspection and its success condition). "Tests pass" alone is not a scenario. The independent reviewer verifies the fix against the original failure before the PR is ready. When the PR lands, add the finding to the Pending reconciliation list in `review/README.md` (finding, fix PR and commit, reviewer, evidence), adding that section below the index table if the file lacks one. The next incremental review owns closure and clears that list.
