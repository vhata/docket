#!/usr/bin/env bash
# Prepare this worktree: install dependencies from the lockfile and install
# the git hooks. Idempotent; run after cloning, creating a worktree, or
# changing hook configuration.
set -euo pipefail
cd "$(dirname "$0")/.."

# <Dependencies, lockfile-exact, into this worktree's own environment:>
# uv sync --locked            # Python
# pnpm install --frozen-lockfile   # Node
# cargo fetch                 # Rust
# go mod download             # Go

# <Hooks, one manager:>
# lefthook install
# uv run --locked pre-commit install --install-hooks
# pnpm exec simple-git-hooks
# git config core.hooksPath .githooks

echo "setup: done. Run 'bash scripts/check.sh' to verify the baseline."
