# Queues: capture, triage, claim, resolve

Two Markdown queues by default. `TODO.md` holds ordinary deferred work, including bugs found during feature work. `review/BACKLOG.md` holds only work promoted from whole-codebase reviews. A repository may add a third prose queue for vision-sized themes (a roadmap); its items are claimed by a slug derived from the heading. The rule text an agent needs when touching a queue is the repository's `docs/TODO_GUIDE.md` (template in `templates/docs/TODO_GUIDE.md`); this reference explains how to apply it and why.

Natural-language selection follows the file boundary: "grab a TODO" means `TODO.md` only; "grab a review finding" means `review/BACKLOG.md`; "grab something from the roadmap" means the roadmap. State the queue, section and slug before claiming. Never switch queues because the named one has nothing suitable.

## Entry format

```md
- [AREA] `stable-kebab-slug` — **One-sentence outcome.** One-sentence rationale.
  - Source: task, branch, PR or review file, YYYY-MM-DD          (required)
  - Starting point: where a future worker should begin            (optional)
  - Depends on: `other-slug`                                       (when blocked by queued work)
  - Blocked by: a decision, person or external condition, in prose (when blocked by something that is not queued work)
  - Related: `other-slug`                                          (optional)
  - Findings: `finding-slug`, `finding-slug`                       (review backlog only, required)
  - Remaining from: `original-slug` / Split from: `original-slug` (lineage, when applicable)
```

Slugs are unique across all queues and never change when an entry moves. One area marker per entry; the repository defines its area list. Free-form indented lines for evidence are fine. `bash scripts/check-queues.sh` validates all of this.

## Stages and priorities

TODO stages, as `##` sections: **Needs triage** (outcome, value or dependencies unclear), **Needs proof of concept** (a bounded experiment decides feasibility or approach), **Ready for separate work** (understood well enough to implement and verify, and unblocked). Priorities as `###` subsections within each stage: P0 Critical, P1 High, P2 Normal, P3 Low, Unprioritized. The review backlog has priority sections only; everything in it is ready by construction.

**Ready means available now.** Available is the conjunction of: Ready stage, no unresolved `Depends on:`, no `Blocked by:` (a product decision, a human playtest, an external service), no live claim, and inside the scope the user asked for. An entry with a `Depends on:` naming unresolved queued work or any `Blocked by:` is not ready, whatever its section; the validator fails it. Eligible to land is a third thing again, decided at the PR (see pr-and-landing.md). Two repositories had ready items whose own text said they were blocked, and readers had to interpret. When the dependency lands, the resolving PR drops the `Depends on:` line and moves the dependent to Ready if nothing else blocks it.

New entries are Unprioritized unless the user assigned a priority or the item objectively qualifies as P0 (active data loss, security exposure, release blocker). Do not guess urgency to promote a distraction.

## Capture: the discovery rule

When an idea, improvement, bug or alternative surfaces, from the user or from investigation:

1. Search all queues for an existing entry (`grep -rn "keyword" TODO.md review/BACKLOG.md`); update rather than duplicate.
2. Write the entry first, with `Source:` and the evidence gathered so far, before asking whether to do it now. The in-conversation trade-off is the most valuable thing to preserve.
3. Add `Files TODO: <slug>` to the current PR body so the capture is auditable; a follow-up mentioned only in PR prose went missing from the queue in one repository.
4. Continue the original task. Pulling the entry forward is a second, deliberate decision, normally the user's.

Exceptions: work required for the requested outcome, its correctness or its verification stays in scope without a queue entry. An unrelated P0 is recorded, reported prominently, and work pauses for direction.

Who edits the queue file: in a fan-out, writers report discoveries and the coordinator files them, serialising edits, and acknowledges each one back to the writer with its slug; until that acknowledgement the discovery is pending, and the coordinator reconciles pending discoveries against the queue before any handoff or ready flag. Alone, the agent files them in its own PR.

## Triage

Triage is a scheduled ritual, not something that happens when an agent trips over the triage section. Run it when the user asks, when Needs triage exceeds roughly a dozen entries, or at least every few weeks. For each entry in Needs triage: decide the stage (or that a proof of concept is needed), set a priority, add or verify `Depends on:`, merge duplicates, and remove obsolete entries with the reason in the PR. Triage lands as its own queue-only PR ("Triage TODO.md, YYYY-MM-DD"); it uses no resolution markers because nothing was implemented.

Review-close triage of findings is a separate step owned by codebase reviews (see reviews.md).

## Claiming

1. Follow the user's selection. Otherwise take the highest-priority suitable unclaimed entry in the Ready section of the named queue. If none is suitable, say so; do not pick from Needs triage or another queue.
2. `bash scripts/claim-check.sh <slug>`: open PRs whose body carries a marker for the slug or whose head branch contains it, merged PRs that already resolved it, branches and worktrees containing it. For a backlog entry the script also checks every slug in its `Findings:` line, because a raw finding can be explicitly assigned without the batch being claimed.
3. Create the branch and worktree immediately (`bash scripts/start-work.sh <queue> <slug>`), then recheck once; two agents can take the same slug within seconds. Search-then-create is not a lock: within one team the coordinator is the single dispatcher and no two writers are given overlapping slugs; across independent sessions or machines, the draft PR is the only shared record, so publish it early or accept the race.
4. After the first meaningful commit, open a draft PR with the claim marker. The entry stays in the queue while work is underway. If no PR can be created (no remote, no forge access, no push authority), write the finished body to `.feral/pr-<slug>.md` (excluded from git), say so in the report (and in the audit log when one is in use) so the user knows the claim is local-only, and leave the branch and worktree for the user to publish with `git push -u origin <branch> && gh pr create --head <branch> --body-file .feral/pr-<slug>.md`.
5. Abandoning the work releases the claim: close the draft, remove the worktree and branch, leave the entry untouched.

## Markers

One marker per line in the PR body, exact text, no backticks, nothing after the slug (the validator rejects both because exact-match searches miss them):

```text
Claims TODO: <slug>                        Claims review backlog: <slug>
Resolves TODO: <slug>                      Resolves review backlog: <slug>
Partially resolves TODO: <slug>            Partially resolves review backlog: <slug>
Remaining TODO: <new-slug>                 Remaining review backlog: <new-slug>
Files TODO: <slug>                         Claims review finding: <slug> / Resolves review finding: <slug>
Claims roadmap: <slug>                     Resolves roadmap: <slug>
```

Directly requested work needs no invented entry and no marker. A review batch claims its backlog slug plus each finding actually in scope. `bash scripts/check-pr-markers.sh --body <file> --base origin/main --head HEAD` checks every marker against the queue files at base and head, so it belongs in CI.

## Resolving

Before marking the PR ready, verify the implementation against the complete entry, not the part that was convenient.

- **Full**: remove the entry in the PR; change `Claims` to `Resolves`. Search every queue for the slug and repair `Related:` and `Depends on:` lines that named it.
- **Partial**: remove the original; add a remainder with a new slug, reassessed stage, priority and area, and `Remaining from: <original>`. Use the `Partially resolves` and `Remaining` pair. For review work the remainder lists only the still-open findings; never mark the others resolved. A remainder records what is left; it cannot waive an acceptance condition the original carried, so a PR that delivers a subset is ready only if the entry or the user allows separate delivery of that subset.
- **Split for parallel subsets**: land a queue-only PR first. Keep the original slug on one narrowed entry; give the other subsets new slugs with `Split from: <original>`. Only then can several agents claim subsets. Splitting is bookkeeping, not resolution.
- **Rejected or obsolete**: remove with the reason stated in the PR.

A review finding is not closed by its fix PR. The fix PR supplies evidence (code, validation scenario, reviewer confirmation); the next incremental review records closure. Review backlog entries, which are scheduling units, are removed by the fix PR like any other entry.

## Doing without the full machinery

A repository that deliberately keeps one queue and no claim markers (as one of the studied repositories does) still needs: stable slugs so entries can be referenced, a Ready/blocked distinction, a source on each entry, and the discovery rule. Markers and the review backlog can be added when parallel sessions make overlap real. Write the choice down in `AGENTS.md`.
