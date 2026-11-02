---
name: docket
description: Use when adopting, repairing, auditing or comparing a repository's agent workflow (queues, worktrees, paired review, gates, review ledger); when coordinating a multi-agent fan-out or an unattended run; when running a full or incremental codebase review; when triaging the queues; or when cleaning up after changes land. Not needed for ordinary single-task work in a repository whose AGENTS.md and guides already encode the workflow; those documents are sufficient there.
---

# Docket

A project run this way answers four questions from its own files at any moment: what is being worked on, what is ready to work on, what was decided, and what is known to be broken. Everything below exists to keep those answers true while many agents work at once.

**Core principle:** every unit of work is a branch, a worktree, a change
description with an exact claim, an independent review, and a cleanup.
Use a draft PR with a PR-capable remote, or local review without one.
Every idea that is not that unit of work goes into a queue, immediately,
and the current work continues. Two things may go straight to `main`
without a branch: documentation that records work to be done (queue
entries, triage, plans, design specs; these may also ride along in
whatever PR they came up in, which does not then do that work), and
housekeeping metadata files when the user says so for that case; see
[pr-and-landing](references/pr-and-landing.md#direct-to-main).

The repository's own `AGENTS.md` and guides win wherever they exist and are what an agent reads for everyday work; this skill is for the operations below, and for installing those guides where they are missing (see `references/setup.md`). Loading it for an ordinary implementation task in an already-set-up repository spends context on rules the repository already states.

## Quick start

The user needs only these phrases; this skill works out the rest by inspecting the repository first.

| The user says | What it means |
| --- | --- |
| "Use docket to set up or audit this project" | Inspect first. A project with a contract gets an audit and repairs on a branch; one without gets the workflow installed; an empty one gets initialised before any product code. Propose hosting settings, never apply them. If the repository records a policy that conflicts with the default model (for example one queue, no markers), report the conflict and ask which way to go before changing it. |
| "Use docket to do a full / incremental review" | The codebase review procedure in [reviews](references/reviews.md), landed as its own reviewed change. |
| "Use docket to fan out the ready TODOs" / "run overnight" | The coordinator procedure in [parallel-work](references/parallel-work.md), with the autonomy mode stated up front. |
| "Grab a TODO" / any single task | Not this skill. The repository's `AGENTS.md` and guides. |

## Choose the operation

| Operation | Read | Tools |
| --- | --- | --- |
| Adopt, repair, audit or compare the workflow in a repository, or set up a sidecar for a repository docket cannot be installed in | [setup](references/setup.md), then the pillar references it points to | `install.sh [--check]`, `check-queues`, `check-links`, `review-due`, `gh api` protection inspection |
| Coordinate a fan-out of writers and reviewers, or an unattended run | [parallel-work](references/parallel-work.md), [pr-and-landing](references/pr-and-landing.md) | `claim-check`, `start-work`, `check-pr-markers`, `pr-labels` |
| Triage the queues, split a batch, or reconcile claims | [queues](references/queues.md) | `check-queues`, `claim-check` |
| Run a full or incremental codebase review, or reconcile finding closure | [reviews](references/reviews.md) | `review-due` |
| Define or repair gates, respond to a red main, change protection | [quality-gates](references/quality-gates.md) | `ci.sh`, templates under `templates/.github/` |
| Land a stack, clean up after merges | [pr-and-landing](references/pr-and-landing.md) | `cleanup-landed` |
| Implement one queued or requested task in a set-up repository | the repository's `AGENTS.md`, `docket/CONTRACT.md` and guides; not this skill | the repository's `docket/scripts/` |

## Five pillars

| Pillar | Non-negotiable | Reference |
| --- | --- | --- |
| Parallel work | One owner, one branch, one worktree per task. Shared interfaces land before dependents start. The coordinator integrates and serialises queue edits. | [parallel-work](references/parallel-work.md) |
| Paired review | Every code-writing agent gets a separate reviewer before work is ready. The reviewer verifies claims, the author fixes, and a PR comment or local review file records reviewed commits and dispositions. | [parallel-work](references/parallel-work.md#writer-and-reviewer-pairs) |
| Queues, not tangents | Discoveries become queue entries with a source, in the repository that owns them, then the current task resumes. Ready means unblocked. Claims are exact slugs in descriptions and local branches. | [queues](references/queues.md) |
| Gates everywhere | The same local gates in every mode; hosted repositories add CI on PRs and main, schedules and protection. Empty suites never pass. | [quality-gates](references/quality-gates.md) |
| Review ledger | Full reviews record a revision and findings; incremental reviews start from the last revision and verify claimed fixes. Findings are promoted deliberately into a review backlog. | [reviews](references/reviews.md) |

Hosted and local review, stacking, landing and cleanup are in
[pr-and-landing](references/pr-and-landing.md). Installing or adapting
the system is in [setup](references/setup.md).

## The unit of work, start to finish

Script paths below are the installed paths (`docket/scripts/`), the only ones anyone runs; the skill's `templates/docket/scripts/` copies reach a repository only through `install.sh` (see Bundled tools).

1. **Select.** Follow the user's selection, or take the highest-priority unclaimed entry from the named queue in its Ready section. Never switch queues or stages because the requested one is empty; report that instead.
2. **Check claims.** `bash docket/scripts/claim-check.sh <slug>` (open and merged PRs, branches, worktrees, mapped findings). A matching branch or worktree is a provisional claim. Overlap means stop and coordinate, not race.
3. **Branch and worktree first.** `bash docket/scripts/start-work.sh <queue> <slug>` creates branch `<queue>/<slug>` and its worktree `.worktrees/<queue>-<slug>` (an ignored directory) before any investigation, so the claim is visible immediately. If the harness has its own worktree tool, use it instead for the worktree, but keep the claim check and the `<queue>/<slug>` branch name; the name is what later claim checks find.
4. **Commit early, describe early.** Prepare a title and a change
   description after the first meaningful commit, starting with `## Why`
   and carrying `Type:` and exact claim markers. With a PR-capable
   remote, open a draft PR and run `pr-labels.sh --pr <number> --apply`.
   Without a remote or with a non-PR remote, save
   `.docket/title-<slug>.txt`, `.docket/change-<slug>.md`,
   `.docket/review-<slug>.md` and a separate `.docket/state-<slug>.md`
   for mode, branch, base/head, checks, readiness and user approval.
   Leave the branch and worktree for review. Missing forge access or
   push authority preserves these files pending a PR; it does not permit
   bypassing hosted policy. See the contract's [review
   modes](templates/docket/CONTRACT.md#review-mode).
5. **Stay on task.** Work needed for the requested outcome and its
   verification stays in scope. File separately shippable discoveries in
   the owning queue with a source; add `Files TODO:` when added on this
   branch. Report an unrelated P0 immediately and pause for direction.
6. **Verify.** Run `scripts/check.sh` and change-specific checks. Record
   what ran and its limits. Local mode requires no hosted CI.
7. **Independent review.** A separate reviewer reads the actual diff and
   claims, reruns decisive checks and reports findings. Authors fix;
   reviewers verify fixes. Record the reviewed commit and dispositions
   in a PR comment headed `## Review`, or the local review file. Keep
   this history out of the description, which becomes the commit
   message.
8. **Resolve the queue.** Remove the entry in the same change and use
   `Resolves <queue>: <slug>`, or file a new remainder for partial work.
   Validate with `check-pr-markers.sh --body <file> --strict`; in local
   mode pass `--base main`, and set `--head` when not in the task
   worktree.
9. **Ready, then approved landing.** Ready means implementation, checks
   and independent review are complete. Landing also requires the
   current main base, landed parents and all original acceptance gates.
   Hosted merging stays with the user unless delegated. In local mode
   leave the worktree until the user approves landing its reviewed head;
   then run `land-local.sh` to squash with the title and full
   description. A moved base requires rebase, new validation and
   approval of the new head. Agent review alone never authorises
   landing.
10. **Clean up.** Verify the squash message and main's applicable gates.
    Preserve local artifacts under the retained main checkout's
    `.docket/landed-<slug>/`, then dry-run and apply
    `cleanup-landed.sh`. Local receipts prove the exact tip landed.
    Rebase stacked children and retarget hosted PRs. Details and
    commands are in [pr-and-landing](references/pr-and-landing.md).

## Authorisation ladder

Autonomy grants cover implementation. Which other actions need the user's word, and when:

| Action | Needs explicit go-ahead |
| --- | --- |
| Push a branch, open a draft PR | Interactive sessions: normal, no ask. Unattended autonomy grants: only with the user's word; otherwise branches stay local (see below) |
| Mark work ready | No, once checks and independent review are complete |
| Land into main | Yes: explicit approval to land the reviewed head in local mode; hosted merge delegation in the turn, session or `AGENTS.md` |
| Force-push | Only the PR branch, only `--force-with-lease`, only after a rebase. Never main, even where GitHub allows it; that ability is the owner's, for recovery. |
| Release tag, deploy, publish | Yes, in that turn or the one before, even under "go wild" |
| Change CI, branch protection, hooks policy | Yes |
| Delete a branch with unmerged commits, remove a dirty worktree | Yes |
| Commit directly to main | Work-recording documentation (TODO entries, triage, plans, design specs): normal. Housekeeping metadata such as `.git-blame-ignore-revs`: only when the user says so for that case. Nothing else; pushing the commit follows the session's push authority |

Under an autonomy grant without push authority, work lands on local
branches with the finished description saved to
`.docket/change-<slug>.md`, title to `.docket/title-<slug>.txt`, review
to `.docket/review-<slug>.md` and every load-bearing decision appended
to `.docket/AUDIT.md` with an undo line. See
[parallel-work](references/parallel-work.md#autonomy-modes).

## Bundled tools

All scripts are portable shell (bash 3.2) and need only git, plus `gh` where PRs are involved. They live in the skill under `templates/docket/scripts/` and reach a repository only through `bash ~/.claude/skills/docket/install.sh` (the path is wherever the skill is installed; that one is the Claude Code default), run from inside that repository, which copies the whole `templates/docket/` directory to `docket/` verbatim; `install.sh --check` reports drift without writing. Both compare against the skill checkout they run from, so that checkout must be at or beyond the commit in `docket/VERSION`; from an older checkout `--check` reports that the installed copy is newer and exits 1 without a diff (see [setup](references/setup.md#the-vendored-directory)). Run the installed copies as `bash docket/scripts/<name>.sh`; that is the path the contract, the guides and CI use, so agents without this skill run the same tools. Nobody runs the skill's copies against a repository directly: when `docket/` is missing or stale, install first. Every script acts on the repository of the current directory, except in a sidecar whose `.docket-target` names a managed repository (see [setup](references/setup.md#7-a-sidecar-for-a-managed-repository)).

| Script | Purpose |
| --- | --- |
| `ci.sh` | Runs `check-queues.sh --strict`, `check-links.sh` and, on pull requests, `check-pr-markers.sh` (reads `PR`, `BASE`, `HEAD_BRANCH`, `GH_TOKEN` and `GITHUB_EVENT_PATH` from the environment; the change description comes from the event payload when it is available, otherwise from `gh pr view`). The one hygiene step CI calls. |
| `check-queues.sh [--strict] [--no-target]` | Validates TODO.md and review/BACKLOG.md: entry format, unique slugs, Source lines, resolvable `Related`/`Depends on`, no Ready entry blocked by unresolved work, no Waiting entry without a blocker, each finding mapped by at most one backlog entry, `PR:` claim lines well formed. Run in CI. |
| `check-pr-markers.sh --body FILE \| --pr N [--local] [--strict] [--no-target]` | Validates change-description markers against the queues at base and head, checks the `Type:` line, fails a body whose first heading is not `## Why`, requires a Validation section for finding fixes, and warns on prose lines over 72 characters. `--strict` turns warnings into errors. Run in CI on pull requests. Stands down in a sidecar unless `--no-target`. |
| `pr-labels.sh --pr N [--apply] \| --body FILE [--no-target]` | Derives the PR's labels (`docket`, `type:`, `queue:`, `area:`, `priority:`) from the branch, the `Type:` line and the claimed or resolved queue entries; `--apply` creates missing labels and sets them on the PR. Stands down in a sidecar unless `--no-target`. |
| `claim-check.sh [--local] [--no-target] [--queue Q] [--self] <slug>...` | Finds existing claims across available PRs, branches, worktrees and `PR:` lines on queue entries, and local completions in landing receipts and main commit messages, following backlog findings. `--self` is the recheck from inside the claimed worktree: it ignores the worker's own branch and pushed copy but not another worker's. |
| `start-work.sh <queue> <slug> [--local] [--no-target]` | Claim check, then branch plus worktree with the repository's naming; in a sidecar, in the managed clone. |
| `target.sh` | Sourced by the four scripts that can work in a managed repository, and by the two PR-body scripts that stand down there; run directly, it validates the sidecar's `.docket-target` and prints the resolved settings. |
| `pr-health.sh [--repo OWNER/REPO] [--pr N]... [--land-comment TEXT] [--strict]` | Read-only report on open PRs (your own by default): CI rollup with failing check names, review decision, merge state and conflicts, commits behind base, a landing comment still waiting, and queue markers whose entry this checkout no longer has. `--strict` exits 1 on failing checks, changes requested or conflicts. See [pr-and-landing](references/pr-and-landing.md#checking-pr-health). |
| `review-due.sh [--paths ...] [--repo-dir PATH]` | Reads the review index, measures drift since the reviewed commit, says whether an incremental or full review is due. `--repo-dir` (the managed clone by default in a sidecar) resolves commits in another repository. |
| `land-local.sh BRANCH --title TEXT --body FILE --approved-head SHA` | After user approval, squash-lands a reviewed local branch from the clean base checkout, preserving its title and full description and recording an exact-tip landing receipt. |
| `cleanup-landed.sh [--local] [--no-target] [--apply] [--empty] [--discard-ignored]` | Removes worktrees and branches proved landed by a merged PR or local receipt, and empty harness placeholder branches. Known caches (build and tool output, by name) never hold a worktree back; other ignored files do unless `--discard-ignored` is passed. Dry run by default. In a sidecar it also lists entries whose `PR:` pull requests have closed. |
| `check-links.sh` | Relative Markdown links resolve. Cheap drift catcher for hooks or CI. |

## Red flags

Any of these thoughts means stop and do the step you were about to skip.

| Thought | Reality |
| --- | --- |
| "I'll file that idea after I finish this bit" | Ideas evaporate. Write the entry now, with its source, then continue. |
| "It's a one-line fix, I'll just include it" | If it is separately shippable it is a separate entry. The change covers its slug only. |
| "The TODO is empty so I'll take a triage item instead" | Report that the requested queue has nothing ready. Switching queues or stages is the user's call. |
| "Nobody else is working here, I'll skip the claim check" | The check takes seconds and also finds merged work that already resolved the entry. |
| "The author's tests pass, a second reviewer is overkill" | Independent review of self-checked overnight PRs has found bugs the authors' own checks missed. Every code change gets one. |
| "Checks are green, I'll mark it ready" | Ready means checks and independent review are complete, and the review is recorded in a PR comment or local file. |
| "I'll clean the worktrees up later" | Later is when twelve prunable worktrees and sixty placeholder branches make claim checks unreadable. Clean up at landing. |
| "The user said go wild, so pushing is fine" | Autonomy covers implementation. Push, merge, tag and protection changes each need their own word. |
| "The review ledger says 47 open findings, I'll fix a few while I'm here" | Findings are inventory. Work comes from the review backlog or an explicit assignment. |
| "No tests were collected but the job passed" | An empty suite is a failed gate. Fix the selection or the configuration. |

## Scaling the ceremony

Claims, markers and the review ledger pay for themselves when more than
one agent works at once or when sessions hand work to each other. A
solo, interactive session in a small repo still keeps: branch and
worktree per unit of work, hosted or local review, the discovery rule,
the independent reviewer and the check entrypoint. CI on PRs and main
applies where hosted. It may defer: the review ledger (until the first
codebase review is requested), stacked PRs, and the scheduled extended
run (until main has something expensive to validate). Record which
pieces are in force and which are deferred under Optional pieces in the
Docket section of the repository's `AGENTS.md`; silence is read as "all
of it".
