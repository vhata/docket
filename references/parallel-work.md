# Parallel work: coordinator, owners, worktrees and paired review

## Roles

**Coordinator** (the main thread): decomposes the task, owns shared interfaces, dispatches writers and reviewers, integrates, serialises every edit to the queue files, holds the push, merge and release gates, and writes the report. The coordinator writes code only when no one else is available, and then its code gets a reviewer like anyone else's.

**Writer**: one bounded outcome, one branch, one worktree, owned files or components named in the brief. Commits incrementally. Reports what changed, what was verified, what was left out, and any discovery filed.

**Reviewer**: fresh context, did not write the code. Read-only unless dispatched again as a fix agent. Reports findings with evidence; does not edit the author's branch or post to the forge unless the brief says so.

## Decomposing a task

Split along files or components, never along a shared mutable surface. Before dispatching:

1. Name the shared interfaces (types, schemas, protocol, scripts, config) that more than one task touches. Land them first, in their own PR, or stack dependents on that branch explicitly.
2. Pick tasks whose file sets are disjoint. If two tasks must touch the same file, one owner does both or one feeds the other a patch through the coordinator.
3. Hold back items that would confound another task's measurements (a behaviour change while someone is baselining behaviour).
4. Cap concurrency for heavy builds or simulations. Four concurrent agents is a reasonable default where each fresh worktree compiles the project; write the repository's own cap into `AGENTS.md`. One session recorded a load average near 150 before a cap existed.
5. Decide what runs where. Expensive processes get an explicit limit per agent, and tests that share ports, caches, databases or browser profiles need per-worktree paths (see Isolation).

## Worktrees and branches

- Branch: `<queue>/<slug>` for queued work (`todo/`, `review/`, `roadmap/`), `fix/<slug>` for directly requested fixes, `task/<slug>` for other direct requests. The slug appears verbatim so claim checks find it.
- Worktree: use the harness's native tool when it has one (it owns placement and cleanup), naming the branch `<queue>/<slug>` and running the claim check first. Otherwise `.worktrees/<queue>-<slug>` under the repository root, ignored by git. A repository-local ignored directory survives temp-directory cleaning; worktrees under `/tmp` left twelve prunable registrations and fifteen orphaned branches in one repository.
- Create the branch and worktree before investigating. `bash scripts/start-work.sh <queue> <slug>` does the claim check and creation.
- Run the repository's setup script in the new worktree (dependencies, hooks). Hooks installed into the shared `.git/hooks` cover every worktree; hooks managed through `core.hooksPath` pointing at a tracked directory also do.
- Baseline before changing anything: run the check entrypoint once so later failures are attributable.

### Isolation

Each worktree owns its mutable state: virtualenv or `node_modules`, tool caches, test databases, browser profiles, evidence directories, dev-server ports. Put per-worktree paths under the worktree (a `.cache/` or `.runtime/` directory, ignored) and have scripts resolve tools relative to the worktree, never through another worktree's environment or a shared interpreter. Package managers that symlink or hoist across directories have committed a `node_modules` symlink from a worktree before; make sure the ignore rules cover bare names, not just root paths.

## Briefing an agent

A brief is self-contained. The agent does not see the conversation. Include, in this order:

```markdown
Task: <one sentence outcome>. Queue entry: <queue> `<slug>` (quote the entry).
You work in your own worktree on branch <branch>. Refer to files by paths relative to the worktree root (e.g. `src/foo.ts`), never by absolute paths into the main checkout.
Owned files/components: <list>. Do not edit: <list>. Other agents are working on: <list>.
Shared interfaces you depend on: <names, and whether they are landed or stacked>.
Environment constraints: <concurrency cap, "never open a GUI window", "do not start the dev server", ports to use>.
Checks: run <entrypoint> and <specific checks>; report exact commands and results. An empty or skipped suite is a failure, not a pass.
Git: commit incrementally with single-purpose messages in the repo's style; no attribution trailers; do not change `git config` (the coordinator sets the repository's identity once, before the first commit); never push, never merge, never tag.
If you discover something separately shippable, do not fix it; report it as a discovery with the evidence and where it belongs.
If blocked on a decision the brief does not settle, stop and report the options.
Return: a short report with what changed, what was verified (commands and results), what was left out and why, discoveries, and the PR body draft (## Why first).
```

Why these lines: an agent briefed with absolute paths into the main checkout wrote its half-finished files there and broke the main thread's typecheck; an agent that set `git config user.email` changed the shared repository config; an agent allowed to open the GUI popped windows on the user's desktop; agents that stalled on long tasks were recovered by "commit incrementally" and by resuming the same agent rather than starting over.

## Writer and reviewer pairs

Every PR that changes code gets a reviewer who did not write it, including the coordinator's own code and the integration commits. Measurement-only and documentation-only PRs get a lighter review of their claims. The pipeline is writer, reviewer, fix if needed, ready.

Reviewer brief:

```markdown
Review branch <branch> (commits <base>..<head>) against this PR description: <body>.
You are not the author. Read the full diff and enough surrounding code to judge it. Verify the description's claims independently: rerun the decisive checks (name them), reproduce any "before" behaviour the description claims to fix, and where the change claims to be behaviour-neutral, prove it on an input the author did not use.
Hunt for correctness bugs, missing error handling, scope creep beyond the slug, undocumented behaviour changes, and tests that would pass with the bug present (mutation-test new tests by breaking the code they cover).
Do not edit files or comment on the forge. Report: verdict (approve, approve with nits, changes needed), each finding with location, failure scenario and evidence, which claims you verified and how, and anything you could not check.
```

After the review: confirmed findings are fixed on the same branch by the writer or a fix agent; the reviewer (or a fresh one) confirms the fixes against the original failure. A reviewer who starts fixing has become an author for that scope and needs a different reviewer for it; one reviewer may cover several independent authors. Then the PR body gets:

```markdown
## Review
Independent review by <agent/model> at <commit>: <verdict>. Verified: <claims rechecked and how>. Findings: <n> (<fixed in <commit> | disposition with reason>). Not checked: <gaps, e.g. GUI appearance>.
```

A fix agent writes the review section only after reading the review itself; one wrote a section without having seen the review and the coordinator had to redo it.

Why the pair is mandatory: in one repository a single post-merge pass over 25 self-checked overnight PRs found three real bugs the authors' own checks had missed. On the forge, all three repositories studied show zero review records; the PR body section is what makes the review auditable later.

## Integration

The coordinator integrates after each writer reports. Passing checks on isolated branches does not establish that their combination works; two gates that each passed alone contradicted each other once they met on main. Before marking a set of related PRs ready, either rebase each onto the others in merge order and run the check entrypoint on the result, or build a disposable integration worktree that combines them and run the checks there. Record the integration check in the coordinator's report.

Keep linear history: rebase, never merge main into a branch. To limit conflict rounds, squash the branch to one commit (`git reset --soft $(git merge-base origin/main HEAD) && git commit`) before `git rebase origin/main`, then `git push --force-with-lease` the PR branch. Queue files and decision logs are where nearly every branch conflicts; expect it, and resolve in the branch, never with a merge commit.

## Autonomy modes

Which mode is in force is said at the top of the session and written to the audit log.

| Mode | Push | Draft PRs | Merge | What the user finds |
| --- | --- | --- | --- | --- |
| Interactive | yes | yes, after first commit | user, or agent when told in that turn | ready PRs with review sections |
| Fan-out with PRs ("put PRs up while I'm away") | yes | yes | user | ready PRs, one per item, plus a summary |
| Unattended without push authority ("I'm going to bed") | no | no | no | local branches, `.feral/pr-<slug>.md` bodies, `AUDIT.md`, a report |

In the unattended mode, claims are not globally visible. Say so in the audit log. Stack dependent plan steps branch on branch rather than waiting for merges, and record the merge order in the report. Publishing in the morning is one command per branch: `git push -u origin <branch> && gh pr create --head <branch> --title "<title>" --body-file .feral/pr-<slug>.md`.

### Audit log

`AUDIT.md` at the repository root, excluded from git through `.git/info/exclude` (so it never reaches a PR), append-only. Each session opens with a scope entry stating what is authorised. Each load-bearing decision (interface change, approach chosen over alternatives, dependency added, behaviour changed, work held back) gets:

```markdown
## 2026-09-23 00:12 — <title>
**Chose:** what, concretely.
**Why:** reasoning and the alternatives discarded.
**Undo by:** one command or file (git branch -D ..., git revert <sha>, rm path).
**Status:** done | needs review | blocked | in progress
```

### Report

End every fan-out or unattended run with: branches and their state in merge order; decisions logged (count, pointer to the audit); discoveries reported by writers and the slug each was filed under (any still pending are listed as pending, not dropped); items held back and why; what needs the user (design calls, GUI checks, encoding choices); expected rebase conflicts. The detail lives in the audit and PR bodies; the report is the index.

## Harness pitfalls seen in practice

- Placeholder branches (`worktree-agent-*`) accumulate with no commits; `bash scripts/cleanup-landed.sh --empty` removes them.
- Agents in worktrees cannot write into the main checkout; have them leave PR bodies and reports in their own worktree and let the coordinator copy them.
- Watchdog timeouts kill long single commands; prefer several shorter commands and incremental commits.
- Concurrency groups that cancel in-progress runs on pushes to main hide red main builds when several PRs merge quickly; see quality-gates.
