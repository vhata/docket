#!/usr/bin/env bash
# Run both regression suites under /bin/bash, which is 3.2 on macOS: the
# vendored scripts against disposable repositories with a fake forge, and the
# installer against scratch projects and clones of this checkout.
set -euo pipefail
cd "$(dirname "$0")/.."
/bin/bash tests/scripts.sh
/bin/bash tests/install.sh
