#!/usr/bin/env bash
# Prepare this checkout: point git at the tracked hooks in .githooks/. Nothing
# else needs installing; the tools are git and bash, plus gh and ShellCheck
# when available. Idempotent; the setting is shared by every worktree of the
# clone.
set -euo pipefail
cd "$(dirname "$0")/.."

git config core.hooksPath .githooks
command -v shellcheck >/dev/null 2>&1 || echo "setup: shellcheck is not installed; scripts/lint.sh will skip it"
echo "setup: hooks installed from .githooks/. Run 'bash scripts/check.sh' to verify the baseline."
