# Pull requests, stacking, landing and cleanup

## The PR body is the commit message

PRs are squash-merged with the title as subject and the body as commit body, so the body is the permanent record. Order, always:

1. `## Why`: the unmet need, bug or risk and the outcome it produces, readable without opening a queue or a conversation. For a feature, the need and the capability; for a bug, the old behaviour and why it was wrong; for internal work, the concrete cost removed.
2. `## What changed`: behaviour and structure, not a file list.
3. Markers, one per line (see queues.md).
4. `## Validation`: exact commands run and their results; for behaviour changes a reproducible scenario with before and after; for review-finding fixes a human-runnable scenario (setup, actions, old failure, expected result); what was not checked (GUI appearance, production state) and why.
5. `## Review`: independent reviewer, commit reviewed, verdict, verified claims, findings and dispositions (see parallel-work.md).

Never merge with a one-line body. One PR does one thing; several commits inside it are fine because the squash folds them. After an agent-performed merge, confirm the resulting commit body is the full PR body and not just the subject (one commit on record has its body pasted twice; another has only the title).

Template: `templates/.github/pull_request_template.md`. Keep the template's headings even when the sections are short; later PRs in two repositories dropped the template entirely and the marker and validation lines became hard to find.

## Draft, ready, merge

- **Draft** after the first meaningful commit. Draft is the claim and the coordination surface. Stays draft while implementation, required checks or independent review are incomplete. If a rebase or a fix reopens any of those, convert back to draft.
- **Ready** when the check entrypoint and any change-specific checks passed on the final commit, the queue is resolved in the PR, the markers validate, and the review section is filled in. Ready describes the PR's own scope.
- **Eligible to land** is separate: base is the default branch, required checks are green against the current base, every parent in a stack has landed, and no acceptance gate the queue entry carried is outstanding. A remainder entry cannot waive such a gate. A ready PR that is not eligible says why in its body.
- **Merge** is the user's unless they delegated it for the session or `AGENTS.md` records a standing delegation. Squash. Then confirm the commit body, confirm main's CI run for the push, and clean up (below).

### Direct to main

Two kinds of change go straight to `main` without a branch, a PR or a review:

1. **Documentation that records work to be done** rather than describing behaviour: adding or triaging entries in `TODO.md` or `review/BACKLOG.md`, and plans (dated files under `plans/`). A plan is planning for work, not work; everything it describes still goes through branches, PRs and independent review. Resolving an entry is not in this exception, because resolution happens in the PR that does the work.
2. **Housekeeping metadata files** such as `.git-blame-ignore-revs`, and only when the user says so for that case. It is a per-case allowance, not a standing rule.

Cases that extrapolate from these without violating the spirit of the rule are a judgement call; state it in the commit message. Everything else goes through a PR: all code, anything CI or the build reads, and any documentation that describes behaviour or policy (decisions, features, architecture, quality, the contract itself). Run the proportionate check before committing (`bash scripts/workflow/check-queues.sh` for queue edits, `bash scripts/workflow/check-links.sh` for plans). Pushing the direct commit follows the session's push authority like any other push: normal in an interactive session, held for the user under an unattended autonomy grant. Branch protection has to permit this (administrator bypass or no required-PR rule), which is why admin enforcement stays off in repositories that use it.

## Keeping branches current

Rebase, never merge main into a branch. When a long branch would conflict in several commits, squashing it to one commit first keeps the conflict to a single round; the squash merge discards the internal history anyway. Keep the commits when their history is worth reviewing separately.

```bash
git fetch origin
git reset --soft "$(git merge-base origin/main HEAD)" && git commit -m "<PR title>"   # optional: one commit, one conflict round
git rebase origin/main
bash scripts/check.sh
git push --force-with-lease
```

`--force-with-lease` on the PR branch only. Main is protected against force pushes and that stays a hard boundary. Expect queue files and decision logs to conflict on nearly every rebase; resolve them in the branch.

## Stacked PRs

Stack when step N+1 cannot start until step N's code exists and waiting for N to merge would stall the work (plan steps, a contract PR followed by implementations). Do not stack independent work; independent work gets independent branches off main.

- Child branch starts from the parent branch. Child PR base is the parent branch: `gh pr create --base <parent-branch>`. Body says `Stacked on #N` and the merge order is written in the coordinator's report.
- Shared-contract parents land first. Children show only their own diff while the base is the parent branch.
- **When the parent merges**: rebase the child onto main immediately (`git rebase --onto origin/main <old-parent-tip> <child>`, or the squash-then-rebase flow above), retarget the PR (`gh pr edit <child> --base main`), force-with-lease, let CI run again. GitHub retargets children automatically only when the parent branch is deleted on merge and the event arrives; verify `gh pr view <child> --json baseRefName` rather than assume.
- **Never merge a PR whose base is not the default branch.** One repository merged a child into its already-squashed parent branch, orphaning the engine code and forcing a hand cherry-pick onto main. Before any merge: `gh pr view N --json baseRefName,mergeStateStatus`.
- The `gh stack` extension automates init, rebase, submit and ordered merge for stacks. It consumes issue numbers for stack objects, and `submit --auto` generates titles from branch names, so set titles and bodies afterwards. Native stacking is optional; the rules above hold either way.
- Expect many force-pushes and draft/ready flips while a stack lands; convert children back to draft while they are being rebased so nobody merges a stale one.

## After landing: cleanup

Run after every merge, or at least at the end of every session:

```bash
bash scripts/cleanup-landed.sh            # dry run: lists branches whose PRs merged and their worktrees
bash scripts/cleanup-landed.sh --apply    # removes clean worktrees and deletes those branches
bash scripts/cleanup-landed.sh --apply --empty   # also deletes placeholder branches with no commits, no PR, no worktree
git worktree prune; git fetch --prune
```

The script deletes a branch only when its tip is the exact commit a merged PR landed; a branch with commits after that is kept and reported. Dirty worktrees are never removed; worktrees holding ignored files (evidence, `.feral/`) are kept unless told otherwise. Look at what is in them (`git -C <path> status --porcelain --ignored -uall`) and either commit, move or, with the user's word, discard. Branches with unmerged, unpushed commits are reported, not deleted; one repository carried an unpushed capacity-measurement branch for days that nobody knew about. Rebase stacked children onto the new main as part of the same cleanup. Then check the push CI run on main (`gh run list --branch main --limit 3`) and apply the red-main policy if needed.

## Releases

A release tag is a separate decision from the ship commit and the documentation reconciliation. It requires the user's explicit sign-off in the current or immediately preceding turn, even under a broad autonomy grant. Tags point at the commit that the acceptance evidence describes; annotated tags carry the acceptance summary. Deployments and publishing follow the same rule.
