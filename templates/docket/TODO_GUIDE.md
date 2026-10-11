# Deferred work: capture, triage, claim, resolve

Read when an idea surfaces during work, or when adding, selecting, claiming, moving or resolving an entry in [TODO.md](../TODO.md) or [review/BACKLOG.md](../review/BACKLOG.md). `bash docket/scripts/check-queues.sh` validates both files and runs in CI.

## Scope decision

Work required for the requested outcome, its correctness or its verification stays in the current branch. A separately shippable feature, refactor, optimisation or polish item is a follow-up: write the entry first (with the evidence and trade-offs discussed so far), add `Files TODO: <slug>` to the PR body when the entry was added on the branch (an entry committed directly to `main` takes no marker), and continue the original task. Ask the user when the boundary is ambiguous. Pulling the entry forward is a separate decision, normally the user's. An unrelated P0 (data loss, security exposure, release blocker) is recorded, reported prominently, and work pauses for direction.

Discoveries go to `TODO.md`, bugs included. `review/BACKLOG.md` holds only findings a codebase review promoted.

## Entry format

```md
- [AREA] `stable-kebab-slug` — **One-sentence outcome.** One-sentence rationale.
  - Source: task, branch, PR or review file, YYYY-MM-DD
  - Starting point: where a future worker should begin (optional)
  - Depends on: `other-slug` (when blocked by queued work)
  - Blocked by: a decision, person or external condition, in prose (when blocked by something that is not queued work)
  - Related: `other-slug` (optional)
  - Findings: `finding-slug`, `finding-slug` (review backlog only, required)
  - Remaining from: `original-slug` / Split from: `original-slug` (lineage, when applicable)
```

`Source` is required. Slugs are unique across all queues and never change when an entry moves. One area per entry, from the list in the Docket section of `AGENTS.md`. Add free-form indented lines for evidence. Search both queues before adding; update an existing entry instead of duplicating it.

Review backlog entries additionally carry a `Findings:` line naming every raw review finding they cover, each slug in backticks (``Findings: `finding-slug`, `finding-slug` ``), and `Source` names the review file. Each finding maps to at most one backlog entry.

## Stages and priorities

TODO stages: **Needs triage** (outcome, value or dependencies unclear), **Needs proof of concept** (a focused experiment is needed first), **Ready for separate work** (understood well enough to implement and verify, and unblocked). Priorities within each stage: **P0 Critical** (active data loss, security exposure or release blocker; the Docket section of `AGENTS.md` may extend this definition), **P1 High**, **P2 Normal**, **P3 Low**, **Unprioritized**. New entries are Unprioritized unless the user assigned a priority or the item objectively qualifies as P0. The review backlog has priority sections only; its entries are ready by construction.

An entry with a `Depends on:` naming unresolved queued work, or any `Blocked by:` line, is not ready whatever its section. When the dependency lands or the blocker clears, the resolving PR drops the line and moves the entry to Ready if nothing else blocks it. A remainder records what is left; it cannot waive an acceptance condition the original entry carried.

## Triage

Triage runs when the user asks, when Needs triage holds more than about a dozen entries, or every few weeks. For each entry: decide the stage, set a priority, add or verify `Depends on:`, merge duplicates, remove obsolete entries with the reason in the commit message. Triage records work rather than doing it, so it lands as a direct commit to `main` (see `CONTRACT.md`) with no resolution markers.

## Selecting and claiming

1. Follow the user's selection. Otherwise take the highest-priority suitable unclaimed entry in **Ready for separate work** of the named queue. If nothing suitable is ready, say so; do not take a triage or proof-of-concept item, and do not switch queues. State the queue, section and slug before claiming. Directly requested work takes no entry and a `task/<slug>` or `fix/<slug>` branch.
2. Run `bash docket/scripts/claim-check.sh <slug>`. For a backlog entry it also checks every finding slug. A branch or worktree containing the slug is a provisional claim; an open PR with a marker for it is a claim; a merged PR that resolved it means the entry is stale. Stop and coordinate on any hit.
3. Create the branch and worktree immediately: `bash docket/scripts/start-work.sh <queue> <slug>` (branch `<queue>/<slug>`). Recheck claims once after creating it, from inside the new worktree: `bash docket/scripts/claim-check.sh --self <slug>` ignores your own branch and its worktree, and a remote copy or same-repository open PR of that branch only when its tip is your own work (in your branch, not in main). Any remaining hit, including another worker's push or a fork PR under the same branch name, is a competing claim. From elsewhere, name the branch with `--exclude-branch <queue>/<slug>`.
4. After the first meaningful commit, open a draft PR with the claim marker. Leave the entry in the queue while work is underway. If no PR can be opened, save the body as `.docket/pr-<slug>.md` (excluded from git), say so where the user will see it, and leave the branch and worktree for the user; the claim is then local only.
5. Abandoned work: close the draft and leave the entry untouched. Remove the worktree and branch only when the worktree is clean and the branch has no unmerged work; otherwise ask.

## Markers

One per line in the PR body, at the start of the line (not a list item, task-list item, numbered item or quote), exact text, no backticks, nothing after the slug:

```text
Claims TODO: <slug>                      Claims review backlog: <slug>
Resolves TODO: <slug>                    Resolves review backlog: <slug>
Partially resolves TODO: <slug>          Partially resolves review backlog: <slug>
Remaining TODO: <new-slug>               Remaining review backlog: <new-slug>
Files TODO: <slug>                       Claims review finding: <slug> / Resolves review finding: <slug>
Claims roadmap: <slug>                   Resolves roadmap: <slug>
```

Directly requested work needs no invented entry and no marker. A `todo/`, `review/` or `roadmap/` branch is a claim: the validator fails a PR from such a branch unless the body carries a `Claims`, `Resolves` or `Partially resolves` marker in that queue's namespace for the branch's slug (`review/` means a `review/BACKLOG.md` entry). Other prefixes need no marker. A review batch claims its backlog slug and each finding actually in scope; a raw finding taken by explicit assignment claims only the finding and says why. `bash docket/scripts/check-pr-markers.sh --body <file>` validates markers against the queues.

## Resolving

Verify the implementation against the complete entry before marking the PR ready.

- **Full:** remove the entry in the PR; change `Claims` to `Resolves`. Search both queues for the slug and repair `Related:` and `Depends on:` lines that name it.
- **Partial:** remove the original; add a remainder with a new slug, reassessed stage, priority and area, and a ``Remaining from: `original-slug` `` line (the validator reads the backticked slug). Use `Partially resolves` plus `Remaining`. For review work the remainder lists only the still-open findings.
- **Parallel subsets of a batch:** first land a direct commit to `main` that keeps the original slug on one narrowed entry and adds new entries with a ``Split from: `original-slug` `` line. Then each subset is claimed separately. Splitting is not resolution.
- **Rejected or obsolete:** remove with the reason in the PR.

Merging a fix PR removes the backlog entry but does not close a review finding; the next incremental review verifies and records closure (see [CODE_REVIEW_GUIDE.md](CODE_REVIEW_GUIDE.md)). Implementation PRs never edit review snapshots.

## Roadmap queue (when in force)

When the Docket section of `AGENTS.md` lists the roadmap queue, the roadmap file (`docs/ROADMAP.md` by default) is a third queue of vision-sized themes. Its items are prose sections, not entries; the slug is the kebab-case form of the section heading. Claim one with branch `roadmap/<slug>` and `Claims roadmap: <slug>`, checked and created with the same scripts. Landing updates the roadmap section in the same PR and changes the marker to `Resolves roadmap: <slug>`. A follow-up spun off a theme is an ordinary `TODO.md` entry whose `Source` names the theme. `check-queues.sh` does not read the roadmap, and the marker validator accepts roadmap markers without checking them against the file.
