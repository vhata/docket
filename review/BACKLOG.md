# Review backlog

Only work promoted from whole-codebase reviews belongs here. Every entry is ready for separate work and carries a `Findings:` line naming the raw review findings it covers; each finding maps to at most one entry. Claiming and resolving follow [docket/TODO_GUIDE.md](../docket/TODO_GUIDE.md); promotion follows [docket/CODE_REVIEW_GUIDE.md](../docket/CODE_REVIEW_GUIDE.md).

## P0 Critical

## P1 High

- [INSTALLER] `keep-wrapped-settings-on-resync` — **A resync keeps every settings bullet whole, including wrapped continuation lines and sub-bullets, and recognises a filled value that contains angle brackets.** Today the continuation lines are silently deleted while the installer reports keeping the settings.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Starting point: `install.sh:190-211` (`expected`, `unfilled`).
  - Findings: `wrapped-setting-bullets-truncated`, `placeholder-detector-false-positive`

## P2 Normal

- [INSTALLER] `installer-marker-detection` — **The installer finds the Docket markers and the `@AGENTS.md` line in CRLF files and ignores markers inside fenced code.** A CRLF `AGENTS.md` gets a second section and loses its filled values.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Starting point: `install.sh:183`, `install.sh:216-220`, `install.sh:449`.
  - Findings: `crlf-agents-md-duplicate-section`, `fenced-marker-example-replaced`, `header-claims-outside-never-read-or-written`

- [INSTALLER] `installer-file-shape-safety` — **The installer refuses or safely handles a symlinked, looping or directory `AGENTS.md`/`CLAUDE.md`, a pre-existing project `docket/`, and an exclude file without a final newline.** Several of these write outside the installer's write set or destroy project files.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `agents-md-symlink-written-through`, `existing-docket-dir-overwritten`, `symlink-loop-hangs-installer`, `agents-md-directory-gets-nested-file`, `exclude-append-corrupts-last-line`

- [INSTALLER] `installer-version-guard` — **A plain install refuses a skill checkout older than `docket/VERSION`, and subtree hosts compare correctly when the upstream commit object is absent.** Today a stale checkout silently downgrades the vendored copy, and fresh clones of a subtree host hide local edits.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Starting point: `install.sh:160-170`, `install.sh:285-299`.
  - Findings: `install-mode-skips-version-guard`, `subtree-host-clone-misses-dirty-and-newer`

- [TOOLING] `installer-safety-fixtures` — **`tests/install.sh` fails when the installer deletes a file, duplicates the exclude line, clobbers `AGENTS.md` on malformed markers, or mishandles usage errors.** Mutations breaking each of these left the suite green.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `install-fixture-gaps-never-delete-and-malformed`

- [SCRIPTS] `marker-body-cleaning` — **The PR body cleaning in `check-pr-markers.sh` and `pr-labels.sh` hides only what GitHub hides, and the near-miss rule leaves wrapped prose alone.** An inline `<!--` hides later markers, a fenced Validation section counts as empty, and ordinary wrapped prose fails as a malformed marker.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Starting point: The shared awk at `check-pr-markers.sh:113-130` and `pr-labels.sh:101-118`; keep the two copies identical.
  - Findings: `validation-section-blind-to-fenced-content`, `unterminated-comment-opener-swallows-body`, `near-miss-marker-rule-flags-wrapped-prose`, `four-backtick-fences-not-recognised`, `trailing-whitespace-fails-markers`, `comment-fixtures-vacuous`

- [SCRIPTS] `marker-rule-fixtures` — **Every base/head rule in `check-pr-markers.sh` and every path in `ci.sh` has a fixture that fails without it, and each partial resolution names its own remainder.** Mutation testing removed most of these rules without a failure.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `marker-queue-rules-lack-negative-fixtures`, `unnamed-remainder-passes`, `ci-sh-untested-and-test-header-drift`

- [SCRIPTS] `cleanup-landed-safety` — **`cleanup-landed.sh` keeps any worktree it cannot prove clean, survives a locked worktree, and reports un-PR'd branches ahead of base.** A failing `git status` currently reads as clean and the worktree is force-removed.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `cleanup-landed-status-error-treated-clean`, `cleanup-landed-locked-worktree-aborts-run`, `cleanup-landed-unpushed-branches-not-reported`, `tests-cleanup-landed-fake-gh-always-tip`

- [SCRIPTS] `start-work-hardening` — **`start-work.sh` creates an untracked branch, validates its queue, separates forge failure from a claim, and works from a subdirectory or linked worktree.** Today the new branch tracks `origin/main`, so a plain push can target main.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `start-work-branch-tracks-origin-main`, `start-work-queue-unvalidated`, `start-work-misreports-forge-failure`, `start-work-nests-in-linked-worktree`, `scripts-resolve-own-path-after-cd`

- [TOOLING] `honest-local-gates` — **The local gates run the scripts under `/bin/bash`, fail on an empty suite, lint every shipped script and print the reason a hook refused a commit.** Locally, 3.2 breakage passes when a newer bash is first on PATH, and the pre-commit hook fails silently.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Starting point: `scripts/test.sh`, `scripts/lint.sh:9`, `.githooks/pre-commit:7-9`.
  - Findings: `fixtures-run-scripts-under-path-bash`, `pre-commit-hides-failure-reasons`, `lint-skips-template-scripts`, `test-gate-passes-empty-suite`

## P3 Low

- [SCRIPTS] `check-links-parsing` — **`check-links.sh` skips code, understands CommonMark link targets and reference definitions, and slugs headings with emphasis or inline HTML as GitHub does.** Example links in code are reported broken and some valid links fail.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `check-links-checks-code-spans-and-fences`, `check-links-target-forms`, `check-links-anchor-emphasis-html`, `tests-check-links-and-start-work-gaps`
  - Also hit in vhata/partlet, 2026-10-15: a plan's fenced Python tests contained string literals holding Markdown link syntax, which the link checker reported as four broken links and blocked the plan's direct commit to main. Partlet worked around it by splitting the string literals.

- [SCRIPTS] `review-due-accuracy` — **`review-due.sh` counts churn with one root-anchored exclusion list, compares the unrounded ratio, warns on `--paths` that match nothing, survives blank `--paths` under 3.2, and has a fixture per threshold.** Several of these make the full-review verdict wrong or silent.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `review-due-excludes-nested-docs-review-dirs`, `review-due-svg-in-churn-not-denominator`, `review-due-paths-matching-nothing-silent`, `review-due-whitespace-paths-bash32`, `review-due-full-threshold-rounded`, `tests-review-due-thresholds-unfixtured`

- [SCRIPTS] `check-queues-strictness` — **`check-queues.sh` rejects malformed finding slugs and non-dash entries, checks areas against `AGENTS.md`, agrees with the guides on `Blocked by: None`, and has a fixture per rule.** Entries it accepts today can break `claim-check.sh` or go unvalidated.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `check-queues-finding-slugs-unvalidated`, `check-queues-skips-non-dash-entries`, `check-queues-area-unchecked`, `blocked-by-none-accepted-in-ready`, `tests-check-queues-core-rules-unfixtured`

- [SCRIPTS] `claim-check-freshness` — **`claim-check.sh` sees branches pushed since the last fetch and queries each PR list once per run.** Two workers can claim the same slug before the first draft PR exists.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `claim-check-stale-remote-refs`, `claim-check-closed-pr-pagination`, `tests-claim-check-body-regex-not-jq-run`

- [TOOLING] `ci-workflow-upkeep` — **The workflows use Node 24 action majors, the PR matrix does not fail fast, body edits rerun only the hygiene job, and `.aiignore` patterns are anchored.** Each is a small, independent workflow or config change.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `ci-actions-node20-deprecated`, `ci-matrix-fail-fast-hides-macos`, `edited-trigger-reruns-full-ci`, `aiignore-unanchored-readme`

- [GUIDES] `guide-reference-tidy` — **The SKILL.md script table, the script headers, the template quality table and the vendored README agree with the scripts and templates they describe.** Small documentation drift found by the first full review.
  - Source: review/2026-10-12-1702-full.md, 2026-10-12
  - Findings: `skill-script-table-flags-incomplete`, `script-headers-missing-exit-codes`, `template-quality-table-vs-template-workflows`, `vendored-readme-names-feral-history`

## Unprioritized
