#!/usr/bin/env bash
# Remove branches and worktrees whose work has demonstrably landed, plus empty
# placeholder branches. Dry run by default and the dry run changes nothing;
# pass --apply to act.
#
# Usage: cleanup-landed.sh [--apply] [--base main] [--empty] [--discard-ignored]
#   A branch is "landed" only when gh finds a merged PR whose head was this
#   branch AND the branch's current tip is the commit that PR merged. A branch
#   with commits after the merged head is kept and reported.
#   --empty also removes branches with no commits beyond the base, no PR and no
#   worktree (harness placeholders such as worktree-agent-*).
#   Worktrees with modified or untracked files are never removed. Worktrees
#   with ignored files (caches, evidence, .feral/) are kept unless
#   --discard-ignored is given. Nothing is pushed; remote branches are untouched.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "cleanup-landed: not in a git repository" >&2; exit 2; }
cd "$root"
apply=0; base="main"; empty=0; discard_ignored=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1; shift ;;
    --base) base="$2"; shift 2 ;;
    --empty) empty=1; shift ;;
    --discard-ignored) discard_ignored=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "cleanup-landed: unknown argument $1" >&2; exit 2 ;;
  esac
done

have_gh=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then have_gh=1; fi
[ "$apply" -eq 1 ] && mode="APPLY" || mode="DRY RUN (changes nothing; pass --apply to act)"
echo "cleanup-landed: $mode"
if [ "$have_gh" -eq 0 ]; then
  echo "cleanup-landed: no authenticated gh for this repository; merged-PR detection is OFF (only --empty placeholder cleanup can run)"
  [ "$empty" -eq 1 ] || { echo "cleanup-landed: nothing to do without gh; pass --empty to remove placeholder branches"; exit 0; }
fi
current="$(git branch --show-current || true)"

wt_for() {
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree / { p = substr($0, 10) }
    /^branch / { if ($2 == b) print p }'
}

removed=0; kept=0
for br in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  [ "$br" = "$base" ] || [ "$br" = "main" ] || [ "$br" = "master" ] && continue
  [ "$br" = "$current" ] && { echo "skip $br (checked out here)"; continue; }
  tip="$(git rev-parse "$br")"
  reason=""
  if [ "$have_gh" -eq 1 ]; then
    merged="$(gh pr list --head "$br" --state merged --json number,headRefOid --jq '.[0] | select(. != null) | "\(.number) \(.headRefOid)"' 2>/dev/null || true)"
    if [ -n "$merged" ]; then
      num="${merged%% *}"; oid="${merged##* }"
      if [ "$oid" = "$tip" ]; then
        reason="merged in PR #$num at this exact tip"
      elif git merge-base --is-ancestor "$oid" "$tip" 2>/dev/null; then
        n="$(git rev-list --count "$oid..$tip")"
        echo "keep $br: PR #$num merged at ${oid:0:7} but the branch has $n later commit(s) (${tip:0:7}); inspect before deleting"
        kept=$((kept + 1)); continue
      else
        echo "keep $br: PR #$num merged a different history (${oid:0:7}) than the local tip (${tip:0:7}); inspect before deleting"
        kept=$((kept + 1)); continue
      fi
    fi
  fi
  if [ -z "$reason" ] && [ "$empty" -eq 1 ]; then
    ahead="$(git rev-list --count "$base..$br" 2>/dev/null || echo 1)"
    openpr=""; [ "$have_gh" -eq 1 ] && openpr="$(gh pr list --head "$br" --state open --json number --jq '.[0].number' 2>/dev/null || true)"
    if [ "$ahead" -eq 0 ] && [ -z "$openpr" ] && [ -z "$(wt_for "$br")" ]; then reason="no commits beyond $base, no PR, no worktree"; fi
  fi
  [ -n "$reason" ] || continue

  path="$(wt_for "$br")"
  if [ -n "$path" ]; then
    if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
      echo "keep $br: $reason, but worktree $path has modified or untracked files"
      kept=$((kept + 1)); continue
    fi
    ignored="$(git -C "$path" status --porcelain --ignored 2>/dev/null | grep '^!!' | grep -vE '^!! (node_modules|target|\.venv|\.cache|__pycache__|dist|build)/?$' || true)"
    if [ -n "$ignored" ] && [ "$discard_ignored" -eq 0 ]; then
      echo "keep $br: $reason, but worktree $path holds ignored files that would be lost (pass --discard-ignored to remove anyway):"
      echo "$ignored" | sed 's/^!! /    /' | head -10
      kept=$((kept + 1)); continue
    fi
    echo "remove worktree $path and branch $br ($reason)"
    if [ "$apply" -eq 1 ]; then git worktree remove --force "$path"; fi
  else
    echo "delete branch $br ($reason)"
  fi
  if [ "$apply" -eq 1 ]; then git branch -D "$br" >/dev/null; fi
  removed=$((removed + 1))
done
echo "cleanup-landed: $removed branch(es) $( [ "$apply" -eq 1 ] && echo removed || echo 'would be removed'), $kept kept for inspection"
stale="$(git worktree list --porcelain | grep -c '^prunable' || true)"
if [ "$stale" -gt 0 ]; then
  if [ "$apply" -eq 1 ]; then git worktree prune; echo "cleanup-landed: pruned $stale stale worktree registration(s) (directories were already gone)"
  else echo "note: $stale prunable worktree registration(s); --apply prunes them (a missing directory does not by itself prove its branch landed)"; fi
fi
if [ "$apply" -eq 1 ]; then git fetch --prune --quiet origin 2>/dev/null || true; fi
exit 0
