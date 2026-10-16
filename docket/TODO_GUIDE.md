# Deferred work: capture, triage, claim, resolve

Read when an idea surfaces during work, or when adding, selecting, claiming, moving or resolving an entry in [TODO.md](../TODO.md) or [review/BACKLOG.md](../review/BACKLOG.md). `bash docket/scripts/check-queues.sh` validates both files and runs in CI.

## Scope decision

Work required for the requested outcome, its correctness or its verification stays in the current branch. A separately shippable feature, refactor, optimisation or polish item is a follow-up: write the entry first (with the evidence and trade-offs discussed so far), add `Files TODO: <slug>` to the PR body when the entry was added on the branch (an entry committed directly to `main` takes no marker), and continue the original task. Ask the user when the boundary is ambiguous. Pulling the entry forward is a separate decision, normally the user's. An unrelated P0 (data loss, security exposure, release blocker) is recorded, reported prominently, and work pauses for direction.

Discoveries go to `TODO.md`, bugs included. `review/BACKLOG.md` holds only findings a codebase review promoted.

A discovery that belongs to another repository goes in that repository's queue, not this one's, because that is where its work is picked up. When the other repository uses Docket, add the entry to its `TODO.md` as a direct commit to its `main`: search its queues for an existing entry first (slugs are unique only within a repository), work in a fresh worktree of its `origin/main` rather than a checkout someone may be using, run its `docket/scripts/check-queues.sh`, and push under the session's push authority, removing the worktree afterwards. When the push is held, leave the worktree and give the user the command that publishes it, with `<worktree>` as an absolute path: `git -C <worktree> fetch origin && git -C <worktree> rebase origin/main && (cd <worktree> && bash docket/scripts/check-queues.sh) && git -C <worktree> push origin HEAD:main`. `Source:` names the originating repository as well as the branch or PR (`Source: owner/repo#12, YYYY-MM-DD`). The PR here takes no `Files TODO` marker, because markers name entries in these queues only; name the entry in its prose as `` `repo:slug` `` instead. Work here that cannot proceed until that entry is resolved records `` Blocked by: `repo:slug` ``, and triage clears it. An unrelated P0 found in another repository is filed there, reported prominently, and work pauses for direction. A repository that does not use Docket gets the report in whatever tracker it uses. In a fan-out the coordinator files it, as with any discovery.

## Entry format

```md
- [AREA] `stable-kebab-slug` — **One-sentence outcome.** One-sentence rationale.
  - Source: task, branch, PR or review file, YYYY-MM-DD
  - Starting point: where a future worker should begin (optional)
  - Depends on: `other-slug` (when blocked by queued work in this repository)
  - Blocked by: a decision, person or external condition, in prose, or `repo:slug` for another repository's entry (when blocked by anything else)
  - Related: `other-slug` (optional)
  - Findings: `finding-slug`, `finding-slug` (review backlog only, required)
  - Remaining from: `original-slug` / Split from: `original-slug` (lineage, when applicable)
```

`Source` is required. Slugs are unique across all queues and never change when an entry moves. `Blocked by:` and `Related:` may name an entry in another repository as `` `repo:slug` `` (or `` `owner/repo:slug` ``), which the validator does not resolve; `Depends on:` names only slugs in these queues. One area per entry, from the list in the Docket section of `AGENTS.md`. Add free-form indented lines for evidence. Search both queues before adding; update an existing entry instead of duplicating it.

Review backlog entries additionally carry a `Findings:` line naming every raw review finding they cover, each slug in backticks (``Findings: `finding-slug`, `finding-slug` ``), and `Source` names the review file. Each finding maps to at most one backlog entry.

## Stages and priorities

TODO stages: **Needs triage** (outcome, value or dependencies unclear), **Needs proof of concept** (a focused experiment is needed first), **Waiting** (understood well enough to implement and verify, but blocked by a `Depends on:` or `Blocked by:` line), **Ready for separate work** (understood well enough to implement and verify, and unblocked). Priorities within each stage: **P0 Critical** (active data loss, security exposure or release blocker; the Docket section of `AGENTS.md` may extend this definition), **P1 High**, **P2 Normal**, **P3 Low**, **Unprioritized**. New entries are Unprioritized unless the user assigned a priority or the item objectively qualifies as P0. The review backlog has priority sections only; its entries are ready by construction.

An entry with a `Depends on:` naming unresolved queued work, or any `Blocked by:` line, is not ready whatever its section; once nothing else about it is open it goes in Waiting, so that Needs triage holds only entries that still need a decision. A Waiting entry with neither line is either ready or not yet understood, and the validator warns. When the dependency lands or the blocker clears, the resolving PR drops the line and moves the entry from Waiting to Ready if nothing else blocks it. A `TODO.md` written before Waiting existed has no such section; add it, with its priority subsections, between Needs proof of concept and Ready for separate work the first time an entry needs it. A blocker in another repository is cleared by triage here, since the PR that resolves it cannot see this queue. A remainder records what is left; it cannot waive an acceptance condition the original entry carried.

## Triage

Triage runs when the user asks, when Needs triage holds more than about a dozen entries, or every few weeks. For each entry: decide the stage, set a priority, add or verify `Depends on:`, merge duplicates, remove obsolete entries with the reason in the commit message. Then go through Waiting and, for any entry whose prose blocker (a decision, a person, an external condition) has cleared, drop the `Blocked by:` line and move it to Ready if nothing else blocks it. Across every stage, check each `` Blocked by: `repo:slug` `` against that repository's queues; when the entry is gone because it was resolved, drop the line and move the dependent to Ready if nothing else blocks it; when it was rejected or removed as obsolete, reassess the dependent instead. Triage records work rather than doing it, so it lands as a direct commit to `main` (see `CONTRACT.md`) with no resolution markers.

## Selecting and claiming

1. Follow the user's selection. Otherwise take the highest-priority suitable unclaimed entry in **Ready for separate work** of the named queue. If nothing suitable is ready, say so; do not take an item from Needs triage, Needs proof of concept or Waiting, and do not switch queues. State the queue, section and slug before claiming. Directly requested work takes no entry and a `task/<slug>` or `fix/<slug>` branch.
2. Run `bash docket/scripts/claim-check.sh <slug>`. For a backlog entry it also checks every finding slug. A branch whose last path component is the slug (`todo/<slug>`), or a worktree on such a branch or in a directory named `<queue>-<slug>` or `<slug>`, is a provisional claim (a longer name that merely contains the slug is not); an open PR with a marker for it is a claim; a merged PR that resolved it means the entry is stale. Stop and coordinate on any hit.
3. Create the branch and worktree immediately: `bash docket/scripts/start-work.sh <queue> <slug>` (branch `<queue>/<slug>`). Recheck claims once after creating it, from inside the new worktree: `bash docket/scripts/claim-check.sh --self <slug>` ignores your own branch and its worktree, and a remote copy or same-repository open PR of that branch only when its tip is your own work (in your branch, not in main). Any remaining hit, including another worker's push or a fork PR under the same branch name, is a competing claim. From elsewhere, name the branch with `--exclude-branch <queue>/<slug>`.
4. After the first meaningful commit, open a draft PR with the claim marker. Leave the entry in the queue while work is underway. If no PR can be opened, save the body as `.docket/pr-<slug>.md` and the review comment as `.docket/review-<slug>.md` (both excluded from git), say so where the user will see it, and leave the branch and worktree for the user; the claim is then local only.
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

Every PR body also carries exactly one change-type line, in the same form, whether or not it touches a queue:

```text
Type: <feature | fix | refactor | perf | docs | test | tooling | review>
```

`review` is for codebase review snapshots; `tooling` covers scripts, CI, hooks and dependencies. The validator warns when the line is missing and fails a malformed or repeated one. `bash docket/scripts/pr-labels.sh --pr <number> --apply` turns the branch, the `Type:` line and the claimed or resolved entries into the PR's labels: `docket`, `type:<kind>`, `queue:<todo | review | roadmap>`, `area:<area>` and `priority:<p0-p3>`.

Directly requested work needs no invented entry and no marker. A `todo/`, `review/` or `roadmap/` branch is a claim: the validator fails a PR from such a branch unless the body carries a `Claims`, `Resolves` or `Partially resolves` marker in that queue's namespace for the branch's slug (`review/` means a `review/BACKLOG.md` entry). Other prefixes need no marker. A review batch claims its backlog slug and each finding actually in scope; a raw finding taken by explicit assignment claims only the finding and says why. `bash docket/scripts/check-pr-markers.sh --body <file>` validates markers against the queues.

## Resolving

Verify the implementation against the complete entry before marking the PR ready.

- **Full:** remove the entry in the PR; change `Claims` to `Resolves`. Search both queues for the slug and repair `Related:` and `Depends on:` lines that name it; move each dependent left with nothing to wait on from Waiting to Ready.
- **Partial:** remove the original; add a remainder with a new slug, reassessed stage, priority and area, and a ``Remaining from: `original-slug` `` line (the validator reads the backticked slug). Use `Partially resolves` plus `Remaining`. For review work the remainder lists only the still-open findings.
- **Parallel subsets of a batch:** first land a direct commit to `main` that keeps the original slug on one narrowed entry and adds new entries with a ``Split from: `original-slug` `` line. Then each subset is claimed separately. Splitting is not resolution.
- **Rejected or obsolete:** remove with the reason in the PR.

Merging a fix PR removes the backlog entry but does not close a review finding; the next incremental review verifies and records closure (see [CODE_REVIEW_GUIDE.md](CODE_REVIEW_GUIDE.md)). Implementation PRs never edit review snapshots.

## Roadmap queue (when in force)

When the Docket section of `AGENTS.md` lists the roadmap queue, the roadmap file (`docs/ROADMAP.md` by default) is a third queue of vision-sized themes. Its items are prose sections, not entries; the slug is the kebab-case form of the section heading. Claim one with branch `roadmap/<slug>` and `Claims roadmap: <slug>`, checked and created with the same scripts. Landing updates the roadmap section in the same PR and changes the marker to `Resolves roadmap: <slug>`. A follow-up spun off a theme is an ordinary `TODO.md` entry whose `Source` names the theme. `check-queues.sh` does not read the roadmap, and the marker validator accepts roadmap markers without checking them against the file.
