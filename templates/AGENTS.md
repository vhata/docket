# <Project>: agent contract

<One or two sentences on what the project is and what it is for. If it is a personal project with no deliverable, say so; priorities follow the motivation.>

## Workflow

- Every unit of work is a branch, a worktree and a pull request. Branch `<queue>/<slug>` (`todo/`, `review/`, `roadmap/`; `fix/` or `task/` for direct requests). Worktrees live in `.worktrees/` (ignored) or the harness's own location. Never commit to `main` directly. <Exceptions, if any, listed here with their proportionate check; default: none.>
- Before claiming anything run `bash scripts/workflow/claim-check.sh <slug>` (open and merged PRs, branches, worktrees), then create the branch and worktree immediately with `bash scripts/workflow/start-work.sh <queue> <slug>`.
- Open a draft PR after the first meaningful commit. The body opens with `## Why`, then what changed, markers, validation, review. PRs are squash-merged, so the body is the commit message. Never merge with a one-line body. If no PR can be opened, save the body as `.feral/pr-<slug>.md`, say so, and leave the branch and worktree for the user.
- Parallelise independent work through sub-agents in separate worktrees with disjoint file ownership. Shared interfaces land (or are explicitly stacked) before dependents start. The coordinating agent integrates, serialises edits to `TODO.md` and `review/BACKLOG.md`, and holds the push, merge and release gates. Cap at <N> concurrent heavy builds or runs.
- Every code-writing agent, including the coordinator, gets a separate reviewer agent before a PR is marked ready. The reviewer verifies the PR's claims and reports findings; the author fixes; the PR body records the review in a `## Review` section.
- Keep the branch on its stated outcome. A separately shippable idea becomes a queue entry with a `Source:` line (and a `Files TODO: <slug>` marker in the PR), then the original work continues. An unrelated P0 is reported immediately and work pauses for direction.
- Run `bash scripts/check.sh` before opening or updating a PR; `bash scripts/setup.sh` installs the hooks that run the same gates. Report checks actually run and their limits. An empty or skipped suite is a failure.
- Linear history: rebase, never merge `main` into a branch; `--force-with-lease` on PR branches only. The user merges unless they delegate it in that turn <or: standing delegation recorded here>. Release tags need the user's explicit sign-off in the current or preceding turn.
- Commit regularly, one logical change per commit, in the style of the existing log. No attribution trailers. The repository's git identity is set once by the user or the coordinator before the first commit; sub-agents never change `git config`.
- Update documentation in the same PR when a change makes it inaccurate. Each rule has one authoritative home; link to it rather than restating it.
- <Environment rules: e.g. "Warn before launching anything that opens a window", "The user runs the dev server", "Use the worktree's own virtualenv through uv run --locked".>

## Process guides

Read only the guide the task needs.

- An idea surfaces, or you are selecting, claiming, moving or resolving deferred work: [`docs/TODO_GUIDE.md`](docs/TODO_GUIDE.md). "Grab a TODO" means `TODO.md` only; "grab a review finding" means `review/BACKLOG.md` only. Never switch queues.
- A codebase review is requested, or a PR resolves a review finding: [`docs/CODE_REVIEW_GUIDE.md`](docs/CODE_REVIEW_GUIDE.md).
- Changing code or validating a PR: [`docs/QUALITY.md`](docs/QUALITY.md).
- Working unattended under a broad autonomy grant: no pushes, merges or tags without the user's word; local branches with PR bodies in `.feral/pr-<slug>.md`; load-bearing decisions in `AUDIT.md` (excluded from git) with an undo line each.

## Where to find what

- `README.md`: build, run, scripts.
- `ARCHITECTURE.md`: structure, shared interfaces, invariants, per-worktree isolation.
- `docs/DECISIONS.md`: non-obvious choices and their trade-offs. Read before changing a mechanism that looks odd.
- `TODO.md`, `review/`: deferred work and the review ledger.
- <Other authoritative documents: roadmap, spec, acceptance, design notes.>

Keep this file short. Add a line only when it prevents a concrete recurring mistake; details go in the guide that owns them.
