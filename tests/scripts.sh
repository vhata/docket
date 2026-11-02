#!/usr/bin/env bash
# Regression checks for the vendored scripts, run against a disposable git
# repository. Exercises check-pr-markers.sh, check-queues.sh, claim-check.sh,
# start-work.sh, review-due.sh, check-links.sh and cleanup-landed.sh (also in
# managed-repository target mode, with target.sh) with
# positive and negative fixtures (gh is replaced by a fake on PATH), and checks
# that every script is executable on disk and in the committed mode.
#
# Usage: bash tests/scripts.sh   (from anywhere; needs git and bash 3.2+)
set -euo pipefail
# Git exports GIT_DIR (and, in some cases, GIT_WORK_TREE and GIT_INDEX_FILE) to
# hooks; from a linked worktree GIT_DIR is absolute. Left set, every fixture
# command below would act on the repository running the hook: `git init`
# reinitialises it as bare, `git config` writes fixture settings into its
# shared config and `git symbolic-ref HEAD` moves its HEAD.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)
root="$(cd "$(dirname "$0")/.." && pwd)"
scripts="$root/templates/docket/scripts"
# start-work.sh runs claim-check.sh directly, so every script must stay
# executable both on disk and in the committed mode.
for f in "$scripts"/*.sh; do
  [ -x "$f" ] || { echo "scripts-test: $f is not executable" >&2; exit 1; }
done
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  modes="$(git -C "$root" ls-files -s -- templates/docket/scripts | awk '$4 ~ /\.sh$/ && $1 != "100755" { print $4 }')"
  [ -z "$modes" ] || { echo "scripts-test: not committed as executable: $modes" >&2; exit 1; }
fi
fixture="$(mktemp -d)"
external="$(mktemp -d)"
gitcfg="$(mktemp)"
# Run every script under the bash running this suite. The suite calls scripts
# as `bash <script>` and through `#!/usr/bin/env bash` shebangs, which resolve
# bash through PATH; on macOS a newer bash usually comes first there, so a
# suite started under /bin/bash (3.2, as scripts/test.sh does) would otherwise
# test the scripts under the newer one.
suitebash="$(mktemp -d)"
trap 'rm -rf "$fixture" "$external" "$gitcfg" "$suitebash"' EXIT
ln -s "$BASH" "$suitebash/bash"
PATH="$suitebash:$PATH"; export PATH
[ "$(bash -c 'echo "$BASH_VERSION"')" = "$BASH_VERSION" ] \
  || { echo "scripts-test: bash on PATH is not the suite's bash ($BASH_VERSION)" >&2; exit 1; }
# Isolate every fixture from the user's and the system's git configuration
# (fetch.prune, init.defaultBranch, identity and the like): each repository
# sets its own identity, and behaviour must not depend on the machine.
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$gitcfg"
mkdir -p "$fixture/docket/scripts" "$fixture/review" "$fixture/bin"
cp "$scripts"/*.sh "$fixture/docket/scripts/"
cp "$root/templates/.github/pull_request_template.md" "$fixture/template.md"
cd "$fixture"
git init --quiet
git symbolic-ref HEAD refs/heads/main
git config user.name 'Scripts fixture'
git config user.email 'scripts-fixture@example.invalid'
git config core.hooksPath /dev/null
markers="docket/scripts/check-pr-markers.sh"
queues="docket/scripts/check-queues.sh"
claim="$fixture/docket/scripts/claim-check.sh"
due="docket/scripts/review-due.sh"

pass() {
  label="$1"; shift
  if ! "$@" > "$fixture/result.log" 2>&1; then
    echo "scripts-test: $label unexpectedly failed" >&2
    cat "$fixture/result.log" >&2
    exit 1
  fi
}
reject() {
  label="$1"; expected="$2"; shift 2
  if "$@" > "$fixture/result.log" 2>&1; then
    echo "scripts-test: $label unexpectedly passed" >&2
    exit 1
  fi
  if ! grep -Fq "$expected" "$fixture/result.log"; then
    echo "scripts-test: $label failed for the wrong reason" >&2
    cat "$fixture/result.log" >&2
    exit 1
  fi
}

expect() {
  # expect LABEL TEXT: the last pass() output must contain TEXT.
  grep -Fq "$2" "$fixture/result.log" || { echo "scripts-test: $1" >&2; cat "$fixture/result.log" >&2; exit 1; }
}

# check-pr-markers.sh
cat > TODO.md <<'QUEUE'
# TODO

## Ready for separate work

### P2 Normal

- [TOOLS] `claimed-task` **Complete the task.**
  - Source: scripts regression fixture
QUEUE
printf '# Review backlog\n\n## P2 Normal\n' > review/BACKLOG.md
git add TODO.md review/BACKLOG.md
git commit --quiet -m 'Initial fixture queues'
base="$(git rev-parse HEAD)"
printf '## Why\n\nRequested work.\n\nClaims TODO: claimed-task\n' > body.md
pass 'valid queued claim' bash "$markers" --body body.md --base "$base" --head HEAD --branch todo/claimed-task
pass 'template comments' bash "$markers" --body template.md --base "$base" --head HEAD --branch task/direct
reject 'missing refs' 'not found' bash "$markers" --body template.md --base missing-base --head missing-head --branch task/direct
printf 'Requested work without a heading.\n' > body.md
reject 'missing heading' 'description has no' bash "$markers" --body body.md --base "$base" --head HEAD --branch task/direct
printf '## Why\n\nWrong namespace.\n\nClaims roadmap: claimed-task\n' > body.md
reject 'wrong namespace' 'no marker claims or resolves' bash "$markers" --body body.md --base "$base" --head HEAD --branch todo/claimed-task
# Markers written as list items or quotes are rejected rather than ignored.
printf '## Why\n\nListed marker.\n\n- Claims TODO: claimed-task\n' > body.md
reject 'dash list marker' 'written as a list item or quote' bash "$markers" --body body.md --base "$base" --head HEAD --branch task/direct
printf '## Why\n\nListed marker.\n\n1. Resolves review backlog: claimed-task\n' > body.md
reject 'numbered list marker' 'written as a list item or quote' bash "$markers" --body body.md --base "$base" --head HEAD --branch task/direct
printf '## Why\n\nQuoted marker.\n\n> Claims TODO: claimed-task\n' > body.md
reject 'quoted marker' 'written as a list item or quote' bash "$markers" --body body.md --base "$base" --head HEAD --branch task/direct
printf '## Why\n\nListed marker beside a valid one.\n\nClaims TODO: claimed-task\n+ Files TODO: claimed-task\n' > body.md
reject 'list marker beside a valid one' 'written as a list item or quote' bash "$markers" --body body.md --base "$base" --head HEAD --branch todo/claimed-task
for item in '- [ ] Claims TODO: claimed-task' '- [x] Resolves TODO: claimed-task' '* [X] Claims TODO: claimed-task' '1. [ ] Claims TODO: claimed-task'; do
  printf '## Why\n\nTask-list marker.\n\n%s\n' "$item" > body.md
  reject "task-list marker $item" 'written as a list item or quote' bash "$markers" --body body.md --base "$base" --head HEAD --branch task/direct
done
printf '## Why\n\nProse lists that mention the queues.\n\n- Files TODO entries for later discoveries\n- Resolves the TODO about naming\n- [ ] Files TODO entries once the spike lands\n\nClaims TODO: claimed-task\n' > body.md
pass 'prose list items' bash "$markers" --body body.md --base "$base" --head HEAD --branch todo/claimed-task
printf '## Why\n\nMalformed.\n\n`Claims TODO: claimed-task`\n' > body.md
reject 'backticked marker' 'malformed marker' bash "$markers" --body body.md --base "$base" --head HEAD --branch task/direct
printf '## Why\n\nMulti-line comment.\n\n<!-- Claims TODO: not-a-slug\nstill a comment -->\nClaims TODO: claimed-task\n' > body.md
pass 'multi-line comment' bash "$markers" --body body.md --base "$base" --head HEAD --branch todo/claimed-task

printf '# TODO\n\n## Needs triage\n\n### P2 Normal\n' > TODO.md
git add TODO.md
git commit --quiet -m 'Resolve fixture task'
printf '## Why\n\nCompleted work.\n\nResolves TODO: claimed-task\n' > body.md
pass 'valid queued resolution' bash "$markers" --body body.md --base "$base" --head HEAD --branch todo/claimed-task

# Partial resolutions: the remainder must be new at head and carry a
# "Remaining from" line that points back at the original.
cat > TODO.md <<'QUEUE'
# TODO

## Ready for separate work

### P2 Normal

- [TOOLS] `original-task` **Finish the original task.**
  - Source: scripts regression fixture
- [TOOLS] `old-remainder` **An entry that already exists at base.**
  - Source: scripts regression fixture
QUEUE
git add TODO.md
git commit --quiet -m 'Partial resolution fixture base'
partial_base="$(git rev-parse HEAD)"
cat > TODO.md <<'QUEUE'
# TODO

## Ready for separate work

### P2 Normal

- [TOOLS] `remainder-task` **Finish what the original left.**
  - Source: scripts regression fixture
  - Remaining from: `original-task`
- [TOOLS] `bad-remainder` **A remainder with no back-reference.**
  - Source: scripts regression fixture
- [TOOLS] `old-remainder` **An entry that already exists at base.**
  - Source: scripts regression fixture
  - Remaining from: `original-task`
QUEUE
git add TODO.md
git commit --quiet -m 'Partial resolution fixture head'
printf '## Why\n\nPartial work.\n\nPartially resolves TODO: original-task\nRemaining TODO: remainder-task\n' > body.md
pass 'partial resolution with a remainder' bash "$markers" --body body.md --base "$partial_base" --head HEAD --branch todo/original-task
printf '## Why\n\nPartial work.\n\nPartially resolves TODO: original-task\nRemaining TODO: bad-remainder\n' > body.md
reject 'remainder without Remaining from' 'has no "Remaining from:' bash "$markers" --body body.md --base "$partial_base" --head HEAD --branch todo/original-task
printf '## Why\n\nPartial work.\n\nPartially resolves TODO: original-task\nRemaining TODO: old-remainder\n' > body.md
reject 'remainder that existed at base' 'already existed at' bash "$markers" --body body.md --base "$partial_base" --head HEAD --branch todo/original-task
printf '## Why\n\nPartial work without a remainder marker.\n\nPartially resolves TODO: original-task\n' > body.md
reject 'partial resolution without a Remaining marker' 'has no matching "Remaining TODO:' bash "$markers" --body body.md --base "$partial_base" --head HEAD --branch todo/original-task

# The change-type line: missing warns, exact passes, near misses and
# repeats fail, and prose that merely mentions a type: label is not a near miss.
printf '## Why\n\nNo type.\n' > body.md
pass 'missing type line' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
expect 'missing type line was not warned' 'no "Type: <kind>" line'
printf '## Why\n\nTyped.\n\n- `type:` labels are mentioned in prose\n\nType: refactor\n' > body.md
pass 'exact type line' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
grep -Fq 'Type: <kind>' "$fixture/result.log" && { echo 'scripts-test: exact type line was warned as missing' >&2; exit 1; }
for item in 'Type: Feature' 'type: fix' '**Type:** fix' '- Type: fix' '> Type: docs' 'Type: fix.' 'Type: chore' '`Type: fix`' ' Type: fix' '- [ ] Type: fix'; do
  printf '## Why\n\nNear miss.\n\n%s\n' "$item" > body.md
  reject "type near miss $item" 'malformed type line' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
done
printf '## Why\n\nTwo kinds.\n\nType: fix\nType: docs\n' > body.md
reject 'two type lines' '2 Type lines' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
printf '## Why\n\nProse.\n\n- type: fix and docs both work now\n\nType: fix\n' > body.md
pass 'list prose after a kind' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
# Fenced code blocks (examples, pasted YAML) are not part of the description's structure.
printf '## Why\n\nFenced.\n\n```yaml\ntype: Opaque\nType: docs\n```\n\n~~~\n- Claims TODO: not-real\n~~~\n\nType: fix\n' > body.md
pass 'fenced code blocks' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
grep -Fq 'Type: <kind>' "$fixture/result.log" && { echo 'scripts-test: the type line after the fences was missed' >&2; exit 1; }
printf '## Why\n\nInline.\n\n```inline``` code at the start of a line\n\nType: fix\n' > body.md
pass 'inline triple backticks' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
grep -Fq 'Type: <kind>' "$fixture/result.log" && { echo 'scripts-test: inline triple backticks opened a fence' >&2; exit 1; }

# Line length: the body becomes the squash commit message, so prose lines
# over 72 characters warn, and --strict turns every warning into an error.
cat > body.md <<'BODY'
## Why

This description was hard-wrapped at seventy-eight columns, which is too wide.

Type: docs
BODY
pass 'wide body' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
expect 'wide body was not warned' 'warning: 1 line longer than 72 characters (line 3: 78)'
reject 'wide body under --strict' 'error: 1 line longer than 72 characters' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct --strict
printf '## Why\n\nNo type.\n' > body.md
reject 'missing type line under --strict' 'error: no "Type: <kind>" line' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct --strict
# Fenced code, comments, tables and unbreakable tokens are exempt, a wrapped
# list item keeps its indentation, and width counts characters, not bytes.
cat > body.md <<'BODY'
## Why

Width is counted in characters — this line has 72 of them, “not” octets.

- A list item whose continuation line stays indented under the marker so
  that it renders as one item; the long link sits on a line of its own:
  https://example.com/a/very/long/path/that/cannot/be/broken/across/lines
- [ ] [docs](https://example.com/another/very/long/path/that/cannot/be/split)

[ref]: https://example.com/a/reference/definition/that/cannot/be/broken/up

| Column | A table row is exempt because a row cannot be broken across lines |
| --- | --- |

<!-- A template hint left in a comment is not checked, however long it is. -->

```
A fenced code block keeps its lines as they are, however long the lines are.
```

Type: docs
BODY
pass 'exempt long lines' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct --strict
cat > body.md <<'BODY'
## Why

- A list item that puts its link on the same line as prose: https://example.com/x
> A quoted line that runs past the limit is prose and can be wrapped like it.

Type: docs
BODY
pass 'breakable long lines' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
expect 'breakable long lines were not warned' 'warning: 2 lines longer than 72 characters (line 3: 81, line 4: 77)'
# The boundary, trailing whitespace, a long marker line and tables written
# without leading pipes; a prose line with a pipe is not a table.
cat > body.md <<'BODY'
## Why

Seventy-three characters is one too many for the lines of a commit's body
This line has seventy-two characters, and ends with two trailing blanks.  

Claims roadmap: a-roadmap-theme-whose-slug-is-long-enough-to-pass-the-limit

Column A | Column B, a table written without the leading pipes that is long
--- | ---
first | a body row in that table, also written without leading pipes at all

A prose line that mentions a | pipe character but is not a table, and runs on.

Type: docs
BODY
pass 'boundary and tables' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct
expect 'boundary and tables were not warned as expected' 'warning: 2 lines longer than 72 characters (line 3: 73, line 12: 78)'
# A markerless body that fails only on length does not blame its markers.
printf '## Why

This description was hard-wrapped at seventy-eight columns, which is too wide.

Type: docs
' > body.md
reject 'wide body message' 'no work-tracking markers found' bash "$markers" --body body.md --base "$base" --head "$base" --branch task/direct --strict
grep -Fq 'no well-formed markers' "$fixture/result.log" && { echo 'scripts-test: a wide body blamed its markers' >&2; exit 1; }

# pr-labels.sh: labels from the branch, the type line and the claimed or
# resolved entries, looked up at base and then at head.
labels="docket/scripts/pr-labels.sh"
cat > TODO.md <<'QUEUE'
# TODO

## Ready for separate work

### P1 High

- [CORE] `urgent-task` **Do the urgent thing.**
  - Source: scripts regression fixture

### Unprioritized

- [DOCS] `loose-task` **Write it down.**
  - Source: scripts regression fixture

## Needs triage

### P0 Critical

- [TOOLS] `triage-task` **Look into it.**
  - Source: scripts regression fixture
QUEUE
cat > review/BACKLOG.md <<'QUEUE'
# Review backlog

## P3 Low

- [UI_KIT] `backlog-fix` **Fix the reviewed thing.**
  - Source: scripts regression fixture
  - Findings: `some-finding`
QUEUE
git add TODO.md review/BACKLOG.md
git commit --quiet -m 'Label fixture base'
labels_base="$(git rev-parse HEAD)"
awk '/`urgent-task`/ { skip = 2 } skip > 0 { skip--; next } { print }' TODO.md > TODO.next && mv TODO.next TODO.md
printf -- '- [WEB] `filed-here` **Filed in the same PR.**\n  - Source: scripts regression fixture\n' >> TODO.md
git add TODO.md
git commit --quiet -m 'Label fixture head'
labels_are() {
  # labels_are LABEL "WANTED LABELS" CMD...: stdout must be exactly the labels.
  label="$1"; want="$2"; shift 2
  "$@" > "$fixture/result.log" 2> "$fixture/stderr.log" || { echo "scripts-test: $label unexpectedly failed" >&2; cat "$fixture/stderr.log" >&2; exit 1; }
  printf '%s\n' "$want" | tr ' ' '\n' > "$fixture/want.txt"
  diff -u "$fixture/want.txt" "$fixture/result.log" > /dev/null 2>&1 || { echo "scripts-test: $label labelled wrongly" >&2; diff -u "$fixture/want.txt" "$fixture/result.log" >&2; exit 1; }
}
printf '## Why\n\nQueued work.\n\nType: feature\nResolves TODO: urgent-task\nClaims TODO: loose-task\n' > body.md
labels_are 'labels for resolved and claimed entries' 'docket type:feature queue:todo area:core area:docs priority:p1' \
  bash "$labels" --body body.md --base "$labels_base" --head HEAD --branch todo/loose-task
printf '## Why\n\nA reviewed fix.\n\nClaims review backlog: backlog-fix\nClaims review finding: some-finding\n' > body.md
labels_are 'labels for a fix branch without a type line' 'docket type:fix queue:review area:ui_kit priority:p3' \
  bash "$labels" --body body.md --base "$labels_base" --head HEAD --branch fix/backlog-fix
printf '## Why\n\nTriage spike.\n\n<!-- Claims TODO: urgent-task -->\nType: refactor\nClaims TODO: triage-task\nClaims TODO: filed-here\nFiles TODO: loose-task\n' > body.md
labels_are 'labels ignore comments and Files markers, read head-only entries' 'docket type:refactor queue:todo area:tools area:web priority:p0' \
  bash "$labels" --body body.md --base "$labels_base" --head HEAD --branch todo/triage-task
printf '## Why\n\nFenced example.\n\n```\nType: perf\n```\n\nType: docs\n' > body.md
labels_are 'labels for directly requested work' 'docket type:docs' \
  bash "$labels" --body body.md --base "$labels_base" --head HEAD --branch task/direct
printf '## Why\n\nNo type.\n\nClaims roadmap: big-theme\n' > body.md
labels_are 'labels without a type line' 'docket queue:roadmap' \
  bash "$labels" --body body.md --base "$labels_base" --head HEAD --branch roadmap/big-theme
grep -Fq 'no "Type: <kind>" line' "$fixture/stderr.log" || { echo 'scripts-test: pr-labels did not warn about the missing type line' >&2; exit 1; }
reject 'pr-labels --apply without --pr' 'needs --pr' bash "$labels" --body body.md --apply
reject 'pr-labels option without a value' 'needs a value' bash "$labels" --body

# --apply against a fake forge: creates only missing labels, adds what applies,
# removes stale labels of the managed forms and leaves every other label alone.
cat > bin/gh <<'GH'
#!/usr/bin/env bash
echo "$*" >> "$FIXTURE_GH_LOG"
case "$1 $2" in
  'pr view')
    case "$5" in
      body) cat "$FIXTURE_BODY" ;;
      baseRefName,headRefName) echo 'main todo/loose-task' ;;
      labels) printf 'docket\ntype:fix\narea:old\nbug\npriority:high\n' ;;
      *) exit 2 ;;
    esac ;;
  'label list') printf 'Docket\nbug\ntype:feature\n' ;;
  'label create'|'pr edit') exit 0 ;;
  *) exit 2 ;;
esac
GH
chmod +x bin/gh
printf '## Why\n\nQueued work.\n\nType: feature\nResolves TODO: urgent-task\nClaims TODO: loose-task\n' > body.md
: > gh.log
pass 'pr-labels --apply' env PATH="$fixture/bin:$PATH" FIXTURE_BODY="$fixture/body.md" FIXTURE_GH_LOG="$fixture/gh.log" \
  bash "$labels" --pr 7 --apply --base "$labels_base" --head HEAD
created="$(grep '^label create' gh.log | awk '{ print $3 }' | paste -sd' ' -)"
[ "$created" = 'queue:todo area:core area:docs priority:p1' ] || { echo "scripts-test: pr-labels created the wrong labels: $created" >&2; exit 1; }
grep -qx 'pr edit 7 --add-label type:feature,queue:todo,area:core,area:docs,priority:p1 --remove-label type:fix,area:old' gh.log \
  || { echo 'scripts-test: pr-labels edited the PR wrongly' >&2; cat gh.log >&2; exit 1; }
expect 'pr-labels did not report the removal' 'removed type:fix, area:old'

# check-queues.sh
cat > TODO.md <<'QUEUE'
# TODO

## Needs triage

### P2 Normal

- [TOOLS] `prerequisite` **Resolve the prerequisite.**
  - Source: scripts regression fixture
QUEUE
cat > review/BACKLOG.md <<'QUEUE'
# Review backlog

## P2 Normal

- [TOOLS] `promoted-fix` **Fix reviewed behaviour.**
  - Source: scripts regression fixture
  - Findings: `review-proof`
QUEUE
cp review/BACKLOG.md unblocked.md
pass 'unblocked backlog' bash "$queues" --strict
printf '  - Blocked by: operator decision\n' >> review/BACKLOG.md
reject 'blocked backlog' 'but is Blocked by' bash "$queues" --strict
cp unblocked.md review/BACKLOG.md
printf '  - Depends on: `prerequisite`\n' >> review/BACKLOG.md
reject 'dependent backlog' 'depends on unresolved' bash "$queues" --strict
cp unblocked.md review/BACKLOG.md
cp TODO.md local-todo.md
printf '  - Blocked by: `owner/other-repo:upstream-fix` landing upstream\n  - Related: `other-repo:upstream-note`, `prerequisite`\n' >> TODO.md
pass 'cross-repository blocker and related' bash "$queues" --strict
expect 'cross-repository references were not accepted' 'no errors'
printf '  - Related: `missing-local`\n' >> TODO.md
reject 'local related still checked' 'Related slug `missing-local` is not in any queue' bash "$queues" --strict
cp local-todo.md TODO.md
printf '  - Blocked by: `other-repo:upstream-fix` and `missing-local`\n' >> TODO.md
reject 'local blocker still checked' 'depends on `missing-local` which is not in any queue' bash "$queues" --strict
cp local-todo.md TODO.md
printf '  - Depends on: `other-repo:upstream-fix`\n' >> TODO.md
reject 'cross-repository dependency' 'in another repository' bash "$queues" --strict
cp local-todo.md TODO.md
cat >> TODO.md <<'QUEUE'

## Ready for separate work

### P2 Normal

- [TOOLS] `waits-upstream` **Use the upstream fix.**
  - Source: scripts regression fixture
  - Blocked by: `other-repo:upstream-fix`
QUEUE
reject 'ready with cross-repository blocker' 'but is Blocked by' bash "$queues" --strict
cp local-todo.md TODO.md
# Waiting holds understood entries that are blocked; the fixtures above have
# no Waiting section, as an older TODO.md does not, and still pass.
cat >> TODO.md <<'QUEUE'

## Waiting

### P1 High

- [TOOLS] `waits-local` **Build on the prerequisite.**
  - Source: scripts regression fixture
  - Depends on: `prerequisite`

- [TOOLS] `waits-decision` **Ship the decided thing.**
  - Source: scripts regression fixture
  - Blocked by: operator decision on the format
QUEUE
cp TODO.md waiting-todo.md
pass 'waiting entries with dependencies and blockers' bash "$queues" --strict
expect 'waiting entries were not accepted' 'no errors'
printf -- '- [TOOLS] `waits-nothing` **Wait for nothing.**\n  - Source: scripts regression fixture\n  - Blocked by: none\n' >> TODO.md
pass 'waiting entry without a blocker is only a warning' bash "$queues"
expect 'waiting entry without a blocker was not warned' '`waits-nothing` is in Waiting but names nothing it waits on'
reject 'waiting entry without a blocker under --strict' '`waits-nothing` is in Waiting' bash "$queues" --strict
pass 'check-queues --help' bash "$queues" --help
expect 'check-queues --help cut its header short' 'Portable to bash 3.2 and POSIX awk.'
cp waiting-todo.md TODO.md
printf -- '- [TOOLS] `waits-upstream` **Use the upstream fix.**\n  - Source: scripts regression fixture\n  - Blocked by: `other-repo:upstream-fix`\n' >> TODO.md
pass 'waiting on another repository' bash "$queues" --strict
cp waiting-todo.md TODO.md
awk '/`prerequisite`/ && /^- / { skip = 2 } skip > 0 { skip--; next } { print }' TODO.md > TODO.next && mv TODO.next TODO.md
reject 'waiting on a landed dependency' '`waits-local` depends on `prerequisite` which is not in any queue' bash "$queues" --strict
cp local-todo.md TODO.md

# claim-check.sh against a fake forge
# A configured remote distinguishes hosted fixtures from remote-less mode.
git remote add fixture "$external/nonexistent-remote"
cat > bin/gh <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  'auth status'|'repo view') exit 0 ;;
  'api --paginate') echo 'API unavailable' >&2; exit 1 ;;
  *) exit 2 ;;
esac
GH
chmod +x bin/gh
reject 'hosted ownership query' 'ownership remains unverified' env PATH="$fixture/bin:$PATH" bash "$claim" fixture-unclaimed-task

cat > bin/gh <<'GH'
#!/usr/bin/env bash
# Search deliberately returns nothing: branch names and fresh body markers
# need direct, paginated pull records rather than a search-index match.
case "$1 $2" in
  'auth status'|'repo view') exit 0 ;;
  'pr list') exit 0 ;;
  'api --paginate')
    case "$*" in *--search*) exit 0 ;; esac
    case "$3" in
      *'state=open&per_page=100')
        case "$5" in *'note: open PR'*) exit 0 ;; esac
        case "$FIXTURE_PR_KIND" in
          branch) echo '  open PR #42 [draft] task/fixture-unclaimed-task: Unrelated title' ;;
          body) echo '  open PR #43 [draft] task/another-task: Fresh body claim' ;;
        esac ;;
      *'state=closed&per_page=100')
        case "$5" in *'.merged_at != null'*) ;; *) exit 2 ;; esac
        if [ "$FIXTURE_PR_KIND" = merged ]; then
          echo '  merged PR #44 (2026-10-06) resolved or carried this slug: Unrelated title'
        fi ;;
      *) exit 2 ;;
    esac ;;
  *) exit 2 ;;
esac
GH
reject 'branch-only remote claim' 'open PR #42' env PATH="$fixture/bin:$PATH" FIXTURE_PR_KIND=branch bash "$claim" fixture-unclaimed-task
reject 'fresh body remote claim' 'open PR #43' env PATH="$fixture/bin:$PATH" FIXTURE_PR_KIND=body bash "$claim" fixture-unclaimed-task
reject 'branch-only merged work' 'merged PR #44' env PATH="$fixture/bin:$PATH" FIXTURE_PR_KIND=merged bash "$claim" fixture-unclaimed-task
pass 'unclaimed hosted work' env PATH="$fixture/bin:$PATH" FIXTURE_PR_KIND=none bash "$claim" fixture-unclaimed-task
reject 'slug that is not kebab-case' 'not lowercase kebab-case' env PATH="$fixture/bin:$PATH" FIXTURE_PR_KIND=none bash "$claim" 'Fixture Task'

# Head-branch matching runs the real jq program over canned pull records: a
# head branch counts only when its last path component is the slug.
if command -v jq >/dev/null 2>&1; then
  cat > bin/gh <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  'auth status'|'repo view') exit 0 ;;
  'api --paginate')
    case "$3" in
      *'state=open&per_page=100')
        printf '%s' '[{"number":60,"draft":true,"title":"Longer name","body":"## Why\n\nText.","head":{"ref":"todo/fixture-unclaimed-task-v2","sha":"0","repo":{"full_name":"fixture/repo"}}},{"number":61,"draft":false,"title":"Prefixed name","body":"## Why\n\nText.","head":{"ref":"old-fixture-unclaimed-task","sha":"0","repo":{"full_name":"fixture/repo"}}}'"$FIXTURE_EXTRA_PR"']' | jq -r "$5" ;;
      *'state=closed&per_page=100') echo '[]' | jq -r "$5" ;;
      *) exit 2 ;;
    esac ;;
  *) exit 2 ;;
esac
GH
  pass 'head branch that merely contains the slug' env PATH="$fixture/bin:$PATH" FIXTURE_EXTRA_PR='' bash "$claim" fixture-unclaimed-task
  exact=',{"number":62,"draft":true,"title":"Exact name","body":"## Why\n\nText.","head":{"ref":"fix/fixture-unclaimed-task","sha":"0","repo":{"full_name":"fixture/repo"}}}'
  reject 'head branch whose last component is the slug' 'open PR #62 [draft] fix/fixture-unclaimed-task' env PATH="$fixture/bin:$PATH" FIXTURE_EXTRA_PR="$exact" bash "$claim" fixture-unclaimed-task
else
  echo 'scripts-test: note: jq not installed; head-branch matching checked only with canned output'
fi

# Claim recheck from inside the claimed worktree, created the way workers
# create it. --self ignores the local own branch and its worktree always, and
# a remote copy or open PR of that branch only when its tip is the worker's
# own pushed work; same-named claims from other workers are still reported.
# Branch matching is by whole path component: a longer branch name that merely
# contains the slug is not a claim.
mkdir -p "$fixture/nogh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fixture/nogh/gh"
chmod +x "$fixture/nogh/gh"
nogh="$fixture/nogh:$PATH"
in_dir() { d="$1"; shift; (cd "$d" && "$@"); }
wt="$fixture/.worktrees/todo-fixture-self-task"
pass 'start-work on a free slug' env PATH="$nogh" bash docket/scripts/start-work.sh todo fixture-self-task --base main
[ -d "$wt" ] || { echo 'scripts-test: start-work created no worktree' >&2; exit 1; }
reject 'start-work on a claimed slug' 'existing claim' env PATH="$nogh" bash docket/scripts/start-work.sh fix fixture-self-task --base main
# A --dir outside the repository cannot be ignored by it: start-work must leave
# the exclude file alone and print no .gitignore advice, however often it runs.
cp .git/info/exclude "$fixture/exclude.before"
for n in one two; do
  pass "start-work with an external --dir ($n)" env PATH="$nogh" bash docket/scripts/start-work.sh todo "fixture-external-$n" --base main --dir "$external"
  [ -d "$external/todo-fixture-external-$n" ] || { echo "scripts-test: start-work created no external worktree ($n)" >&2; exit 1; }
  grep -Fq '.gitignore' "$fixture/result.log" && { echo "scripts-test: start-work gave .gitignore advice for an external --dir ($n)" >&2; cat "$fixture/result.log" >&2; exit 1; }
done
cmp -s .git/info/exclude "$fixture/exclude.before" || { echo 'scripts-test: start-work changed the exclude file for an external --dir' >&2; diff "$fixture/exclude.before" .git/info/exclude >&2; exit 1; }
for n in one two; do
  git worktree remove --force "$external/todo-fixture-external-$n"
  git branch --quiet -D "todo/fixture-external-$n"
done
# Without a target file a relative --dir is still taken from the root, even
# when start-work runs from a subdirectory.
pass 'start-work from a subdirectory with a relative --dir' in_dir "$fixture/review" env PATH="$nogh" bash "$fixture/docket/scripts/start-work.sh" todo fixture-subdir --base main --dir .worktrees
[ -d "$fixture/.worktrees/todo-fixture-subdir" ] && [ ! -e "$fixture/review/.worktrees" ] || { echo 'scripts-test: a relative --dir without a target was not taken from the root' >&2; exit 1; }
git worktree remove --force "$fixture/.worktrees/todo-fixture-subdir"
git branch --quiet -D todo/fixture-subdir
git -C "$wt" commit --quiet --allow-empty -m 'Own fixture work'
own_sha="$(git -C "$wt" rev-parse HEAD)"
foreign_sha="$(git commit-tree -p main -m 'Another worker' "$(git rev-parse 'main^{tree}')")"
base_sha="$(git rev-parse main)"
git update-ref refs/remotes/origin/todo/fixture-self-task "$own_sha"
reject 'own claim without --self' 'branch: todo/fixture-self-task' in_dir "$wt" env PATH="$nogh" bash "$claim" fixture-self-task
pass 'own claim with --self' in_dir "$wt" env PATH="$nogh" bash "$claim" --self fixture-self-task
pass 'own claim excluded by name' env PATH="$nogh" bash "$claim" --exclude-branch todo/fixture-self-task fixture-self-task
git update-ref refs/remotes/origin/todo/fixture-self-task "$foreign_sha"
reject 'foreign remote commit with --self' 'branch: origin/todo/fixture-self-task' in_dir "$wt" env PATH="$nogh" bash "$claim" --self fixture-self-task
git update-ref refs/remotes/origin/todo/fixture-self-task "$base_sha"
reject 'remote at base with --self' 'branch: origin/todo/fixture-self-task' in_dir "$wt" env PATH="$nogh" bash "$claim" --self fixture-self-task
git update-ref refs/remotes/origin/todo/fixture-self-task "$own_sha"
git branch --quiet fix/fixture-self-task main
reject 'other branch with --self' 'branch: fix/fixture-self-task' in_dir "$wt" env PATH="$nogh" bash "$claim" --self fixture-self-task
git branch --quiet -D fix/fixture-self-task
git branch --quiet todo/fixture-self-task-v2 main
pass 'longer branch name is not a claim' in_dir "$wt" env PATH="$nogh" bash "$claim" --self fixture-self-task
git branch --quiet -D todo/fixture-self-task-v2
git worktree add --quiet -b review/fixture-self-task "$fixture/wt-other" main
reject 'other worktree with --self' '[review/fixture-self-task]' in_dir "$wt" env PATH="$nogh" bash "$claim" --self fixture-self-task
git worktree remove --force "$fixture/wt-other"
git branch --quiet -D review/fixture-self-task
mkdir -p "$fixture/elsewhere"
git worktree add --quiet --detach "$fixture/elsewhere/fixture-self-task" main
reject 'detached worktree named after the slug' 'elsewhere/fixture-self-task (detached)' in_dir "$wt" env PATH="$nogh" bash "$claim" --self fixture-self-task
git worktree remove --force "$fixture/elsewhere/fixture-self-task"
git -C "$wt" checkout --quiet --detach
reject 'detached --self' 'no branch is checked out' in_dir "$wt" env PATH="$nogh" bash "$claim" --self fixture-self-task
git -C "$wt" checkout --quiet todo/fixture-self-task
cat > bin/gh <<'GH'
#!/usr/bin/env bash
# Simulates the jq output for one open PR on the branch todo/fixture-self-task.
# FIXTURE_PR picks its source: own (this repository, the worker's pushed tip),
# fork (another repository) or foreign (this repository, another worker's tip).
case "$1 $2" in
  'auth status') exit 0 ;;
  'repo view') [ "${3:-}" = --json ] && echo 'fixture/repo'; exit 0 ;;
  'api --paginate')
    case "$3" in
      *'state=open&per_page=100')
        case "$5" in *'note: open PR'*) exit 0 ;; esac
        case "$FIXTURE_PR" in
          own) n=45; repo=fixture/repo; sha="$FIXTURE_OWN_SHA" ;;
          fork) n=77; repo=fork/repo; sha="$FIXTURE_OWN_SHA" ;;
          foreign) n=78; repo=fixture/repo; sha="$FIXTURE_FOREIGN_SHA" ;;
        esac
        text="  open PR #$n [draft] todo/fixture-self-task: Claims TODO: fixture-self-task"
        case "$5" in
          *'"own\t'*) printf 'own\t%s\t%s\t%s\n' "$sha" "$repo" "$text" ;;
          *) printf '%s\n' "$text" ;;
        esac ;;
      *'state=closed&per_page=100') exit 0 ;;
      *) exit 2 ;;
    esac ;;
  *) exit 2 ;;
esac
GH
ghpr() { kind="$1"; shift; env PATH="$fixture/bin:$PATH" FIXTURE_OWN_SHA="$own_sha" FIXTURE_FOREIGN_SHA="$foreign_sha" FIXTURE_PR="$kind" "$@"; }
reject 'own hosted PR without --self' 'open PR #45' in_dir "$wt" ghpr own bash "$claim" fixture-self-task
pass 'own hosted PR with --self' in_dir "$wt" ghpr own bash "$claim" --self fixture-self-task
reject 'fork PR with --self' 'open PR #77' in_dir "$wt" ghpr fork bash "$claim" --self fixture-self-task
reject 'foreign-tip PR with --self' 'open PR #78' in_dir "$wt" ghpr foreign bash "$claim" --self fixture-self-task
git worktree remove --force "$wt"
git branch --quiet -D todo/fixture-self-task
git update-ref -d refs/remotes/origin/todo/fixture-self-task

# review-due.sh. Index rows are dated today, so the 21-day trigger never
# fires on its own and these verdicts hold whenever the suite runs; the
# trigger itself is checked against a fixed date long past. The verdicts
# assume the default thresholds, whatever the caller has exported.
unset REVIEW_DUE_COMMITS REVIEW_DUE_DAYS REVIEW_FULL_FRACTION
today="$(date -u +%Y-%m-%d)"
head="$(git rev-parse HEAD)"
printf '| Date | Type | Commit |\n| %s | full | `%s` |\n' "$today" "$head" > review-index.md
pass 'zero review churn' bash "$due" --index review-index.md --base "$head"
expect 'zero review churn gave the wrong verdict' 'verdict: no review due'
printf '| Date | Type | Commit |\n| 2000-01-01 | full | `%s` |\n' "$head" > review-index.md
pass 'old review' bash "$due" --index review-index.md --base "$head"
expect 'old review did not trigger an incremental review' 'verdict: INCREMENTAL review due ('
expect 'old review did not report the day trigger' 'days >= 21)'
# Days count from local midnight of the review date on BSD date as on GNU
# date. A date one day ahead of the local one (a review recorded in a zone
# east of the reader) is less than a day away from midnight, so 0 days; BSD
# date used to take the time of day from the clock and report -1. UTC+10
# midnight is 10:00 UTC; near it the date the fixture writes and the one
# the script reads can differ, so the check stands aside there.
case "$(date -u +%H%M)" in 0959|1000) midnight_offsets='' ;; *) midnight_offsets="-1:1 +0:0 +1:0" ;; esac
for offset in $midnight_offsets; do
  d="$(TZ=UTC+10 date -v"${offset%%:*}"d +%Y-%m-%d 2>/dev/null || TZ=UTC+10 date -d "${offset%%:*} day" +%Y-%m-%d)"
  printf '| Date | Type | Commit |\n| %s | full | `%s` |\n' "$d" "$head" > review-index.md
  pass "review dated ${offset%%:*} day west of UTC" env TZ=UTC+10 bash "$due" --index review-index.md --base "$head"
  expect "review dated ${offset%%:*} day did not count from local midnight" ", ${offset#*:} days"
done

# A tracked source file deleted in the working tree must not abort the report.
mkdir -p src
printf 'one\ntwo\n' > src/kept.sh
printf 'three\n' > src/deleted.sh
git add src
git commit --quiet -m 'Add fixture sources'
head="$(git rev-parse HEAD)"
printf '| Date | Type | Commit |\n| %s | full | `%s` |\n' "$today" "$head" > review-index.md
rm src/deleted.sh
pass 'deleted tracked source' bash "$due" --index review-index.md --base "$head"
expect 'deleted tracked source gave the wrong verdict' 'verdict: no review due'
expect 'deleted tracked source was not reported' 'note: 1 tracked source file(s) are missing'
expect 'deleted tracked source miscounted lines' 'against 2 current source lines'
git checkout --quiet -- src/deleted.sh
pass 'paths with --paths' bash "$due" --index review-index.md --base "$head" --paths 'src docket'
# A binary asset under src/ (fonts, icons, archives) contributes no source lines.
printf 'PK\003\004\000\001\n\n\n\n\n\n\n\n\n\n' > src/asset.bin
git add src/asset.bin
git commit --quiet -m 'Add binary fixture asset'
head="$(git rev-parse HEAD)"
printf '| Date | Type | Commit |\n| %s | full | `%s` |\n' "$today" "$head" > review-index.md
pass 'binary asset in src' bash "$due" --index review-index.md --base "$head" --paths src
expect 'binary asset was not skipped' 'note: 1 binary file(s) skipped'
expect 'binary asset was counted as source lines' 'against 3 current source lines'
expect 'binary asset changed the verdict' 'verdict: no review due'

# check-links.sh: links and anchors resolve or fail, and untracked Markdown
# that is not ignored is checked too.
links="docket/scripts/check-links.sh"
mkdir -p docs
printf '# Good\n\n## Target heading\n\n[queue](../TODO.md) [self](#target-heading) [other](other.md#other-heading)\n' > docs/good.md
printf '# Other\n\n## Other heading\n' > docs/other.md
git add docs
git commit --quiet -m 'Add link fixtures'
pass 'good links and anchors' bash "$links" docs
printf '[gone](missing.md)\n' > docs/broken.md
reject 'broken link' 'docs/broken.md: broken link -> missing.md' bash "$links" docs/broken.md
rm docs/broken.md
printf '[nope](other.md#no-such-heading)\n' > docs/badanchor.md
reject 'broken anchor' 'docs/badanchor.md: broken anchor -> other.md#no-such-heading' bash "$links" docs/badanchor.md
rm docs/badanchor.md
printf '[gone](missing.md)\n' > docs/untracked.md
reject 'untracked markdown is checked' 'docs/untracked.md: broken link' bash "$links"
rm docs/untracked.md
printf '[gone](missing.md)\n' > docs/ignored.md
printf 'docs/ignored.md\n' >> .git/info/exclude
pass 'ignored markdown is not checked' bash "$links"
rm docs/ignored.md

# cleanup-landed.sh --apply against a fake forge that reports every branch in
# FIXTURE_MERGED as merged at its current tip.
cat > bin/gh <<'GH'
#!/usr/bin/env bash
case "$1 $2" in
  'auth status'|'repo view') exit 0 ;;
  'pr list')
    [ "$6" = merged ] || exit 0
    n=50
    for m in $FIXTURE_MERGED; do
      n=$((n + 1))
      [ "$m" = "$4" ] && echo "$n $(git rev-parse "$4")"
    done
    exit 0 ;;
  *) exit 2 ;;
esac
GH
cleanup="$fixture/docket/scripts/cleanup-landed.sh"
git worktree add --quiet -b landed-clean "$fixture/.worktrees/landed-clean" main
git -C "$fixture/.worktrees/landed-clean" commit --quiet --allow-empty -m 'Landed, clean worktree'
git worktree add --quiet -b landed-dirty "$fixture/.worktrees/landed-dirty" main
git -C "$fixture/.worktrees/landed-dirty" commit --quiet --allow-empty -m 'Landed, dirty worktree'
echo scratch > "$fixture/.worktrees/landed-dirty/scratch.txt"
git worktree add --quiet -b runner "$fixture/.worktrees/runner" main
git checkout --quiet -b landed-main
git commit --quiet --allow-empty -m 'Landed, checked out in the main worktree'
merged='landed-clean landed-dirty landed-main'
pass 'cleanup-landed dry run' in_dir "$fixture/.worktrees/runner" env PATH="$fixture/bin:$PATH" FIXTURE_MERGED="$merged" bash "$cleanup"
expect 'dry run did not plan the clean removal' 'remove worktree'
[ -d "$fixture/.worktrees/landed-clean" ] || { echo 'scripts-test: cleanup-landed dry run removed a worktree' >&2; exit 1; }
pass 'cleanup-landed --apply' in_dir "$fixture/.worktrees/runner" env PATH="$fixture/bin:$PATH" FIXTURE_MERGED="$merged" bash "$cleanup" --apply
expect 'dirty worktree was not reported as kept' 'has modified or untracked files'
expect 'main worktree branch was not reported as kept' 'checked out in the main worktree'
[ ! -d "$fixture/.worktrees/landed-clean" ] || { echo 'scripts-test: cleanup-landed kept the merged clean worktree' >&2; exit 1; }
git rev-parse --verify --quiet landed-clean >/dev/null && { echo 'scripts-test: cleanup-landed kept the merged clean branch' >&2; exit 1; }
[ -f "$fixture/.worktrees/landed-dirty/scratch.txt" ] || { echo 'scripts-test: cleanup-landed removed the dirty worktree' >&2; exit 1; }
git rev-parse --verify --quiet landed-dirty >/dev/null || { echo 'scripts-test: cleanup-landed deleted the dirty branch' >&2; exit 1; }
git rev-parse --verify --quiet landed-main >/dev/null || { echo 'scripts-test: cleanup-landed deleted the main worktree branch' >&2; exit 1; }
git checkout --quiet main
git worktree remove --force "$fixture/.worktrees/landed-dirty"
# Ignored files: known caches at any depth never hold a worktree back; any
# other ignored file does until --discard-ignored is passed.
printf 'node_modules/\n__pycache__/\n.pytest_cache/\n.docket/\n' >> "$fixture/.git/info/exclude"
git worktree add --quiet -b landed-caches "$fixture/.worktrees/landed-caches" main
git -C "$fixture/.worktrees/landed-caches" commit --quiet --allow-empty -m 'Landed, caches only'
mkdir -p "$fixture/.worktrees/landed-caches/node_modules/pkg" "$fixture/.worktrees/landed-caches/src/pkg/__pycache__" "$fixture/.worktrees/landed-caches/.pytest_cache/v"
echo x > "$fixture/.worktrees/landed-caches/node_modules/pkg/index.js"; echo x > "$fixture/.worktrees/landed-caches/src/pkg/__pycache__/a.pyc"; echo x > "$fixture/.worktrees/landed-caches/.pytest_cache/v/data"
git worktree add --quiet -b landed-record "$fixture/.worktrees/landed-record" main
git -C "$fixture/.worktrees/landed-record" commit --quiet --allow-empty -m 'Landed, holds a record'
mkdir -p "$fixture/.worktrees/landed-record/.docket" "$fixture/.worktrees/landed-record/node_modules"
echo body > "$fixture/.worktrees/landed-record/.docket/pr-landed-record.md"; echo x > "$fixture/.worktrees/landed-record/node_modules/x"
printf '*.log\n' >> "$fixture/.git/info/exclude"
git worktree add --quiet -b landed-log "$fixture/.worktrees/landed-log" main
git -C "$fixture/.worktrees/landed-log" commit --quiet --allow-empty -m 'Landed, holds a log'
mkdir -p "$fixture/.worktrees/landed-log/results"; echo run > "$fixture/.worktrees/landed-log/results/audit.log"
merged='landed-caches landed-record landed-log'
pass 'cleanup-landed dry run with caches and records' in_dir "$fixture/.worktrees/runner" env PATH="$fixture/bin:$PATH" FIXTURE_MERGED="$merged" bash "$cleanup"
expect 'dry run did not plan to remove the caches-only worktree' 'and branch landed-caches (merged'
expect 'dry run did not keep the record-holding worktree' 'keep landed-record'
expect 'dry run did not keep the log-holding worktree' 'keep landed-log'
[ -d "$fixture/.worktrees/landed-caches" ] || { echo 'scripts-test: cleanup-landed dry run removed the caches-only worktree' >&2; exit 1; }
pass 'cleanup-landed --apply with caches and a record' in_dir "$fixture/.worktrees/runner" env PATH="$fixture/bin:$PATH" FIXTURE_MERGED="$merged" bash "$cleanup" --apply
[ ! -d "$fixture/.worktrees/landed-caches" ] || { echo 'scripts-test: cleanup-landed kept a worktree holding only caches' >&2; exit 1; }
expect 'record-holding worktree was not reported as kept' 'not known caches and would be lost'
expect 'the record was not named' '.docket/'
grep -q 'node_modules' "$fixture/result.log" && grep 'node_modules' "$fixture/result.log" | grep -vq 'landed-caches' && { echo 'scripts-test: cleanup-landed listed a cache as a reason to keep' >&2; exit 1; }
[ -f "$fixture/.worktrees/landed-record/.docket/pr-landed-record.md" ] || { echo 'scripts-test: cleanup-landed removed the record-holding worktree' >&2; exit 1; }
[ -f "$fixture/.worktrees/landed-log/results/audit.log" ] || { echo 'scripts-test: cleanup-landed removed the log-holding worktree' >&2; exit 1; }
pass 'cleanup-landed --apply --discard-ignored' in_dir "$fixture/.worktrees/runner" env PATH="$fixture/bin:$PATH" FIXTURE_MERGED="$merged" bash "$cleanup" --apply --discard-ignored
[ ! -d "$fixture/.worktrees/landed-record" ] || { echo 'scripts-test: --discard-ignored kept the record-holding worktree' >&2; exit 1; }
[ ! -d "$fixture/.worktrees/landed-log" ] || { echo 'scripts-test: --discard-ignored kept the log-holding worktree' >&2; exit 1; }
git worktree remove --force "$fixture/.worktrees/runner"
git branch --quiet -D landed-dirty landed-main runner

# Remote-less lifecycle: even an installed gh and inherited GH_REPO must not
# cause any forge calls. Keep these fixtures isolated from hosted test state.
local_repo="$external/local-repo"
mkdir -p "$local_repo/bin" "$local_repo/docket/scripts"
cp "$scripts"/*.sh "$local_repo/docket/scripts/"
cd "$local_repo"
git init --quiet
git symbolic-ref HEAD refs/heads/main
git config user.name 'Local fixture'
git config user.email 'local-fixture@example.invalid'
git config core.hooksPath /dev/null
printf 'bin/\n.worktrees/\n.docket/\nignored.txt\n' > .gitignore
cat > TODO.md <<'QUEUE'
# TODO

## Ready for separate work

### P2 Normal

- [TOOLS] `local-task` **Complete local work.**
  - Source: local lifecycle fixture
QUEUE
git add .gitignore docket
git commit --quiet -m 'Initial local project'
# The stale remote lacks the queued task, so choosing it as the marker base
# incorrectly rejects its resolution.
git update-ref refs/remotes/origin/main "$(git rev-parse HEAD)"
git add TODO.md
git commit --quiet -m 'Queue local task'
local_base="$(git rev-parse HEAD)"
cat > bin/gh <<'GH'
#!/usr/bin/env bash
printf 'unexpected gh call\n' >> "$GH_CALL_LOG"
exit 90
GH
chmod +x bin/gh
export GH_REPO=wrong/repository GH_CALL_LOG="$local_repo/gh-calls"
local_env="$local_repo/bin:$PATH"
pass 'remote-less free claim' env PATH="$local_env" bash docket/scripts/claim-check.sh fresh-local
pass 'remote-less start' env PATH="$local_env" bash docket/scripts/start-work.sh todo local-task
expect 'local start did not describe local review' '.docket/change-local-task.md'
local_wt="$local_repo/.worktrees/todo-local-task"
[ "$(git rev-parse todo/local-task)" = "$local_base" ] || { echo 'scripts-test: remote-less task used stale origin base' >&2; exit 1; }
[ -z "$(git for-each-ref --format='%(upstream)' refs/heads/todo/local-task)" ] || { echo 'scripts-test: task unexpectedly tracks main' >&2; exit 1; }
printf '# TODO\n' > "$local_wt/TODO.md"
printf 'approved content\n' > "$local_wt/result.txt"
git -C "$local_wt" add TODO.md result.txt
git -C "$local_wt" commit --quiet -m 'Complete local task'
local_head="$(git -C "$local_wt" rev-parse HEAD)"
mkdir -p .docket "$local_wt/.docket"
cat > .docket/change.md <<'BODY'
## Why

Local work must land without a forge.

## What changed

Complete the queued local task.

Type: feature
Resolves TODO: local-task

## Validation

Exercise the isolated local lifecycle fixture.
BODY
cp .docket/change.md "$local_wt/.docket/change-local-task.md"
local_land="$local_repo/docket/scripts/land-local.sh"
local_cleanup="$local_repo/docket/scripts/cleanup-landed.sh"
# Simulate tracking metadata that must survive safe atomic branch deletion.
git config branch.todo/local-task.remote .
git config branch.todo/local-task.merge refs/heads/main
git config branch.todo/local-task.description 'Preserve this branch note'
reject 'approval is required' 'Usage:' bash "$local_land" todo/local-task --title 'Land local task' --body .docket/change.md
reject 'ref is not approval' 'full current task' bash "$local_land" todo/local-task --title 'Land local task' --body .docket/change.md --approved-head todo/local-task
reject 'abbreviated approval' 'full current task' bash "$local_land" todo/local-task --title 'Land local task' --body .docket/change.md --approved-head "${local_head:0:10}"
reject 'multiline title' 'one nonempty line' bash "$local_land" todo/local-task --title $'Bad\nTitle' --body .docket/change.md --approved-head "$local_head"
printf 'dirty\n' > result.txt
reject 'dirty base refuses landing' 'modified or untracked' bash "$local_land" todo/local-task --title 'Land local task' --body .docket/change.md --approved-head "$local_head"
rm result.txt
printf 'dirty\n' >> "$local_wt/result.txt"
reject 'dirty task refuses landing' 'modified or untracked' bash "$local_land" todo/local-task --title 'Land local task' --body .docket/change.md --approved-head "$local_head"
git -C "$local_wt" restore result.txt
printf '%s\n' "$local_head" > .git/MERGE_HEAD
reject 'in-progress base refuses landing' 'in-progress Git operation' bash "$local_land" todo/local-task --title 'Land local task' --body .docket/change.md --approved-head "$local_head"
rm .git/MERGE_HEAD
printf '%s\n' "$local_base" > "$(git -C "$local_wt" rev-parse --git-path CHERRY_PICK_HEAD)"
reject 'in-progress task refuses landing' 'in-progress Git operation' bash "$local_land" todo/local-task --title 'Land local task' --body .docket/change.md --approved-head "$local_head"
rm "$(git -C "$local_wt" rev-parse --git-path CHERRY_PICK_HEAD)"
git commit --quiet --allow-empty -m 'Base advanced'
reject 'advanced base refuses stale task' 'rebase onto main' bash "$local_land" todo/local-task --title 'Land local task' --body .docket/change.md --approved-head "$local_head"
git -C "$local_wt" rebase --quiet main
local_head="$(git -C "$local_wt" rev-parse HEAD)"
local_base="$(git rev-parse main)"
# Default marker base must be current local main, even with a stale origin ref.
pass 'remote-less markers' in_dir "$local_wt" env PATH="$local_env" bash docket/scripts/check-pr-markers.sh --body .docket/change-local-task.md --strict
# Explicit local mode also works with a non-PR remote, without queries/fetches.
git remote add archive "$external/unavailable-archive"
pass 'explicit local claim' env PATH="$local_env" bash docket/scripts/claim-check.sh --local fresh-local
pass 'explicit local start' env PATH="$local_env" bash docket/scripts/start-work.sh task local-second --local
[ "$(git rev-parse task/local-second)" = "$local_base" ] || { echo 'scripts-test: explicit local mode used stale remote base' >&2; exit 1; }
git worktree remove "$local_repo/.worktrees/task-local-second"
git branch --quiet -D task/local-second
git remote remove archive
git init --bare --quiet "$external/local-origin.git"
git remote add origin "$external/local-origin.git"
git push --quiet origin main
pass 'hosted base does not become task upstream' bash docket/scripts/start-work.sh task hosted-upstream --no-check
[ -z "$(git for-each-ref --format='%(upstream)' refs/heads/task/hosted-upstream)" ] || { echo 'scripts-test: task tracks origin/main' >&2; exit 1; }
git worktree remove "$local_repo/.worktrees/task-hosted-upstream"
git branch --quiet -D task/hosted-upstream
git remote remove origin
# Keep a stale remote ref after removal, as an incomplete migration may do.
git update-ref refs/remotes/origin/main "$local_base"
# Run from a subdirectory, with an absolute helper path.
pass 'approved local squash' in_dir "$local_repo/docket" env PATH="$local_env" bash "$local_land" todo/local-task --title 'Land local task' --body ../.docket/change.md --approved-head "$local_head"
local_landed="$(git rev-parse main)"
[ "$(git show -s --format=%P "$local_landed")" = "$local_base" ] || { echo 'scripts-test: local landing created a merge commit or wrong parent' >&2; exit 1; }
[ "$(git rev-parse 'main^{tree}')" = "$(git rev-parse 'todo/local-task^{tree}')" ] || { echo 'scripts-test: local landing lost task content' >&2; exit 1; }
printf 'Land local task\n\n' > .docket/expected-message
cat .docket/change.md >> .docket/expected-message
git cat-file commit main | sed '1,/^$/d' > .docket/actual-message
cmp .docket/expected-message .docket/actual-message
[ -d "$local_wt" ] || { echo 'scripts-test: landing removed review worktree early' >&2; exit 1; }
pass 'local cleanup retains ignored evidence' env PATH="$local_env" bash "$local_cleanup" --apply
expect 'local evidence was not retained' 'not known caches and would be lost'
[ -f "$local_wt/.docket/change-local-task.md" ] || exit 1
mv "$local_wt/.docket/change-local-task.md" .docket/reviewed-change.md
rmdir "$local_wt/.docket"
pass 'local cleanup dry run' env PATH="$local_env" bash "$local_cleanup"
expect 'local receipt was not recognized' 'locally squash-landed'
[ -d "$local_wt" ] || { echo 'scripts-test: cleanup dry run removed local worktree' >&2; exit 1; }
printf '%s\n' "$local_base" > "$(git -C "$local_wt" rev-parse --git-path MERGE_HEAD)"
pass 'local cleanup retains in-progress operation' env PATH="$local_env" bash "$local_cleanup" --apply
expect 'active operation was not retained' 'in-progress Git operation'
[ -d "$local_wt" ] || exit 1
rm "$(git -C "$local_wt" rev-parse --git-path MERGE_HEAD)"
git worktree lock "$local_wt"
pass 'local cleanup retains locked worktree' env PATH="$local_env" bash "$local_cleanup" --apply
expect 'locked worktree was not retained' 'worktree removal failed'
[ -d "$local_wt" ] || exit 1
git worktree unlock "$local_wt"
# A later commit invalidates exact-tip proof even if empty.
git -C "$local_wt" commit --quiet --allow-empty -m 'Unlanded later work'
pass 'local cleanup retains later commits' env PATH="$local_env" bash "$local_cleanup" --apply
expect 'later local work was not retained' 'does not verify this tip'
[ -d "$local_wt" ] || exit 1
git -C "$local_wt" reset --quiet --hard "$local_head"
# A status failure must preserve the worktree, not be interpreted as clean.
real_git="$(command -v git)"
cat > bin/git <<'GIT'
#!/usr/bin/env bash
case "$*" in *'status --porcelain --ignored=matching'*) exit 91 ;; esac
exec "$REAL_GIT" "$@"
GIT
chmod +x bin/git
pass 'local cleanup retains uninspectable worktree' env PATH="$local_env" REAL_GIT="$real_git" bash "$local_cleanup" --apply
expect 'status failure was not retained' 'cannot inspect worktree'
[ -d "$local_wt" ] || exit 1
rm bin/git
# Advance the ref exactly at deletion, after cleanup's earlier tip check.
# Atomic expected-old-value deletion must retain the newly committed work.
race_head="$(git commit-tree -p "$local_head" -m 'Concurrent local work' "$(git rev-parse "$local_head^{tree}")")"
cat > bin/git <<'GIT'
#!/usr/bin/env bash
case "$*" in
  'update-ref --no-deref -d refs/heads/todo/local-task '*|'update-ref -d refs/heads/todo/local-task '*|'branch -D todo/local-task')
    "$REAL_GIT" update-ref refs/heads/todo/local-task "$RACE_HEAD" "$RACE_OLD" || exit 92 ;;
esac
exec "$REAL_GIT" "$@"
GIT
chmod +x bin/git
pass 'cleanup retains concurrent tip at deletion' env PATH="$local_env" REAL_GIT="$real_git" RACE_HEAD="$race_head" RACE_OLD="$local_head" bash "$local_cleanup" --apply
[ "$(git rev-parse refs/heads/todo/local-task)" = "$race_head" ] || { echo 'scripts-test: cleanup deleted concurrent work' >&2; exit 1; }
expect 'concurrent branch advance was not reported' 'branch moved during cleanup'
rm bin/git
git update-ref refs/heads/todo/local-task "$local_head" "$race_head"
pass 'local cleanup apply' env PATH="$local_env" bash "$local_cleanup" --apply
[ ! -d "$local_wt" ] || { echo 'scripts-test: local cleanup kept landed clean worktree' >&2; exit 1; }
! git show-ref --verify --quiet refs/heads/todo/local-task || { echo 'scripts-test: local cleanup kept landed branch' >&2; exit 1; }
# Atomic ref deletion must not follow a symbolic branch alias into main.
git symbolic-ref refs/heads/local-main-alias refs/heads/main
pass 'cleanup does not dereference a main alias' env PATH="$local_env" bash "$local_cleanup" --apply --empty
[ "$(git rev-parse refs/heads/main)" = "$local_landed" ] || { echo 'scripts-test: cleanup deleted main through an alias' >&2; exit 1; }
! git symbolic-ref --quiet refs/heads/local-main-alias >/dev/null || { echo 'scripts-test: empty alias was not removed' >&2; exit 1; }
reject 'local completion remains claimed after cleanup' 'locally landed todo/local-task' env PATH="$local_env" bash docket/scripts/claim-check.sh local-task
expect 'main resolution marker was not recognized' 'local main records resolution of local-task'
# Garbage collection must preserve approved-head proof, not just its text SHA.
git gc --prune=now --quiet
reject 'local completion survives garbage collection' 'locally landed todo/local-task' env PATH="$local_env" bash docket/scripts/claim-check.sh local-task
[ "$(git config branch.todo/local-task.description)" = 'Preserve this branch note' ] || { echo 'scripts-test: cleanup erased branch metadata' >&2; exit 1; }
pass 'recreated task drops retained tracking' env PATH="$local_env" bash docket/scripts/start-work.sh todo local-task --no-check
[ -z "$(git for-each-ref --format='%(upstream)' refs/heads/todo/local-task)" ] || { echo 'scripts-test: recreated task inherited old upstream' >&2; exit 1; }
! git config --get branch.todo/local-task.remote >/dev/null || { echo 'scripts-test: recreated task retained old remote' >&2; exit 1; }
[ "$(git config branch.todo/local-task.description)" = 'Preserve this branch note' ] || { echo 'scripts-test: start-work erased unrelated branch metadata' >&2; exit 1; }
git worktree remove "$local_repo/.worktrees/todo-local-task"
git branch --quiet -D todo/local-task
# Partially retained tracking configuration is cleared too; Git's
# --unset-upstream refuses a merge key without a remote key.
git config branch.task/partial-tracking.merge refs/heads/main
pass 'new task clears partial tracking metadata' env PATH="$local_env" bash docket/scripts/start-work.sh task partial-tracking --no-check
! git config --get branch.task/partial-tracking.merge >/dev/null || { echo 'scripts-test: partial tracking metadata survived creation' >&2; exit 1; }
git worktree remove "$local_repo/.worktrees/task-partial-tracking"
git branch --quiet -D task/partial-tracking
git commit --quiet --allow-empty -m 'Record fixture finding completion' -m 'Resolves review finding: mapped-local-finding'
local_landed="$(git rev-parse main)"
reject 'mapped finding completion on local main' 'local main records resolution of mapped-local-finding' env PATH="$local_env" bash docket/scripts/claim-check.sh mapped-local-finding
pass 'marker slug prefix is not a completion' env PATH="$local_env" bash docket/scripts/claim-check.sh mapped-local
# Ignored files in the base must not be overwritten by a task's tracked file.
pass 'start ignored collision task' env PATH="$local_env" bash docket/scripts/start-work.sh task ignored-collision
collision_wt="$local_repo/.worktrees/task-ignored-collision"
[ "$(git rev-parse task/ignored-collision)" = "$local_landed" ] || { echo 'scripts-test: remote-less start used stale origin base' >&2; exit 1; }
printf 'task version\n' > "$collision_wt/ignored.txt"
git -C "$collision_wt" add -f ignored.txt
git -C "$collision_wt" commit --quiet -m 'Track collision file'
printf 'local record\n' > ignored.txt
sed '/^Resolves TODO:/d' .docket/change.md > .docket/collision.md
collision_head="$(git -C "$collision_wt" rev-parse HEAD)"
reject 'ignored collision preserves base evidence' 'squash failed' bash "$local_land" task/ignored-collision --title 'Track file' --body .docket/collision.md --approved-head "$collision_head"
grep -qx 'local record' ignored.txt || { echo 'scripts-test: squash overwrote ignored evidence' >&2; exit 1; }
[ "$(git rev-parse main)" = "$local_landed" ] || { echo 'scripts-test: failed squash moved main' >&2; exit 1; }
[ ! -e "$GH_CALL_LOG" ] || { echo 'scripts-test: remote-less mode called gh' >&2; cat "$GH_CALL_LOG" >&2; exit 1; }
# First installation: main has no Docket helper yet. Invoke the installed
# helper in the task worktree while the clean main checkout is the caller.
bootstrap="$external/bootstrap"
mkdir -p "$bootstrap"
cd "$bootstrap"
git init --quiet
git symbolic-ref HEAD refs/heads/main
git config user.name 'Bootstrap fixture'
git config user.email 'bootstrap-fixture@example.invalid'
git config core.hooksPath /dev/null
printf '.worktrees/\n.docket/\n' > .gitignore
git add .gitignore
git commit --quiet -m 'Initial repository without Docket'
bootstrap_base="$(git rev-parse HEAD)"
git worktree add --quiet -b task/bootstrap .worktrees/task-bootstrap main
mkdir -p .worktrees/task-bootstrap/docket/scripts .docket
cp "$scripts"/*.sh .worktrees/task-bootstrap/docket/scripts/
git -C .worktrees/task-bootstrap add docket
git -C .worktrees/task-bootstrap commit --quiet -m 'Install Docket helpers'
cp "$local_repo/.docket/collision.md" .docket/change.md
pass 'bootstrap landing with helper only on task branch' bash "$bootstrap/.worktrees/task-bootstrap/docket/scripts/land-local.sh" task/bootstrap --title 'Install Docket' --body .docket/change.md --approved-head "$(git rev-parse task/bootstrap)"
[ "$(git show -s --format=%P main)" = "$bootstrap_base" ] && [ -f docket/scripts/land-local.sh ] || { echo 'scripts-test: first installation did not squash-land' >&2; exit 1; }
unset GH_REPO GH_CALL_LOG
cd "$fixture"

# ---- pr-health.sh -------------------------------------------------------
# A separate fake gh (its own bin directory) serves canned pull request JSON
# and runs the script's real jq program over it, so this needs jq; it logs
# every call with the GH_REPO it saw. PRs: 11 passing and clean, 12 failing
# and behind with a landing comment, 13 pending, draft and conflicting, 14 no
# checks, 15 merged, 16 changes requested, 17 failing commit statuses and a
# cancelled run with review backlog markers and two landing comments, 18
# dirty with mergeability unknown, 19 conflicting but blocked (not dirty)
# with only a stale check outstanding.
if command -v jq >/dev/null 2>&1; then
  prh_repo="$external/pr-health"
  prh_data="$external/pr-health-data"
  mkdir -p "$prh_repo" "$prh_data/bin"
  cat > "$prh_data/bin/gh" <<'GH'
#!/usr/bin/env bash
printf 'GH_REPO=%s %s\n' "${GH_REPO-unset}" "$(printf '%s' "$*" | tr '\n' ' ')" >> "$PRH_LOG"
prog=""; prev=""
for a in "$@"; do [ "$prev" = --jq ] && prog="$a"; prev="$a"; done
case "$1" in
  pr)
    case "$2" in
      list) printf '%s' "$PRH_LIST" | jq -r "$prog" ;;
      view) [ -f "$PRH_DATA/pr-$3.json" ] || exit 1; jq -r "$prog" "$PRH_DATA/pr-$3.json" ;;
      *) exit 2 ;;
    esac ;;
  api)
    case "$2" in
      repos/*/compare/*) f="$PRH_DATA/behind-${2##*...}"; [ -f "$f" ] || exit 1; cat "$f" ;;
      *) exit 2 ;;
    esac ;;
  *) exit 2 ;;
esac
GH
  chmod +x "$prh_data/bin/gh"
  prh_pr() {
    # prh_pr N STATE DRAFT HEAD REVIEW MERGEABLE MERGESTATE CHECKS COMMENTS BODY
    printf '{"number":%s,"state":"%s","isDraft":%s,"headRefName":"%s","baseRefName":"main","headRefOid":"sha%s","reviewDecision":"%s","mergeable":"%s","mergeStateStatus":"%s","title":"Fixture PR %s","statusCheckRollup":%s,"comments":%s,"body":"%s"}\n' \
      "$1" "$2" "$3" "$4" "$1" "$5" "$6" "$7" "$1" "$8" "$9" "${10}" > "$prh_data/pr-$1.json"
  }
  ok_run='{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}'
  ok_status='{"__typename":"StatusContext","context":"ci/legacy","state":"SUCCESS"}'
  prh_pr 11 OPEN false todo/present-task APPROVED MERGEABLE CLEAN "[$ok_run,$ok_status]" '[]' '## Why\n\nText.\n\nClaims TODO: present-task\nType: feature'
  prh_pr 12 OPEN false task/failing APPROVED MERGEABLE BEHIND \
    "[$ok_run,{\"__typename\":\"CheckRun\",\"name\":\"lint\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\"}]" \
    '[{"body":"please /merge after review","createdAt":"2026-10-30T09:00:00Z"},{"body":"  /merge\n","createdAt":"2026-10-30T10:00:00Z"}]' \
    '## Why\r\n\r\nText.\r\n\r\nResolves TODO: gone-task\r\nFiles TODO: new-task\r\n'
  prh_pr 13 OPEN true todo/conflicted REVIEW_REQUIRED CONFLICTING DIRTY \
    "[{\"__typename\":\"CheckRun\",\"name\":\"build\",\"status\":\"IN_PROGRESS\",\"conclusion\":\"\"},{\"__typename\":\"StatusContext\",\"context\":\"ci/legacy\",\"state\":\"PENDING\"}]" \
    '[{"body":"please /merge","createdAt":"2026-10-30T11:00:00Z"}]' '## Why\n\nText.'
  prh_pr 14 OPEN false task/unchecked '' MERGEABLE CLEAN '[]' '[]' ''
  prh_pr 15 MERGED false task/merged APPROVED UNKNOWN UNKNOWN "[$ok_run]" '[]' 'Resolves TODO: gone-task'
  prh_pr 16 OPEN false task/rejected CHANGES_REQUESTED MERGEABLE BLOCKED "[$ok_run]" '[]' ''
  printf '0\n' > "$prh_data/behind-sha11"
  printf '3\n' > "$prh_data/behind-sha12"
  printf '0\n' > "$prh_data/behind-sha14"
  for n in 16 17 18 19; do printf '0\n' > "$prh_data/behind-sha$n"; done
  prh_pr 17 OPEN false review/status-checks APPROVED MERGEABLE CLEAN \
    "[$ok_run,{\"__typename\":\"StatusContext\",\"context\":\"ci/status-fail\",\"state\":\"FAILURE\"},{\"__typename\":\"StatusContext\",\"context\":\"ci/status-error\",\"state\":\"ERROR\"},{\"__typename\":\"CheckRun\",\"name\":\"deploy\",\"status\":\"COMPLETED\",\"conclusion\":\"CANCELLED\"}]" \
    '[{"body":"/merge","createdAt":"2026-10-31T10:00:00Z"},{"body":"/merge please","createdAt":"2026-10-31T11:00:00Z"},{"body":"/merge","createdAt":"2026-10-31T12:00:00Z"}]' \
    '## Why\n\nText.\n\nResolves review backlog: gone-entry\nClaims review backlog: kept-entry\nPartially resolves TODO: missing-partial\nRemaining TODO: missing-remainder'
  prh_pr 18 OPEN false task/dirty '' UNKNOWN DIRTY "[$ok_run]" '[]' ''
  prh_pr 19 OPEN false task/conflicting '' CONFLICTING BLOCKED \
    "[$ok_run,{\"__typename\":\"CheckRun\",\"name\":\"superseded\",\"status\":\"COMPLETED\",\"conclusion\":\"STALE\"}]" '[]' ''
  cd "$prh_repo"
  git init --quiet
  printf '# TODO\n\n## Ready for separate work\n\n### P2 Normal\n\n- [CORE] `present-task` **Still queued.**\n  - Source: scripts regression fixture\n' > TODO.md
  # gone-entry is a TODO slug but not a backlog one, so a backlog marker
  # checked against the wrong queue file would pass silently.
  printf -- '- [CORE] `gone-entry` **A TODO entry, not a backlog one.**\n  - Source: scripts regression fixture\n' >> TODO.md
  mkdir -p review
  printf '# Review backlog\n\n## P2 Normal\n\n- [CORE] `kept-entry` **Still in the backlog.**\n  - Source: scripts regression fixture\n' > review/BACKLOG.md
  prh="$fixture/docket/scripts/pr-health.sh"
  prh_log="$prh_data/gh.log"
  prh_env() { : > "$prh_log"; env PATH="$prh_data/bin:$PATH" PRH_LOG="$prh_log" PRH_DATA="$prh_data" PRH_LIST="${PRH_LIST:-[]}" GH_REPO=wrong/repository "$@"; }

  # Default selection: the current user's open PRs, in this repository only.
  PRH_LIST='[{"number":11},{"number":14}]'
  pass 'pr-health default selection' prh_env bash "$prh"
  expect 'pr-health missed the passing PR' '#11 todo/present-task [ready] Fixture PR 11'
  expect 'pr-health passing rollup' 'checks: passing (2)'
  expect 'pr-health approved review' 'review: approved'
  expect 'pr-health clean merge state' 'merge: clean; up to date with main'
  expect 'pr-health queue marker' 'queue: Claims TODO: present-task'
  expect 'pr-health no-checks rollup' 'checks: none'
  expect 'pr-health empty review decision' 'review: none'
  expect 'pr-health summary' 'summary: 2 PR(s) in this repository; 0 need attention'
  ! grep -q 'warning:' "$fixture/result.log" || { echo 'scripts-test: pr-health warned about a queued slug' >&2; cat "$fixture/result.log" >&2; exit 1; }
  grep -q '^GH_REPO=unset pr list --author @me --state open ' "$prh_log" || { echo 'scripts-test: pr-health did not list the open PRs authored by @me' >&2; cat "$prh_log" >&2; exit 1; }
  ! grep -v '^GH_REPO=unset ' "$prh_log" | grep -q . || { echo 'scripts-test: pr-health let an inherited GH_REPO through' >&2; cat "$prh_log" >&2; exit 1; }
  ! grep -q -- '--repo' "$prh_log" || { echo 'scripts-test: pr-health passed --repo unasked' >&2; cat "$prh_log" >&2; exit 1; }
  grep -q 'api repos/{owner}/{repo}/compare/main...sha11 ' "$prh_log" || { echo 'scripts-test: pr-health compared against the wrong repository' >&2; cat "$prh_log" >&2; exit 1; }
  PRH_LIST='[]'
  pass 'pr-health with no open PRs' prh_env bash "$prh"
  expect 'pr-health with no open PRs' 'no open PRs authored by you in this repository'

  # Failing, pending, behind, conflicting, landing requested, queue mismatch.
  pass 'pr-health named PRs' prh_env bash "$prh" --pr 12 --pr 13 --land-comment /merge
  expect 'pr-health failing rollup' 'checks: failing (lint)'
  expect 'pr-health behind state' 'merge: behind; behind main by 3 commit(s)'
  expect 'pr-health landing comment' 'landing: requested 2026-10-30T10:00:00Z, still open with failing checks; the merge attempt failed or expired'
  expect 'pr-health missing queue entry' 'warning: Resolves TODO: gone-task, but TODO.md here has no entry `gone-task`'
  expect 'pr-health draft PR' '#13 todo/conflicted [draft] Fixture PR 13'
  expect 'pr-health pending rollup' 'checks: pending (2 of 2)'
  expect 'pr-health review required' 'review: review required'
  expect 'pr-health dirty state' 'merge: dirty, conflicting; behind base: unknown'
  expect 'pr-health attention count' '2 need attention (failing checks, changes requested or conflicts); 1 queue warning(s)'
  [ "$(grep -c 'landing:' "$fixture/result.log")" = 1 ] || { echo 'scripts-test: pr-health matched a comment that only mentions the land command' >&2; cat "$fixture/result.log" >&2; exit 1; }
  ! grep -q 'warning: Files TODO' "$fixture/result.log" || { echo 'scripts-test: pr-health warned about a Files marker' >&2; cat "$fixture/result.log" >&2; exit 1; }
  pass 'pr-health without --land-comment' prh_env bash "$prh" --pr 12
  ! grep -q 'landing:' "$fixture/result.log" || { echo 'scripts-test: pr-health reported landing without --land-comment' >&2; exit 1; }
  pass 'pr-health merged PR' prh_env bash "$prh" --pr 15
  expect 'pr-health merged PR' '#15 task/merged [merged] Fixture PR 15'
  ! grep -q 'warning:' "$fixture/result.log" || { echo 'scripts-test: pr-health cross-checked a merged PR' >&2; exit 1; }

  # --strict: each of failing checks, conflicts and changes requested fails it.
  pass 'pr-health --strict on healthy PRs' prh_env bash "$prh" --strict --pr 11 --pr 14
  reject 'pr-health --strict on failing checks' '1 need attention' prh_env bash "$prh" --strict --pr 12
  reject 'pr-health --strict on conflicts' '1 need attention' prh_env bash "$prh" --strict --pr 13
  reject 'pr-health --strict on changes requested' 'review: changes requested' prh_env bash "$prh" --strict --pr 16
  pass 'pr-health without --strict on changes requested' prh_env bash "$prh" --pr 16

  # Commit statuses that failed or errored and a cancelled run all fail; a
  # stale run is pending. Review backlog markers are checked against
  # review/BACKLOG.md, Partially resolves TODO against TODO.md, and the
  # latest exact landing comment wins.
  pass 'pr-health statuses, backlog markers and repeated landing' prh_env bash "$prh" --pr 17 --land-comment '  /merge '
  expect 'pr-health status and cancelled failures' 'checks: failing (ci/status-fail, ci/status-error, deploy)'
  expect 'pr-health latest landing comment' 'landing: requested 2026-10-31T12:00:00Z, still open with failing checks'
  expect 'pr-health missing backlog entry' 'warning: Resolves review backlog: gone-entry, but review/BACKLOG.md here has no entry `gone-entry`'
  expect 'pr-health missing partial entry' 'warning: Partially resolves TODO: missing-partial, but TODO.md here has no entry `missing-partial`'
  expect 'pr-health backlog warning count' '2 queue warning(s)'
  ! grep -q 'warning: Claims review backlog: kept-entry' "$fixture/result.log" || { echo 'scripts-test: pr-health checked a backlog marker against the wrong file' >&2; exit 1; }
  ! grep -q 'warning: Remaining TODO' "$fixture/result.log" || { echo 'scripts-test: pr-health warned about a Remaining marker' >&2; exit 1; }
  reject 'pr-health --strict on failing statuses' '1 need attention' prh_env bash "$prh" --strict --pr 17
  pass 'pr-health dirty with unknown mergeability' prh_env bash "$prh" --pr 18
  expect 'pr-health dirty alone' 'merge: dirty, conflicting; up to date with main'
  reject 'pr-health --strict on dirty alone' '1 need attention' prh_env bash "$prh" --strict --pr 18
  pass 'pr-health conflicting but blocked' prh_env bash "$prh" --pr 19
  expect 'pr-health conflicting alone' 'merge: blocked, conflicting; up to date with main'
  expect 'pr-health stale check is pending' 'checks: pending (1 of 2)'
  reject 'pr-health --strict on conflicting alone' '1 need attention' prh_env bash "$prh" --strict --pr 19

  # --repo is passed to every gh call, including the compare path.
  pass 'pr-health --repo' prh_env bash "$prh" --repo owner/managed --pr 11
  grep -q ' pr view 11 --json .* --repo owner/managed$' "$prh_log" || { echo 'scripts-test: pr-health did not pass --repo to pr view' >&2; cat "$prh_log" >&2; exit 1; }
  grep -q ' api repos/owner/managed/compare/main...sha11 ' "$prh_log" || { echo 'scripts-test: pr-health did not compare in the named repository' >&2; cat "$prh_log" >&2; exit 1; }
  expect 'pr-health --repo summary' 'summary: 1 PR(s) in owner/managed'
  PRH_LIST='[{"number":11}]'
  pass 'pr-health --repo default selection' prh_env bash "$prh" --repo owner/managed
  grep -q ' pr list --author @me --state open .* --repo owner/managed$' "$prh_log" || { echo 'scripts-test: pr-health did not pass --repo to pr list' >&2; cat "$prh_log" >&2; exit 1; }

  # Usage errors and failed queries exit 2.
  set +e
  prh_env bash "$prh" --pr abc > "$fixture/result.log" 2>&1; rc=$?
  [ "$rc" = 2 ] && grep -q 'takes a PR number' "$fixture/result.log" || { echo "scripts-test: pr-health accepted a bad --pr ($rc)" >&2; exit 1; }
  prh_env bash "$prh" --repo 'not a repo' > "$fixture/result.log" 2>&1; rc=$?
  [ "$rc" = 2 ] || { echo "scripts-test: pr-health accepted a bad --repo ($rc)" >&2; exit 1; }
  prh_env bash "$prh" --pr '' > "$fixture/result.log" 2>&1; rc=$?
  [ "$rc" = 2 ] && grep -q 'needs a PR number' "$fixture/result.log" || { echo "scripts-test: pr-health accepted an empty --pr ($rc)" >&2; exit 1; }
  prh_env bash "$prh" --pr ' ' > "$fixture/result.log" 2>&1; rc=$?
  [ "$rc" = 2 ] && grep -q 'takes a PR number' "$fixture/result.log" || { echo "scripts-test: pr-health accepted a whitespace --pr ($rc)" >&2; exit 1; }
  prh_env bash "$prh" --pr 11 --land-comment '  ' > "$fixture/result.log" 2>&1; rc=$?
  [ "$rc" = 2 ] && grep -q 'needs non-empty text' "$fixture/result.log" || { echo "scripts-test: pr-health accepted an empty --land-comment ($rc)" >&2; exit 1; }
  prh_env bash "$prh" --pr 99 > "$fixture/result.log" 2>&1; rc=$?
  [ "$rc" = 2 ] && grep -q 'gh query failed (reading PR #99' "$fixture/result.log" || { echo "scripts-test: pr-health hid a failed query ($rc)" >&2; cat "$fixture/result.log" >&2; exit 1; }
  set -e
  pass 'pr-health --help' bash "$prh" --help
  expect 'pr-health --help' 'Usage: docket/scripts/pr-health.sh'
  unset PRH_LIST
  cd "$fixture"
else
  echo 'scripts-test: note: jq not installed; pr-health.sh fixtures skipped'
fi
# ---- end pr-health.sh ---------------------------------------------------
# ==== Managed-repository target (target.sh) ================================
# A sidecar repository holds docket and the queues; branches, worktrees and
# PRs belong to a separate managed clone with a bare "remote". The fake gh
# fails any call that does not name the target, by --repo and by GH_REPO.
tgt="$external/target"
mkdir -p "$tgt/bin"
git init --quiet --bare "$tgt/remote.git"
git -C "$tgt/remote.git" symbolic-ref HEAD refs/heads/main
tgt_git() { git -c user.name='Target fixture' -c user.email='target-fixture@example.invalid' -c core.hooksPath=/dev/null "$@"; }
tgt_git clone --quiet "$tgt/remote.git" "$tgt/seed" 2>/dev/null
tgt_git -C "$tgt/seed" commit --quiet --allow-empty -m 'Managed initial'
tgt_git -C "$tgt/seed" push --quiet origin HEAD:main
tgt_git clone --quiet "$tgt/remote.git" "$tgt/managed"
managed="$(cd "$tgt/managed" && pwd -P)"
git -C "$managed" config user.name 'Target fixture'
git -C "$managed" config user.email 'target-fixture@example.invalid'
git -C "$managed" config core.hooksPath /dev/null
# The remote moves on after the clone: start-work must fetch it.
tgt_git -C "$tgt/seed" commit --quiet --allow-empty -m 'Managed second'
tgt_git -C "$tgt/seed" push --quiet origin HEAD:main
remote_tip="$(git -C "$tgt/remote.git" rev-parse main)"
sidecar="$tgt/sidecar"
mkdir -p "$sidecar/docket/scripts" "$sidecar/review"
cp "$scripts"/*.sh "$sidecar/docket/scripts/"
cd "$sidecar"
git init --quiet
git symbolic-ref HEAD refs/heads/main
git config user.name 'Sidecar fixture'
git config user.email 'sidecar-fixture@example.invalid'
git config core.hooksPath /dev/null
printf '.worktrees/\n.docket/\n' > .gitignore
cat > review/BACKLOG.md <<'QUEUE'
# Review backlog

## P2 Normal

- [CORE] `tgt-backlog` **Fix the mapped finding.**
  - Source: scripts regression fixture
  - Findings: `tgt-finding`
QUEUE
cat > .docket-target <<'TARGET'
# Managed repository for this sidecar.
repo = owner/managed
dir=../managed     # relative to this file
TARGET
git add .
git commit --quiet -m 'Sidecar fixture'
cat > "$tgt/bin/gh" <<'GH'
#!/usr/bin/env bash
# Fake forge for target mode. Records are lines of FIXTURE_TARGET_PRS:
# state, number, draft, cross-repository, head sha, head branch, merge date
# (- when unmerged), author, title. The caller's login is "me";
# FIXTURE_GH_FAIL=1 fails every PR query.
printf '%s | GH_REPO=%s\n' "$*" "${GH_REPO:-}" >> "$FIXTURE_GH_LOG"
violation() { printf 'VIOLATION %s\n' "$1" >> "$FIXTURE_GH_LOG"; echo "fake gh: $1" >&2; exit 3; }
[ "${GH_REPO:-}" = owner/managed ] || violation "GH_REPO is '${GH_REPO:-}', not the target"
case "$1 $2" in
  'auth status') exit 0 ;;
  'repo view') [ "${3:-}" = owner/managed ] || violation "repo view without the target"; exit 0 ;;
  'api user') echo me; exit 0 ;;
  'pr list') [ -z "${FIXTURE_GH_FAIL:-}" ] || { echo 'fake gh: forge unavailable' >&2; exit 1; } ;;
  *) violation "unexpected call: $*" ;;
esac
shift 2
repo=""; head=""; state=""; jqx=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --state) state="$2"; shift 2 ;;
    --jq) jqx="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$repo" = owner/managed ] || violation "pr list without --repo owner/managed"
json="["; sep=""; plain=""
tab="$(printf '\t')"
while IFS="$tab" read -r st num draft cross oid ref merged author title; do
  [ -n "$st" ] && [ "$ref" = "$head" ] || continue
  case "$state" in all) ;; merged) [ "$st" = MERGED ] || continue ;; open) [ "$st" = OPEN ] || continue ;; esac
  if [ "$merged" != - ]; then at="\"${merged}T00:00:00Z\""; else at=null; fi
  json="$json$sep{\"state\":\"$st\",\"number\":$num,\"isDraft\":$draft,\"isCrossRepository\":$cross,\"headRefOid\":\"$oid\",\"headRefName\":\"$ref\",\"mergedAt\":$at,\"author\":{\"login\":\"$author\"},\"title\":\"$title\"}"
  sep=","
  case "$state" in
    all) plain="$plain$st$tab$num$tab$draft$tab$cross$tab$oid$tab$ref$tab$merged$tab$author$tab$title
" ;;
    merged) [ -n "$plain" ] || plain="$num $oid
" ;;
    open) [ -n "$plain" ] || plain="$num
" ;;
  esac
done < "${FIXTURE_TARGET_PRS:-/dev/null}"
if command -v jq >/dev/null 2>&1; then printf '%s]' "$json" | jq -r "$jqx"; else printf '%s' "$plain"; fi
GH
chmod +x "$tgt/bin/gh"
tgt_log="$tgt/gh.log"
prs="$tgt/prs.tsv"
: > "$prs"; : > "$tgt_log"
# An inherited GH_REPO naming another repository must not leak into queries.
tgh() { env PATH="$tgt/bin:$PATH" GH_REPO=wrong/repository FIXTURE_GH_LOG="$tgt_log" FIXTURE_TARGET_PRS="$prs" "$@"; }
sw="$sidecar/docket/scripts/start-work.sh"
tclaim="$sidecar/docket/scripts/claim-check.sh"
tclean="$sidecar/docket/scripts/cleanup-landed.sh"
tdue="$sidecar/docket/scripts/review-due.sh"
tshow="$sidecar/docket/scripts/target.sh"

# The loader: comments, whitespace, relative and ~/ paths, defaults.
pass 'target file with comments and a relative dir' bash "$tshow"
expect 'relative dir was not resolved' "dir: $managed"
expect 'default branches are not <queue>/<slug>' 'branches: <queue>/<slug>'
expect 'default worktree dir is not a sibling of the clone' "worktrees: $managed-worktrees/<queue>-<slug>"
expect 'default base is not origin/main' 'base: origin/main'
printf 'repo=owner/managed\n  dir = ~/managed   # under HOME\n\nbranch_prefix=me/\nland_comment=/merge now\n' > "$tgt/home.target"
pass 'target file with ~/' env HOME="$tgt" DOCKET_TARGET_FILE="$tgt/home.target" bash "$tshow"
expect 'a home-relative dir was not expanded' "dir: $managed"
expect 'branch_prefix was not applied' 'branches: me/<slug>'
expect 'land_comment was not read' 'land_comment: /merge now'
pass 'target --no-target' bash "$tshow" --no-target
expect '--no-target still loaded the target' 'no managed-repository target'
# A sidecar worktree resolves the relative dir against the main worktree.
git worktree add --quiet --detach "$sidecar/.worktrees/side" main
pass 'target from a sidecar worktree' in_dir "$sidecar/.worktrees/side" bash "$sidecar/.worktrees/side/docket/scripts/target.sh"
expect 'a sidecar worktree resolved dir against itself' "dir: $managed"
git worktree remove --force "$sidecar/.worktrees/side"
# A sidecar whose git directory lives elsewhere (--separate-git-dir, or a
# .git file as in a submodule) still resolves against its main worktree.
git init --quiet --separate-git-dir "$tgt/sep.git" "$tgt/sepside"
mkdir -p "$tgt/sepside/docket/scripts"
cp "$scripts"/*.sh "$tgt/sepside/docket/scripts/"
printf 'repo=owner/managed\ndir=../managed\n' > "$tgt/sepside/.docket-target"
pass 'target from a separate-git-dir sidecar' in_dir "$tgt/sepside" bash "$tgt/sepside/docket/scripts/target.sh"
expect 'a separate-git-dir sidecar resolved dir against its git directory' "dir: $managed"
bad() {
  label="$1"; expected="$2"; content="$3"
  printf "$content" > "$tgt/bad.target"
  reject "bad target: $label" "$expected" env DOCKET_TARGET_FILE="$tgt/bad.target" bash "$tshow"
}
bad 'unknown key' "bad.target:2: unknown key 'colour'" "repo=owner/managed\ncolour=blue\ndir=$managed\n"
bad 'malformed line' "bad.target:1: expected key=value, got 'just some text'" "just some text\n"
bad 'missing repo' "bad.target: required key 'repo' is missing" "dir=$managed\n"
bad 'missing dir' "bad.target: required key 'dir' is missing" "repo=owner/managed\n"
bad 'repo not owner/repo' "bad.target:1: repo must be owner/repo" "repo=managed\ndir=$managed\n"
bad 'repeated key' "bad.target:3: 'repo' is set twice" "repo=owner/managed\ndir=$managed\nrepo=owner/other\n"
bad 'prefix without a slash' "bad.target:3: branch_prefix must end in '/'" "repo=owner/managed\ndir=$managed\nbranch_prefix=me\n"
bad 'missing dir path' 'does not exist' "repo=owner/managed\ndir=$tgt/nowhere\n"
bad 'dir not a repository' 'is not a git working tree' "repo=owner/managed\ndir=$tgt/bin\n"
bad 'dir is the sidecar' 'is the sidecar repository itself' "repo=owner/managed\ndir=$sidecar\n"
bad 'missing remote' "has no remote 'upstream'" "repo=owner/managed\ndir=$managed\nremote=upstream\n"
reject 'DOCKET_TARGET_FILE names nothing' 'which is not a file' env DOCKET_TARGET_FILE="$tgt/absent.target" bash "$tshow"
printf 'repo=owner/managed\ndir=%s\nshade=dark\n' "$managed" > "$tgt/bad.target"
reject 'bad target stops start-work' "bad.target:3: unknown key 'shade'" tgh env DOCKET_TARGET_FILE="$tgt/bad.target" bash "$sw" todo tgt-bad
reject 'bad target stops claim-check' "bad.target:3: unknown key 'shade'" tgh env DOCKET_TARGET_FILE="$tgt/bad.target" bash "$tclaim" tgt-bad
reject 'bad target stops cleanup-landed' "bad.target:3: unknown key 'shade'" tgh env DOCKET_TARGET_FILE="$tgt/bad.target" bash "$tclean"
reject 'bad target stops review-due' "bad.target:3: unknown key 'shade'" tgh env DOCKET_TARGET_FILE="$tgt/bad.target" bash "$tdue"

# start-work: the branch and worktree land in the managed clone, from the
# fetched remote base, and nothing is written into the clone's exclude file.
mkdir -p "$managed/.git/info"; touch "$managed/.git/info/exclude"
cp "$managed/.git/info/exclude" "$tgt/exclude.before"
pass 'target start-work' tgh bash "$sw" todo tgt-one
expect 'start-work did not name the claim record' "the sidecar's queue entry is the claim record"
tgt_wt="$managed-worktrees/todo-tgt-one"
[ -d "$tgt_wt" ] || { echo 'scripts-test: target start-work created no worktree beside the clone' >&2; cat "$fixture/result.log" >&2; exit 1; }
[ "$(git -C "$tgt_wt" rev-parse HEAD)" = "$remote_tip" ] || { echo 'scripts-test: target start-work did not start from the fetched remote base' >&2; exit 1; }
[ "$(git -C "$tgt_wt" symbolic-ref --short HEAD)" = todo/tgt-one ] || { echo 'scripts-test: target worktree is on the wrong branch' >&2; exit 1; }
git rev-parse --verify --quiet refs/heads/todo/tgt-one >/dev/null && { echo 'scripts-test: target start-work created the branch in the sidecar' >&2; exit 1; }
[ "$(git worktree list | wc -l | tr -d ' ')" = 1 ] || { echo 'scripts-test: target start-work added a sidecar worktree' >&2; git worktree list >&2; exit 1; }
cmp -s "$managed/.git/info/exclude" "$tgt/exclude.before" || { echo 'scripts-test: target start-work wrote the managed exclude file' >&2; exit 1; }
grep -q '^pr list .*--head todo/tgt-one' "$tgt_log" || { echo 'scripts-test: target claim check made no PR query' >&2; cat "$tgt_log" >&2; exit 1; }

# claim-check: branches and worktrees in the managed clone, PRs by head branch.
reject 'target claim on a started slug' 'branch: todo/tgt-one' tgh bash "$tclaim" tgt-one
expect 'target claim did not report the managed worktree' "worktree: $tgt_wt [todo/tgt-one]"
reject 'target start-work on a claimed slug' 'existing claim' tgh bash "$sw" fix tgt-one
git -C "$tgt_wt" commit --quiet --allow-empty -m 'Own target work'
own_tip="$(git -C "$tgt_wt" rev-parse HEAD)"
printf 'OPEN\t7\ttrue\tfalse\t%s\ttodo/tgt-one\t-\tme\tManaged title\n' "$own_tip" > "$prs"
reject 'target open PR without --self' 'open PR owner/managed#7 [draft] todo/tgt-one: Managed title' tgh bash "$tclaim" tgt-one
pass 'target own PR with --self' in_dir "$tgt_wt" tgh bash "$tclaim" --self tgt-one
pass 'target --self with DOCKET_TARGET_FILE' in_dir "$tgt_wt" tgh env DOCKET_TARGET_FILE="$sidecar/.docket-target" bash "$tclaim" --self tgt-one
printf 'OPEN\t8\tfalse\ttrue\t%s\ttodo/tgt-one\t-\tme\tFork title\n' "$own_tip" > "$prs"
reject 'target fork PR with --self' 'open PR owner/managed#8 [ready]' in_dir "$tgt_wt" tgh bash "$tclaim" --self tgt-one
reject 'target --self outside the managed clone' 'must run from a worktree of the managed clone' tgh bash "$tclaim" --self tgt-one
printf 'MERGED\t9\tfalse\tfalse\t%s\ttask/tgt-done\t2026-10-30\tme\tDone title\n' "$remote_tip" > "$prs"
reject 'target merged PR by head branch' 'merged PR owner/managed#9 (2026-10-30) carried this slug: Done title' tgh bash "$tclaim" tgt-done
# Someone else's merged or closed PR on the name is a note, not a claim, and
# a queue named by --queue narrows the names to that one.
printf 'MERGED\t13\tfalse\tfalse\t%s\ttodo/tgt-other\t2026-10-30\talice\tTheirs\nCLOSED\t14\tfalse\tfalse\t%s\ttodo/tgt-other\t-\talice\tAbandoned\nOPEN\t15\tfalse\tfalse\t%s\tfix/tgt-other\t-\talice\tOther queue\n' "$remote_tip" "$remote_tip" "$remote_tip" > "$prs"
pass "target merged PR by someone else" tgh bash "$tclaim" --queue todo tgt-other
expect 'merged PR by someone else was not noted' 'note: merged PR owner/managed#13 by alice'
expect 'closed PR by someone else was not noted' 'note: closed PR owner/managed#14 by alice'
grep -q 'fix/tgt-other' "$fixture/result.log" && { echo 'scripts-test: --queue todo still queried fix/' >&2; exit 1; }
reject 'target open PR in another queue without --queue' 'open PR owner/managed#15' tgh bash "$tclaim" tgt-other
: > "$prs"
pass 'target unclaimed slug' tgh bash "$tclaim" tgt-free
grep -q -- '--head tgt-free ' "$tgt_log" && { echo 'scripts-test: target claim queried the bare slug' >&2; exit 1; }
# Other contributors' branches that merely end in the slug are not claims.
git -C "$managed" update-ref refs/remotes/origin/alice/tgt-alice "$remote_tip"
git -C "$managed" branch --quiet alice/tgt-alice origin/main
pass 'target branch under another name' tgh bash "$tclaim" tgt-alice
git -C "$managed" update-ref -d refs/remotes/origin/alice/tgt-alice
git -C "$managed" branch --quiet -D alice/tgt-alice
# A failed PR query is an error: start-work reports it as one, not as a claim.
set +e
tgh env FIXTURE_GH_FAIL=1 bash "$sw" todo tgt-unverified > "$fixture/result.log" 2>&1; rc=$?
set -e
[ "$rc" = 2 ] && grep -q 'ownership is unverified' "$fixture/result.log" || { echo "scripts-test: start-work did not report a failed claim check (exit $rc)" >&2; cat "$fixture/result.log" >&2; exit 1; }
git -C "$managed" branch --quiet fix/tgt-finding origin/main
reject 'target backlog finding from the sidecar backlog' 'branch: fix/tgt-finding' tgh bash "$tclaim" tgt-backlog
git -C "$managed" branch --quiet -D fix/tgt-finding
pass 'target claim with --no-target' tgh bash "$tclaim" --no-target tgt-one

# --no-target works on the sidecar itself, as without a target file.
pass 'start-work --no-target' tgh bash "$sw" todo tgt-sidecar --no-target
[ -d "$sidecar/.worktrees/todo-tgt-sidecar" ] && git rev-parse --verify --quiet refs/heads/todo/tgt-sidecar >/dev/null || { echo 'scripts-test: start-work --no-target did not work in the sidecar' >&2; exit 1; }
git -C "$managed" rev-parse --verify --quiet refs/heads/todo/tgt-sidecar >/dev/null && { echo 'scripts-test: start-work --no-target touched the managed clone' >&2; exit 1; }
git worktree remove --force "$sidecar/.worktrees/todo-tgt-sidecar"
git branch --quiet -D todo/tgt-sidecar

# A branch prefix, and a worktree directory inside the clone, which is then
# excluded there.
printf 'repo=owner/managed\ndir=%s\nbranch_prefix=me/\nworktree_dir=%s/.wt\n' "$managed" "$managed" > "$tgt/prefix.target"
pass 'target start-work with a prefix' tgh env DOCKET_TARGET_FILE="$tgt/prefix.target" bash "$sw" todo tgt-two
[ "$(git -C "$managed/.wt/todo-tgt-two" symbolic-ref --short HEAD)" = me/tgt-two ] || { echo 'scripts-test: branch_prefix was not used' >&2; exit 1; }
grep -qx '.wt/' "$managed/.git/info/exclude" || { echo 'scripts-test: a worktree dir inside the clone was not excluded there' >&2; exit 1; }
[ -z "$(git -C "$managed" status --porcelain)" ] || { echo 'scripts-test: the managed clone shows the worktree dir' >&2; exit 1; }
reject 'target claim on a prefixed branch' 'branch: me/tgt-two' tgh env DOCKET_TARGET_FILE="$tgt/prefix.target" bash "$tclaim" tgt-two
# Taken from the caller's directory, and the same file reaches claim-check
# after start-work moves to the sidecar root.
pass 'relative DOCKET_TARGET_FILE' in_dir "$sidecar/review" tgh env DOCKET_TARGET_FILE=../../prefix.target bash "$sw" todo tgt-rel
[ "$(git -C "$managed/.wt/todo-tgt-rel" symbolic-ref --short HEAD)" = me/tgt-rel ] || { echo 'scripts-test: relative DOCKET_TARGET_FILE was not used' >&2; exit 1; }
git -C "$managed" worktree remove --force "$managed/.wt/todo-tgt-rel"
git -C "$managed" branch --quiet -D me/tgt-rel
# A relative --dir is taken from the caller's directory, not the sidecar root.
pass 'target start-work with a relative --dir' in_dir "$sidecar/review" tgh bash "$sw" todo tgt-reldir --dir reldir
[ -d "$sidecar/review/reldir/todo-tgt-reldir" ] || { echo 'scripts-test: relative --dir was not taken from the caller' >&2; exit 1; }
git -C "$managed" worktree remove --force "$sidecar/review/reldir/todo-tgt-reldir"
git -C "$managed" branch --quiet -D todo/tgt-reldir
rm -rf "$sidecar/review/reldir"

# cleanup-landed: landing proved by a merged PR in the target, only docket
# branches considered, the base never deleted, the remote pruned.
git -C "$managed" branch --quiet personal origin/main
# The user's own branches carry docket-like names but no marker: neither the
# merged nor the --empty path may touch them.
git -C "$managed" branch --quiet fix/tgt-mine origin/main
git -C "$managed" branch --quiet me/tgt-mine origin/main
# A marked branch with nothing beyond the remote base, behind which the local
# base lags: --empty must measure against <remote>/<base>.
git -C "$managed" branch --quiet todo/tgt-empty origin/main
git -C "$managed" config branch.todo/tgt-empty.docket true
tgt_git -C "$tgt/seed" push --quiet origin HEAD:refs/heads/todo/tgt-stale
git -C "$managed" fetch --quiet origin
tgt_git -C "$tgt/seed" push --quiet origin :refs/heads/todo/tgt-stale
git -C "$managed" checkout --quiet --detach
main_tip="$(git -C "$managed" rev-parse main)"
printf 'MERGED\t10\tfalse\tfalse\t%s\ttodo/tgt-one\t2026-10-31\tme\tOne\nMERGED\t11\tfalse\tfalse\t%s\tpersonal\t2026-10-31\tme\tPersonal\nMERGED\t12\tfalse\tfalse\t%s\tmain\t2026-10-31\tme\tBase\nMERGED\t16\tfalse\tfalse\t%s\tfix/tgt-mine\t2026-10-31\tme\tMine\nMERGED\t17\tfalse\tfalse\t%s\tme/tgt-mine\t2026-10-31\tme\tMine too\n' "$own_tip" "$remote_tip" "$main_tip" "$remote_tip" "$remote_tip" > "$prs"
pass 'target cleanup dry run' tgh bash "$tclean"
expect 'target cleanup did not plan the landed worktree' "remove worktree $tgt_wt and branch todo/tgt-one (merged in PR #10"
grep -Eq 'personal|branch main|tgt-mine' "$fixture/result.log" && { echo 'scripts-test: target cleanup considered a non-docket branch or the base' >&2; cat "$fixture/result.log" >&2; exit 1; }
[ -d "$tgt_wt" ] || { echo 'scripts-test: target cleanup dry run removed a worktree' >&2; exit 1; }
pass 'target cleanup --apply' tgh bash "$tclean" --apply --empty
for b in fix/tgt-mine me/tgt-mine personal main; do
  git -C "$managed" rev-parse --verify --quiet "refs/heads/$b" >/dev/null || { echo "scripts-test: target cleanup deleted the unmarked branch $b" >&2; exit 1; }
done
git -C "$managed" rev-parse --verify --quiet refs/heads/todo/tgt-empty >/dev/null && { echo 'scripts-test: target --empty did not measure against the remote base' >&2; cat "$fixture/result.log" >&2; exit 1; }
[ -z "$(git -C "$managed" config --get branch.todo/tgt-one.docket || true)" ] || { echo 'scripts-test: target cleanup kept the marker of a deleted branch' >&2; exit 1; }
[ ! -d "$tgt_wt" ] || { echo 'scripts-test: target cleanup kept the landed worktree' >&2; exit 1; }
git -C "$managed" rev-parse --verify --quiet refs/heads/todo/tgt-one >/dev/null && { echo 'scripts-test: target cleanup kept the landed branch' >&2; exit 1; }
git -C "$managed" rev-parse --verify --quiet refs/heads/main >/dev/null && git -C "$managed" rev-parse --verify --quiet refs/heads/personal >/dev/null || { echo 'scripts-test: target cleanup deleted the base or a personal branch' >&2; exit 1; }
git -C "$managed" rev-parse --verify --quiet refs/remotes/origin/todo/tgt-stale >/dev/null && { echo 'scripts-test: target cleanup did not prune the remote' >&2; exit 1; }
git -C "$managed" rev-parse --verify --quiet refs/heads/me/tgt-two >/dev/null || { echo 'scripts-test: target cleanup removed an unlanded branch' >&2; exit 1; }
pass 'target cleanup --no-target' tgh bash "$tclean" --no-target
grep -q 'managed-repository target' "$fixture/result.log" && { echo 'scripts-test: cleanup --no-target used the target' >&2; exit 1; }

# A target whose base is not main: owned() measures against the target base,
# cleanup never deletes that base whatever --base says, and it skips the
# branch checked out in the managed worktree it runs from.
tgt_git -C "$tgt/seed" checkout --quiet -b trunk
tgt_git -C "$tgt/seed" commit --quiet --allow-empty -m 'Trunk only'
tgt_git -C "$tgt/seed" push --quiet origin trunk
trunk_tip="$(git -C "$tgt/seed" rev-parse HEAD)"
printf 'repo=owner/managed\ndir=%s\nbase=trunk\nbranch_prefix=tr/\n' "$managed" > "$tgt/trunk.target"
ttr() { tgh env DOCKET_TARGET_FILE="$tgt/trunk.target" "$@"; }
: > "$prs"
pass 'trunk start-work' ttr bash "$sw" todo tgt-trunk
trunk_wt="$managed-worktrees/todo-tgt-trunk"
[ "$(git -C "$trunk_wt" rev-parse HEAD)" = "$trunk_tip" ] || { echo 'scripts-test: start-work did not start from the target base' >&2; exit 1; }
git -C "$trunk_wt" commit --quiet --allow-empty -m 'Own trunk work'
own_trunk="$(git -C "$trunk_wt" rev-parse HEAD)"
printf 'OPEN\t20\ttrue\tfalse\t%s\ttr/tgt-trunk\t-\tme\tAt base\n' "$trunk_tip" > "$prs"
reject 'PR at the target base with --self' 'open PR owner/managed#20' in_dir "$trunk_wt" ttr bash "$tclaim" --self tgt-trunk
git -C "$managed" branch --quiet trunk origin/trunk
git -C "$managed" config branch.trunk.docket true
printf 'MERGED\t21\tfalse\tfalse\t%s\ttr/tgt-trunk\t2026-10-31\tme\tTrunk work\nMERGED\t22\tfalse\tfalse\t%s\ttrunk\t2026-10-31\tme\tBase\n' "$own_trunk" "$trunk_tip" > "$prs"
pass 'cleanup from a managed worktree' in_dir "$trunk_wt" ttr bash "$tclean" --base main
expect 'cleanup did not skip the branch checked out here' 'skip tr/tgt-trunk (checked out here)'
grep -q 'branch trunk ' "$fixture/result.log" && { echo 'scripts-test: cleanup considered the target base' >&2; cat "$fixture/result.log" >&2; exit 1; }
git -C "$managed" worktree remove --force "$trunk_wt"
git -C "$managed" branch --quiet -D tr/tgt-trunk trunk
: > "$prs"

# review-due: commits resolve in the managed clone, the index in the sidecar.
printf '| Date | Type | Commit |\n| %s | full | `%s` |\n' "$(date -u +%Y-%m-%d)" "$remote_tip" > review/README.md
pass 'target review-due' tgh bash "$tdue"
expect 'target review-due did not measure the managed clone' 'verdict: no review due'
expect 'target review-due did not default to the remote base' 'since then: 0 commits'
pass 'review-due --no-target' tgh bash "$tdue" --no-target
expect 'review-due --no-target resolved the managed commit' 'BASELINE LOST'
pass 'review-due --repo-dir' tgh bash "$tdue" --no-target --repo-dir "$managed" --base origin/main
expect 'review-due --repo-dir did not resolve the commit' 'verdict: no review due'
pass 'review-due with a relative --repo-dir' in_dir "$sidecar/review" tgh bash "$tdue" --no-target --repo-dir ../../managed --base origin/main
expect 'a relative --repo-dir was not taken from the caller' 'verdict: no review due'

grep -q VIOLATION "$tgt_log" && { echo 'scripts-test: a target-mode gh call did not name the target' >&2; grep VIOLATION "$tgt_log" >&2; exit 1; }
grep -q '^pr list' "$tgt_log" || { echo 'scripts-test: target mode made no PR queries' >&2; exit 1; }
cd "$fixture"
# ==== End of managed-repository target fixtures ============================

# ==== Sidecar claims and resolution (PR: lines) ============================
# In a sidecar the queue entry records the claim with a "PR: owner/repo#N"
# line; check-queues.sh validates it, claim-check.sh reports it,
# start-work.sh says how to add it, cleanup-landed.sh reports entries whose
# PRs have finished, and check-pr-markers.sh and pr-labels.sh stand down for
# the managed repository's PRs while --no-target keeps them working for the
# sidecar's own. Reuses the sidecar, the managed clone and the fake forge
# above.
cd "$sidecar"
cat > TODO.md <<'QUEUE'
# TODO

## Ready for separate work

### P2 Normal

- [CORE] `sc-claimed` **Claimed through the managed repository.**
  - Source: scripts regression fixture
  - PR: owner/managed#30
- [CORE] `sc-open` **Still in review.**
  - Source: scripts regression fixture
  - PR: owner/managed#31
- [CORE] `sc-closed` **Abandoned in the managed repository.**
  - Source: scripts regression fixture
  - PR: owner/managed#32
- [CORE] `sc-mixed` **Split over two PRs, one still open.**
  - Source: scripts regression fixture
  - PR: owner/managed#30, owner/managed#31
- [CORE] `sc-free` **Not yet claimed.**
  - Source: scripts regression fixture
QUEUE
cat >> review/BACKLOG.md <<'QUEUE'
  - PR: owner/managed#30
QUEUE
git add TODO.md review/BACKLOG.md
git commit --quiet -m 'Sidecar queue with PR lines'

# check-queues.sh: the PR: line's format in any mode, and in a sidecar the
# repository, read from the target file without the clone.
pass 'PR lines in a sidecar queue' bash docket/scripts/check-queues.sh --strict
sc_q() {
  # sc_q LINE: a one-entry queue whose entry carries LINE.
  printf '# TODO\n\n## Ready for separate work\n\n### P2 Normal\n\n- [CORE] `sc-one` **Outcome.**\n  - Source: fixture\n%s\n' "$1" > "$tgt/sc-todo.md"
}
for bad_line in '  - PR: #12' '  - PR: owner/managed' '  - PR: owner/managed#0' '  - PR: owner/managed#12 (draft)' '  - PR: owner/managed#12; owner/managed#13'; do
  sc_q "$bad_line"
  reject "malformed PR line: $bad_line" 'expected owner/repo#N, comma-separated' bash docket/scripts/check-queues.sh --todo "$tgt/sc-todo.md"
done
sc_q '  - PR:'
reject 'empty PR line' 'empty PR line for `sc-one`' bash docket/scripts/check-queues.sh --todo "$tgt/sc-todo.md"
sc_q "$(printf '  - PR: owner/managed#12\n  - PR: owner/managed#13')"
reject 'two PR lines' '`sc-one` has a second PR line' bash docket/scripts/check-queues.sh --todo "$tgt/sc-todo.md"
sc_q '  - PR: owner/managed#12,owner/managed#13 , owner/managed#14'
pass 'PR line spacing' bash docket/scripts/check-queues.sh --todo "$tgt/sc-todo.md" --strict
sc_q '  - PR: other/repo#5'
pass 'PR outside the target warns' bash docket/scripts/check-queues.sh --todo "$tgt/sc-todo.md"
expect 'no warning for a PR outside the target' 'warning: PR line for `sc-one` names other/repo#5, outside the managed repository owner/managed'
reject 'PR outside the target under --strict' 'outside the managed repository owner/managed' bash docket/scripts/check-queues.sh --todo "$tgt/sc-todo.md" --strict
pass 'PR outside the target with --no-target' bash docket/scripts/check-queues.sh --todo "$tgt/sc-todo.md" --strict --no-target
# CI has no managed clone: the repo line alone drives the warning.
printf 'repo = owner/managed  # trailing comment\ndir=%s/no-clone-here\n' "$tgt" > "$tgt/ci.target"
reject 'PR repo check without the clone' 'outside the managed repository owner/managed' env DOCKET_TARGET_FILE="$tgt/ci.target" bash docket/scripts/check-queues.sh --todo "$tgt/sc-todo.md" --strict
# A relative DOCKET_TARGET_FILE is taken from the caller's directory and
# named in the warning.
reject 'relative target file' "outside the managed repository owner/managed in $sidecar/review/../../ci.target" in_dir "$sidecar/review" env DOCKET_TARGET_FILE=../../ci.target bash "$sidecar/docket/scripts/check-queues.sh" --todo "$tgt/sc-todo.md" --strict
# Without a target file only the format is checked.
pass 'PR line in an ordinary repository' in_dir "$fixture" bash "$fixture/docket/scripts/check-queues.sh" --todo "$tgt/sc-todo.md" --strict
sc_q '  - PR: owner#5'
reject 'malformed PR line in an ordinary repository' 'expected owner/repo#N' in_dir "$fixture" bash "$fixture/docket/scripts/check-queues.sh" --todo "$tgt/sc-todo.md"

# A second fake answers "pr view" from FIXTURE_VIEW_PRS: number, state, head
# branch, head sha, cross-repository. --jq .state prints the state alone.
mkdir -p "$tgt/viewbin"
cat > "$tgt/viewbin/gh" <<'GH'
#!/usr/bin/env bash
if [ "$1 $2" = 'pr view' ]; then
  printf '%s | GH_REPO=%s\n' "$*" "${GH_REPO:-}" >> "$FIXTURE_GH_LOG"
  num="$3"; shift 3; repo=""; jqx=""
  while [ $# -gt 0 ]; do case "$1" in --repo) repo="$2"; shift 2 ;; --jq|-q) jqx="$2"; shift 2 ;; *) shift ;; esac; done
  [ "$repo" = owner/managed ] && [ "${GH_REPO:-}" = owner/managed ] || { echo 'VIOLATION pr view without the target' >> "$FIXTURE_GH_LOG"; exit 3; }
  awk -F '\t' -v n="$num" -v only="$jqx" '$1 == n { if (only == ".state") print $2; else print $2 "\t" $3 "\t" $4 "\t" $5; found = 1 } END { exit !found }' "$FIXTURE_VIEW_PRS"
  exit
fi
exec "$(dirname "$0")/../bin/gh" "$@"
GH
chmod +x "$tgt/viewbin/gh"
printf '30\tMERGED\n31\tOPEN\n32\tCLOSED\n' > "$tgt/view.tsv"
tgv() { tgh env PATH="$tgt/viewbin:$tgt/bin:$PATH" FIXTURE_VIEW_PRS="$tgt/view.tsv" "$@"; }

# claim-check.sh: a PR: line is a claim, in target mode and with --no-target.
: > "$prs"
reject 'claim recorded by a PR line' 'queue entry in TODO.md is claimed by PR: owner/managed#30' tgv bash "$tclaim" sc-claimed
reject 'backlog claim recorded by a PR line' 'queue entry in review/BACKLOG.md is claimed by PR: owner/managed#30' tgv bash "$tclaim" tgt-backlog
reject 'PR line claim with --no-target' 'queue entry in TODO.md is claimed by PR: owner/managed#30' tgv bash "$tclaim" --no-target --local sc-claimed
pass 'entry without a PR line' tgv bash "$tclaim" sc-free
# A PR: line after the entry's section ended belongs to no entry.
cp TODO.md "$tgt/todo.saved"
printf '\n### P3 Low\n\n  - PR: owner/managed#77\n' >> TODO.md
pass 'PR line under the next heading' tgv bash "$tclaim" sc-free
cp "$tgt/todo.saved" TODO.md
# The worker's own recheck: a note only when every recorded PR is an open
# same-repository PR headed by the own branch at an owned tip.
pass 'start-work for the own recheck' tgv bash "$sw" todo sc-self
sc_wt="$managed-worktrees/todo-sc-self"
git -C "$sc_wt" commit --quiet --allow-empty -m 'Own sidecar-claims work'
sc_tip="$(git -C "$sc_wt" rev-parse HEAD)"
printf -- '- [CORE] `sc-self` **Own claim.**\n  - Source: scripts regression fixture\n  - PR: owner/managed#40\n' >> TODO.md
printf '40\tOPEN\ttodo/sc-self\t%s\tfalse\n41\tOPEN\ttodo/sc-other\t%s\tfalse\n42\tOPEN\ttodo/sc-self\t%s\ttrue\n' "$sc_tip" "$sc_tip" "$sc_tip" >> "$tgt/view.tsv"
pass 'own PR line on --self' in_dir "$sc_wt" tgv bash "$tclaim" --self sc-self
expect 'own --self recheck did not note the PR line' 'note: the entry in TODO.md records PR: owner/managed#40, your own open PR'
pass 'own PR line on --exclude-branch' tgv bash "$tclaim" --exclude-branch todo/sc-self sc-self
expect 'own --exclude-branch recheck did not note the PR line' 'your own open PR'
reject 'merged PR line on --exclude-branch' 'queue entry in TODO.md is claimed by PR: owner/managed#30' tgv bash "$tclaim" --exclude-branch todo/sc-self sc-claimed
sed -i.bak 's/  - PR: owner\/managed#40$/  - PR: owner\/managed#40, owner\/managed#41/' TODO.md
reject "another worker's PR on --self" 'claimed by PR: owner/managed#40, owner/managed#41' in_dir "$sc_wt" tgv bash "$tclaim" --self sc-self
sed -i.bak 's/  - PR: owner\/managed#40, owner\/managed#41$/  - PR: owner\/managed#42/' TODO.md
reject 'fork PR on --self' 'claimed by PR: owner/managed#42' in_dir "$sc_wt" tgv bash "$tclaim" --self sc-self
sed -i.bak 's/  - PR: owner\/managed#42$/  - PR: other\/repo#40/' TODO.md
reject 'foreign PR on --self' 'claimed by PR: other/repo#40' in_dir "$sc_wt" tgv bash "$tclaim" --self sc-self
git -C "$sc_wt" commit --quiet --allow-empty -m 'Later own work'
printf '43\tOPEN\ttodo/sc-self\t%s\tfalse\n' "$(git -C "$managed" rev-parse origin/main)" >> "$tgt/view.tsv"
sed -i.bak 's/  - PR: other\/repo#40$/  - PR: owner\/managed#43/' TODO.md
reject 'unowned tip on --self' 'claimed by PR: owner/managed#43' in_dir "$sc_wt" tgv bash "$tclaim" --self sc-self
# The worker's own PR that already merged is still a claim: the work landed.
printf '45\tMERGED\ttodo/sc-self\t%s\tfalse\n' "$sc_tip" >> "$tgt/view.tsv"
sed -i.bak 's/  - PR: owner\/managed#43$/  - PR: owner\/managed#45/' TODO.md
reject 'own merged PR on --self' 'claimed by PR: owner/managed#45' in_dir "$sc_wt" tgv bash "$tclaim" --self sc-self
pass 'PR line on --self without gh' in_dir "$sc_wt" tgv bash "$tclaim" --self --local sc-self
expect 'local --self recheck did not note the PR line' 'taken to be your own, unverified without gh'
rm -f TODO.md.bak
cp "$tgt/todo.saved" TODO.md
git -C "$managed" worktree remove --force "$sc_wt"
git -C "$managed" branch --quiet -D todo/sc-self
# The entry as published on origin/main counts when the checkout is stale.
git checkout --quiet -b sc-published
printf -- '- [CORE] `sc-elsewhere` **Claimed on the published main.**\n  - Source: scripts regression fixture\n  - PR: owner/managed#44\n' >> TODO.md
rm -f TODO.md.bak
git commit --quiet -am 'Published claim'
git update-ref refs/remotes/origin/main HEAD
git checkout --quiet main
git branch --quiet -D sc-published
reject 'PR line on origin/main' 'queue entry in TODO.md on origin/main is claimed by PR: owner/managed#44' tgv bash "$tclaim" --local sc-elsewhere
git update-ref -d refs/remotes/origin/main
pass 'no PR line without origin/main' tgv bash "$tclaim" --local sc-elsewhere

# start-work.sh: the next steps name the PR: line and the sidecar file.
pass 'target start-work names the PR line' tgh bash "$sw" todo sc-free
expect 'start-work did not give the PR line' "then record the claim: add '  - PR: owner/managed#<number>' to the 'sc-free' entry in the sidecar's TODO.md as a direct commit to the sidecar's main"
expect 'start-work did not keep markers in the state file' "the 'Claims TODO: sc-free' marker, the Type: line and state in the sidecar's .docket/state-sc-free.md"
pass 'target start-work for a backlog entry' tgh bash "$sw" review sc-review --no-check
expect 'start-work named the wrong queue file' "to the 'sc-review' entry in the sidecar's review/BACKLOG.md"
pass 'target start-work for a direct task' tgh bash "$sw" task sc-task
grep -q 'record the claim' "$fixture/result.log" && { echo 'scripts-test: start-work asked for a PR line without a queue entry' >&2; exit 1; }
for b in todo/sc-free review/sc-review task/sc-task; do
  git -C "$managed" worktree remove --force "$managed-worktrees/${b%%/*}-${b#*/}"
  git -C "$managed" branch --quiet -D "$b"
done

# cleanup-landed.sh: entries whose target PRs all closed are listed, never
# edited. A PR in another repository is not queried, and one the forge cannot
# read keeps its entry open.
printf -- '- [CORE] `sc-foreign` **Claimed in another repository.**\n  - Source: scripts regression fixture\n  - PR: other/repo#30\n- [CORE] `sc-unknown` **One PR unreadable.**\n  - Source: scripts regression fixture\n  - PR: owner/managed#32, owner/managed#99\n' >> TODO.md
before="$(git rev-parse HEAD)"; cp TODO.md "$tgt/todo.before"
pass 'target cleanup reports finished claims' tgv bash "$tclean"
expect 'cleanup did not ask to resolve a merged claim' "resolve sc-claimed: owner/managed#30 merged; remove its entry from the sidecar's TODO.md in a direct commit to its main carrying 'Resolves TODO: sc-claimed'"
expect 'cleanup did not name the backlog marker' "resolve tgt-backlog: owner/managed#30 merged; remove its entry from the sidecar's review/BACKLOG.md in a direct commit to its main carrying 'Resolves review backlog: tgt-backlog'"
expect 'cleanup did not ask to release a closed claim' "release sc-closed: owner/managed#32 closed without GitHub's merged state; confirm it did not land (some merge processes close after squashing) before releasing"
expect 'cleanup did not report an unreadable PR' 'note: could not read owner/managed#99 for sc-unknown'
grep -Eq 'sc-open|sc-mixed|sc-free|sc-foreign|(resolve|release) sc-unknown' "$fixture/result.log" && { echo 'scripts-test: cleanup reported an entry whose PRs are open, foreign or unreadable' >&2; cat "$fixture/result.log" >&2; exit 1; }
[ "$(git rev-parse HEAD)" = "$before" ] && cmp -s TODO.md "$tgt/todo.before" || { echo 'scripts-test: cleanup edited the sidecar queue' >&2; exit 1; }
pass 'target cleanup --apply reports finished claims' tgv bash "$tclean" --apply
expect 'cleanup --apply did not report' 'resolve sc-claimed:'
cmp -s TODO.md "$tgt/todo.before" || { echo 'scripts-test: cleanup --apply edited the sidecar queue' >&2; exit 1; }
pass 'target cleanup --local' tgv bash "$tclean" --local
expect 'cleanup --local did not say the claims went unchecked' 'were not checked for resolution'
pass 'cleanup --no-target ignores PR lines' tgv bash "$tclean" --no-target
grep -q 'resolve sc-claimed' "$fixture/result.log" && { echo 'scripts-test: cleanup --no-target reported target claims' >&2; exit 1; }
git checkout --quiet -- TODO.md

# check-pr-markers.sh and pr-labels.sh stand down in a sidecar, from the
# sidecar or a managed worktree, without a forge call; --no-target checks the
# sidecar's own PR.
printf 'No heading, no markers.\n' > "$tgt/managed-body.md"
printf '## Why\n\nA sidecar change.\n\nType: docs\n' > "$tgt/sidecar-body.md"
calls="$(wc -l < "$tgt_log")"
tmarkers="$sidecar/docket/scripts/check-pr-markers.sh"
tlabels="$sidecar/docket/scripts/pr-labels.sh"
pass 'check-pr-markers stands down' tgh bash "$tmarkers" --body "$tgt/managed-body.md" --strict
expect 'check-pr-markers did not say it stands down' "check-pr-markers: not applicable: owner/managed's PRs follow its own template"
pass 'check-pr-markers --pr stands down' tgh bash "$tmarkers" --pr 7
pass 'check-pr-markers stands down in a managed worktree' in_dir "$managed/.wt/todo-tgt-two" tgh bash "$tmarkers" --body "$tgt/managed-body.md"
expect 'check-pr-markers did not stand down in a managed worktree' 'not applicable'
pass 'pr-labels stands down' tgh bash "$tlabels" --pr 7 --apply
expect 'pr-labels did not say it stands down' 'pr-labels: not applicable: docket labels are not used in owner/managed'
[ "$(wc -l < "$tgt_log")" = "$calls" ] || { echo 'scripts-test: a stood-down script called gh' >&2; tail -n 3 "$tgt_log" >&2; exit 1; }
reject 'check-pr-markers --no-target checks the sidecar PR' 'description has no "## " headings' tgh bash "$tmarkers" --no-target --body "$tgt/managed-body.md"
pass 'check-pr-markers --no-target passes a sidecar PR' tgh bash "$tmarkers" --no-target --body "$tgt/sidecar-body.md" --strict
pass 'pr-labels --no-target labels a sidecar PR' tgh bash "$tlabels" --no-target --body "$tgt/sidecar-body.md" --base main
expect 'pr-labels --no-target gave no labels' 'type:docs'
reject 'a bad target still stops check-pr-markers' "bad.target:3: unknown key 'shade'" tgh env DOCKET_TARGET_FILE="$tgt/bad.target" bash "$tmarkers" --body "$tgt/sidecar-body.md"

# land-local.sh in a sidecar checks the sidecar's own description.
git stash push --quiet --include-untracked
git checkout --quiet -b task/sc-land
printf 'land me\n' > sc-land.txt
git add sc-land.txt
git commit --quiet -m 'Sidecar change to land'
sc_land="$(git rev-parse HEAD)"
git checkout --quiet main
reject 'land-local in a sidecar checks the body' 'description has no "## " headings' tgh bash docket/scripts/land-local.sh task/sc-land --title 'Sidecar change' --body "$tgt/managed-body.md" --approved-head "$sc_land"
[ "$(git rev-parse main)" = "$before" ] || { echo 'scripts-test: land-local landed a bad sidecar description' >&2; exit 1; }
git branch --quiet -D task/sc-land
git stash pop --quiet

# ci.sh in the sidecar's CI, which has no managed clone: the queue check reads
# only the repo line and the markers are checked for the sidecar's own PR.
mkdir -p "$tgt/cibin"
printf '#!/usr/bin/env bash\n[ "$1 $2" = "pr view" ] || exit 3\ncat "$FIXTURE_CI_BODY"\n' > "$tgt/cibin/gh"
chmod +x "$tgt/cibin/gh"
git update-ref refs/remotes/origin/main HEAD
sci() { env -u GITHUB_EVENT_PATH PATH="$tgt/cibin:$PATH" DOCKET_TARGET_FILE="$tgt/ci.target" PR=5 BASE=main HEAD_BRANCH=task/sc-docs "$@"; }
pass 'sidecar ci.sh checks its own PR' sci FIXTURE_CI_BODY="$tgt/sidecar-body.md" bash docket/scripts/ci.sh
expect 'sidecar ci.sh skipped the markers' 'ci: all checks passed (check-queues, check-links, check-pr-markers)'
reject 'sidecar ci.sh fails a bad sidecar PR' "check 'check-pr-markers' failed" sci FIXTURE_CI_BODY="$tgt/managed-body.md" bash docket/scripts/ci.sh
git update-ref -d refs/remotes/origin/main

grep -q VIOLATION "$tgt_log" && { echo 'scripts-test: a sidecar-claims gh call did not name the target' >&2; grep VIOLATION "$tgt_log" >&2; exit 1; }
grep -q '^pr view 30 ' "$tgt_log" || { echo 'scripts-test: cleanup made no pr view query' >&2; exit 1; }
cd "$fixture"
# ==== End of sidecar claims fixtures =======================================

echo 'scripts-test: all checks passed'
