# Quality and validation

Read when changing code or preparing a PR. This document describes the gates as they exist now; history and rationale for past changes live in `docs/DECISIONS.md` and git.

## What quality means here

<Two to four bullets on what matters for this project: e.g. determinism, accounting correctness, replay, privacy, and what deliberately stays manual (GUI appearance, judgement about emergent behaviour).>

## Gates

Each check is a standalone script in `scripts/`, runnable from any directory, exiting non-zero on failure. Hooks, CI and agents run the same scripts.

| Script | Runs | Pre-commit | Pre-push | CI on PR | CI on main | Scheduled |
| --- | --- | --- | --- | --- | --- | --- |
| `scripts/fmt-check.sh` | <formatter --check> | yes | | yes | yes | yes |
| `scripts/lint.sh` | <linter, warnings denied> | yes | | yes | yes | yes |
| `scripts/typecheck.sh` | <type checker> | | yes | yes | yes | yes |
| `scripts/test.sh` | <unit/integration tests; fails on empty collection> | | yes | yes | yes | yes |
| `scripts/build.sh` | <release build / packaging> | | | yes | yes | yes |
| `scripts/e2e.sh` | <browser or system tests; unique evidence dir per run> | | | yes | yes | yes |
| `scripts/smoke.sh` | <cheapest end-to-end exercise of the built product> | | | yes | yes | yes |
| `scripts/workflow/check-queues.sh --strict` | queue hygiene | | | yes | yes | |
| `scripts/workflow/check-pr-markers.sh` | PR markers against queues | | | yes | | |
| `scripts/workflow/check-links.sh` | relative Markdown links | | | yes | yes | |
| `scripts/workflow/review-due.sh` | review cadence report | | | | | yes |
| `scripts/check.sh` | fmt-check, lint, typecheck, test, in order | | | | | |

Hooks are managed by <manager> from <config file> and installed by `bash scripts/setup.sh`. Pre-commit <checks only | rewrites staged files>. Measured pre-commit time: <n> s warm. Bypassing a hook is for a broken toolchain only; state the bypass and the equivalent checks in the PR.

Toolchain pins: <files>. Bumping a pin is its own PR.

## Test policy

- <Which changes need a regression test, and at which layer.>
- <Which changes need no new tests and how they are verified instead.>
- <Rules for goldens, seeds, property tests, determinism.>
- An empty or skipped suite is a failed gate. Coverage gates, if any, measure the exact claim: <threshold and scope>.
- No automatic retries. A flaky test is filed in `TODO.md` with its evidence directory and fixed or quarantined by name.

## CI

`.github/workflows/ci.yml` runs on pull requests and on pushes to `main`. Jobs: <names>. Superseded runs are cancelled on PR branches only, never on `main`. Failure evidence is uploaded for <n> days.

## Scheduled validation of main

`.github/workflows/main-validation.yml` runs <daily at HH:MM UTC | weekly> and on demand. It runs <extended checks>, uploads evidence for <n> days, and reports whether a codebase review is due. A red main, from the push run or the schedule, is reverted or filed as a P1 (P0 if release-blocking) the same day. A missing scheduled run is not a pass.

## Branch protection (as configured on <date>)

- Required checks: <job names>; up-to-date-with-base: <on|off>.
- Linear history: <on>. Conversation resolution: <on>. Force pushes and deletions: blocked.
- Approving reviews required: 0; independent agent review is recorded in each PR's `## Review` section.
- Administrator enforcement: <on | off, with the exceptions listed in AGENTS.md>.
- Merge method: squash only; title from PR title, message from PR body; head branches deleted on merge.

## PR evidence

Every PR lists the commands run and their results, a reproducible scenario for behaviour changes, what was not run and why, and the independent review. See [CODE_REVIEW_GUIDE.md](CODE_REVIEW_GUIDE.md).
