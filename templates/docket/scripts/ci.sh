#!/usr/bin/env bash
# Run every docket validator that CI applies to a project, in order, stopping
# at the first failure and naming the check that failed.
#
# Contract: CI calls only this script (`bash docket/scripts/ci.sh`). The list
# of validators lives here, inside the vendored docket/ directory, so a
# validator added to the skill reaches every project on its next resync
# without a workflow edit. Projects never edit this file; drift is reported
# by `install.sh --check`.
#
# Checks, in order:
#   1. check-queues.sh --strict      queue structure, warnings are errors
#   2. check-links.sh                relative Markdown links and anchors
#   3. check-pr-markers.sh           only when PR is set (see below)
#
# Environment (all optional; set them on pull_request events):
#   PR           GitHub pull request number. When non-empty the PR body is
#                fetched with `gh pr view` and validated against the queues.
#   BASE         the PR's base branch name (for example "main"); required
#                with PR. The comparison uses "origin/$BASE".
#   HEAD_BRANCH  the PR's head branch name; required with PR. Enables the
#                claim rule for branches named <queue>/<slug>.
#
# Exit 1 on the first failing check, 2 on a configuration error.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ci: not in a git repository" >&2; exit 2; }
cd "$root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_check() {
  # run_check NAME COMMAND...: run one validator and stop on failure.
  local name="$1"; shift
  echo "==> $name"
  if ! "$@"; then
    echo "ci: check '$name' failed" >&2
    exit 1
  fi
}

run_check "check-queues" "$here/check-queues.sh" --strict
run_check "check-links" "$here/check-links.sh"

ran_markers=0
if [ -n "${PR:-}" ]; then
  if [ -z "${BASE:-}" ] || [ -z "${HEAD_BRANCH:-}" ]; then
    echo "ci: check 'check-pr-markers' cannot run: PR=$PR is set but BASE or HEAD_BRANCH is empty; both are required" >&2
    exit 2
  fi
  echo "==> check-pr-markers (PR #$PR, base origin/$BASE, head branch $HEAD_BRANCH)"
  if ! gh pr view "$PR" --json body -q .body > "$tmp/pr-body.md"; then
    echo "ci: check 'check-pr-markers' failed: could not fetch the body of PR #$PR with gh" >&2
    exit 1
  fi
  if ! "$here/check-pr-markers.sh" --body "$tmp/pr-body.md" --base "origin/$BASE" --head HEAD --branch "$HEAD_BRANCH"; then
    echo "ci: check 'check-pr-markers' failed" >&2
    exit 1
  fi
  ran_markers=1
fi

if [ "$ran_markers" -eq 1 ]; then
  echo "ci: all checks passed (check-queues, check-links, check-pr-markers)"
else
  echo "ci: all checks passed (check-queues, check-links; no PR set, markers skipped)"
fi
