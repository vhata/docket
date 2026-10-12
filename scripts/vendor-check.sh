#!/usr/bin/env bash
# This repository's docket/ is generated from templates/docket/ by
# `bash install.sh --self`. Fail when the two differ, when VERSION is not
# `self`, or when the Docket section of AGENTS.md has drifted.
set -euo pipefail
cd "$(dirname "$0")/.."
bash install.sh --self --check
