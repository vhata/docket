#!/usr/bin/env bash
# Squash an approved local branch into the checked-out base, without a forge.
#
# Usage: docket/scripts/land-local.sh BRANCH --title TEXT --body FILE --approved-head SHA [--base main]
# SHA must be the full commit ID the user approved, not a ref or abbreviated ID.
# Run from a clean base worktree after checks and independent review. The task
# must be rebased onto that base; any checked-out task worktree must be clean.
# --approved-head records approval supplied by the caller; it does not obtain
# user approval or run the project's checks. No push or cleanup is performed.
# A verified receipt in the common Git directory, docket/landed/BRANCH, lets
# cleanup-landed.sh remove this exact task tip after landing. Its four lines
# are base branch, old base ID, approved head ID and resulting squash ID.
# refs/docket/landed/BRANCH retains the approved commit for receipt verification
# after cleanup and garbage collection; it is local audit state, not a branch.
# Failure after squash/commit leaves the state for inspection; never retry
# blindly, reset the base, or discard task evidence to recover automatically.
# It lands only in the repository it runs in; in a sidecar, its own work.
set -euo pipefail

fail() { echo "land-local: $*" >&2; exit 1; }
usage() { sed -n '2,17p' "$0"; exit 2; }
[ $# -gt 0 ] || usage
case "$1" in -h|--help) sed -n '2,17p' "$0"; exit 0 ;; -*) usage ;; esac
branch="$1"; shift
title=""; body=""; approved=""; base="main"
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --title) title="$2" ;;
    --body) body="$2" ;;
    --approved-head) approved="$2" ;;
    --base) base="$2" ;;
    *) usage ;;
  esac
  shift 2
done
[ -n "$title" ] && [ -n "$body" ] && [ -n "$approved" ] || usage
case "$title" in *$'\n'*|*$'\r'*) fail 'title must be one nonempty line' ;; esac
printf '%s' "$title" | grep -q '[^[:space:]]' || fail 'title must be one nonempty line'
[ -f "$body" ] && [ -r "$body" ] || fail "cannot read description $body"
case "$body" in /*) ;; *) body="$PWD/$body" ;; esac
root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail 'not in a git repository'
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"
git check-ref-format "refs/heads/$branch" >/dev/null || fail 'invalid task branch'
git check-ref-format "refs/heads/$base" >/dev/null || fail 'invalid base branch'
case "$branch" in "$base"|main|master) fail 'task branch must differ from the primary branch' ;; esac
[ "$(git symbolic-ref --quiet HEAD)" = "refs/heads/$base" ] || fail "run from the checked-out $base worktree"
head="$(git rev-parse --verify "refs/heads/$branch^{commit}")" || fail 'task branch does not exist'
[ "$approved" = "$head" ] || fail 'approved head must equal the full current task commit ID'
old_base="$(git rev-parse --verify "refs/heads/$base^{commit}")"
[ "$head" != "$old_base" ] || fail 'task has no commits to land'
git merge-base --is-ancestor "$old_base" "$head" || fail "rebase onto $base, rerun checks and review, and obtain approval for the new head"
[ "$(git rev-parse "$old_base^{tree}")" != "$(git rev-parse "$head^{tree}")" ] || fail 'task has no tree changes to land'

clean() {
  local path="$1" status state git_dir
  git_dir="$(git -C "$path" rev-parse --absolute-git-dir)" || fail "cannot locate Git state for $path"
  status="$(git -C "$path" status --porcelain --untracked-files=normal)" || fail "cannot inspect worktree $path"
  [ -z "$status" ] || fail "worktree $path has modified or untracked files"
  for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_LOG; do
    [ ! -e "$git_dir/$state" ] || fail "worktree $path has an in-progress Git operation ($state)"
  done
}
clean "$root"
task_wt="$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '/^worktree / { p = substr($0, 10) } /^branch / && substr($0, 8) == b { print p }')"
[ -z "$task_wt" ] || clean "$task_wt"

common="$(git rev-parse --git-common-dir)"
common="$(cd "$common" && pwd -P)"
mkdir -p "$common/docket/landed/$(dirname "$branch")"
lock="$common/docket/landing.lock"
mkdir "$lock" 2>/dev/null || fail "another local landing may be running ($lock); inspect before removing its lock"
tmp="$(mktemp -d "$common/docket/landing.XXXXXX")"
started=0; completed=0
finish() {
  local status=$?
  rm -rf "$tmp"
  rmdir "$lock"
  if [ "$status" -ne 0 ] && [ "$started" -eq 1 ] && [ "$completed" -eq 0 ]; then
    echo 'land-local: squash or commit may have completed; inspect HEAD and the index before recovery. The task branch and worktree were retained.' >&2
  fi
}
trap finish EXIT
printf '%s\n\n' "$title" > "$tmp/message"
cp "$body" "$tmp/body"
"$here/check-pr-markers.sh" --no-target --body "$tmp/body" --base "$old_base" --head "$head" --branch "$branch" --strict
cat "$tmp/body" >> "$tmp/message"
[ -z "$(tail -c 1 "$tmp/message")" ] || printf '\n' >> "$tmp/message"
# Ref and cleanliness checks are repeated immediately before changing the base.
[ "$(git rev-parse HEAD)" = "$old_base" ] && [ "$(git rev-parse "refs/heads/$branch")" = "$head" ] || fail 'branch moved during preparation; review again'
clean "$root"
[ -z "$task_wt" ] || clean "$task_wt"
started=1
git merge --squash --no-commit --no-overwrite-ignore "$head" || fail 'squash failed; inspect the base worktree'
[ "$(git rev-parse HEAD)" = "$old_base" ] && [ "$(git rev-parse "refs/heads/$branch")" = "$head" ] || fail 'branch moved during squash; inspect the index'
[ "$(git write-tree)" = "$(git rev-parse "$head^{tree}")" ] || fail 'squash index differs from approved tree; inspect it'
git commit --cleanup=verbatim --file "$tmp/message" || fail 'commit failed; inspect HEAD and the index'
landed="$(git rev-parse HEAD)"
[ "$(git show -s --format=%P "$landed")" = "$old_base" ] || fail 'result is not a single-parent squash commit'
[ "$(git rev-parse "$landed^{tree}")" = "$(git rev-parse "$head^{tree}")" ] || fail 'committed tree differs from approved tree; cleanup withheld'
git cat-file commit "$landed" | sed '1,/^$/d' > "$tmp/actual-message"
cmp -s "$tmp/message" "$tmp/actual-message" || fail 'commit message differs from the supplied title and description; cleanup withheld'
[ "$(git symbolic-ref --quiet HEAD)" = "refs/heads/$base" ] || fail 'base checkout changed during commit; cleanup withheld'
printf '%s\n%s\n%s\n%s\n' "$base" "$old_base" "$head" "$landed" > "$tmp/receipt"
git update-ref "refs/docket/landed/$branch" "$head" || fail "landed as $landed but proof ref failed; cleanup remains pending"
mv "$tmp/receipt" "$common/docket/landed/$branch" || fail "landed as $landed but receipt publication failed; cleanup remains pending"
completed=1
echo "land-local: landed $branch at $landed (approved head $head)"
echo 'next: check the resulting base, preserve .docket review records outside the task worktree, then run cleanup-landed.sh and cleanup-landed.sh --apply'
