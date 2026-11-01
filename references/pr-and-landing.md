# Change review, stacking, landing and cleanup

## The change description is the commit message

Hosted PRs and approved local branches are squash-landed with the title
as subject and the change description as commit body. The description is
the permanent record. Order, always:

1. `## Why`: the unmet need, bug or risk and the outcome it produces, readable without opening a queue or a conversation. For a feature, the need and the capability; for a bug, the old behaviour and why it was wrong; for internal work, the concrete cost removed.
2. `## What changed`: behaviour and structure, not a file list.
3. The `Type:` line, then the queue markers, one per line (see queues.md and [Labels](#labels)).
4. `## Validation`: exact commands run and their results; for behaviour changes a reproducible scenario with before and after; for review-finding fixes a human-runnable scenario (setup, actions, old failure, expected result); what was not checked (GUI appearance, production state) and why.

The description is timeless: it explains the final change for a future
`git log` reader. The contract defines its content and 72-column
wrapping rule. Review-cycle history belongs in PR comments or local
review/state files, as described in
[parallel-work](parallel-work.md#writer-and-reviewer-pairs). Rewrite a
revised description as a whole. One change does one thing; several
branch commits are fine because the squash folds them. After an
agent-performed landing, verify that the resulting commit contains the
full description once, with the title as subject.

Use the headings in `templates/.github/pull_request_template.md` for
both modes, even if the project has no `.github/` directory. Save local
titles in `.docket/title-<slug>.txt` and descriptions in
`.docket/change-<slug>.md`. Existing `.docket/pr-<slug>.md` files are
usable descriptions and can be renamed when updated. The legacy script
name `check-pr-markers.sh` remains valid for both modes:

```bash
bash docket/scripts/check-pr-markers.sh --body .docket/change-<slug>.md --base main --head HEAD --strict
```

## Local review and approved landing

Choose review mode by repository capability, as the
[contract](../templates/docket/CONTRACT.md#review-mode) specifies. No
remote means local mode automatically. With a non-PR remote, pass
`--local` to claim, start and cleanup helpers. Missing credentials or an
unavailable forge on a PR-capable remote means work waits locally for
publication; it does not turn off hosted policy. No remote or hosted CI
is needed for local review, and local landing never pushes a remote
main.

```bash
bash docket/scripts/claim-check.sh --local <slug>
bash docket/scripts/start-work.sh task <slug> --local
```

Keep `.docket/state-<slug>.md` separate from the description. Record
mode, branch, current base and head commits, actual check results and
limits, independent review location, draft/ready status and the user's
landing approval when given. The review file is
`.docket/review-<slug>.md`. Once implementation, applicable local
checks, marker validation and independent review are complete, report
the branch/worktree, reviewed head, title, description and review paths
and leave them available for the user.

After the user explicitly approves landing that reviewed head:

1. Confirm the branch still has that exact head and that its reviewed
   base is the current local `main`. If main moved, rebase the task,
   rerun gates and review the changed result, then obtain approval for
   its new head. Independent agent approval and readiness are not user
   landing approval.
2. Preserve the title, description, state, review and other unique
   evidence in `.docket/landed-<slug>/` under the retained main
   checkout. Verify the copies, then remove only those preserved source
   artifacts from the task worktree. Use `rmdir` for now-empty directories,
   including `.docket/`; an empty ignored directory can still hold cleanup
   back. If other content remains, preserve and inspect it. Do not use
   blanket `--discard-ignored` to make cleanup pass.
3. From a clean checkout of `main`, run the helper below with the title,
   preserved description and full approved commit ID. Both task and main
   worktrees must be clean, with no operation in progress; the task must
   already be rebased on main. Complete project acceptance gates before
   invoking it; the helper does not supply a human approval or perform
   independent review.

   ```bash
   bash docket/scripts/land-local.sh task/<slug> --title "<change title>" --body .docket/landed-<slug>/change-<slug>.md --approved-head <full-reviewed-sha>
   ```

   On the first installation, or an upgrade whose main lacks the helper,
   keep the working directory at clean main and invoke the installed
   script in the task worktree by absolute path:

   ```bash
   bash /absolute/task-worktree/docket/scripts/land-local.sh task/<slug> --title "<change title>" --body .docket/landed-<slug>/change-<slug>.md --approved-head <full-reviewed-sha>
   ```

   Its script location supplies the installed helpers; the current
   directory supplies the repository and base checkout. After landing,
   main contains the helper and cleanup can use its ordinary installed
   path. Never run the skill's `templates/` copies against the project.

4. Verify the resulting single-parent squash commit and its full
   message. Run main's applicable local gates. The helper records the
   base, exact approved head and squash commit under the common Git
   directory at `docket/landed/<branch>`, with an audit ref at
   `refs/docket/landed/<branch>` retaining the approved commit through
   Git garbage collection. These proof records survive work branch
   cleanup. Cleanup uses the receipt and Git ancestry and tree checks; a
   content match alone is not landing proof.
5. Run cleanup as a dry run and then with `--apply` (with `--local` for
   a non-PR remote). Preserve anything it reports for inspection. Rebase
   stacked children onto the squash commit with the old parent tip: `git
   rebase --onto main <old-parent-tip> <child>`. Revalidate and review
   each child before requesting its own landing approval.

If landing fails, inspect main, the index and the helper's output before
retrying. A completed commit may already exist; never create another
squash blindly or use a destructive reset to clear a partial operation.

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

- The following forge states apply in hosted mode; local state uses the
  same draft/ready gates and the approved landing procedure above.
- **Draft** after the first meaningful commit. Draft is the claim and the coordination surface. Stays draft while implementation, required checks or independent review are incomplete. If a rebase or a fix reopens any of those, convert back to draft.
- **Ready** when the check entrypoint and any change-specific checks passed on the final commit, the queue is resolved in the PR, the markers validate, and the review comment is posted. Ready describes the PR's own scope.
- **Eligible to land** is separate: base is the default branch, required checks are green against the current base, every parent in a stack has landed, and no acceptance gate the queue entry carried is outstanding. A remainder entry cannot waive such a gate. A ready PR that is not eligible says why in a PR comment.
- **Merge** is the user's unless they delegated it for the session or `AGENTS.md` records a standing delegation. Squash. Then confirm the commit body, confirm main's CI run for the push, and clean up (below).

### Direct to main

Two kinds of change may go straight to `main` without a branch, a PR or a review:

1. **Documentation that records work to be done** rather than describing
   behaviour: adding, triaging or splitting entries in `TODO.md` or
   `review/BACKLOG.md`, plans (dated files under `plans/`) and design
   specs (dated files under `docs/specs/`). Plans and specs are planning
   for work, not work; everything they describe still goes through
   branches and independent review in the repository's review mode.
   Going direct is an option, not a requirement: an entry, plan or spec
   drawn up in the middle of other work can be added in that work's PR
   instead, as long as the PR does not start doing what it records.
   Resolving an entry is not in this exception, because resolution
   happens in the PR that does the work. A discovery entry committed
   this way takes no `Files TODO` marker in the PR that found it; that
   marker is for entries added on the branch.
2. **Housekeeping metadata files** such as `.git-blame-ignore-revs`, and only when the user says so for that case. It is a per-case allowance, not a standing rule.

Cases that extrapolate from these without violating the spirit of the
rule are a judgement call; state it in the commit message. Everything
else goes through a reviewed branch, hosted or local: all code, anything
CI or the build reads, and any documentation that describes behaviour as
built or policy (decisions, features, architecture, quality, the
contract itself). Run the proportionate check before committing (`bash
docket/scripts/check-queues.sh` for queue edits, `bash
docket/scripts/check-links.sh` for plans and specs). Pushing the direct
commit follows the session's push authority like any other push: normal
in an interactive session, held for the user under an unattended
autonomy grant. Branch protection has to permit this (administrator
bypass or no required-PR rule), which is why admin enforcement stays off
in repositories that use it.

## Checking PR health

`bash docket/scripts/pr-health.sh` reports, for each of your open PRs,
the head branch, draft or ready, the CI rollup (passing, failing with
the failing check names, pending, or none), the review decision, the
merge state with any conflicts, and how many commits the head is behind
its base. It also lists the queue markers in each body and warns when a
`Claims`, `Resolves` or `Partially resolves` marker names a `TODO.md` or
`review/BACKLOG.md` entry that this checkout no longer has, which means
the queue and the PR disagree. It is read-only and exits 0; `--strict`
exits 1 when any PR has failing checks, changes requested or conflicts.

```bash
bash docket/scripts/pr-health.sh                        # your open PRs here
bash docket/scripts/pr-health.sh --pr 12 --pr 14        # named PRs
bash docket/scripts/pr-health.sh --repo owner/repo      # another repository
bash docket/scripts/pr-health.sh --land-comment "<merge-bot command>"
```

Run it from a checkout of the base branch, since a task worktree has
already removed the entries its PR resolves. Use it:

- at session start, before picking up or reporting on work, so a red
  check or a review asking for changes is seen before anything new
  starts;
- before reporting the status of PRs to the user, instead of describing
  them from memory or from an earlier session's handoff;
- after a landing comment, where the repository lands through a merge
  bot. `--land-comment` takes the command's exact text; an open PR that
  carries it is reported as landing requested with the comment's time,
  and flagged when its checks are failing, because the merge attempt
  then failed or expired and needs a new comment or a fix.

Without `--repo` the script queries the current directory's remote and
ignores an inherited `GH_REPO`; with it, every query names that
repository. Reading the health does not change who lands: merging, and
posting a landing comment, stay the user's unless delegated.

## Keeping branches current

Rebase, never merge main into a branch. In local mode use `git rebase
main` and omit fetch and push; rerun local gates and review before new
approval. The commands below are for a hosted `origin` remote. When a
long branch would conflict in several commits, squashing it to one
commit first keeps the conflict to a single round; the squash merge
discards the internal history anyway. Keep the commits when their
history is worth reviewing separately.

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
bash docket/scripts/cleanup-landed.sh                  # dry run: lists proved landed branches and worktrees
bash docket/scripts/cleanup-landed.sh --apply          # removes clean worktrees, deletes those branches, prunes stale worktree registrations, fetches with --prune
bash docket/scripts/cleanup-landed.sh --apply --empty  # also deletes placeholder branches with no commits, no PR, no worktree
```

The script deletes a branch only when a merged PR or a verified local
landing receipt proves its exact tip landed; later commits are kept and
reported. Deletion succeeds only if the branch still points to the
verified tip, so a concurrently advanced branch is retained. Cleanup
leaves branch-specific Git configuration in place to avoid deleting
settings another worker may be using. When creating a branch,
`start-work.sh` clears stale upstream tracking but preserves other
branch settings. Local receipts come from `land-local.sh`, and are verified
against the current base history and squash tree. Without a PR-capable
remote, use local mode and run local main gates instead of forge CI.
Preserve `.docket/` review artifacts in the retained main checkout
before removal. Dirty worktrees are never removed. Ignored files that
are known caches (`node_modules`, `target`, `.venv`, `__pycache__`,
`.pytest_cache` and similar, at any depth) never hold a worktree back;
any other ignored file (evidence, logs, `.docket/`, an audit log) does,
unless `--discard-ignored` is passed, because it may be the only copy of
a record. The allowlist goes by name, so a directory of records should
not be called `build`, `out`, `dist`, `coverage` or `test-results`. Look
at what is in them (`git -C <path> status --porcelain
--ignored=matching`) and either commit, move or, with the user's word,
discard. Branches with unmerged, unpushed commits are reported, not
deleted; one repository carried an unpushed capacity-measurement branch
for days that nobody knew about. Rebase stacked children onto the new
main as part of the same cleanup. In hosted mode check the push CI run
on main (`gh run list --branch main --limit 3`); in local mode run
main's local gates. Apply the red-main policy if needed.

## Releases

A release tag is a separate decision from the ship commit and the documentation reconciliation. It requires the user's explicit sign-off in the current or immediately preceding turn, even under a broad autonomy grant. Tags point at the commit that the acceptance evidence describes; annotated tags carry the acceptance summary. Deployments and publishing follow the same rule.
