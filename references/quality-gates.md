# Quality gates: scripts, hooks, CI, scheduled validation, protection

The point of the gates is to make "the user merges" safe rather than ceremonial, and to make agents' claims checkable. Agents drift toward whatever the tooling tolerates, so the mechanical layer tolerates nothing. The rule text for a repository lives in its `docs/QUALITY.md` (template in `templates/docs/QUALITY.md`), which describes the current state only; history and rollout plans belong in decision logs or git, because one repository's quality doc still described a state from before CI existed and could mislead a cold reader.

## One set of scripts, three callers

Every check is a standalone executable in `scripts/`, runnable with no arguments from any directory, exiting non-zero on failure, forwarding extra arguments to its tool. Hooks, CI and agents all call the same scripts, so a red CI run is a surprise, not a discovery.

| Script | Role |
| --- | --- |
| `scripts/setup.sh` | Install dependencies for this worktree and the git hooks. Idempotent. |
| `scripts/fmt-check.sh`, `scripts/format.sh` | Formatter in check mode and in write mode. |
| `scripts/lint.sh` | Linter with warnings denied. |
| `scripts/typecheck.sh` | Static types where the language has them. |
| `scripts/test.sh` | Unit and integration tests. Fails when nothing is collected. |
| `scripts/e2e.sh` | Browser, end-to-end or system tests; writes a unique evidence directory per run and prints it. |
| `scripts/smoke.sh` | The cheapest end-to-end exercise of the built product (headless run, CLI invocation, installed-package import). |
| `scripts/build.sh` | Production or release build and packaging. |
| `scripts/check.sh` | Runs format check, lint, typecheck, test, in that order, stopping at the first failure and naming it. The thing an agent runs before presenting a PR. |

Timings decide placement: anything under a couple of seconds with a warm cache can run on commit; compilation-heavy tests run on push; browser and release builds run in CI only.

## Hooks

- **pre-commit**: format check and lint on staged files only, preserving unstaged changes. Decide once whether the hook rewrites files (`--fix`, `--write`) or only checks; both are fine, write it down. Package-level checks that cannot run on staged content (compilers, `go vet`, `cargo clippy`) run on the whole tree: keep them on commit only while they fit the budget, otherwise move them to pre-push. Target: under two to three seconds warm.
- **pre-push**: typecheck and the unit suite. A docs-only skip is allowed only through a wrapper that diffs the refs actually being pushed against their remote tips, allowlists specific documentation paths, and refuses to skip when any source file reads an allowlisted file at compile time (`include_str!`, `embed`, `go:embed`, `readFileSync` of a doc). One repository had a README-only push skip the test that CI then failed, because the README was embedded in a test.
- Hook manager: a single tracked config that calls the scripts. Lefthook (one binary, polyglot), the `pre-commit` framework (Python), simple-git-hooks or husky (Node), or a tracked `.githooks/` directory wired with `git config core.hooksPath .githooks` all work; the scripts are what matter. Hooks installed by `scripts/setup.sh` cover every worktree when they live in the shared `.git/hooks` or in a tracked hooks path.
- Bypass (`--no-verify`, `LEFTHOOK=0`, `SKIP=`) is for a broken toolchain, not a deferred fix. Every bypass is stated in the PR with the equivalent checks run by hand.

## CI on pull requests and on main

- Triggers: `pull_request` and `push` to the default branch. The push run is what catches two individually green PRs whose combination is red.
- Jobs call the scripts. A fast `check` job (the check entrypoint plus build) and parallel jobs for browser or smoke checks. Pin toolchains through files the runner reads (`rust-toolchain.toml`, `.python-version` plus a lock, `packageManager` plus a lock, `go.mod`), never a version typed only into the workflow.
- Concurrency: cancel superseded runs on PR branches, never on main. Cancelling main runs when several PRs merge in quick succession is how one repository ended up with nine cancelled main builds and two red ones nobody saw.

  ```yaml
  concurrency:
    group: ci-${{ github.ref }}
    cancel-in-progress: ${{ github.event_name == 'pull_request' }}
  ```

- Timeouts on every job. Upload failure evidence (test results, traces, logs, coverage) with `if: failure()` and a short retention.
- No automatic retries. One deliberate diagnostic rerun is allowed and both results are kept; rerunning until green is not. A flaky test is a finding: record it in the queue with the evidence directory, fix the flake or quarantine it with a named reason, never widen a timeout silently. Traces configured "on first retry" with retries at zero are never captured; configure them "retain on failure".
- Add the workflow checks: `bash scripts/check-queues.sh --strict` on every PR, `bash scripts/check-pr-markers.sh` on pull_request events (fetch the body with `gh pr view "$PR" --json body -q .body`), `bash scripts/check-links.sh` on documentation changes.
- PR runs of a scheduled workflow: give the scheduled workflow a `pull_request` trigger filtered to its own paths so edits to it are exercised before they land.

## Empty suites and weakened gates

A test job that collects nothing has passed nothing. Set the runner to fail on empty collection (`passWithNoTests: false`, pytest's exit code 5 left as a failure, `go test` with no packages treated as an error in the script). Coverage gates measure the exact claim: when the policy is engine branch coverage, measure branch coverage of the engine, not combined statement coverage of everything. Never lower a threshold, skip a suite or mark a test expected-to-fail to finish a PR; report the failure and stop.

## Scheduled validation of main

A separate workflow runs on the default branch on a schedule (daily for a fast suite, weekly for a long one) and on `workflow_dispatch`, with a concurrency group that does not cancel in-progress runs. It runs what PR CI cannot afford: the full browser suite, long headless or simulation runs over many seeds, property tests at ten times the examples with the run id as the seed so reruns reproduce, package build plus an installed-artifact smoke test in a clean environment, recovery or restore drills against synthetic state, and `bash scripts/review-due.sh`. Each job uploads evidence with `if: always()`. A determinism probe (same seed twice, diff the outputs) fails its own job on mismatch; that job is simply not a required PR check. A green workflow whose steps swallow a mismatch with `continue-on-error` or `exit 0` is a failed experiment wearing a green badge, so keep job status and verdict the same thing.

Policy for a red main, whether from the push run or the schedule: the same day, either revert or file a P1 entry (P0 if it blocks releases) with the run link and evidence. A green fix branch is not recovery; recovery is the next main run going green, and the entry stays open until it does. A red main left unaddressed is how a port-collision flake stayed on record in one repository with no follow-up. GitHub disables schedules after sixty days without repository activity and runs them best-effort; the README badge for the scheduled workflow is the cheap visibility, and a missing run is not a pass.

## Branch protection

Set once, by the user, and recorded in `docs/QUALITY.md`. Inspect with:

```bash
gh api repos/{owner}/{repo}/branches/main/protection
gh api repos/{owner}/{repo}/rulesets
gh api repos/{owner}/{repo} --jq '{allow_squash_merge,allow_merge_commit,allow_rebase_merge,delete_branch_on_merge,squash_merge_commit_title,squash_merge_commit_message}'
```

These are recommendations for a repository worked by agents and merged by one person; the repository's own recorded policy wins, and changing hosting settings needs the user's word.

- Required status checks: the PR CI jobs by exact name. `strict: true` (branch up to date with base) when PRs are usually merged one at a time; it forces a rebase before each merge, which the squash-then-rebase flow makes cheap, and it removes the two-green-PRs-make-red-main failure. With many near-simultaneous merges, a merge queue does the same job.
- Required linear history and conversation resolution. Force pushes and deletions blocked.
- Repository merge settings: squash only; squash title from PR title; squash message from PR body; delete head branch on merge.
- Required approving reviews: zero is acceptable when the reviewers are agents, because the forge cannot see them; the `## Review` section in the PR body is the record. Say so in the quality doc.
- Administrator enforcement: on, if the repository has no direct-to-main exceptions. Off only when `AGENTS.md` enumerates the exceptions (plans, housekeeping files, authorised recovery), and then the bypass is a deliberate click with the reason stated in the commit.
- Scheduled workflows are not required checks.

Two of the three studied repositories had protection at all; one had none, so a red main CI and zero reviews blocked nothing. Hosting settings are a one-way door: confirm with the user before changing them.

## Per-language defaults

Principles over tools; name a tool in the repository's docs only once it is chosen and load-bearing. Reasonable starting points when a repository has nothing:

| Language | Format | Lint | Types | Tests | Pin |
| --- | --- | --- | --- | --- | --- |
| Rust | `cargo fmt --check` | `cargo clippy --all-targets -D warnings` | compiler | `cargo test --workspace` | `rust-toolchain.toml`, `Cargo.lock` |
| Python | ruff format | ruff check | basedpyright or mypy strict | pytest with `--strict-markers`, coverage with branch | `.python-version`, `uv.lock` or equivalent |
| TypeScript/JS | prettier or biome | eslint or biome | `tsc --noEmit` strict | vitest or jest, `passWithNoTests: false`; Playwright for browsers | `packageManager`, lockfile, `.nvmrc` |
| Go | `gofmt -l`, `goimports` | `go vet`, golangci-lint | compiler | `go test ./... -race -count=1` | `go.mod`, `go.sum` |
| Shell | shfmt | shellcheck | n/a | bats or script self-tests | n/a |
| Mixed | one entrypoint per language behind the same `scripts/` names | | | | |

Domain-specific lint rules (no clock or randomness in deterministic code, no cross-layer imports) are worth more than generic style rules; add them when a review finds the same class of violation twice.

## Evidence

Every PR records the commands actually run and their results, and names what was not run and why. Evidence directories from browser or system runs are unique per invocation and kept until the PR lands; a later run must never overwrite the failing run's traces. Measurements go in the PR body with the seed, the command and the before and after figures; a claim about performance or behaviour without a reproducible command is an opinion.
