# Docket: workflow contract

Docket is a working discipline for repositories where agents do most of the work: staged queues for deferred work, a branch and worktree per unit of work, an independent reviewer for every change, and gates that hooks, CI and agents all run the same way. This file is the authoritative workflow; every agent reads it before any work. Project-specific settings (queue areas, concurrency cap, merge delegation, optional pieces, environment rules) live in the Docket section of the project's `AGENTS.md`. Nothing under `docket/` is edited in the project; it is vendored verbatim and resynced from the skill (see [README.md](README.md)).

## Review mode

Every unit of work has a branch, a worktree, a change description and an
independent review. With a PR-capable remote, use a pull request. With
no remote, or a remote that does not provide pull requests, use local
review: keep the branch and worktree for the user, then squash-land
after their explicit approval. No hosting service, `gh`, push or CI is
required for local review. Record the chosen mode in the handoff; use
`--local` on `claim-check.sh`, `start-work.sh` and `cleanup-landed.sh`
for a non-PR remote. With no remotes these helpers use local mode
automatically.

Missing credentials, an unavailable forge or missing `gh` does not make
a PR-capable remote a local-review repository. Keep the work locally and
report the blocker; do not bypass its hosted review or landing policy.
Without push authority, keep the same local artifacts pending
publication.

## Managed repository

A sidecar repository holds docket, the queues and plans for work in a
separate managed repository that docket cannot be installed in. Its
tracked `.docket-target` file (format in `docket/scripts/target.sh`)
names the managed repository and its local clone. `claim-check.sh`,
`start-work.sh` and `cleanup-landed.sh` then work on branches and
worktrees in that clone and PRs in that repository, matched by head
branch; `review-due.sh` resolves commits there, and `pr-health.sh`
reports on its PRs against the sidecar's `PR:` lines. From a managed
worktree, run the sidecar's scripts by absolute path. Pass `--no-target`
for work on the sidecar itself, and set `DOCKET_TARGET_FILE` only per
command. The managed repository's template, CI and merge process govern
its PRs. Their descriptions still follow the future `git log` reader
rules, but markers and the `Type:` line stay out of them, in the
sidecar's `.docket/state-<slug>.md`; `check-pr-markers.sh` and
`pr-labels.sh` stand down there. The sidecar entry is the claim: once
the PR is open, add `PR: owner/repo#N` to it as a direct commit to the
sidecar's main. When the PR merges, remove the entry the same way, with
`Resolves TODO: <slug>` (or `Resolves review backlog: <slug>`) and the
PR in the commit message; a remainder kept in the same entry drops that
`PR:` line. `cleanup-landed.sh` lists entries ready for this. Roadmap
claims are out of scope in a sidecar. Push branches to the
managed repository itself, or to a fork when `.docket-target` names its
remote as `push_remote`, and never to the managed repository's base.
Its configured `land_comment`, when posted, merges, so it stays the
user's unless delegated; after posting it, leave the branch untouched
until the PR merges or the merge fails.

## Workflow

- Branch `<queue>/<slug>` for queued work (`todo/`, `review/`,
  `roadmap/`); `task/<slug>` or `fix/<slug>` for direct requests,
  including review snapshots. A `review/<slug>` branch claims a
  `review/BACKLOG.md` entry and needs its marker. Worktrees live in
  `.worktrees/` (ignored) or the harness's own location.
- Two things may go straight to `main` without a branch or review:
  documentation recording work to be done (queue entries, triage, plans,
  design specs), and housekeeping metadata such as
  `.git-blame-ignore-revs` when the user says so for that case. Planning
  does not authorise its implementation. Such documents may also be
  included in the change that prompted them without doing their work.
  Everything else, including code and documentation of built behaviour,
  follows branch review. State any common-sense extrapolation in the
  commit message.
- Plans live in `plans/YYYY-MM-DD-<slug>.md` and design specs in
  `docs/specs/YYYY-MM-DD-<slug>.md`. These override other tools' default
  locations: directory names describe content, never its writing tool.
- Before claiming anything run `bash docket/scripts/claim-check.sh
  <slug>` (branches, worktrees and available hosted claims), then
  immediately run `bash docket/scripts/start-work.sh <queue> <slug>`. In
  local mode use local `main` as the base, even if stale remote-tracking
  refs remain.
- After the first meaningful commit prepare the change title and
  description. Open a draft PR in hosted mode. Otherwise save the title
  to `.docket/title-<slug>.txt`, the description to
  `.docket/change-<slug>.md`, and the independent review to
  `.docket/review-<slug>.md`. Keep a separate `.docket/state-<slug>.md`
  recording mode, branch, base and head commit, checks, draft/ready
  status and any user approval. Keep the branch and worktree until
  approved landing. Existing `.docket/pr-<slug>.md` drafts remain usable
  descriptions; rename them when next updated.
- The change description follows `.github/pull_request_template.md` when
  present: `## Why` first, then changes, the `Type:` line and markers,
  validation. The title becomes the squash commit subject and the full
  description its body. Write for a future `git log` reader: problem,
  approach, non-obvious implementation details and relevant validation.
  Keep rebase/stack ordering, review history, status, to-dos and
  reviewer instructions in PR comments or local review/state files.
  Rewrite a revised description as a whole; never append revision
  history. Give sub-agents this rule. Hard-wrap descriptions at 72
  columns, including local drafts; fenced code, tables and unbreakable
  tokens are exempt. Indent list continuations and keep headings within
  72 columns. `check-pr-markers.sh --body <file> --base main --strict`
  validates local descriptions. Never land a one-line description.
  Hosted PRs additionally use `pr-labels.sh --pr <number> --apply` when
  opened or markers change.
- Parallelise independent work through sub-agents in separate worktrees
  with disjoint file ownership. Shared interfaces land or are explicitly
  stacked before dependents start. The coordinator integrates,
  serialises queue edits and holds push, landing and release gates. The
  heavy-run concurrency cap is in `AGENTS.md`. The coordinator also owns
  cleanup of workers folded into a shared parent after it lands.
- Every code-writing agent, including the coordinator, gets a separate
  reviewer before work is ready. The reviewer verifies the change's
  claims and reports findings; the author fixes and the reviewer
  verifies fixes. Record reviewed commits and dispositions in a PR
  comment headed `## Review`, or the local review file, never in the
  change description.
- Keep the branch on its stated outcome. Separately shippable ideas go
  into the owning repository's queue with a `Source:` line, then work
  continues. Add `Files TODO: <slug>` to the description for entries
  added on this branch. See [TODO_GUIDE.md](TODO_GUIDE.md). Report an
  unrelated P0 immediately and pause for direction.
- Run `bash scripts/check.sh` and change-specific gates before
  presenting or updating work for review. `bash scripts/setup.sh`
  installs hooks. Report actual checks and limits; an empty or skipped
  suite is a failure. Local mode runs the same applicable gates without
  requiring hosted CI.
- Rebase, never merge `main` into a branch. Force-push only PR branches,
  only after rebase, using `--force-with-lease`; never force-push main.
- Work is ready when implementation, checks and independent review are
  complete for its scope. Mark hosted PRs ready then; mark local state
  ready and report the branch, worktree, head, title, description and
  review paths. A new change or rebase that invalidates a gate returns
  it to draft/pending. Readiness and agent review do not authorise
  landing.
- In hosted mode run `bash docket/scripts/pr-health.sh` at session start
  and before reporting PR status, rather than relying on memory.
- Landing requires the current `main` base, green applicable gates,
  landed stack parents and every acceptance gate from the original queue
  entry. A remainder cannot waive one. Hosted merging remains the user's
  unless delegated in the turn or `AGENTS.md`. In local mode the agent
  lands after the user explicitly approves landing the reviewed head;
  keep the approval in the state file. Rebase and revalidate if main
  moved; obtain approval for the resulting head before landing. Use
  `land-local.sh <branch> --title <title> --body <file> --approved-head
  <full-sha>` from a clean main checkout. It creates one squash commit
  with the title and full description, never a merge commit. Its
  approval argument records a decision already given by the user, not
  permission for the agent to approve itself. If main lacks the helper
  during initial installation or upgrade, invoke the installed helper by
  absolute path from the task worktree while keeping the working
  directory at clean main; never invoke the skill's template copy.
- After landing verify the commit message and run main's applicable
  checks (hosted CI where present, local gates otherwise). Preserve
  local review evidence in the retained main checkout's
  `.docket/landed-<slug>/` before removing the task worktree. After
  verifying preservation, remove only those source artifacts and use
  `rmdir` for now-empty directories, including `.docket/`; inspect and
  preserve other unique content before cleanup. Ignored `.docket/`
  directories are allowed to be discarded with a landed worktree;
  cleanup does not archive them or check that records were preserved.
  Run `cleanup-landed.sh` as a dry run, then with `--apply`; local landing
  receipts and retained audit refs let it verify the exact landed tip
  without a forge. Ordinary cleanup also discovers workers folded into
  a parent by comparing their changed paths with reachable merged-PR
  landings or verified local receipts. It reports the matching landing
  and retains open PRs, later work and uncertain proof. Review that dry
  run, preserve worker records, then apply cleanup; supplying commit IDs
  or reconstructing integration history is not a normal cleanup step.
  Rebase stacked children onto main and retarget hosted PRs. Never
  remove dirty worktrees, discard unique ignored evidence or delete
  unlanded commits without the user's word.
- Autonomy grants cover implementation. CI, hooks policy and branch
  protection changes need the user's word in that turn. Release tags,
  deploys and publishing need it in that turn or the previous one.
- Commit regularly, one logical change per commit, in the log's style.
  No attribution trailers. The user or coordinator sets repository git
  identity before the first commit; sub-agents never change git config.
- Update documentation in the same change when behaviour makes it
  inaccurate. Give each rule one authoritative home and link to it.
- Environment rules are in the Docket section of `AGENTS.md`.

## Process guides

Read only the guide the task needs.

- An idea surfaces, or you are selecting, claiming, moving or resolving deferred work: [`docket/TODO_GUIDE.md`](TODO_GUIDE.md). "Grab a TODO" means `TODO.md` only; "grab a review finding" means `review/BACKLOG.md` only. Never switch queues. Queue areas, and whether the review ledger and roadmap queue are in force, are in the Docket section of `AGENTS.md`.
- A codebase review is requested, or a change resolves a review finding:
  [`docket/CODE_REVIEW_GUIDE.md`](CODE_REVIEW_GUIDE.md).
- Changing code or validating a change:
  [`docs/QUALITY.md`](../docs/QUALITY.md).
- Working unattended under a broad autonomy grant: no pushes, merges or
  tags without the user's word; local branches with change descriptions
  in `.docket/change-<slug>.md`, titles in `.docket/title-<slug>.txt`
  and independent reviews in `.docket/review-<slug>.md`; load-bearing
  decisions appended to `.docket/AUDIT.md` with an undo line each.
  `.docket/` is excluded from git.
