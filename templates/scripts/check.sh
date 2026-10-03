#!/usr/bin/env bash
# Local entry point: run the mechanical gates in order, cheapest first, and
# stop at the first failure, naming the gate. Hooks and CI call the same
# per-gate scripts. See docs/QUALITY.md.
set -euo pipefail
cd "$(dirname "$0")/.."

for gate in fmt-check lint typecheck test; do
  [ -x "scripts/$gate.sh" ] || { echo "check: scripts/$gate.sh missing or not executable" >&2; exit 1; }
  echo "==> $gate"
  if ! "scripts/$gate.sh" "$@"; then
    echo "check: gate '$gate' failed (scripts/$gate.sh)" >&2
    exit 1
  fi
done
echo "check: all gates passed"
