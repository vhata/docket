---
name: docket
description: Use when adopting, repairing, auditing or comparing a repository's agent workflow (queues, worktrees, paired review, gates, review ledger); when coordinating a multi-agent fan-out or an unattended run; when running a full or incremental codebase review; when triaging the queues; or when cleaning up after PRs land. Not needed for ordinary single-task work in a repository whose AGENTS.md and guides already encode the workflow; those documents are sufficient there.
---

# Docket

A project run this way answers four questions from its own files at any moment: what is being worked on, what is ready to work on, what was decided, and what is known to be broken. Everything below exists to keep those answers true while many agents work at once.

**Core principle:** every unit of work is a branch, a worktree, a draft PR with an exact claim, an independent review, and a cleanup. Every idea that is not that unit of work goes into a queue, immediately, and the current work continues. Two things may go straight to `main` without a branch: documentation that records work to be done (queue entries, triage, plans, design specs; these may also ride along in whatever PR they came up in, which does not then do that work), and housekeeping metadata files when the user says so for that case; see [pr-and-landing](references/pr-and-landing.md#direct-to-main).

The repository's own `AGENTS.md` and guides win wherever they exist and are what an agent reads for everyday work; this skill is for the operations below, and for installing those guides where they are missing (see `references/setup.md`). Loading it for an ordinary implementation task in an already-set-up repository spends context on rules the repository already states.

## Quick start

The user needs only these phrases; this skill works out the rest by inspecting the repository first.

| The user says | What it means |
| --- | --- |
| "Use docket to set up or audit this project" | Inspect first. A project with a contract gets an audit and repairs on a branch; one without gets the workflow installed; an empty one gets initialised before any product code. Propose hosting settings, never apply them. If the repository records a policy that conflicts with the default model (for example one queue, no markers), report the conflict and ask which way to go before changing it. |
| "Use docket to do a full / incremental review" | The codebase review procedure in [reviews](references/reviews.md), landed as its own PR. |
| "Use docket to fan out the ready TODOs" / "run overnight" | The coordinator procedure in [parallel-work](references/parallel-work.md), with the autonomy mode stated up front. |
| "Grab a TODO" / any single task | Not this skill. The repository's `AGENTS.md` and guides. |

## Choose the operation

| Operation | Read | Tools |
| --- | --- | --- |
| Adopt, repair, audit or compare the workflow in a repository | [setup](references/setup.md), then the pillar references it points to | `install.sh [--check]`, `check-queues`, `check-links`, `review-due`, `gh api` protection inspection |
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
| Paired review | Every code-writing agent gets a separate reviewer agent before the PR is called ready. The reviewer verifies claims, the author fixes, the PR body records who reviewed what. | [parallel-work](references/parallel-work.md#writer-and-reviewer-pairs) |
| Queues, not tangents | Discoveries become queue entries with a source, in the repository that owns them, then the current task resumes. Ready means unblocked. Claims are exact slugs in draft PRs. | [queues](references/queues.md) |
| Gates everywhere | Fast hooks, full CI on PRs and on pushes to main, scheduled extended runs on main, protection that makes the user's merge safe rather than ceremonial. Empty suites never pass. | [quality-gates](references/quality-gates.md) |
| Review ledger | Full reviews record a revision and findings; incremental reviews start from the last revision and verify claimed fixes. Findings are promoted deliberately into a review backlog. | [reviews](references/reviews.md) |

PRs, stacking, landing and cleanup are in [pr-and-landing](references/pr-and-landing.md). Installing or adapting the system is in [setup](references/setup.md).

## The unit of work, start to finish

Script paths below are the installed paths (`docket/scripts/`), the only ones anyone runs; the skill's `templates/docket/scripts/` copies reach a repository only through `install.sh` (see Bundled tools).

1. **Select.** Follow the user's selection, or take the highest-priority unclaimed entry from the named queue in its Ready section. Never switch queues or stages because the requested one is empty; report that instead.
2. **Check claims.** `bash docket/scripts/claim-check.sh <slug>` (open and merged PRs, branches, worktrees, mapped findings). A matching branch or worktree is a provisional claim. Overlap means stop and coordinate, not race.
3. **Branch and worktree first.** `bash docket/scripts/start-work.sh <queue> <slug>` creates `<queue>/<slug>` in an ignored `.worktrees/` directory before any investigation, so the claim is visible immediately. If the harness has its own worktree tool, use it instead for the worktree, but keep the claim check and the `<queue>/<slug>` branch name; the name is what later claim checks find.
4. **Commit early, draft early.** After the first meaningful commit, open a draft PR whose body starts with `## Why` and carries a `Type: <kind>` line and `Claims <queue>: <slug>`, then label it with `bash docket/scripts/pr-labels.sh --pr <number> --apply` (see [pr-and-landing](references/pr-and-landing.md#labels)). Keep the queue entry in place while the work is underway. When no PR can be opened (no remote, no forge access, no push authority), save the body as `.docket/pr-<slug>.md`, record in the report that the claim is local-only, and leave the branch and worktree in place for the user.
5. **Stay on task.** Fixes needed for the requested outcome, its correctness or its verification are in scope. Anything separately shippable gets a queue entry with a `Source:` line and, when the entry is added on the branch rather than committed to `main`, a `Files TODO: <slug>` marker in the PR; then the work continues. An unrelated P0 (data loss, security, release blocker) is reported immediately and work pauses for direction.
6. **Verify.** Run the repository's check entrypoint (`scripts/check.sh` by convention) plus whatever the change needs beyond it. Record what was run and what was not.
7. **Independent review.** A reviewer agent that did not write the code reads the diff against the PR's claims, reruns the decisive checks, and reports findings. Authors fix; the reviewer confirms the fixes. The PR body gains a `## Review` section naming reviewer, commit reviewed, and dispositions.
8. **Resolve the queue.** Remove the entry in the same PR and change the marker to `Resolves <queue>: <slug>`, or file a remainder with a new slug and `Remaining from:` for partial work. `bash docket/scripts/check-pr-markers.sh --body <file>` validates the markers against the queue files (compares `origin/main` to `HEAD` by default; pass `--base`/`--head` for anything else).
9. **Ready, then the user merges.** Ready means checks and independent review are complete for this PR's own scope. Eligible to land is separate: base is main, required checks are green on the current base, any parent in a stack has landed, and no acceptance gate the queue entry carried is outstanding. A remainder entry never waives an acceptance gate the original entry carried. Merge only when told to in that turn or under a recorded delegation: squash, PR title as subject, PR body as commit body.
10. **Clean up.** After landing: `bash docket/scripts/cleanup-landed.sh --apply` removes the worktree and branch, rebase any stacked children onto main and retarget them, and re-check main's CI. Nothing of the task survives except the commit and the queue change.

## Authorisation ladder

Autonomy grants cover implementation. Which other actions need the user's word, and when:

| Action | Needs explicit go-ahead |
| --- | --- |
| Push a branch, open a draft PR | Interactive sessions: normal, no ask. Unattended autonomy grants: only with the user's word; otherwise branches stay local (see below) |
| Mark a PR ready | No, once checks and independent review are complete |
| Merge into main | Yes, in that turn, unless the user delegated it for the session or `AGENTS.md` records a standing delegation |
| Force-push | Only the PR branch, only `--force-with-lease`, only after a rebase. Never main, even where GitHub allows it; that ability is the owner's, for recovery. |
| Release tag, deploy, publish | Yes, in that turn or the one before, even under "go wild" |
| Change CI, branch protection, hooks policy | Yes |
| Delete a branch with unmerged commits, remove a dirty worktree | Yes |
| Commit directly to main | Work-recording documentation (TODO entries, triage, plans, design specs): normal. Housekeeping metadata such as `.git-blame-ignore-revs`: only when the user says so for that case. Nothing else; pushing the commit follows the session's push authority |

Under an autonomy grant without push authority, work lands on local branches with the finished PR body saved to `.docket/pr-<slug>.md` and every load-bearing decision appended to `.docket/AUDIT.md` with an undo line. See [parallel-work](references/parallel-work.md#autonomy-modes).

## Bundled tools

All scripts are portable shell (bash 3.2) and need only git, plus `gh` where PRs are involved. They live in the skill under `templates/docket/scripts/` and reach a repository only through `bash ~/.claude/skills/docket/install.sh` (the path is wherever the skill is installed; that one is the Claude Code default), run from inside that repository, which copies the whole `templates/docket/` directory to `docket/` verbatim; `install.sh --check` reports drift without writing. Both compare against the skill checkout they run from, so that checkout must be at or beyond the commit in `docket/VERSION`; from an older checkout `--check` reports that the installed copy is newer and exits 1 without a diff (see [setup](references/setup.md#the-vendored-directory)). Run the installed copies as `bash docket/scripts/<name>.sh`; that is the path the contract, the guides and CI use, so agents without this skill run the same tools. Nobody runs the skill's copies against a repository directly: when `docket/` is missing or stale, install first. Every script acts on the repository of the current directory.

| Script | Purpose |
| --- | --- |
| `ci.sh` | Runs `check-queues.sh --strict`, `check-links.sh` and, on pull requests, `check-pr-markers.sh` (reads `PR`, `BASE`, `HEAD_BRANCH`, `GH_TOKEN` and `GITHUB_EVENT_PATH` from the environment; the PR body comes from the event payload when it is available, otherwise from `gh pr view`). The one hygiene step CI calls. |
| `check-queues.sh [--strict]` | Validates TODO.md and review/BACKLOG.md: entry format, unique slugs, Source lines, resolvable `Related`/`Depends on`, no Ready entry blocked by unresolved work, one finding per backlog entry. Run in CI. |
| `check-pr-markers.sh --body FILE \| --pr N` | Validates PR markers against the queues at base and head, checks the `Type:` line, fails a body whose first heading is not `## Why`, and requires a Validation section for finding fixes. Run in CI on pull requests. |
| `pr-labels.sh --pr N [--apply] \| --body FILE` | Derives the PR's labels (`docket`, `type:`, `queue:`, `area:`, `priority:`) from the branch, the `Type:` line and the claimed or resolved queue entries; `--apply` creates missing labels and sets them on the PR. |
| `claim-check.sh [--self] <slug>...` | Finds existing claims across PRs, branches and worktrees, following backlog findings. `--self` is the recheck from inside the claimed worktree: it ignores the worker's own branch and pushed copy but not another worker's. |
| `start-work.sh <queue> <slug>` | Claim check, then branch plus worktree with the repository's naming. |
| `review-due.sh [--paths ...]` | Reads the review index, measures drift since the reviewed commit, says whether an incremental or full review is due. |
| `cleanup-landed.sh [--apply] [--empty] [--discard-ignored]` | Removes worktrees and branches whose PRs merged, and empty harness placeholder branches. Known caches (build and tool output, by name) never hold a worktree back; other ignored files do unless `--discard-ignored` is passed. Dry run by default. |
| `check-links.sh` | Relative Markdown links resolve. Cheap drift catcher for hooks or CI. |

## Red flags

Any of these thoughts means stop and do the step you were about to skip.

| Thought | Reality |
| --- | --- |
| "I'll file that idea after I finish this bit" | Ideas evaporate. Write the entry now, with its source, then continue. |
| "It's a one-line fix, I'll just include it" | If it is separately shippable it is a separate entry. The PR covers its slug only. |
| "The TODO is empty so I'll take a triage item instead" | Report that the requested queue has nothing ready. Switching queues or stages is the user's call. |
| "Nobody else is working here, I'll skip the claim check" | The check takes seconds and also finds merged work that already resolved the entry. |
| "The author's tests pass, a second reviewer is overkill" | Independent review of self-checked overnight PRs has found bugs the authors' own checks missed. Every code PR gets one. |
| "Checks are green, I'll mark it ready" | Ready means checks and independent review are complete and recorded in the body. |
| "I'll clean the worktrees up later" | Later is when twelve prunable worktrees and sixty placeholder branches make claim checks unreadable. Clean up at landing. |
| "The user said go wild, so pushing is fine" | Autonomy covers implementation. Push, merge, tag and protection changes each need their own word. |
| "The review ledger says 47 open findings, I'll fix a few while I'm here" | Findings are inventory. Work comes from the review backlog or an explicit assignment. |
| "No tests were collected but the job passed" | An empty suite is a failed gate. Fix the selection or the configuration. |

## Scaling the ceremony

Claims, markers and the review ledger pay for themselves when more than one agent works at once or when sessions hand work to each other. A solo, interactive session in a small repo still keeps: branch and PR per unit of work, the discovery rule, the independent reviewer, the check entrypoint, CI on PRs and main. It may defer: the review ledger (until the first codebase review is requested), stacked PRs, and the scheduled extended run (until main has something expensive to validate). Record which pieces are in force and which are deferred under Optional pieces in the Docket section of the repository's `AGENTS.md`; silence is read as "all of it".
