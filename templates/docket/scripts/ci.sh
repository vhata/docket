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
#                validated against the queues.
#   BASE         the PR's base branch name (for example "main"); required
#                with PR. The comparison uses "origin/$BASE".
#   HEAD_BRANCH  the PR's head branch name; required with PR. Enables the
#                claim rule for branches named <queue>/<slug>.
#
# The PR body comes from one of two places. When GITHUB_EVENT_PATH names a
# readable pull_request event payload for PR and jq is installed, the body is
# read from it with `jq -r`; this needs no token. A re-run reuses the original
# payload, so the workflow must also trigger on `edited` for a changed body to
# be re-validated. Otherwise it is fetched with `gh pr view`, which needs
# GH_TOKEN with `pull-requests: read` (the default GITHUB_TOKEN has it only
# when the workflow's permissions block grants it).
# On a pull_request event the checkout is the merge commit, so --head HEAD is
# the base-plus-PR tree, and --base "origin/$BASE" is the base branch tip at
# the time the job runs; fetch it with enough depth (fetch-depth: 0) for the
# queue snapshots to resolve.
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
  # Prefer the event payload (no token needed); fall back to gh when jq or the
  # payload is missing, or the payload describes a different pull request.
  body_from=""
  if command -v jq >/dev/null 2>&1 && [ -n "${GITHUB_EVENT_PATH:-}" ] && [ -r "$GITHUB_EVENT_PATH" ] \
    && jq -e --arg pr "$PR" '.pull_request | type == "object" and has("body") and ((.number | tostring) == $pr)' "$GITHUB_EVENT_PATH" >/dev/null 2>&1; then
    jq -r '.pull_request.body // ""' "$GITHUB_EVENT_PATH" > "$tmp/pr-body.md"
    body_from="$GITHUB_EVENT_PATH"
  elif gh pr view "$PR" --json body -q .body > "$tmp/pr-body.md"; then
    body_from="gh pr view"
  else
    echo "ci: check 'check-pr-markers' failed: could not read the body of PR #$PR (no usable GITHUB_EVENT_PATH, and gh failed; the gh path needs pull-requests: read)" >&2
    exit 1
  fi
  echo "    (body from $body_from)"
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
