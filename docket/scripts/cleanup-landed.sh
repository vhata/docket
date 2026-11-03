#!/usr/bin/env bash
# Remove branches and worktrees whose work has demonstrably landed, plus empty
# placeholder branches. Dry run by default and the dry run changes nothing;
# pass --apply to act.
#
# Usage: docket/scripts/cleanup-landed.sh [--apply] [--base main] [--empty] [--discard-ignored] [--local] [--no-target]
#   A branch is "landed" only when gh finds a merged PR whose head was this
#   branch AND the branch's current tip is the commit that PR merged. A branch
#   with commits after the merged head is kept and reported. A verified local
#   squash receipt from land-local.sh also proves landing without a forge.
#   --local skips forge queries and fetches; automatic without remotes.
#   --empty also removes branches with no commits beyond the base, no PR and no
#   worktree (harness placeholders such as worktree-agent-*).
#   Worktrees with modified or untracked files are never removed. Ignored files
#   that are known caches (node_modules, target, .venv, __pycache__, .pytest_cache
#   and the like, at any depth; see cache_re below) never hold a worktree back.
#   Any other ignored file (evidence, logs, .docket/, an audit log) does, unless
#   --discard-ignored is given, because it may be the only copy of a record.
#   The allowlist goes by name, so keep records out of directories named like
#   build output (build, out, dist, coverage, test-results).
#   Nothing is pushed; remote branches are untouched.
#   With a managed-repository target (.docket-target; see target.sh) it works
#   in the managed clone: only branches start-work.sh marked as docket's
#   (git config branch.<name>.docket true) are considered, on both the merged
#   and the --empty paths, so the user's own branches are never touched;
#   landing is proved by a merged PR in the target repository (with
#   push_remote set, one headed in the managed repository itself or in that
#   fork, never in another fork under the same name); --empty measures
#   against <remote>/<base>; the base defaults to the target's and is never
#   deleted; deleting a branch also removes its marker; and --apply fetches and
#   prunes the target's remote. It also reads the "PR:" lines in the
#   sidecar's TODO.md and review/BACKLOG.md and lists each entry whose pull
#   requests in the target have all closed: "resolve" when one merged (remove
#   the entry in a direct sidecar commit), "release" when none did (confirm
#   first that it did not land some other way). It never edits the queues.
#   --no-target ignores the target file.
set -euo pipefail

# Ignored paths whose last component matches this are reproducible build or
# tool output and are discarded with the worktree without asking.
cache_re='^(node_modules|target|dist|build|out|coverage|\.docket|\.venv|venv|\.tox|\.nox|__pycache__|\.pytest_cache|\.hypothesis|\.mypy_cache|\.ruff_cache|\.cache|\.parcel-cache|\.turbo|\.next|\.nuxt|\.svelte-kit|\.wrangler|\.gradle|\.eslintcache|[^/]*\.tsbuildinfo|test-results|playwright-report|\.nyc_output|\.DS_Store|[^/]*\.pyc)$'
# Reads a successful status snapshot and prints ignored non-cache entries.
# --ignored=matching reports the path that matched an ignore rule (for example
# src/pkg/__pycache__/) rather than collapsing it to the first directory that
# holds nothing else, so the last component is the name the allowlist knows.
non_cache_ignored() {
  grep '^!!' | sed 's/^!! //' | while IFS= read -r p; do
    last="${p%/}"; last="${last##*/}"
    printf '%s\n' "$last" | grep -Eq "$cache_re" || printf '%s\n' "$p"
  done
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
orig="$(pwd)"
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "cleanup-landed: not in a git repository" >&2; exit 2; }
apply=0; base=""; empty=0; discard_ignored=0; local_only=0; no_target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --local) local_only=1; shift ;;
    --no-target) no_target=--no-target; shift ;;
    --apply) apply=1; shift ;;
    --base) base="$2"; shift 2 ;;
    --empty) empty=1; shift ;;
    --discard-ignored) discard_ignored=1; shift ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "cleanup-landed: unknown argument $1" >&2; exit 2 ;;
  esac
done
# shellcheck source=target.sh
. "$here/target.sh"
docket_target_init "$here" "$no_target" || exit 2
remote="origin"; repo_args=()
if [ -n "$DOCKET_TARGET" ]; then
  [ -n "$base" ] || base="$TARGET_BASE"
  remote="$TARGET_REMOTE"; repo_args=(--repo "$TARGET_REPO")
  # GH_REPO is pinned to the target as well, so no query can fall back to cwd.
  export GH_REPO="$TARGET_REPO"
  echo "cleanup-landed: managed-repository target $TARGET_REPO (clone $TARGET_DIR)"
  cd "$TARGET_DIR"
else
  [ -n "$base" ] || base="main"
  unset GH_REPO
  cd "$DOCKET_SIDECAR_ROOT"
fi
# In target mode, only branches start-work.sh marked as docket's are
# candidates; a name alone proves nothing in someone else's clone.
docket_branch() {
  [ -n "$DOCKET_TARGET" ] || return 0
  [ "$(git config --get "branch.$1.docket" 2>/dev/null || true)" = true ]
}
[ -n "$(git remote)" ] || local_only=1
common="$(git rev-parse --git-common-dir)"
common="$(cd "$common" && pwd -P)"
have_gh=0
if [ "$local_only" -eq 0 ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh repo view ${DOCKET_TARGET:+"$TARGET_REPO"} >/dev/null 2>&1; then have_gh=1; fi
[ "$apply" -eq 1 ] && mode="APPLY" || mode="DRY RUN (changes nothing; pass --apply to act)"
echo "cleanup-landed: $mode"
if [ "$have_gh" -eq 0 ]; then
  echo "cleanup-landed: merged-PR detection is OFF; checking verified local landing receipts"
fi
if [ -z "$DOCKET_TARGET" ]; then
  current="$(git branch --show-current || true)"
elif docket_target_contains "$orig"; then
  current="$(git -C "$orig" branch --show-current || true)"
else
  current=""
fi
# The main worktree is listed first; it can never be removed, so a branch checked out there is only reported.
main_wt="$(git worktree list --porcelain | awk '/^worktree / && !p { p = substr($0, 10) } END { print p }')"

wt_for() {
  git worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree / { p = substr($0, 10) }
    /^branch / { if ($2 == b) print p }'
}

removed=0; kept=0
for br in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  [ "$br" = "$base" ] || [ "$br" = "main" ] || [ "$br" = "master" ] && continue
  [ -n "$DOCKET_TARGET" ] && [ "$br" = "$TARGET_BASE" ] && continue
  docket_branch "$br" || continue
  [ "$br" = "$current" ] && { echo "skip $br (checked out here)"; continue; }
  tip="$(git rev-parse "$br")"
  reason=""
  receipt="$common/docket/landed/$br"
  if [ -f "$receipt" ]; then
    recorded_base="$(sed -n '1p' "$receipt")"
    old_base="$(sed -n '2p' "$receipt")"
    approved="$(sed -n '3p' "$receipt")"
    landed="$(sed -n '4p' "$receipt")"
    if [ "$recorded_base" = "$base" ] && [ "$approved" = "$tip" ] &&
       [ "$(git rev-parse --verify "refs/docket/landed/$br" 2>/dev/null || true)" = "$approved" ] &&
       [ "$(wc -l < "$receipt" | tr -d ' ')" = 4 ] &&
       git cat-file -e "$landed^{commit}" 2>/dev/null &&
       [ "$(git show -s --format=%P "$landed")" = "$old_base" ] &&
       git merge-base --is-ancestor "$old_base" "$approved" &&
       git merge-base --is-ancestor "$landed" "refs/heads/$base" &&
       [ "$(git rev-parse "$landed^{tree}")" = "$(git rev-parse "$approved^{tree}")" ]; then
      reason="locally squash-landed at $landed from this exact tip"
    else
      echo "keep $br: local landing receipt does not verify this tip on $base; inspect before deleting"
      kept=$((kept + 1)); continue
    fi
  fi
  if [ -z "$reason" ] && [ "$have_gh" -eq 1 ]; then
    # gh matches --head by branch name alone. With a fork configured, a
    # merged PR from another fork under the same name is skipped: only one
    # headed in the managed repository or that fork can prove landing.
    pick='.[0]'
    if [ -n "$DOCKET_TARGET" ] && [ -n "$TARGET_PUSH_OWNER" ]; then
      pick="[.[] | select((.isCrossRepository | not) or ((.headRepositoryOwner.login // \"\") | ascii_downcase) == (\"$TARGET_PUSH_OWNER\" | ascii_downcase))] | .[0]"
    fi
    merged="$(gh pr list ${repo_args[@]+"${repo_args[@]}"} --head "$br" --state merged --json number,headRefOid,isCrossRepository,headRepositoryOwner --jq "$pick"' | select(. != null) | "\(.number) \(.headRefOid)"' 2>/dev/null || true)"
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
    upto="$base"
    if [ -n "$DOCKET_TARGET" ] && git rev-parse --verify --quiet "refs/remotes/$remote/$base" >/dev/null; then upto="$remote/$base"; fi
    ahead="$(git rev-list --count "$upto..$br" 2>/dev/null || echo 1)"
    openpr=""; [ "$have_gh" -eq 1 ] && openpr="$(gh pr list ${repo_args[@]+"${repo_args[@]}"} --head "$br" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)"
    if [ "$ahead" -eq 0 ] && [ -z "$openpr" ] && [ -z "$(wt_for "$br")" ]; then reason="no commits beyond $base, no PR, no worktree"; fi
  fi
  [ -n "$reason" ] || continue

  path="$(wt_for "$br")"
  if [ -n "$path" ] && [ "$path" = "$main_wt" ]; then
    echo "keep $br: $reason, but it is checked out in the main worktree $path (switch it to $base there, then rerun)"
    kept=$((kept + 1)); continue
  fi
  if [ -n "$path" ]; then
    if ! status="$(git -C "$path" status --porcelain --ignored=matching 2>/dev/null)"; then
      echo "keep $br: cannot inspect worktree $path"
      kept=$((kept + 1)); continue
    fi
    # A here-string, not a pipe: under pipefail, grep -q exiting at the first
    # modified file would make a long status listing die of SIGPIPE and read
    # as a clean worktree.
    if grep -qvE '^(!!|$)' <<< "$status"; then
      echo "keep $br: $reason, but worktree $path has modified or untracked files"
      kept=$((kept + 1)); continue
    fi
    git_dir="$(git -C "$path" rev-parse --absolute-git-dir)" || { echo "keep $br: cannot locate worktree Git state"; kept=$((kept + 1)); continue; }
    active=0
    for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer BISECT_LOG; do
      [ ! -e "$git_dir/$state" ] || active=1
    done
    if [ "$active" -eq 1 ]; then
      echo "keep $br: worktree $path has an in-progress Git operation"
      kept=$((kept + 1)); continue
    fi
    ignored="$(printf '%s\n' "$status" | non_cache_ignored || true)"
    if [ -n "$ignored" ] && [ "$discard_ignored" -eq 0 ]; then
      echo "keep $br: $reason, but worktree $path holds ignored files that are not known caches and would be lost (pass --discard-ignored to remove anyway):"
      sed -n '1,10s/^/    /p' <<< "$ignored"
      kept=$((kept + 1)); continue
    fi
    echo "remove worktree $path and branch $br ($reason)"
    if [ "$apply" -eq 1 ]; then
      if ! git worktree remove --force "$path"; then
        echo "keep $br: worktree removal failed; branch and receipt retained"
        kept=$((kept + 1)); continue
      fi
    fi
  else
    echo "delete branch $br ($reason)"
  fi
  if [ "$apply" -eq 1 ]; then
    # Delete only the tip whose landing was proved, atomically. Keep branch
    # config: deleting it afterwards could erase a concurrent recreation's
    # settings. Git's branch -D has no expected-old-value guard.
    if ! git update-ref --no-deref -d "refs/heads/$br" "$tip"; then
      echo "keep $br: branch moved during cleanup or ref deletion failed"
      kept=$((kept + 1)); continue
    fi
    # The docket marker goes with the branch it marked.
    [ -z "$DOCKET_TARGET" ] || git config --unset-all "branch.$br.docket" 2>/dev/null || true
  fi
  removed=$((removed + 1))
done
echo "cleanup-landed: $removed branch(es) $( [ "$apply" -eq 1 ] && echo removed || echo 'would be removed'), $kept kept for inspection"

# Target mode: entries the sidecar's queues mark as claimed by PRs in the
# target, and whether those PRs have finished. Reported only; the resolution
# is a direct commit to the sidecar's main.
if [ -n "$DOCKET_TARGET" ]; then
  claimed="$(for qf in TODO.md review/BACKLOG.md; do
    [ -f "$DOCKET_SIDECAR_ROOT/$qf" ] || continue
    awk -v qf="$qf" '
      /^- \[[A-Z][A-Z0-9_-]*\] `[a-z0-9][a-z0-9-]*`/ { s = $0; sub(/^- \[[A-Z][A-Z0-9_-]*\] `/, "", s); sub(/`.*/, "", s); next }
      /^#/ || /^- / { s = "" }
      s != "" && /^  - PR:/ { v = $0; sub(/^  - PR:[ \t]*/, "", v); print qf "\t" s "\t" v; s = "" }
    ' "$DOCKET_SIDECAR_ROOT/$qf"
  done)"
  if [ -n "$claimed" ] && [ "$have_gh" -eq 0 ]; then
    echo "note: the sidecar's queues record PRs, but merged-PR detection is off; their entries were not checked for resolution"
  elif [ -n "$claimed" ]; then
    while IFS="$(printf '\t')" read -r qf slug refs; do
      open=""; merged=""; closed=""
      for ref in $(printf '%s\n' "$refs" | tr ',' ' '); do
        [ "${ref%%#*}" = "$TARGET_REPO" ] || continue
        if ! state="$(gh pr view "${ref##*#}" --repo "$TARGET_REPO" --json state --jq .state 2>/dev/null < /dev/null)"; then
          open="$open $ref"; echo "note: could not read $ref for $slug"; continue
        fi
        case "$state" in
          MERGED) merged="$merged $ref" ;;
          CLOSED) closed="$closed $ref" ;;
          *) open="$open $ref" ;;
        esac
      done
      [ -z "$open" ] || continue
      [ "$qf" = TODO.md ] && marker="Resolves TODO: $slug" || marker="Resolves review backlog: $slug"
      if [ -n "$merged" ]; then
        echo "resolve $slug:$merged merged; remove its entry from the sidecar's $qf in a direct commit to its main carrying '$marker' and the PR reference"
      elif [ -n "$closed" ]; then
        echo "release $slug:$closed closed without GitHub's merged state; confirm it did not land (some merge processes close after squashing) before releasing: drop the PR: line from the sidecar's $qf, or record the replacement PR"
      fi
    done <<< "$claimed"
  fi
fi
stale="$(git worktree list --porcelain | grep -c '^prunable' || true)"
if [ "$stale" -gt 0 ]; then
  if [ "$apply" -eq 1 ]; then git worktree prune; echo "cleanup-landed: pruned $stale stale worktree registration(s) (directories were already gone)"
  else echo "note: $stale prunable worktree registration(s); --apply prunes them (a missing directory does not by itself prove its branch landed)"; fi
fi
if [ "$apply" -eq 1 ] && [ "$local_only" -eq 0 ] && git remote get-url "$remote" >/dev/null 2>&1; then git fetch --prune --quiet "$remote" 2>/dev/null || true; fi
exit 0
