# Deferred work: capture, triage, claim, resolve

Read when an idea surfaces during work, or when adding, selecting, claiming, moving or resolving an entry in [TODO.md](../TODO.md) or [review/BACKLOG.md](../review/BACKLOG.md). `bash scripts/workflow/check-queues.sh` validates both files and runs in CI.

## Scope decision

Work required for the requested outcome, its correctness or its verification stays in the current branch. A separately shippable feature, refactor, optimisation or polish item is a follow-up: write the entry first (with the evidence and trade-offs discussed so far), add `Files TODO: <slug>` to the PR body, and continue the original task. Pulling the entry forward is a separate decision, normally the user's. An unrelated P0 (data loss, security exposure, release blocker) is recorded, reported prominently, and work pauses for direction.

## Entry format

```md
- [AREA] `stable-kebab-slug` — **One-sentence outcome.** One-sentence rationale.
  - Source: task, branch, PR or review file, YYYY-MM-DD
  - Starting point: where a future worker should begin (optional)
  - Depends on: `other-slug` (when blocked by queued work)
  - Blocked by: a decision, person or external condition, in prose (when blocked by something that is not queued work)
  - Related: `other-slug` (optional)
```

`Source` is required. Slugs are unique across both queues and never change when an entry moves. One area per entry, from: <`[AREA]`, `[AREA]`, `[TOOLING]`, `[DOCS]`; edit this list>. Add free-form indented lines for evidence. Search both queues before adding; update an existing entry instead of duplicating it.

Review backlog entries additionally carry `Findings: <finding-slug>, ...` naming every raw review finding they cover, and `Source` names the review file. Each finding maps to at most one backlog entry.

## Stages and priorities

TODO stages: **Needs triage** (outcome, value or dependencies unclear), **Needs proof of concept** (a focused experiment is needed first), **Ready for separate work** (understood well enough to implement and verify, and unblocked). Priorities within each stage: **P0 Critical** (active data loss, security exposure or release blocker), **P1 High**, **P2 Normal**, **P3 Low**, **Unprioritized**. New entries are Unprioritized unless the user assigned a priority or the item objectively qualifies as P0. The review backlog has priority sections only; its entries are ready by construction.

An entry with a `Depends on:` naming unresolved queued work, or any `Blocked by:` line, is not ready whatever its section. When the dependency lands or the blocker clears, the resolving PR drops the line and moves the entry to Ready if nothing else blocks it. A remainder records what is left; it cannot waive an acceptance condition the original entry carried.

## Triage

Triage runs when the user asks, when Needs triage holds more than about a dozen entries, or every few weeks. For each entry: decide the stage, set a priority, add or verify `Depends on:`, merge duplicates, remove obsolete entries with the reason in the PR. Triage lands as its own queue-only PR with no resolution markers.

## Selecting and claiming

1. Follow the user's selection. Otherwise take the highest-priority suitable unclaimed entry in **Ready for separate work** of the named queue. If nothing suitable is ready, say so; do not take a triage or proof-of-concept item, and do not switch queues.
2. Run `bash scripts/workflow/claim-check.sh <slug>`. For a backlog entry it also checks every finding slug. A branch or worktree containing the slug is a provisional claim; an open PR with a marker for it is a claim; a merged PR that resolved it means the entry is stale. Stop and coordinate on any hit.
3. Create the branch and worktree immediately: `bash scripts/workflow/start-work.sh <queue> <slug>` (branch `<queue>/<slug>`). Recheck claims once after creating it.
4. After the first meaningful commit, open a draft PR with the claim marker. Leave the entry in the queue while work is underway. If no PR can be opened, save the body as `.feral/pr-<slug>.md` (excluded from git), say so where the user will see it, and leave the branch and worktree for the user; the claim is then local only.
5. Abandoned work: close the draft, remove the worktree and branch, leave the entry untouched.

## Markers

One per line in the PR body, exact text, no backticks, nothing after the slug:

```text
Claims TODO: <slug>                      Claims review backlog: <slug>
Resolves TODO: <slug>                    Resolves review backlog: <slug>
Partially resolves TODO: <slug>          Partially resolves review backlog: <slug>
Remaining TODO: <new-slug>               Remaining review backlog: <new-slug>
Files TODO: <slug>                       Claims review finding: <slug> / Resolves review finding: <slug>
```

Directly requested work needs no invented entry and no marker. A review batch claims its backlog slug and each finding actually in scope; a raw finding taken by explicit assignment claims only the finding and says why. `bash scripts/workflow/check-pr-markers.sh --body <file>` validates markers against the queues.

## Resolving

Verify the implementation against the complete entry before marking the PR ready.

- **Full:** remove the entry in the PR; change `Claims` to `Resolves`. Search both queues for the slug and repair `Related:` and `Depends on:` lines that name it.
- **Partial:** remove the original; add a remainder with a new slug, reassessed stage, priority and area, and `Remaining from: <original-slug>`. Use `Partially resolves` plus `Remaining`. For review work the remainder lists only the still-open findings.
- **Parallel subsets of a batch:** first land a queue-only PR that keeps the original slug on one narrowed entry and adds new entries with `Split from: <original-slug>`. Then each subset is claimed separately. Splitting is not resolution.
- **Rejected or obsolete:** remove with the reason in the PR.

Merging a fix PR removes the backlog entry but does not close a review finding; the next incremental review verifies and records closure (see [CODE_REVIEW_GUIDE.md](CODE_REVIEW_GUIDE.md)). Implementation PRs never edit review snapshots.
