#!/usr/bin/env bash
# Run both regression suites under /bin/bash, which is 3.2 on macOS: the
# vendored scripts against disposable repositories with a fake forge, and the
# installer against scratch projects and clones of this checkout. Each suite
# puts its own bash first on PATH, so the scripts it runs use /bin/bash too.
set -euo pipefail
cd "$(dirname "$0")/.."
echo "test: suites and scripts under /bin/bash $(/bin/bash -c 'echo "$BASH_VERSION"')"
/bin/bash tests/scripts.sh
/bin/bash tests/install.sh
