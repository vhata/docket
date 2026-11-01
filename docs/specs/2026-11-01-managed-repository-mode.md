# Managed repository mode: a docket sidecar for a repository it cannot live in

## Context

Some repositories can't take a docket installation. A large shared monorepo
has its own owners, CI, PR template, hooks and merge process, and one
contributor can't add `docket/`, `TODO.md` or a review ledger to it. That
contributor may still want docket's queues, plans, independent review, PR
tracking and their own checks for the work they do there.

The idea is a small repository per project (the "sidecar") that holds docket,
the queues, plans and the user's own checks, while branches, PRs and CI happen
in a separate repository (the "managed repository") whose policies the user
does not control.

Verdict: **feasible, and part of it works today with no changes.** The
planning half of docket (queues, plans, decisions, audit, the validators that
read Markdown) is repository-agnostic. The execution half (claim, start,
markers, labels, cleanup, review ledger) assumes the managed code is the
repository docket is installed in. `ARCHITECTURE.md` says so outright, and
every script starts by resolving `git rev-parse --show-toplevel`. Closing that
gap needs a managed-repository setting and changes to about five scripts. No
restructuring.

## What works in a sidecar today, unchanged

- `TODO.md`, the stages, priorities and `check-queues.sh --strict`. Entries
  are plain text; the `[AREA]` tags can name areas of the managed repository.
- `plans/`, `docs/specs/`, `docs/DECISIONS.md`, `.docket/AUDIT.md`, and
  `check-links.sh` over the sidecar's own Markdown.
- The sidecar's own hooks and CI: Markdown formatting, link checks, queue
  validation. These only ever touch sidecar files.
- Cross-repository references: `Blocked by: owner/repo#123` and `Related:` are
  accepted already (`check-queues.sh`).
- The agent can drive the managed repository by hand with
  `gh --repo owner/repo` and `git -C <clone>`. That gives the workflow without
  the helper scripts.

## What breaks, and why

| Piece | Problem in sidecar mode | File |
| --- | --- | --- |
| `start-work.sh` | Creates the worktree and branch in the cwd repository (the sidecar) | `start-work.sh` |
| `claim-check.sh` | `unset GH_REPO`, then `gh api repos/{owner}/{repo}/pulls` and `git worktree list` on cwd; searches the sidecar, not the managed repository | `claim-check.sh` |
| Claim markers | `check-pr-markers.sh` reads `TODO.md` via `git show <base>:TODO.md` from the PR's own history. A managed-repository PR never contains `TODO.md`, and `Claims TODO:` lines in its body are noise for other contributors | `check-pr-markers.sh` |
| `pr-labels.sh` | Would create docket labels in the managed repository | `pr-labels.sh` |
| PR description format | Docket's template (`## Why`, `Type:`, markers) may clash with the managed repository's own template | `CONTRACT.md` |
| `land-local.sh` | Not applicable; the managed repository merges through its own process | |
| `cleanup-landed.sh` | `gh pr list --head` and worktree removal on cwd | `cleanup-landed.sh` |
| Review ledger / `review-due.sh` | SHAs are checked against the cwd repository; a managed-repository SHA gives "BASELINE LOST". A full codebase review of a large monorepo also makes no sense; it must be scoped to paths | `review-due.sh` |
| `scripts/check.sh` gates | The sidecar can't run the managed repository's build and tests, and must not install hooks into its clone | |
| PR health | No script reads CI or review status today, in any mode | |

## Recommended design: a managed-repository mode

One new settings bullet in the sidecar's `AGENTS.md` Docket section, which the
installer already preserves by name, plus a small machine-readable file the
scripts read, since no script reads `AGENTS.md`. Every key is optional except
`repo` and `dir`; an absent file means today's behaviour.

```
# .docket-target (tracked, in the sidecar root)
repo=owner/repo            # gh slug of the managed repository
dir=~/src/repo             # local clone
base=main                  # default: main
branch_prefix=<user>/      # default: docket's <queue>/ prefixes
worktree_dir=~/src/repo-worktrees   # default: outside the clone
land_comment=              # e.g. a merge-bot command; empty: user merges
```

Script changes, each with fixtures in `tests/scripts.sh`:

1. **`start-work.sh` / `claim-check.sh` / `cleanup-landed.sh`**: when a
   target is configured, run git against `dir` (`git -C`) and `gh` with
   `--repo <repo>` instead of unsetting `GH_REPO` and using cwd. Worktrees go
   in `worktree_dir`, outside the clone by default so nothing appears
   untracked there. With `branch_prefix` set, branch names become
   `<branch_prefix><slug>` in place of `<queue>/<slug>`. Claims are searched
   by head branch only, not by body markers. Landing is proved by GitHub's
   merged state, as today.
2. **Claims and resolution move into the sidecar.** Claiming adds a
   `PR: owner/repo#N` line to the entry in the sidecar's `TODO.md` (a direct
   commit to sidecar `main`, which the contract already permits for queue
   edits). Resolution happens when the managed PR merges, again as a sidecar
   commit. `check-queues.sh` learns to validate the `PR:` line.
   `check-pr-markers.sh` and `pr-labels.sh` are skipped in this mode.
3. **Change description**: follow the managed repository's PR template when
   it has one. Docket's description rules about a future `git log` reader
   still apply, since squash-merging repositories use the description as the
   commit body. Markers and the `Type:` line live in the sidecar's
   `.docket/state-<slug>.md` instead of the PR body.
4. **Landing**: the managed repository's own process. Pushing to its base is
   never done. When `land_comment` is set, posting that comment is the
   landing action and, like hosted merging today, stays the user's unless
   delegated. `land-local.sh` never applies. Merge bots of this kind
   commonly rebase the PR onto the current base and run CI there before
   squashing, which covers docket's "current base" landing requirement
   without a manual rebase. Many also abandon the merge if the branch
   changes after the comment, so the branch is frozen from the comment
   until the PR merges or the bot reports failure.
5. **Stacked PRs**: unchanged from hosted mode (`gh pr create --base
   <parent>`, retarget after the parent lands), provided the managed
   repository accepts PRs against non-base branches.
6. **`review-due.sh`**: accept `--repo-dir` so SHAs resolve in the managed
   clone; `--paths` (already exists) scopes reviews to the user's area.
7. **New `pr-health.sh`** (useful in normal mode too): for each open PR the
   queues reference, or `gh pr list --author @me --repo <repo>`, report CI
   check status, review decision, mergeability, base staleness, and whether
   the sidecar entry is out of date. With `land_comment` set, it also shows
   PRs that have the comment but are still open, so a failed or expired
   merge attempt is visible. Read-only.
8. **Own checks on own work**: a sidecar `scripts/check-mine.sh` that runs in
   a managed worktree over `git diff --name-only <base>...HEAD` only, for
   example a Markdown formatter on touched files. Agents run it before
   marking ready; nothing is installed into the managed repository's hooks,
   and its CI stays the authority for its own gates.
9. **`install.sh`**: a `--sidecar` path (or a template variant) that skips
   code CI, the PR template, branch protection and local landing, and writes
   the target file and settings bullet.

Docs to update alongside: `ARCHITECTURE.md` (the cwd invariant becomes
conditional), `CONTRACT.md` (a short "Managed repository" section beside
"Review mode"), `references/setup.md` (sidecar setup) and
`references/pr-and-landing.md`.

## Rejected alternative

Dropping docket into the managed clone untracked (via `.git/info/exclude`):
`TODO.md` would be unversioned, the marker checks need it in git history, and
one careless `git add -A` commits it to someone else's repository.

## Open questions

- Several sidecars pointing at one shared clone: `branch_prefix` plus slug
  must stay unique across them, and `claim-check.sh` should see every
  sidecar's worktrees in that clone.
- Whether a managed repository whose merge process closes PRs without
  GitHub's merged state needs a fallback that finds the squash commit on the
  base by title.

## Phasing

1. Phase 0, no code: run a sidecar with the parts that already work and drive
   the managed repository by hand.
2. Phase 1: items 1, 2 and 7 (target pointer, sidecar claims, PR health).
3. Phase 2: the rest.

## Verification (for the build phases)

- Fixtures in `tests/scripts.sh` build two scratch repositories (sidecar and
  managed, with a bare "remote"), run `start-work`, `claim-check` and
  `cleanup-landed` from the sidecar, and assert branches and worktrees land
  in the managed repository only.
- `gh` calls stubbed to assert `--repo` is passed.
- An absent `.docket-target` leaves every existing fixture passing.
- Run the suites under `/bin/bash` 3.2 and current bash; `install.sh --self`
  and `--check` clean.
