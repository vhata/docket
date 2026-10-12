# Pull requests, stacking, landing and cleanup

## The PR body is the commit message

PRs are squash-merged with the title as subject and the body as commit body, so the body is the permanent record. Order, always:

1. `## Why`: the unmet need, bug or risk and the outcome it produces, readable without opening a queue or a conversation. For a feature, the need and the capability; for a bug, the old behaviour and why it was wrong; for internal work, the concrete cost removed.
2. `## What changed`: behaviour and structure, not a file list.
3. The `Type:` line, then the queue markers, one per line (see queues.md and [Labels](#labels)).
4. `## Validation`: exact commands run and their results; for behaviour changes a reproducible scenario with before and after; for review-finding fixes a human-runnable scenario (setup, actions, old failure, expected result); what was not checked (GUI appearance, production state) and why.
5. `## Review`: independent reviewer, commit reviewed, verdict, verified claims, findings and dispositions (see parallel-work.md).

The body is timeless: it describes the change as it will read in `git log` years later, so nothing in it refers to the state of the review (stacking, merge order, what is still to do, other open PRs). That goes in a PR comment or the coordinator's report. Never merge with a one-line body. The body is hard-wrapped at 72 columns like any commit message (the rule and its exceptions are in the contract's workflow section); a body wrapped wider lost its shape in one repository, where the squash re-wrapped every long line at 72 and left a word or two stranded on the line after it throughout the commit message. `check-pr-markers.sh` warns on prose lines over 72 characters and fails them under `--strict`. One PR does one thing; several commits inside it are fine because the squash folds them. After an agent-performed merge, confirm the resulting commit body is the full PR body and not just the subject (one commit on record has its body pasted twice; another has only the title).

Template: `templates/.github/pull_request_template.md`. Keep the template's headings even when the sections are short; later PRs in two repositories dropped the template entirely and the marker and validation lines became hard to find.

## Labels

The author knows what kind of change a PR is and which queue entry it serves; the branch name and the markers record some of that, but only in a form a reader has to parse. Labels make it queryable by GitHub search, dashboards and anything else that reads the forge's API. The body records the change type as one line, `Type: <kind>`, with the kind one of `feature`, `fix`, `refactor`, `perf`, `docs`, `test`, `tooling` (scripts, CI, hooks, dependencies) or `review` (codebase review snapshots). Being in the body, it also lands in the squash commit, so the history keeps it after the forge is gone.

`bash docket/scripts/pr-labels.sh --pr <number> --apply` derives every label from the branch, the body and the queue files, so none is chosen by hand:

| Label | Source |
| --- | --- |
| `docket` | Every PR made under Docket. |
| `type:<kind>` | The `Type:` line; a `fix/` branch without one is `type:fix`. |
| `queue:todo`, `queue:review`, `queue:roadmap` | Each queue the markers claim or resolve work in, and the queue a `todo/`, `review/` or `roadmap/` branch names. No queue label means directly requested work. |
| `area:<area>` | The `[AREA]` of each claimed or resolved entry, lowercased. |
| `priority:p0` to `priority:p3` | The highest priority section among those entries; Unprioritized adds none. |

Run it once the PR is open and again after changing the `Type:` line or the markers; it creates missing labels in the repository without restyling existing ones, adds what applies and removes labels of these forms that no longer do, and leaves every other label alone. Without `--apply` (with `--body <file>` for an unpublished body) it only prints the labels. `check-pr-markers.sh` warns when the `Type:` line is missing and fails a malformed or repeated one. Draft state, base branch, review state and checks are already on the PR itself, so no label duplicates them.

## Draft, ready, merge

- **Draft** after the first meaningful commit. Draft is the claim and the coordination surface. Stays draft while implementation, required checks or independent review are incomplete. If a rebase or a fix reopens any of those, convert back to draft.
- **Ready** when the check entrypoint and any change-specific checks passed on the final commit, the queue is resolved in the PR, the markers validate, and the review section is filled in. Ready describes the PR's own scope.
- **Eligible to land** is separate: base is the default branch, required checks are green against the current base, every parent in a stack has landed, and no acceptance gate the queue entry carried is outstanding. A remainder entry cannot waive such a gate. A ready PR that is not eligible says why in its body.
- **Merge** is the user's unless they delegated it for the session or `AGENTS.md` records a standing delegation. Squash. Then confirm the commit body, confirm main's CI run for the push, and clean up (below).

### Direct to main

Two kinds of change may go straight to `main` without a branch, a PR or a review:

1. **Documentation that records work to be done** rather than describing behaviour: adding, triaging or splitting entries in `TODO.md` or `review/BACKLOG.md`, plans (dated files under `plans/`) and design specs (dated files under `docs/specs/`). Plans and specs are planning for work, not work; everything they describe still goes through branches, PRs and independent review. Going direct is an option, not a requirement: an entry, plan or spec drawn up in the middle of other work can be added in that work's PR instead, as long as the PR does not start doing what it records. Resolving an entry is not in this exception, because resolution happens in the PR that does the work. A discovery entry committed this way takes no `Files TODO` marker in the PR that found it; that marker is for entries added on the branch.
2. **Housekeeping metadata files** such as `.git-blame-ignore-revs`, and only when the user says so for that case. It is a per-case allowance, not a standing rule.

Cases that extrapolate from these without violating the spirit of the rule are a judgement call; state it in the commit message. Everything else goes through a PR: all code, anything CI or the build reads, and any documentation that describes behaviour as built or policy (decisions, features, architecture, quality, the contract itself). Run the proportionate check before committing (`bash docket/scripts/check-queues.sh` for queue edits, `bash docket/scripts/check-links.sh` for plans and specs). Pushing the direct commit follows the session's push authority like any other push: normal in an interactive session, held for the user under an unattended autonomy grant. Branch protection has to permit this (administrator bypass or no required-PR rule), which is why admin enforcement stays off in repositories that use it.

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

- Child branch starts from the parent branch. Child PR base is the parent branch: `gh pr create --base <parent-branch>`. The stacking and the merge order go in a PR comment and the coordinator's report, never in the body, which becomes the commit message.
- Shared-contract parents land first. Children show only their own diff while the base is the parent branch.
- **When the parent merges**: rebase the child onto main immediately (`git rebase --onto origin/main <old-parent-tip> <child>`, or the squash-then-rebase flow above), retarget the PR (`gh pr edit <child> --base main`), force-with-lease, let CI run again. GitHub retargets children automatically only when the parent branch is deleted on merge and the event arrives; verify `gh pr view <child> --json baseRefName` rather than assume.
- **Never merge a PR whose base is not the default branch.** One repository merged a child into its already-squashed parent branch, orphaning the engine code and forcing a hand cherry-pick onto main. Before any merge: `gh pr view N --json baseRefName,mergeStateStatus`.
- The `gh stack` extension automates init, rebase, submit and ordered merge for stacks. It consumes issue numbers for stack objects, and `submit --auto` generates titles from branch names, so set titles and bodies afterwards. Native stacking is optional; the rules above hold either way.
- Expect many force-pushes and draft/ready flips while a stack lands; convert children back to draft while they are being rebased so nobody merges a stale one.

## After landing: cleanup

Run after every merge, or at least at the end of every session:

```bash
bash docket/scripts/cleanup-landed.sh                  # dry run: lists branches whose PRs merged and their worktrees
bash docket/scripts/cleanup-landed.sh --apply          # removes clean worktrees, deletes those branches, prunes stale worktree registrations, fetches with --prune
bash docket/scripts/cleanup-landed.sh --apply --empty  # also deletes placeholder branches with no commits, no PR, no worktree
```

The script deletes a branch only when its tip is the exact commit a merged PR landed; a branch with commits after that is kept and reported. Dirty worktrees are never removed. Ignored files that are known caches (`node_modules`, `target`, `.venv`, `__pycache__`, `.pytest_cache` and similar, at any depth) never hold a worktree back; any other ignored file (evidence, logs, `.docket/`, an audit log) does, unless `--discard-ignored` is passed, because it may be the only copy of a record. The allowlist goes by name, so a directory of records should not be called `build`, `out`, `dist`, `coverage` or `test-results`. Look at what is in them (`git -C <path> status --porcelain --ignored=matching`) and either commit, move or, with the user's word, discard. Branches with unmerged, unpushed commits are reported, not deleted; one repository carried an unpushed capacity-measurement branch for days that nobody knew about. Rebase stacked children onto the new main as part of the same cleanup. Then check the push CI run on main (`gh run list --branch main --limit 3`) and apply the red-main policy if needed.

## Releases

A release tag is a separate decision from the ship commit and the documentation reconciliation. It requires the user's explicit sign-off in the current or immediately preceding turn, even under a broad autonomy grant. Tags point at the commit that the acceptance evidence describes; annotated tags carry the acceptance summary. Deployments and publishing follow the same rule.
