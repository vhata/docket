#!/usr/bin/env bash
# Parse every shell script with /bin/bash (3.2 on macOS) and run shellcheck at
# warning level where it is installed; on a Linux CI runner it is required.
# Covers the shipped scripts, the installer, the tests and this repository's
# own scripts and hooks.
set -euo pipefail
cd "$(dirname "$0")/.."

files=(templates/docket/scripts/*.sh install.sh tests/*.sh scripts/*.sh .githooks/*)
for f in "${files[@]}"; do
  /bin/bash -n "$f" || { echo "lint: $f does not parse under /bin/bash" >&2; exit 1; }
done
echo "lint: ${#files[@]} scripts parse under /bin/bash $(/bin/bash -c 'echo $BASH_VERSION')"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -s bash "${files[@]}"
  echo "lint: shellcheck clean"
elif [ -n "${CI:-}" ] && [ "$(uname -s)" = Linux ]; then
  echo "lint: shellcheck is not installed on this Linux CI runner; the gate needs it here" >&2
  exit 1
else
  echo "lint: shellcheck not installed; skipped"
fi
