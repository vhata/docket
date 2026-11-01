# Quality and validation

Read when changing code or preparing a change. This document describes
the gates as they exist now; history and rationale for past changes live
in `docs/DECISIONS.md` and git.

## What quality means here

<Two to four bullets on what matters for this project: e.g. determinism, accounting correctness, replay, privacy, and what deliberately stays manual (GUI appearance, judgement about emergent behaviour).>

## Review mode

<Hosted PRs | local review because there is no PR-capable remote>.
Describe the actual mode, remote capability and required gates. For
local review, run the applicable checks below before review and after
landing on main; validate the saved description with
`check-pr-markers.sh --body <file> --base main --strict`. Independent
review and explicit user landing approval follow
[docket/CONTRACT.md](../docket/CONTRACT.md#review-mode). The CI,
schedule and protection sections below are hosted examples; replace them
with the local arrangement or mark them not applicable.

## Gates

Each check is a standalone script in `scripts/` or `docket/scripts/`, runnable from any directory, exiting non-zero on failure. Hooks, CI and agents run the same scripts.

| Script | Runs | Pre-commit | Pre-push | CI on PR | CI on main | Scheduled |
| --- | --- | --- | --- | --- | --- | --- |
| `scripts/fmt-check.sh` | <formatter --check> | yes | | yes | yes | yes |
| `scripts/lint.sh` | <linter, warnings denied> | yes | | yes | yes | yes |
| `scripts/typecheck.sh` | <type checker> | | yes | yes | yes | yes |
| `scripts/test.sh` | <unit/integration tests; fails on empty collection> | | yes | yes | yes | yes |
| `scripts/build.sh` | <release build / packaging> | | | yes | yes | yes |
| `scripts/e2e.sh` | <browser or system tests; unique evidence dir per run> | | | yes | yes | yes |
| `scripts/smoke.sh` | <cheapest end-to-end exercise of the built product> | | | yes | yes | yes |
| `docket/scripts/ci.sh` | queue hygiene, Markdown links, PR markers against the queues | | | yes | yes | |
| `docket/scripts/review-due.sh` | review cadence report | | | | | yes |
| `scripts/check.sh` | fmt-check, lint, typecheck, test, in order | | | yes | yes | yes |

`scripts/check.sh` is the composite entry point: `ci.yml` and `main-validation.yml` run it rather than the four gates individually, so its CI columns are those of the gates it runs. `scripts/check.sh` runs the project's gates; hooks and `docket/scripts/ci.sh` run the vendored validators, and including them in `check.sh` is optional.

Hooks are managed by <manager> from <config file> and installed by `bash
scripts/setup.sh`. Pre-commit <checks only | rewrites staged files>.
Measured pre-commit time: <n> s warm. Bypassing a hook is for a broken
toolchain only; state the bypass and equivalent checks in the change
description.

Toolchain pins: <files>. Bumping a pin is its own reviewed change.

## Test policy

- <Which changes need a regression test, and at which layer.>
- <Which changes need no new tests and how they are verified instead.>
- <Rules for goldens, seeds, property tests, determinism.>
- An empty or skipped suite is a failed gate. Coverage gates, if any, measure the exact claim: <threshold and scope>.
- No automatic retries. A flaky test is filed in `TODO.md` with its evidence directory and fixed or quarantined by name.

## Review inputs

Read by `docket/CODE_REVIEW_GUIDE.md`, which links this section by its heading, so keep the heading as it is; a codebase review runs and records exactly what is listed here.

- Focus areas: the correctness boundaries under [What quality means here](#what-quality-means-here) and the invariants in <`ARCHITECTURE.md` or `docs/ARCHITECTURE.md`>.
- Baseline commands beyond `bash scripts/check.sh`: <e2e, smoke, headless or installed-package commands, each with the result format to record>.
- Drift checks for an incremental review: <documented CLI, controls and features against the code; plan status against merged work; this document against the hooks and CI workflows; lint-suppression counts and other language-specific checks>.
- Source paths for `bash docket/scripts/review-due.sh --paths "<source dirs>"`, the same value the scheduled workflow passes.
- Expected tracked files: <the extensions and paths a tracked file may have>, so a review can read `git ls-files` for committed strays.

## CI

`.github/workflows/ci.yml` runs on pull requests and on pushes to `main`. Jobs: <names>. The hygiene job runs `bash docket/scripts/ci.sh`; on pull requests its marker check compares the queues at the base branch tip with the checked-out merge commit. Superseded runs are cancelled on PR branches only, never on `main`. Failure evidence is uploaded for <n> days.

## Scheduled validation of main

The scheduled workflow (`main-validation.yml` in the template) runs <daily at HH:MM UTC | weekly> and on demand. It runs <extended checks>, uploads evidence for <n> days, and reports whether a codebase review is due. A red main, from the push run or the schedule, is reverted or filed as a P1 (P0 if release-blocking) the same day. A missing scheduled run is not a pass.

## Branch protection (as configured on <date>)

- Required checks: <job names>; up-to-date-with-base: <on|off>.
- Linear history: <on>. Conversation resolution: <on>. Force pushes and deletions: blocked.
- Approving reviews required: 0; independent agent review is recorded in a review comment on each PR.
- Administrator enforcement: <on | off, with the exceptions listed in AGENTS.md>.
- Merge method: squash only; title from PR title, message from PR body; head branches deleted on merge.

## Change evidence

Every change description lists actual commands and results, a
reproducible behaviour scenario, and anything not checked. Independent
review lives separately in a PR comment or `.docket/review-<slug>.md`;
local state records reviewed base/head and user approval. See
[docket/CODE_REVIEW_GUIDE.md](../docket/CODE_REVIEW_GUIDE.md).
