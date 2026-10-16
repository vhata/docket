# Queues: capture, triage, claim, resolve

Two Markdown queues by default. `TODO.md` holds ordinary deferred work, including bugs found during feature work. `review/BACKLOG.md` holds only work promoted from whole-codebase reviews. A repository may add a third prose queue for vision-sized themes (a roadmap; see [Roadmap queue](#roadmap-queue) below). The rule text an agent needs when touching a queue is the repository's `docket/TODO_GUIDE.md` (vendored verbatim from the skill's `templates/docket/TODO_GUIDE.md`); this reference explains how to apply it and why.

Natural-language selection follows the file boundary: "grab a TODO" means `TODO.md` only; "grab a review finding" means `review/BACKLOG.md`; "grab something from the roadmap" means the roadmap. State the queue, section and slug before claiming. Never switch queues because the named one has nothing suitable.

## Entry format

```md
- [AREA] `stable-kebab-slug` — **One-sentence outcome.** One-sentence rationale.
  - Source: task, branch, PR or review file, YYYY-MM-DD          (required)
  - Starting point: where a future worker should begin            (optional)
  - Depends on: `other-slug`                                       (when blocked by queued work in this repository)
  - Blocked by: a decision, person or external condition, in prose, or `repo:slug` (when blocked by anything else)
  - Related: `other-slug`                                          (optional)
  - Findings: `finding-slug`, `finding-slug`                       (review backlog only, required)
  - Remaining from: `original-slug` / Split from: `original-slug` (lineage, when applicable)
```

Slugs are unique across all queues and never change when an entry moves. `Blocked by:` and `Related:` may also name an entry in another repository's queue as `` `repo:slug` `` (or `` `owner/repo:slug` `` where the bare name is ambiguous); the validator leaves those unresolved, and rejects them in `Depends on:`, which orders work within one repository. One area marker per entry; the repository defines its area list. Free-form indented lines for evidence are fine. `bash docket/scripts/check-queues.sh` validates all of this.

## Stages and priorities

TODO stages, as `##` sections: **Needs triage** (outcome, value or dependencies unclear), **Needs proof of concept** (a bounded experiment decides feasibility or approach), **Waiting** (understood well enough to implement and verify, but blocked by a `Depends on:` or `Blocked by:` line), **Ready for separate work** (understood well enough to implement and verify, and unblocked). Priorities as `###` subsections within each stage: P0 Critical, P1 High, P2 Normal, P3 Low, Unprioritized. The review backlog has priority sections only; everything in it is ready by construction.

**Ready means available now.** Available is the conjunction of: Ready stage, no unresolved `Depends on:`, no `Blocked by:` (a product decision, a human playtest, an external service), no live claim, and inside the scope the user asked for. An entry with a `Depends on:` naming unresolved queued work or any `Blocked by:` is not ready, whatever its section; the validator fails it. Eligible to land is a third thing again, decided at the PR (see pr-and-landing.md). Two repositories had ready items whose own text said they were blocked, and readers had to interpret. When the dependency lands, the resolving PR drops the `Depends on:` line and moves the dependent to Ready if nothing else blocks it.

**Waiting is for settled work that is blocked.** Without it, an entry whose outcome and approach are decided but which carries a `Depends on:` or `Blocked by:` has nowhere to go but Needs triage. One repository's triage left six of seven Needs triage entries fully specified and prioritized, each waiting only on another entry or an owner decision, and a reader could no longer tell which entries still needed a decision. Triage therefore puts an entry in Waiting once nothing about it is open except its blockers; an entry that is unclear and also blocked stays in Needs triage. The validator warns about a Waiting entry with neither line, since it is either ready or not yet understood, and fails one whose `Depends on:` names a slug no longer in any queue. A `TODO.md` written before the stage existed has no Waiting section and still validates; see [setup](setup.md#adding-the-waiting-stage).

New entries are Unprioritized unless the user assigned a priority or the item objectively qualifies as P0 (active data loss, security exposure, release blocker; a project may extend that definition in the Docket section of `AGENTS.md`). Do not guess urgency to promote a distraction.

## Capture: the discovery rule

When an idea, improvement, bug or alternative surfaces, from the user or from investigation:

1. Search all queues for an existing entry (`grep -rn "keyword" TODO.md review/BACKLOG.md`); update rather than duplicate.
2. Write the entry first, with `Source:` and the evidence gathered so far, before asking whether to do it now. The in-conversation trade-off is the most valuable thing to preserve.
3. If the entry was added on the current branch, add `Files TODO: <slug>` to the PR body so the capture is auditable; a follow-up mentioned only in PR prose went missing from the queue in one repository. If the entry was instead committed directly to `main` (see [pr-and-landing](pr-and-landing.md#direct-to-main)), use no marker; the validator warns when `Files TODO` names an entry that already exists at the base.
4. Continue the original task. Pulling the entry forward is a second, deliberate decision, normally the user's.

Exceptions: work required for the requested outcome, its correctness or its verification stays in scope without a queue entry; when the boundary is ambiguous, ask the user rather than deciding alone. An unrelated P0 is recorded, reported prominently, and work pauses for direction.

Who edits the queue file: in a fan-out, writers report discoveries and the coordinator files them, serialising edits, and acknowledges each one back to the writer with its slug; until that acknowledgement the discovery is pending, and the coordinator reconciles pending discoveries against the queue before any handoff or ready flag. Alone, the agent files them in its own PR.

### Discoveries in another repository

A bug in one repository often turns up while working in another, for instance in a library while working on an application that uses it. The entry belongs in the queue of the repository that owns the problem. Filing it locally would put it where nobody working on the owning repository looks, and the local validator cannot check a slug that lives elsewhere.

When the owning repository uses Docket, the entry lands there as a direct commit to its `main`, which the [direct-to-main](pr-and-landing.md#direct-to-main) exception for adding queue entries already covers. The steps are the ordinary capture steps, done in the other repository:

1. Search its queues, not the current one's; slugs are unique only within a repository.
2. Work in a fresh worktree of its `origin/main` (`git -C <path> fetch origin && git -C <path> worktree add --detach .worktrees/file-<slug> origin/main`). The user's checkout of that repository, or another session's, may be mid-change.
3. Write the entry with a `Source:` that names the originating repository as well as the branch or PR (`Source: owner/repo#12, YYYY-MM-DD`); a bare `PR #12` would be read as one of the owning repository's PRs. Free-form evidence lines carry what was found.
4. Run that repository's `docket/scripts/check-queues.sh`, commit, and push with `git push origin HEAD:main` under the session's push authority, then remove the worktree. Under an unattended grant the push is held like any other; the worktree stays (detached, so `cleanup-landed.sh` does not list it), and the report and the audit log give the command that publishes it, with `<worktree>` the absolute path `<path>/.worktrees/file-<slug>`: `git -C <worktree> fetch origin && git -C <worktree> rebase origin/main && (cd <worktree> && bash docket/scripts/check-queues.sh) && git -C <worktree> push origin HEAD:main`. The rebase and re-check matter because `main` has usually moved by the time the user gets to it. When the rebase stops on a conflict, which is likely when another entry landed in the same section, resolve it, run `git -C <worktree> rebase --continue`, and rerun the rest of the command.

The PR in the originating repository records the filing in prose, naming the entry as `` `repo:slug` ``. It takes no `Files TODO` marker: markers name entries in the local queues, and `check-pr-markers.sh` rejects a qualified slug as malformed and a bare one as missing. If local work cannot proceed until the other entry is resolved, the local entry carries `` Blocked by: `repo:slug` `` and goes in Waiting (or stays in Needs triage if it is not yet understood); `Depends on:` is for local entries only, because the validator can see when a local dependency lands but not when a foreign one does. Whoever resolves the foreign entry has no way to find its dependents, so the dependent repository's triage clears the blocker (see below).

In a fan-out the coordinator files the entry, as with local discoveries; writers never commit to another repository. The P0 rule applies unchanged: an unrelated P0 found in another repository is filed there, reported prominently, and work pauses for direction. When the owning repository does not use Docket, the report goes to whatever tracker it does use (an issue, say), and the local `Blocked by:` names that instead.

## Triage

Triage is a scheduled ritual, not something that happens when an agent trips over the triage section. Run it when the user asks, when Needs triage exceeds roughly a dozen entries, or at least every few weeks. For each entry in Needs triage: decide the stage (a proof of concept, Waiting, or Ready), set a priority, add or verify `Depends on:`, merge duplicates, and remove obsolete entries with the reason in the commit message. Then go through Waiting for prose blockers that have cleared (the decision was made, the person answered, the external condition holds); drop each such `Blocked by:` line and move the entry to Ready if nothing else blocks it. Then, across every stage and not only Needs triage, check each `` Blocked by: `repo:slug` `` against that repository's queues; when the entry is gone, its removal commit or PR says whether it was resolved. If it was, drop the line and move the dependent to Ready if nothing else blocks it; if it was rejected or removed as obsolete, reassess the dependent instead. Triage records work rather than doing it, so it lands as a direct commit to `main` (subject "Triage TODO.md, YYYY-MM-DD"; see [pr-and-landing](pr-and-landing.md#direct-to-main)); it uses no resolution markers because nothing was implemented.

Review-close triage of findings is a separate step owned by codebase reviews (see reviews.md).

## Claiming

1. Follow the user's selection. Otherwise take the highest-priority suitable unclaimed entry in the Ready section of the named queue. If none is suitable, say so; do not pick from Needs triage, Needs proof of concept, Waiting or another queue.
2. `bash docket/scripts/claim-check.sh <slug>`: open PRs whose body carries a marker for the slug or whose head branch has the slug as its last path component, merged PRs that already resolved it, branches whose last path component is the slug, and worktrees on such a branch or in a directory named `<queue>-<slug>` or `<slug>` (a longer name that merely contains the slug does not count). For a backlog entry the script also checks every slug in its `Findings:` line, because a raw finding can be explicitly assigned without the batch being claimed.
3. Create the branch and worktree immediately (`bash docket/scripts/start-work.sh <queue> <slug>`), then recheck once from inside the worktree with `bash docket/scripts/claim-check.sh --self <slug>`, which ignores the worker's own branch, worktree and pushed copy but still reports another worker's push or a fork PR under the same name; two agents can take the same slug within seconds. Search-then-create is not a lock: within one team the coordinator is the single dispatcher and no two writers are given overlapping slugs; across independent sessions or machines, the draft PR is the only shared record, so publish it early or accept the race.
4. After the first meaningful commit, open a draft PR with the claim marker. The entry stays in the queue while work is underway. If no PR can be created (no remote, no forge access, no push authority), write the finished body to `.docket/pr-<slug>.md` and the review comment to `.docket/review-<slug>.md` (both excluded from git), say so in the report (and in the audit log when one is in use) so the user knows the claim is local-only, and leave the branch and worktree for the user to publish with `git push -u origin <branch> && gh pr create --head <branch> --title "<title>" --body-file .docket/pr-<slug>.md && gh pr comment <branch> --body-file .docket/review-<slug>.md && bash docket/scripts/pr-labels.sh --pr <branch> --apply`.
5. Abandoning the work releases the claim: close the draft and leave the entry untouched. Remove the worktree and branch only when the worktree is clean and the branch holds no unmerged work; otherwise ask, because deleting unmerged work is the user's call.

## Markers

One marker per line in the PR body, at the start of the line, exact text, no backticks, nothing after the slug (the validator rejects a marker inside a list item, task-list item, numbered item or quote, and a marker with backticks or trailing text, because exact-match searches miss them):

```text
Claims TODO: <slug>                        Claims review backlog: <slug>
Resolves TODO: <slug>                      Resolves review backlog: <slug>
Partially resolves TODO: <slug>            Partially resolves review backlog: <slug>
Remaining TODO: <new-slug>                 Remaining review backlog: <new-slug>
Files TODO: <slug>                         Claims review finding: <slug> / Resolves review finding: <slug>
Claims roadmap: <slug>                     Resolves roadmap: <slug>
```

Every PR body also carries one `Type: <kind>` line in the same exact form, queue work or not; `pr-labels.sh` turns it, the branch and the claimed entries into labels (see [pr-and-landing](pr-and-landing.md#labels)).

Directly requested work needs no invented entry and no marker; its branch is `task/<slug>` or `fix/<slug>`. That includes review snapshots and every other PR that is not queue work. The `todo/`, `review/` and `roadmap/` branch prefixes are claims: the validator fails a branch with one of them whose body carries no `Claims`, `Resolves` or `Partially resolves` marker in that queue's namespace for the slug (a `Claims TODO` marker does not satisfy a `review/` branch), and `review/` as a branch prefix means a claim on a `review/BACKLOG.md` entry, unrelated to the `review/` directory. Other prefixes need no marker. A review batch claims its backlog slug plus each finding actually in scope. `bash docket/scripts/check-pr-markers.sh --body <file> --base origin/main --head HEAD` checks every marker against the queue files at base and head, so it belongs in CI.

## Resolving

Before marking the PR ready, verify the implementation against the complete entry, not the part that was convenient.

- **Full**: remove the entry in the PR; change `Claims` to `Resolves`. Search every queue for the slug and repair `Related:` and `Depends on:` lines that named it; a dependent in Waiting left with nothing to wait on moves to Ready in the same PR.
- **Partial**: remove the original; add a remainder with a new slug, reassessed stage, priority and area, and a ``Remaining from: `original-slug` `` line (the validator reads the backticked slug). Use the `Partially resolves` and `Remaining` pair. For review work the remainder lists only the still-open findings; never mark the others resolved. A remainder records what is left; it cannot waive an acceptance condition the original carried, so a PR that delivers a subset is ready only if the entry or the user allows separate delivery of that subset.
- **Split for parallel subsets**: land the split as a direct commit to `main` first (bookkeeping, see [pr-and-landing](pr-and-landing.md#direct-to-main)). Keep the original slug on one narrowed entry; give the other subsets new slugs with a ``Split from: `original-slug` `` line. Only then can several agents claim subsets. Splitting is bookkeeping, not resolution.
- **Rejected or obsolete**: remove with the reason stated in the PR.

A review finding is not closed by its fix PR. The fix PR supplies evidence (code, validation scenario, reviewer confirmation); the next incremental review records closure. Review backlog entries, which are scheduling units, are removed by the fix PR like any other entry.

## Doing without the full machinery

A repository that deliberately keeps one queue and no claim markers (as one of the studied repositories does) still needs: stable slugs so entries can be referenced, a Ready/blocked distinction, a source on each entry, and the discovery rule. Markers and the review backlog can be added when parallel sessions make overlap real. Write the choice down in the Docket section of `AGENTS.md`.

## Roadmap queue

A roadmap (`docs/ROADMAP.md` by default) is prose: themes and direction, not entries. Enabling it as a queue, recorded under Optional pieces in the Docket section of `AGENTS.md`, makes those themes claimable without forcing them into the entry format. The slug is the kebab-case form of the section heading, so it is stable as long as the heading is. Work on a theme runs on `roadmap/<slug>` with `Claims roadmap: <slug>`; `claim-check.sh` and `start-work.sh` treat the slug like any other. The landing PR edits the roadmap section itself (what shipped, what the theme now means) and carries `Resolves roadmap: <slug>`; a theme that is finished is removed or marked done in that same PR. Bounded follow-ups that fall out of a theme are ordinary `TODO.md` entries with `Source:` naming the theme, so the roadmap stays prose and the TODO stays the place where work is picked up. `check-queues.sh` does not parse the roadmap, and `check-pr-markers.sh` accepts roadmap markers without checking them against the file; the heading is the only structure the queue has.
