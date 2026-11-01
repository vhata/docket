# Deferred work

Ordinary follow-ups and bugs found during other work live here. Whole-codebase review findings promoted for separate work live in [review/BACKLOG.md](review/BACKLOG.md). Follow [docket/TODO_GUIDE.md](docket/TODO_GUIDE.md) before adding, claiming, moving or resolving an entry. Entries in **Ready for separate work** are unblocked and available now; an understood entry with an unresolved `Depends on:` or a `Blocked by:` goes in **Waiting** until it clears.

## Needs triage

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized

- [SCRIPTS] `finding-membership-sigpipe` — **Finding markers are recognised reliably when a claimed backlog entry exists at both base and head.** The finding-membership pipeline can report a false warning under `pipefail` when `grep -q` exits before the second entry producer finishes.
  - Source: vhata/bw-reconcile#5 and #6, 2026-10-20
  - Starting point: `templates/docket/scripts/check-pr-markers.sh`, the pipeline combining base/head `entry_block` output before `grep -q`; drain the producer or avoid a short-circuit consumer and add a regression fixture.
  - Evidence: a body with `Claims review backlog: redaction-gaps` and `Claims review finding: redaction-gaps` warns that the finding is absent although both queue revisions list it; both findings in `totp-parsing-hardening` also warn. Strict mode fails. Resolving the entry (removing it at head) makes the warning disappear. Repeat enough times to expose the pipe scheduling race.

## Needs proof of concept

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized

## Waiting

### P0 Critical

### P1 High

### P2 Normal

- [SCRIPTS] `sidecar-claims` — **In managed-repository mode, claims and resolution are recorded in the sidecar's queue, not the managed repository's PR body.** A `PR: owner/repo#N` line on the entry, validated by `check-queues.sh`; `check-pr-markers.sh` and `pr-labels.sh` stand down; the PR follows the managed repository's own template.
  - Source: [docs/specs/2026-11-01-managed-repository-mode.md](docs/specs/2026-11-01-managed-repository-mode.md), 2026-11-01
  - Starting point: the spec's design items 2, 3 and 4, and the Review mode section of `templates/docket/CONTRACT.md`.
  - Depends on: `managed-repo-target`
- [INSTALLER] `sidecar-install` — **`install.sh` can set up a sidecar: target file and settings bullet written, code CI, PR template, protection and local landing skipped, plus a diff-scoped check for the user's own changes in the managed repository.**
  - Source: [docs/specs/2026-11-01-managed-repository-mode.md](docs/specs/2026-11-01-managed-repository-mode.md), 2026-11-01
  - Starting point: the spec's design items 8 and 9, and `references/setup.md`.
  - Depends on: `managed-repo-target`

### P3 Low

### Unprioritized

## Ready for separate work

### P0 Critical

### P1 High

### P2 Normal

- [SCRIPTS] `managed-repo-target` — **A sidecar repository's docket scripts claim, start and clean up work in a configured managed repository.** `start-work.sh`, `claim-check.sh` and `cleanup-landed.sh` run git with `-C <dir>` and `gh` with `--repo <repo>` from a tracked target file, with a configurable branch prefix.
  - Source: [docs/specs/2026-11-01-managed-repository-mode.md](docs/specs/2026-11-01-managed-repository-mode.md), 2026-11-01
  - Starting point: the spec's design items 1, 5 and 6; the cwd assumption in `ARCHITECTURE.md` and each script's `git rev-parse --show-toplevel`.
- [SCRIPTS] `pr-health` — **A read-only `pr-health.sh` reports CI status, review decision, mergeability and base staleness for open PRs the queues reference.** Useful in both normal and managed-repository mode.
  - Source: [docs/specs/2026-11-01-managed-repository-mode.md](docs/specs/2026-11-01-managed-repository-mode.md), 2026-11-01
  - Starting point: the spec's design item 7.

### P3 Low

- [SCRIPTS] `review-due-local-midnight` — **`review-due.sh` counts days from midnight of the review date on macOS as it does on GNU.** BSD `date -j -f %Y-%m-%d` takes the time of day from the clock, so west of UTC a review dated today can report `-1 days`; the verdict is unaffected.
  - Source: review/fix-review-due-fixture-dates (PR #22), 2026-10-12
  - Starting point: `templates/docket/scripts/review-due.sh:124`; parse `"$date 00:00:00"` with `-f '%Y-%m-%d %H:%M:%S'`, or clamp `days` at 0.

### Unprioritized
