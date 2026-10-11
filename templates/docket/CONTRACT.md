# Docket: workflow contract

Docket is a working discipline for repositories where agents do most of the work: staged queues for deferred work, a branch and worktree per unit of work, an independent reviewer for every change, and gates that hooks, CI and agents all run the same way. This file is the authoritative workflow; every agent reads it before any work. Project-specific settings (queue areas, concurrency cap, merge delegation, optional pieces, environment rules) live in the Docket section of the project's `AGENTS.md`. Nothing under `docket/` is edited in the project; it is vendored verbatim and resynced from the skill (see [README.md](README.md)).

## Workflow

- Every unit of work is a branch, a worktree and a pull request. Branch `<queue>/<slug>` (`todo/`, `review/`, `roadmap/`; `fix/` or `task/` for direct requests). Worktrees live in `.worktrees/` (ignored) or the harness's own location.
- Two things go straight to `main` without a branch or PR. Documentation that records work to be done: adding or triaging `TODO.md` entries, and plans (`plans/YYYY-MM-DD-<slug>.md`); a plan is planning for work, not work, and everything it describes still goes through branches, PRs and review. Housekeeping metadata files such as `.git-blame-ignore-revs`, only when the user says so for that case. Extrapolate with common sense and say so in the commit; everything else, including all code and any documentation that describes behaviour, goes through a PR.
- Before claiming anything run `bash docket/scripts/claim-check.sh <slug>` (open and merged PRs, branches, worktrees), then create the branch and worktree immediately with `bash docket/scripts/start-work.sh <queue> <slug>`.
- Open a draft PR after the first meaningful commit. The body opens with `## Why`, then what changed, markers, validation, review. PRs are squash-merged, so the body is the commit message. Never merge with a one-line body. If no PR can be opened, save the body as `.docket/pr-<slug>.md`, say so, and leave the branch and worktree for the user.
- Parallelise independent work through sub-agents in separate worktrees with disjoint file ownership. Shared interfaces land (or are explicitly stacked) before dependents start. The coordinating agent integrates, serialises edits to `TODO.md` and `review/BACKLOG.md`, and holds the push, merge and release gates. The cap on concurrent heavy builds or runs is in the Docket section of `AGENTS.md`.
- Every code-writing agent, including the coordinator, gets a separate reviewer agent before a PR is marked ready. The reviewer verifies the PR's claims and reports findings; the author fixes; the PR body records the review in a `## Review` section.
- Keep the branch on its stated outcome. A separately shippable idea becomes a queue entry with a `Source:` line (and a `Files TODO: <slug>` marker in the PR when the entry is added on the branch rather than committed to `main`), then the original work continues. An unrelated P0 is reported immediately and work pauses for direction.
- Run `bash scripts/check.sh` before opening or updating a PR; `bash scripts/setup.sh` installs the hooks that run the same gates. Report checks actually run and their limits. An empty or skipped suite is a failure.
- Linear history: rebase, never merge `main` into a branch; `--force-with-lease` on PR branches only. The user merges unless they delegate it in that turn or a standing delegation is recorded in the Docket section of `AGENTS.md`. Release tags need the user's explicit sign-off in the current or preceding turn.
- Commit regularly, one logical change per commit, in the style of the existing log. No attribution trailers. The repository's git identity is set once by the user or the coordinator before the first commit; sub-agents never change `git config`.
- Update documentation in the same PR when a change makes it inaccurate. Each rule has one authoritative home; link to it rather than restating it.
- Environment rules (what the user runs themselves, what needs a warning before launch, which interpreter or virtualenv to use) are in the Docket section of `AGENTS.md`.

## Process guides

Read only the guide the task needs.

- An idea surfaces, or you are selecting, claiming, moving or resolving deferred work: [`docket/TODO_GUIDE.md`](TODO_GUIDE.md). "Grab a TODO" means `TODO.md` only; "grab a review finding" means `review/BACKLOG.md` only. Never switch queues. Queue areas, and whether the review ledger and roadmap queue are in force, are in the Docket section of `AGENTS.md`.
- A codebase review is requested, or a PR resolves a review finding: [`docket/CODE_REVIEW_GUIDE.md`](CODE_REVIEW_GUIDE.md).
- Changing code or validating a PR: [`docs/QUALITY.md`](../docs/QUALITY.md).
- Working unattended under a broad autonomy grant: no pushes, merges or tags without the user's word; local branches with PR bodies in `.docket/pr-<slug>.md`; load-bearing decisions appended to `.docket/AUDIT.md` with an undo line each. `.docket/` is excluded from git.
