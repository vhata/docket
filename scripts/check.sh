#!/usr/bin/env bash
# Local entry point: run the gates in order, cheapest first, and stop at the
# first failure, naming the gate. CI runs the same scripts. Queue and link
# hygiene (docket/scripts/ci.sh) runs last so one command covers everything
# CI checks on a push. See docs/QUALITY.md.
set -euo pipefail
cd "$(dirname "$0")/.."

for gate in lint vendor-check test; do
  [ -x "scripts/$gate.sh" ] || { echo "check: scripts/$gate.sh missing or not executable" >&2; exit 1; }
  echo "==> $gate"
  if ! "scripts/$gate.sh"; then
    echo "check: gate '$gate' failed (scripts/$gate.sh)" >&2
    exit 1
  fi
done
echo "==> hygiene"
bash docket/scripts/ci.sh || { echo "check: gate 'hygiene' failed (docket/scripts/ci.sh)" >&2; exit 1; }
echo "check: all gates passed"
