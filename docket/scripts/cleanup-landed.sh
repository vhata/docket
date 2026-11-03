#!/usr/bin/env bash
# Remove branches and worktrees whose work has demonstrably landed, plus empty
# placeholder branches. Dry run by default and the dry run changes nothing;
# pass --apply to act.
#
# Usage: docket/scripts/cleanup-landed.sh [--apply] [--base main] [--empty] [--discard-ignored] [--local] [--no-target]
#        [--integrated BRANCH EXPECTED_HEAD LANDED_COMMIT]...
#   Own-name merged PRs and local receipts prove exact landed tips. Workers
#   folded into another branch are discovered from up to 1000
#   merged PRs or retained local receipts: every changed path must match a
#   reachable historical landing. Open PRs, later work and uncertain proof
#   are retained and reported. Local receipts need no forge.
#   --integrated selects only the named workers. Both commits must be full
#   object IDs. The landing must be in base history and contain the worker's
#   exact changed files (or its history). All mappings are checked before
#   any removal. This mode makes no forge calls, fetches or global prunes.
#   --local skips forge queries and fetches; automatic without remotes.
#   --empty also removes branches with no commits beyond the base, no PR and no
#   worktree (harness placeholders such as worktree-agent-*).
#   Worktrees with modified or untracked files are never removed. Ignored files
#   in known caches or .docket/ (at any depth; see cache_re below) never hold
#   a worktree back. Preserve .docket/ records elsewhere before cleanup;
#   the script does not archive them. Other ignored files (evidence, logs)
#   hold it back unless --discard-ignored is given.
#   The allowlist goes by name, so also keep records out of directories named
#   like build output (build, out, dist, coverage, test-results).
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
#   --no-target ignores the target file. Integrated proof uses the target's
#   remote base, or its local base with --local; ownership still applies.
set -euo pipefail

# Ignored paths whose last component matches this are discarded with the
# worktree: reproducible build/tool output and .docket working files.
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
integrated_count=0; integrated_branches=(); integrated_heads=(); integrated_landings=()
die() { echo "cleanup-landed: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --local) local_only=1; shift ;;
    --no-target) no_target=--no-target; shift ;;
    --apply) apply=1; shift ;;
    --base) base="$2"; shift 2 ;;
    --empty) empty=1; shift ;;
    --discard-ignored) discard_ignored=1; shift ;;
    --integrated)
      [ $# -ge 4 ] || die '--integrated requires BRANCH EXPECTED_HEAD LANDED_COMMIT'
      integrated_branches[$integrated_count]="$2"
      integrated_heads[$integrated_count]="$3"
      integrated_landings[$integrated_count]="$4"
      integrated_count=$((integrated_count + 1)); shift 4 ;;
    -h|--help) sed -n '2,/^set -/p' "$0" | sed '$d'; exit 0 ;;
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
integrated_base="refs/heads/$base"
if [ -n "$DOCKET_TARGET" ] && [ "$local_only" -eq 0 ]; then
  integrated_base="refs/remotes/$remote/$base"
fi
proof_dir=""
trap '[ -z "$proof_dir" ] || rm -rf "$proof_dir"' EXIT
prepare_proof() {
  [ -n "$proof_dir" ] || proof_dir="$(mktemp -d)" || die 'cannot create proof scratch directory'
}
# Compare the complete result on every worker-changed path at a historical
# landing, not at today's base. Automatic discovery also rejects histories
# that could be new work restoring an older result or include net-zero work.
prove_integration() {
  local head="$1" landing="$2" automatic="$3" ancestor changed merges
  proof_error=""
  git merge-base --is-ancestor "$landing" "$integrated_base" 2>/dev/null || { proof_error="landing $landing is not in $integrated_base history"; return 1; }
  if [ "$automatic" -eq 1 ]; then
    if git merge-base --is-ancestor "$landing" "$head" 2>/dev/null; then
      proof_error='worker already descends from this landing'; return 1
    else
      [ "$?" -eq 1 ] || { proof_error='cannot inspect landing ancestry'; return 1; }
    fi
  fi
  ancestor="$(git merge-base --all "$head" "$landing" 2>/dev/null)" || { proof_error='cannot find common ancestor'; return 1; }
  case "$ancestor" in ''|*$'\n'*) proof_error='worker and landing need one common ancestor'; return 1 ;; esac
  if [ "$ancestor" = "$head" ]; then
    [ "$automatic" -eq 0 ] && return 0
    proof_error='no branch-exclusive changes'; return 1
  fi
  prepare_proof
  if [ "$automatic" -eq 1 ]; then
    merges="$(git rev-list --merges "$ancestor..$head" 2>/dev/null)" || { proof_error='cannot inspect worker history'; return 1; }
    [ -z "$merges" ] || { proof_error='worker history contains merge commits'; return 1; }
    git log --format=%T "$ancestor..$head" > "$proof_dir/trees" 2>/dev/null || { proof_error='cannot inspect worker trees'; return 1; }
    git rev-parse "$ancestor^{tree}" >> "$proof_dir/trees" 2>/dev/null || { proof_error='cannot inspect common base tree'; return 1; }
    awk 'seen[$0]++ { repeated = 1 } END { exit repeated }' "$proof_dir/trees" || { proof_error='worker history repeats a tree (empty or reverted work)'; return 1; }
  fi
  git --literal-pathspecs diff --no-ext-diff --no-textconv --ignore-submodules=none --no-renames --name-only -z "$ancestor" "$head" -- > "$proof_dir/paths" 2>/dev/null || { proof_error='cannot list changed paths'; return 1; }
  [ -s "$proof_dir/paths" ] || { proof_error='worker has no net changes to prove'; return 1; }
  while IFS= read -r -d '' changed; do
    if ! git --literal-pathspecs diff --quiet --no-ext-diff --no-textconv --ignore-submodules=none "$head" "$landing" -- "$changed" 2>/dev/null; then
      printf -v proof_error 'worker differs from landing %s at %q (or comparison failed)' "$landing" "$changed"
      return 1
    fi
  done < "$proof_dir/paths"
  return 0
}

# Receipts remain useful after the parent branch is removed. The retained
# proof ref, parent, approved tree and current base history must still agree.
verify_receipt() {
  local file="$1" branch="$2" recorded_base old_base
  [ -f "$file" ] || return 1
  recorded_base="$(sed -n '1p' "$file")" || return 1
  old_base="$(sed -n '2p' "$file")" || return 1
  receipt_approved="$(sed -n '3p' "$file")" || return 1
  receipt_landed="$(sed -n '4p' "$file")" || return 1
  [ "$recorded_base" = "$base" ] &&
    [ "$(git rev-parse --verify "refs/docket/landed/$branch" 2>/dev/null)" = "$receipt_approved" ] &&
    [ "$(wc -l < "$file" | tr -d ' ')" = 4 ] &&
    git cat-file -e "$receipt_landed^{commit}" 2>/dev/null &&
    [ "$(git show -s --format=%P "$receipt_landed")" = "$old_base" ] &&
    git merge-base --is-ancestor "$old_base" "$receipt_approved" &&
    git merge-base --is-ancestor "$receipt_landed" "$integrated_base" &&
    [ "$(git rev-parse "$receipt_landed^{tree}")" = "$(git rev-parse "$receipt_approved^{tree}")" ]
}

if [ "$integrated_count" -gt 0 ]; then
  [ "$empty" -eq 0 ] || die '--integrated cannot be combined with --empty'
  git rev-parse --verify "$integrated_base^{commit}" >/dev/null 2>&1 || die "cannot read base $integrated_base"
  i=0
  while [ "$i" -lt "$integrated_count" ]; do
    worker="${integrated_branches[$i]}"
    expected="${integrated_heads[$i]}"
    landing="${integrated_landings[$i]}"
    git check-ref-format "refs/heads/$worker" >/dev/null 2>&1 || die "invalid worker branch $worker"
    j=0
    while [ "$j" -lt "$i" ]; do
      [ "${integrated_branches[$j]}" != "$worker" ] || die "duplicate worker branch $worker"
      j=$((j + 1))
    done
    [ "$worker" != "$base" ] && [ "$worker" != main ] && [ "$worker" != master ] || die "protected base branch $worker"
    [ -z "$DOCKET_TARGET" ] || [ "$worker" != "$TARGET_BASE" ] || die "protected base branch $worker"
    docket_branch "$worker" || die "worker $worker is not marked as docket's in the managed repository"
    if git symbolic-ref --quiet "refs/heads/$worker" >/dev/null 2>&1; then die "worker $worker is a symbolic ref"; fi
    actual="$(git rev-parse --verify "refs/heads/$worker" 2>/dev/null)" || die "worker branch $worker does not exist"
    for oid in "$expected" "$landing"; do
      case "$oid" in ''|*[!0-9a-f]*) die '--integrated requires full commit object IDs' ;; esac
      [ "${#oid}" -eq 40 ] || [ "${#oid}" -eq 64 ] || die '--integrated requires full commit object IDs'
      [ "$(git rev-parse --verify "$oid^{commit}" 2>/dev/null)" = "$oid" ] || die "cannot read commit $oid"
    done
    [ "$actual" = "$expected" ] || die "worker $worker moved from expected head $expected (now $actual)"
    prove_integration "$expected" "$landing" 0 || die "$worker: $proof_error"
    i=$((i + 1))
  done
fi
have_gh=0
if [ "$integrated_count" -eq 0 ] && [ "$local_only" -eq 0 ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh repo view ${DOCKET_TARGET:+"$TARGET_REPO"} >/dev/null 2>&1; then have_gh=1; fi
[ "$apply" -eq 1 ] && mode="APPLY" || mode="DRY RUN (changes nothing; pass --apply to act)"
echo "cleanup-landed: $mode"
if [ "$integrated_count" -gt 0 ]; then
  echo "cleanup-landed: checking only explicitly mapped workers"
elif [ "$have_gh" -eq 0 ]; then
  echo "cleanup-landed: merged-PR detection is OFF; checking verified local landing receipts"
fi
candidate_rows=""; candidates_loaded=0; candidates_ok=1
load_candidates() {
  if [ "$candidates_loaded" -eq 1 ]; then return $((1 - candidates_ok)); fi
  candidates_loaded=1
  local filter='.' rows branch
  if [ "$have_gh" -eq 1 ]; then
    if [ -n "$DOCKET_TARGET" ] && [ -n "$TARGET_PUSH_OWNER" ]; then
      filter="[.[] | select((.isCrossRepository | not) or ((.headRepositoryOwner.login // \"\") | ascii_downcase) == (\"$TARGET_PUSH_OWNER\" | ascii_downcase))]"
    fi
    if ! rows="$(gh pr list ${repo_args[@]+"${repo_args[@]}"} --state merged --limit 1000 --json number,mergeCommit,isCrossRepository,headRepositoryOwner --jq "$filter"' | .[] | select(.mergeCommit.oid != null) | ["pr", (.number | tostring), .mergeCommit.oid] | @tsv' 2>/dev/null)"; then
      candidates_ok=0; return 1
    fi
    candidate_rows="$rows"
  fi
  prepare_proof
  git for-each-ref --format='%(refname:strip=3)' refs/docket/landed/ > "$proof_dir/receipts" || { candidates_ok=0; return 1; }
  while IFS= read -r branch; do
    if verify_receipt "$common/docket/landed/$branch" "$branch" 2>/dev/null; then
      candidate_rows="$candidate_rows"$'\n'"local"$'\t'"$branch"$'\t'"$receipt_landed"
    fi
  done < "$proof_dir/receipts"
  return 0
}
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

integration_current() {
  [ "$integrated_proof" -eq 1 ] || return 0
  if git symbolic-ref --quiet "refs/heads/$br" >/dev/null 2>&1 || [ "$(git rev-parse --verify "refs/heads/$br" 2>/dev/null)" != "$tip" ]; then
    echo "keep $br: branch moved since integration proof"; return 1
  fi
  if ! git merge-base --is-ancestor "$proved_landing" "$integrated_base" 2>/dev/null; then
    echo "keep $br: base no longer contains the proved landing"; return 1
  fi
}

removed=0; kept=0
for br in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  selected=-1
  if [ "$integrated_count" -gt 0 ]; then
    i=0
    while [ "$i" -lt "$integrated_count" ]; do
      [ "${integrated_branches[$i]}" != "$br" ] || selected=$i
      i=$((i + 1))
    done
    [ "$selected" -ge 0 ] || continue
  fi
  [ "$br" = "$base" ] || [ "$br" = "main" ] || [ "$br" = "master" ] && continue
  [ -n "$DOCKET_TARGET" ] && [ "$br" = "$TARGET_BASE" ] && continue
  docket_branch "$br" || continue
  [ "$br" = "$current" ] && { echo "skip $br (checked out here)"; continue; }
  tip="$(git rev-parse "$br")"
  reason=""; integrated_proof=0; proved_landing=""
  if [ "$selected" -ge 0 ]; then
    if [ "$tip" != "${integrated_heads[$selected]}" ]; then
      echo "keep $br: branch moved since integration proof"
      kept=$((kept + 1)); continue
    fi
    reason="integrated at ${integrated_landings[$selected]} from exact worker tip $tip"
    integrated_proof=1
    proved_landing="${integrated_landings[$selected]}"
  fi
  receipt="$common/docket/landed/$br"
  if [ -z "$reason" ] && [ -f "$receipt" ]; then
    if verify_receipt "$receipt" "$br" && [ "$receipt_approved" = "$tip" ]; then
      reason="locally squash-landed at $receipt_landed from this exact tip"
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
    if ! merged="$(gh pr list ${repo_args[@]+"${repo_args[@]}"} --head "$br" --state merged --json number,headRefOid,isCrossRepository,headRepositoryOwner --jq "$pick"' | select(. != null) | "\(.number) \(.headRefOid)"' 2>/dev/null)"; then
      echo "keep $br: cannot check its merged PR history"
      kept=$((kept + 1)); continue
    fi
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
  if [ -z "$reason" ] && [ "$integrated_count" -eq 0 ]; then
    if ! load_candidates; then
      echo "keep $br: cannot read integration landing candidates"
      kept=$((kept + 1)); continue
    fi
    # An empty candidate set adds no new cleanup authority. Do not infer
    # historical incorporation from arbitrary commits on the base branch.
    if [ -n "$candidate_rows" ]; then
      if git symbolic-ref --quiet "refs/heads/$br" >/dev/null 2>&1; then
        echo "keep $br: symbolic refs are not worker candidates"
        kept=$((kept + 1)); continue
      fi
      if [ "$have_gh" -eq 1 ]; then
        if ! openpr="$(gh pr list ${repo_args[@]+"${repo_args[@]}"} --head "$br" --state open --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null)"; then
          echo "keep $br: cannot check for an open PR"
          kept=$((kept + 1)); continue
        fi
        if [ -n "$openpr" ]; then
          echo "keep $br: open PR #$openpr"
          kept=$((kept + 1)); continue
        fi
      elif [ "$local_only" -eq 0 ]; then
        echo "keep $br: forge unavailable; cannot check for an open PR"
        kept=$((kept + 1)); continue
      fi
      proof_error='no readable landing candidate'
      while IFS=$'\t' read -r kind label candidate_landing extra; do
        [ -z "$extra" ] || continue
        case "$kind" in pr|local) ;; *) continue ;; esac
        case "$candidate_landing" in ''|*[!0-9a-f]*) continue ;; esac
        [ "${#candidate_landing}" -eq 40 ] || [ "${#candidate_landing}" -eq 64 ] || continue
        if prove_integration "$tip" "$candidate_landing" 1; then
          if [ "$kind" = pr ]; then
            reason="changes present in PR #$label landing ${candidate_landing:0:12}"
          else
            reason="changes present in verified local landing ${candidate_landing:0:12} ($label)"
          fi
          integrated_proof=1; proved_landing="$candidate_landing"; break
        fi
      done <<< "$candidate_rows"
      if [ -z "$reason" ]; then
        echo "keep $br: no complete integration proof in available landings ($proof_error)"
        kept=$((kept + 1)); continue
      fi
    fi
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
      if ! integration_current; then
        kept=$((kept + 1)); continue
      fi
      if ! git worktree remove --force "$path"; then
        echo "keep $br: worktree removal failed; branch and receipt retained"
        kept=$((kept + 1)); continue
      fi
    fi
  else
    echo "delete branch $br ($reason)"
  fi
  if [ "$apply" -eq 1 ]; then
    if ! integration_current; then kept=$((kept + 1)); continue; fi
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
# An explicit selection does not prune unrelated registrations, fetch refs,
# or report claims in the sidecar's queues.
[ "$integrated_count" -eq 0 ] || exit 0

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
