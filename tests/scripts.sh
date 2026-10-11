#!/usr/bin/env bash
# Regression checks for the vendored scripts, run against a disposable git
# repository. Exercises check-pr-markers.sh, check-queues.sh, claim-check.sh,
# start-work.sh and review-due.sh with positive and negative fixtures, and
# checks that every script is executable on disk and in the committed mode.
#
# Usage: bash tests/scripts.sh   (from anywhere; needs git and bash 3.2+)
set -euo pipefail
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
trap 'rm -rf "$fixture"' EXIT
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

# claim-check.sh against a fake forge
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

# review-due.sh
head="$(git rev-parse HEAD)"
printf '| Date | Type | Commit |\n| 2026-10-06 | full | `%s` |\n' "$head" > review-index.md
pass 'zero review churn' bash "$due" --index review-index.md --base "$head"

# A tracked source file deleted in the working tree must not abort the report.
mkdir -p src
printf 'one\ntwo\n' > src/kept.sh
printf 'three\n' > src/deleted.sh
git add src
git commit --quiet -m 'Add fixture sources'
head="$(git rev-parse HEAD)"
printf '| Date | Type | Commit |\n| 2026-10-06 | full | `%s` |\n' "$head" > review-index.md
rm src/deleted.sh
pass 'deleted tracked source' bash "$due" --index review-index.md --base "$head"
grep -Fq 'verdict:' "$fixture/result.log" || { echo 'scripts-test: deleted tracked source gave no verdict' >&2; cat "$fixture/result.log" >&2; exit 1; }
grep -Fq 'note: 1 tracked source file(s) are missing' "$fixture/result.log" || { echo 'scripts-test: deleted tracked source was not reported' >&2; cat "$fixture/result.log" >&2; exit 1; }
grep -Fq 'against 2 current source lines' "$fixture/result.log" || { echo 'scripts-test: deleted tracked source miscounted lines' >&2; cat "$fixture/result.log" >&2; exit 1; }
git checkout --quiet -- src/deleted.sh
pass 'paths with --paths' bash "$due" --index review-index.md --base "$head" --paths 'src docket'
echo 'scripts-test: all checks passed'
