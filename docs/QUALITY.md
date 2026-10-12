# Quality and validation

Read when changing code or preparing a PR. This document describes the gates as they exist now; history and rationale for past changes live in `docs/DECISIONS.md` and git.

## What quality means here

- The vendored scripts behave the same under macOS `/bin/bash` 3.2 and a current Linux bash, with nothing beyond git and `gh`. A project's CI and its agents' laptops run the same copy.
- The scripts and the documents they parse agree. A guide that describes a marker, entry format or table shape the validator rejects (or the reverse) is a defect, as is a reference or `SKILL.md` passage that contradicts the vendored contract.
- The installer never destroys project content: it writes only the paths listed in [ARCHITECTURE.md](../ARCHITECTURE.md#invariants), keeps settings values, and reports rather than deletes.
- Templates stay generic: no names, paths or history from a particular project.
- Deliberately manual: whether the prose of `SKILL.md` and `references/` reads clearly to an agent with no context. Reviews judge it; no script does.

## Gates

Each check is a standalone script, runnable from any directory, exiting non-zero on failure. Hooks, CI and agents run the same scripts.

| Script | Runs | Pre-commit | Pre-push | CI on PR | CI on main | Scheduled |
| --- | --- | --- | --- | --- | --- | --- |
| `scripts/lint.sh` | `/bin/bash -n` on every shell script and hook; `shellcheck -S warning` where installed | yes | | yes | yes | yes |
| `scripts/vendor-check.sh` | `install.sh --self --check`: `docket/` matches `templates/docket/`, `VERSION` is `self`, the Docket section of `AGENTS.md` matches and its settings are filled | yes | | yes | yes | yes |
| `scripts/test.sh` | `tests/scripts.sh` and `tests/install.sh` under `/bin/bash` | | yes | yes | yes | yes |
| `docket/scripts/ci.sh` | queue hygiene, Markdown links, PR markers against the queues | yes | | yes | yes | yes |
| `docket/scripts/review-due.sh` | review cadence report | | | | | yes |
| `scripts/check.sh` | lint, vendor-check, test, then `docket/scripts/ci.sh` | | | | | yes |

CI runs the three gate scripts as separate steps of one job, on Ubuntu and macOS, so a failure names its gate; `scripts/check.sh` runs the same scripts in the same order plus the hygiene check, and is what to run before opening or updating a PR. `scripts/lint.sh` skips shellcheck when it is not installed and says so, except on a Linux CI runner (`CI` set), where a missing shellcheck fails the gate. In practice shellcheck runs on the Ubuntu jobs and is skipped on macOS, whose runner image does not ship it.

Hooks are the tracked `.githooks/pre-commit` and `.githooks/pre-push`, wired with `git config core.hooksPath .githooks` by `bash scripts/setup.sh`. Pre-commit only checks, never rewrites, and checks the working tree rather than the staged files. Measured pre-commit time: about 1.4 s warm on an Apple-silicon Mac (2026-10-12). Bypassing a hook is for a broken toolchain only; state the bypass and the equivalent checks in the PR.

There are no toolchain pins: the tools are git, bash, `gh` and shellcheck as the runner images and the user's machine provide them.

## Test policy

- A change to a script's or the installer's behaviour adds or updates a fixture in `tests/scripts.sh` or `tests/install.sh` that fails without the change.
- Documentation-only changes need no new test; `docket/scripts/check-links.sh` and `scripts/vendor-check.sh` cover their mechanical side.
- Fixtures build their own scratch repositories under a temporary directory and a fake `gh` for forge calls; they never touch the network or this checkout's refs.
- An empty or skipped suite is a failed gate. No automatic retries. A flaky fixture is filed in `TODO.md` and fixed or removed by name.

## Review inputs

Read by `docket/CODE_REVIEW_GUIDE.md`, which links this section by its heading, so keep the heading as it is; a codebase review runs and records exactly what is listed here.

- Focus areas: the correctness boundaries under [What quality means here](#what-quality-means-here) and the invariants in [ARCHITECTURE.md](../ARCHITECTURE.md#invariants). In particular: behaviour under bash 3.2, agreement between each script and the guide and template it parses, and installer safety on unusual `AGENTS.md` and `CLAUDE.md` shapes.
- Baseline commands beyond `bash scripts/check.sh`: none; record its full output and the `/bin/bash` version.
- Drift checks for an incremental review: `SKILL.md` and `references/` against `templates/docket/CONTRACT.md` and the guides; each script's usage header against its behaviour and the README's script list; `templates/README.md` against the files in `templates/`; this document against `.githooks/` and `.github/workflows/`.
- Source paths for `bash docket/scripts/review-due.sh --paths "install.sh SKILL.md references templates tests"`, the same value the scheduled workflow passes.
- Expected tracked files: `.md`, `.sh`, `.yml`, `.yaml`, `.svg`, `.png`, the extensionless hooks in `.githooks/`, `docket/VERSION`, `LICENSE`, `.gitignore` and `.aiignore`.

## CI

`.github/workflows/ci.yml` runs on pull requests (including body edits) and on pushes to `main`. Jobs: `scripts` (lint, vendored copy, tests) on `ubuntu-latest` and `macos-latest`, and `Queue and PR hygiene`, which runs `bash docket/scripts/ci.sh`; on pull requests its marker check compares the queues at the base branch tip with the checked-out merge commit. Superseded runs are cancelled on PR branches only, never on `main`. No failure evidence is uploaded; the job logs carry the fixture output.

## Scheduled validation of main

`.github/workflows/main-validation.yml` runs weekly (Mondays 11:23 UTC), on demand, and on pull requests that touch it, `docket/` or `scripts/`. On Ubuntu and macOS it runs `bash scripts/check.sh` on main's tip and `docket/scripts/review-due.sh`, and uploads the logs as evidence for 14 days. The PR checks already cover everything this repository can test, so the scheduled run is there to catch changes in the runner images and tools under an unchanged tree, and to report whether a codebase review is due. A red main, from the push run or the schedule, is reverted or filed as a P1 the same day. A missing scheduled run is not a pass.

## Branch protection (as configured on 2026-10-12)

`main` is protected by the repository ruleset "Protect main", not by classic branch protection, so `gh api repos/vhata/docket/rulesets` shows it and `.../branches/main/protection` returns 404.

- Required checks: `scripts (ubuntu-latest)` and `scripts (macos-latest)`; up-to-date-with-base: off. `Queue and PR hygiene` is not required.
- Pull request required, with 0 approving reviews; independent agent review is recorded in each PR's `## Review` section. Conversation resolution: not required.
- Force pushes (non-fast-forward) and deletion of `main`: blocked. There is no separate linear-history rule; squash-only merging keeps history linear.
- Administrator bypass: always allowed (the repository admin role is a bypass actor).
- Merge method: the repository allows squash only; title from the PR title, message from the PR body; head branches deleted on merge.

## PR evidence

Every PR lists the commands run and their results, a reproducible scenario for behaviour changes, what was not run and why, and the independent review. See [docket/CODE_REVIEW_GUIDE.md](../docket/CODE_REVIEW_GUIDE.md).
