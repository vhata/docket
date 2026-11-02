# Deferred work

Ordinary follow-ups and bugs found during other work live here. Whole-codebase review findings promoted for separate work live in [review/BACKLOG.md](review/BACKLOG.md). Follow [docket/TODO_GUIDE.md](docket/TODO_GUIDE.md) before adding, claiming, moving or resolving an entry. Entries in **Ready for separate work** are unblocked and available now; an understood entry with an unresolved `Depends on:` or a `Blocked by:` goes in **Waiting** until it clears.

## Needs triage

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized



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

### P3 Low

### Unprioritized

## Ready for separate work

### P0 Critical

### P1 High

### P2 Normal

- [SCRIPTS] `finding-membership-sigpipe` — **Finding markers are recognised reliably when a claimed backlog entry exists at both base and head.** The finding-membership pipeline can report a false warning under `pipefail` when `grep -q` exits before the second entry producer finishes.
  - Source: vhata/bw-reconcile#5 and #6, 2026-10-20
  - Starting point: `templates/docket/scripts/check-pr-markers.sh`, the pipeline combining base/head `entry_block` output before `grep -q`; drain the producer or avoid a short-circuit consumer and add a regression fixture.
  - Evidence: a body with `Claims review backlog: redaction-gaps` and `Claims review finding: redaction-gaps` warns that the finding is absent although both queue revisions list it; both findings in `totp-parsing-hardening` also warn. Strict mode fails. Resolving the entry (removing it at head) makes the warning disappear. Repeat enough times to expose the pipe scheduling race.
- [TOOLING] `suite-bash-on-path` — **The regression suites exercise the vendored scripts under bash 3.2, not only the suite itself.** `scripts/test.sh` runs each suite with `/bin/bash`, but the suites invoke the scripts as `bash <script>` (and through `#!/usr/bin/env bash` shebangs), which resolves through PATH, so on a machine with a newer bash first on PATH the scripts never run under 3.2 locally.
  - Source: `todo/sidecar-claims` implementation, 2026-11-01
  - Starting point: `scripts/test.sh` could run each suite with a PATH whose first `bash` is `/bin/bash` (e.g. a temporary bin directory with a `bash` symlink), or the suites could call `$BASH`; check what the macOS CI runner's PATH resolves `bash` to.
- [SCRIPTS] `pr-health-target-defaults` — **In a sidecar, `pr-health.sh` reports on the managed repository's PRs without being told where they are.** With a `.docket-target` loaded, `--repo` defaults to the target's `repo` and `--land-comment` to its `land_comment`; `--no-target` and explicit options override.
  - Source: `todo/pr-health` implementation, 2026-11-01
  - Starting point: the placeholder defaults at the top of `templates/docket/scripts/pr-health.sh` and `templates/docket/scripts/target.sh`; queue-marker checks need thought in target mode, where claims are `PR:` lines rather than body markers.

### P3 Low

- [SCRIPTS] `managed-repo-forks` — **Managed-repository mode works for contributors who push branches to a fork rather than to the managed repository.** Target mode expects branches on the managed repository itself; `claim-check.sh --self` reports the user's own fork PR as a competing claim, and `start-work.sh` names the managed remote for the push.
  - Source: independent review of PR #30, 2026-11-01
  - Starting point: an optional `push_remote` (or fork owner) key in `.docket-target`; accept a cross-repository head whose owner matches it in `claim-check.sh`, and name that remote in `start-work.sh`'s next steps.
- [SCRIPTS] `review-due-local-midnight` — **`review-due.sh` counts days from midnight of the review date on macOS as it does on GNU.** BSD `date -j -f %Y-%m-%d` takes the time of day from the clock, so west of UTC a review dated today can report `-1 days`; the verdict is unaffected.
  - Source: review/fix-review-due-fixture-dates (PR #22), 2026-10-12
  - Starting point: `templates/docket/scripts/review-due.sh:124`; parse `"$date 00:00:00"` with `-f '%Y-%m-%d %H:%M:%S'`, or clamp `days` at 0.

### Unprioritized
