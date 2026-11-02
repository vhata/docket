#!/usr/bin/env bash
# Look for existing claims on one or more work slugs before starting them:
# open pull requests, local and remote branches, worktrees, and merged PRs
# (already done). For a review backlog slug, also checks every finding slug
# it maps.
#
# Usage: docket/scripts/claim-check.sh [--local] [--no-target] [--queue Q] [--self | --exclude-branch NAME] <slug> [slug...]
#   --self                 recheck from inside the claimed worktree: ignore the
#                          branch checked out here and its worktree, plus remote
#                          copies and same-repository open PRs of that branch
#                          whose tip is already in its local history
#   --exclude-branch NAME  the same exclusion for a named local branch
# A remote ref or PR with the same branch name but commits you do not have (or
# from a fork other than the target's push_remote) is another worker's claim
# and is still reported.
# A queue entry (TODO.md, review/BACKLOG.md, in the working tree or on
# origin/main when that ref exists) carrying a "PR:" line is claimed by those
# pull requests, in any mode. With --self or --exclude-branch in target mode
# it is only a note when every PR it names is an open PR headed by the own
# branch at an owned tip, from the managed repository or the configured fork;
# without gh it is a note.
# A branch, worktree or PR head branch counts when its last path component is
# the slug (todo/<slug>, origin/fix/<slug>, <slug>); a longer name that merely
# contains the slug does not. A PR body counts when a marker line names the slug.
# Slugs are lowercase kebab-case ([a-z0-9-]); anything else is rejected.
# Exit 1 when any claim or prior completion is found, 0 when all are free, 2
# when a forge query fails (ownership is then unverified).
# --local skips forge queries for repositories without a PR-capable remote.
# With no configured remotes this is automatic. Needs git; gh for PRs.
# With a managed-repository target (.docket-target; see target.sh), only the
# exact branch name docket would create counts: <branch_prefix><slug>, or
# <queue>/<slug> (all five queues unless --queue names one). Branches and
# worktrees are checked in the managed clone; PRs in the target repository by
# that head name only (its PR bodies carry no markers). An open PR is a claim;
# a merged one is a claim when you authored it and a note otherwise. --self
# must run from a managed worktree; an open PR headed by the own branch at an
# owned tip is the worker's own when it comes from the managed repository
# itself or, with push_remote set, from the fork that remote names
# (<push_owner>:<branch>). --no-target ignores the file.
set -euo pipefail

usage() { sed -n '2,39p' "$0"; exit 2; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
orig="$(pwd)"
self=""; self_here=0; local_only=0; no_target=""; queue=""
while [ $# -gt 0 ]; do
  case "$1" in
    --local) local_only=1; shift ;;
    --no-target) no_target=--no-target; shift ;;
    --queue)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      queue="$2"; shift 2 ;;
    --self) self_here=1; shift ;;
    --exclude-branch)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      self="$2"; self_here=0; shift 2 ;;
    --) shift; break ;;
    -*) echo "claim-check: unknown argument $1" >&2; usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage
# shellcheck source=target.sh
. "$here/target.sh"
docket_target_init "$here" "$no_target" || exit 2
root="$DOCKET_SIDECAR_ROOT"
backlog="$root/review/BACKLOG.md"
if [ -n "$DOCKET_TARGET" ]; then
  if [ "$self_here" -eq 1 ]; then
    docket_target_contains "$orig" || { echo "claim-check: --self in target mode must run from a worktree of the managed clone $TARGET_DIR (or use --exclude-branch NAME)" >&2; exit 2; }
    self="$(git -C "$orig" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  fi
  echo "note: managed-repository target $TARGET_REPO (clone $TARGET_DIR); PRs are matched by head branch only"
  cd "$TARGET_DIR"
else
  cd "$root"
  [ "$self_here" -eq 0 ] || self="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
fi
if [ "$self_here" -eq 1 ] && [ -z "$self" ]; then
  echo "claim-check: --self needs a checked-out branch, but no branch is checked out here (detached HEAD)" >&2; exit 2
fi
case "$self" in *\"*|*\\*) echo "claim-check: unsupported character in branch name $self" >&2; exit 2 ;; esac
tab="$(printf '\t')"
[ -n "$(git remote)" ] || local_only=1

# Own-branch exclusion. A ref or PR tip is "owned" when it is a commit of the
# own branch that the base branch lacks: the worker's own push. A tip carrying
# foreign commits, or nothing beyond the base, may be another worker's claim
# under the same name and is still reported.
self_tip=""; base_tip=""
if [ -n "$self" ]; then
  self_tip="$(git rev-parse --verify --quiet "refs/heads/$self^{commit}" || true)"
  base_refs="refs/heads/main"
  [ "$local_only" -eq 1 ] || base_refs="refs/remotes/origin/HEAD refs/remotes/origin/main $base_refs"
  [ -z "$DOCKET_TARGET" ] || base_refs="refs/remotes/$TARGET_REMOTE/$TARGET_BASE refs/heads/$TARGET_BASE"
  for b in $base_refs; do
    base_tip="$(git rev-parse --verify --quiet "$b^{commit}" || true)"
    [ -z "$base_tip" ] || break
  done
  echo "note: ignoring own branch $self and its worktree, and remote copies or open PRs of it whose tip is already in its local history"
fi
owned() {
  [ -n "$self_tip" ] || return 1
  git cat-file -e "$1^{commit}" 2>/dev/null || return 1
  git merge-base --is-ancestor "$1" "$self_tip" || return 1
  if [ -n "$base_tip" ] && git merge-base --is-ancestor "$1" "$base_tip"; then return 1; fi
  return 0
}

# Never let an inherited GH_REPO redirect queries to another repository. In
# target mode every query names the target, and GH_REPO is pinned to it too.
have_gh=0
if [ -n "$DOCKET_TARGET" ]; then
  export GH_REPO="$TARGET_REPO"
  if [ "$local_only" -eq 0 ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh repo view "$TARGET_REPO" >/dev/null 2>&1; then have_gh=1; fi
else
  unset GH_REPO
  if [ "$local_only" -eq 0 ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then have_gh=1; fi
fi
[ "$local_only" -eq 0 ] || echo "note: local review mode; forge queries are disabled"
[ "$have_gh" -eq 1 ] || echo "note: no authenticated gh for this repository (no remote, not logged in, or gh missing); pull requests were NOT checked, so this claim check covers branches and worktrees only"

expand() {
  # Print the slug plus any finding slugs its backlog entry maps.
  echo "$1"
  if [ -f "$backlog" ]; then
    awk -v slug="$1" '
      /^- / { inblock = ($0 ~ "^- \\[[A-Z][A-Z0-9_-]*\\] `" slug "`") }
      inblock && /^  - Findings:/ { s = $0; while (match(s, /`[^`]+`/)) { print substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) } }
    ' "$backlog"
  fi
}

# Open PRs headed by the own branch are tagged "own<TAB>sha<TAB>repo<TAB>" by
# jq; drop_own removes them only for this repository and an owned tip.
own_pre=""; own_post=""; this_repo=""
if [ -n "$self" ] && [ "$have_gh" -eq 1 ] && [ -z "$DOCKET_TARGET" ]; then
  own_pre="(if .head.ref == \"$self\" then \"own\\t\\(.head.sha)\\t\\(.head.repo.full_name // \"\")\\t\" else \"\" end) + ("
  own_post=")"
  this_repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
drop_own() {
  while IFS= read -r line; do
    case "$line" in
      "own$tab"*)
        rest="${line#own"$tab"}"; sha="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"; repo="${rest%%"$tab"*}"; text="${rest#*"$tab"}"
        if [ -n "$this_repo" ] && [ "$repo" = "$this_repo" ] && owned "$sha"; then continue; fi
        printf '%s\n' "$text" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}
# The PR: line of the entry for a slug in the queue file on stdin, if any.
queue_pr() {
  awk -v slug="$1" '
    /^- / { inblock = ($0 ~ "^- \\[[A-Z][A-Z0-9_-]*\\] `" slug "`") ; next }
    /^#/ { inblock = 0 }
    inblock && /^  - PR:/ { v = $0; sub(/^  - PR:[ \t]*/, "", v); print v; exit }
  '
}
# Target mode: succeeds when every PR on a PR: line is an open PR in the
# target, from the target itself or the configured fork, headed by the own
# branch at an owned tip.
own_prs() {
  local ref out st head oid cross owner
  for ref in $(printf '%s\n' "$1" | tr ',' ' '); do
    [ "${ref%%#*}" = "$TARGET_REPO" ] || return 1
    out="$(gh pr view "${ref##*#}" --repo "$TARGET_REPO" --json state,headRefName,headRefOid,isCrossRepository,headRepositoryOwner \
      --jq '"\(.state)\t\(.headRefName)\t\(.headRefOid)\t\(.isCrossRepository)\t\(.headRepositoryOwner.login // "-")"' < /dev/null)" || fail_query
    IFS="$tab" read -r st head oid cross owner <<< "$out"
    [ "$st" = OPEN ] && [ "$head" = "$self" ] && docket_target_own_head "$cross" "$owner" && owned "$oid" || return 1
  done
}
fail_query() { echo "claim-check: hosted PR query failed; ownership remains unverified" >&2; exit 2; }

# Target mode: the branch names docket would create for the slug.
target_names() {
  local q
  if [ -n "$TARGET_BRANCH_PREFIX" ]; then printf '%s%s\n' "$TARGET_BRANCH_PREFIX" "$1"
  elif [ -n "$queue" ]; then printf '%s/%s\n' "$queue" "$1"
  else for q in todo review roadmap fix task; do printf '%s/%s\n' "$q" "$1"; done
  fi
}
# PRs in the managed repository headed by one of those names. Each line is
# state, number, draft, cross-repository, head repository owner, head sha,
# head branch, merge date, author (- when absent; no field may be empty, since
# read collapses tabs), title.
target_prs() {
  local cand
  for cand in $(target_names "$1"); do
    gh pr list --repo "$TARGET_REPO" --head "$cand" --state all --limit 100 \
      --json number,state,isDraft,isCrossRepository,headRepositoryOwner,headRefOid,headRefName,title,mergedAt,author \
      --jq '.[] | "\(.state)\t\(.number)\t\(.isDraft)\t\(.isCrossRepository)\t\(.headRepositoryOwner.login // "-")\t\(.headRefOid)\t\(.headRefName)\t\((.mergedAt // "-")[0:10])\t\(.author.login // "-")\t\(.title)"' || return 1
  done
}
me=""; me_known=0

claims=0
for requested in "$@"; do
  for slug in $(expand "$requested"); do
    # The slug is interpolated into jq programs and regular expressions below;
    # only kebab-case is safe there, and only kebab-case is a valid slug.
    echo "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || { echo "claim-check: slug '$slug' is not lowercase kebab-case" >&2; exit 2; }
    [ "$slug" = "$requested" ] && label="$slug" || label="$slug (finding mapped by $requested)"
    echo "== $label"
    for qf in TODO.md review/BACKLOG.md; do
      where="$qf"; recorded=""
      [ ! -f "$root/$qf" ] || recorded="$(queue_pr "$slug" < "$root/$qf")"
      if [ -z "$recorded" ] && git -C "$root" rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; then
        recorded="$(git -C "$root" show "refs/remotes/origin/main:$qf" 2>/dev/null | queue_pr "$slug" || true)"
        where="$qf on origin/main"
      fi
      [ -n "$recorded" ] || continue
      if [ -n "$self" ] && [ "$have_gh" -eq 0 ]; then
        echo "  note: the entry in $where records PR: $recorded; taken to be your own, unverified without gh (confirm it is)"
      elif [ -n "$self" ] && [ -n "$DOCKET_TARGET" ] && own_prs "$recorded"; then
        echo "  note: the entry in $where records PR: $recorded, your own open PR"
      else
        echo "  queue entry in $where is claimed by PR: $recorded"
        claims=$((claims + 1))
      fi
    done
    if [ "$have_gh" -eq 1 ] && [ -n "$DOCKET_TARGET" ]; then
      prs="$(target_prs "$slug")" || fail_query
      if [ "$me_known" -eq 0 ] && [ -n "$prs" ]; then
        me="$(gh api user --jq .login 2>/dev/null || true)"; me_known=1
      fi
      while IFS="$tab" read -r state num draft cross howner oid head merged author title; do
        case "$state" in
          OPEN)
            if [ -n "$self" ] && [ "$head" = "$self" ] && docket_target_own_head "$cross" "$howner" && owned "$oid"; then continue; fi
            [ "$draft" = true ] && draft=draft || draft=ready
            [ "$cross" = true ] && head="$howner:$head"
            echo "  open PR $TARGET_REPO#$num [$draft] $head: $title"; claims=$((claims + 1)) ;;
          MERGED|CLOSED)
            # Without a known login every merged PR counts, the safe side.
            if [ -n "$me" ] && [ "$author" != "$me" ]; then
              [ "$state" = MERGED ] && kind=merged || kind=closed
              echo "  note: $kind PR $TARGET_REPO#$num by $author had head $head: $title"
            elif [ "$state" = MERGED ]; then
              echo "  merged PR $TARGET_REPO#$num ($merged) carried this slug: $title"
              echo "  -> confirm the queue entry is still current (a remainder may have been filed) before claiming"
              claims=$((claims + 1))
            fi ;;
        esac
      done <<< "$prs"
    elif [ "$have_gh" -eq 1 ]; then
      # Paginate the forge's pull records directly: search does not index head
      # branches, and indexing delays must not hide a freshly published claim.
      # Open PRs: a claim is a body marker naming the slug or a head branch whose
      # last path component is the slug; a bare mention is only a note.
      claim_re="(Claims|Resolves|Partially resolves|Remaining|Files) (TODO|review backlog|review finding|roadmap): $slug(\$|[^a-z0-9-])"
      head_re="(^|/)$slug\$"
      claimsline="$(gh api --paginate 'repos/{owner}/{repo}/pulls?state=open&per_page=100' \
        --jq ".[] | select((((.body // \"\") | test(\"$claim_re\")) or (.head.ref | test(\"$head_re\")))) | $own_pre\"  open PR #\\(.number) [\\(if .draft then \"draft\" else \"ready\" end)] \\(.head.ref): \\(.title)\"$own_post" | drop_own || fail_query)"
      if [ -n "$claimsline" ]; then echo "$claimsline"; claims=$((claims + 1)); fi
      mentions="$(gh api --paginate 'repos/{owner}/{repo}/pulls?state=open&per_page=100' \
        --jq ".[] | select(((.title | contains(\"$slug\")) or ((.body // \"\") | contains(\"$slug\"))) and (((((.body // \"\") | test(\"$claim_re\")) or (.head.ref | test(\"$head_re\"))) | not))) | $own_pre\"  note: open PR #\\(.number) mentions this slug: \\(.title)\"$own_post" | drop_own || fail_query)"
      [ -n "$mentions" ] && echo "$mentions"
      # Merged PRs: already resolved when a merged body resolves the slug or its head branch carried it.
      done_re="(Resolves|Partially resolves) (TODO|review backlog|review finding|roadmap): $slug(\$|[^a-z0-9-])"
      done_line="$(gh api --paginate 'repos/{owner}/{repo}/pulls?state=closed&per_page=100' \
        --jq ".[] | select(.merged_at != null and ((((.body // \"\") | test(\"$done_re\")) or (.head.ref | test(\"$head_re\"))))) | \"  merged PR #\\(.number) (\\(.merged_at[0:10])) resolved or carried this slug: \\(.title)\"" || fail_query)"
      if [ -n "$done_line" ]; then echo "$done_line"; echo "  -> confirm the queue entry is still current (a remainder may have been filed) before claiming"; claims=$((claims + 1)); fi
    fi
    # Local squash receipts survive branch cleanup. Verify their commit proof,
    # rather than inferring squash landing from patch similarity.
    common="$(git rev-parse --git-common-dir)"
    for proof in $(git for-each-ref --format='%(refname)' refs/docket/landed/); do
      landed_branch="${proof#refs/docket/landed/}"
      [ "${landed_branch##*/}" = "$slug" ] || continue
      receipt="$common/docket/landed/$landed_branch"
      [ -f "$receipt" ] || continue
      receipt_base="$(sed -n '1p' "$receipt")"; before="$(sed -n '2p' "$receipt")"
      approved="$(sed -n '3p' "$receipt")"; landed="$(sed -n '4p' "$receipt")"
      if [ "$(wc -l < "$receipt" | tr -d ' ')" = 4 ] &&
         [ "$(git rev-parse "$proof")" = "$approved" ] &&
         git cat-file -e "$landed^{commit}" 2>/dev/null &&
         [ "$(git show -s --format=%P "$landed")" = "$before" ] &&
         git merge-base --is-ancestor "$before" "$approved" &&
         git merge-base --is-ancestor "$landed" "refs/heads/$receipt_base" &&
         [ "$(git rev-parse "$landed^{tree}")" = "$(git rev-parse "$approved^{tree}")" ]; then
        echo "  locally landed $landed_branch at $landed; confirm any queue entry is a current remainder"
        claims=$((claims + 1))
      fi
    done
    if [ "$local_only" -eq 1 ] && git rev-parse --verify --quiet refs/heads/main >/dev/null; then
      resolutions="$(git log refs/heads/main --format='%H%n%B' --extended-regexp --grep="^(Resolves|Partially resolves) (TODO|review backlog|review finding|roadmap): $slug$" --max-count=1)"
      if [ -n "$resolutions" ]; then
        echo "  local main records resolution of $slug; confirm any queue entry is a current remainder"
        claims=$((claims + 1))
      fi
    fi
    # Branches whose last path component is the slug (todo/<slug>, origin/fix/<slug>, <slug>).
    # Whole-component matching: a slug that is a substring of another branch name is not a claim.
    # With --self, refs/heads/<self> is skipped always and a remote copy only when its tip is owned.
    # In target mode only the exact names docket would create, locally or on
    # the target remote, count. One awk pass filters every ref.
    names=""
    [ -z "$DOCKET_TARGET" ] || names="$(target_names "$slug" | tr '\n' ' ')"
    branches="$(git for-each-ref --format='%(refname)%09%(objectname)' refs/heads refs/remotes 2>/dev/null |
      awk -F "$tab" -v slug="$slug" -v names="$names" -v remote="${TARGET_REMOTE:-}" '
        BEGIN { n = split(names, a, " "); for (i = 1; i <= n; i++) { want["refs/heads/" a[i]] = 1; want["refs/remotes/" remote "/" a[i]] = 1 } }
        {
          if (names != "") { if (!($1 in want)) next }
          else {
            s = $1; sub(/^refs\/(heads|remotes)\//, "", s)
            if (!(s == slug || (length(s) > length(slug) && substr(s, length(s) - length(slug)) == "/" slug))) next
          }
          print
        }' | while IFS="$tab" read -r ref sha; do
      short="${ref#refs/heads/}"; short="${short#refs/remotes/}"
      if [ -n "$self" ]; then
        [ "$ref" = "refs/heads/$self" ] && continue
        if [ "${ref#refs/remotes/}" != "$ref" ] && [ "${short#*/}" = "$self" ] && owned "$sha"; then continue; fi
      fi
      printf '%s\n' "$short"
    done || true)"
    if [ -n "$branches" ]; then echo "$branches" | sed 's/^/  branch: /'; claims=$((claims + 1)); fi
    # Worktrees checked out on such a branch, or whose directory is named <queue>-<slug> or <slug>.
    # The main worktree is never a task worktree: it matches only through its branch, never its directory name.
    # With --self, the worktree checked out on the own branch is skipped.
    wts="$(git worktree list --porcelain | awk -v brre="^refs/heads/([^/]+/)?${slug}\$" -v dirre="^((todo|review|roadmap|fix|task)-)?${slug}\$" -v own="${self:+refs/heads/$self}" -v names="$names" '
      BEGIN { k = split(names, a, " "); for (i = 1; i <= k; i++) want["refs/heads/" a[i]] = 1 }
      function flush(   n, parts, onbranch) {
        if (p == "") return
        n = split(p, parts, "/")
        onbranch = (names != "") ? (b in want) : (b ~ brre)
        if (!(own != "" && b == own) && (onbranch || (!ismain && parts[n] ~ dirre))) print p (b != "" ? " [" substr(b, 12) "]" : " (detached)")
        p = ""; b = ""
      }
      /^worktree / { flush(); p = substr($0, 10); ismain = (++count == 1) }
      /^branch / { b = substr($0, 8) }
      END { flush() }')"
    if [ -n "$wts" ]; then echo "$wts" | sed 's/^/  worktree: /'; claims=$((claims + 1)); fi
  done
done

if [ "$claims" -gt 0 ]; then
  echo "result: existing claim(s) found. Do not start this work without resolving the overlap."
  exit 1
fi
if [ "$have_gh" -eq 1 ]; then echo "result: no existing claims found (PRs, branches, worktrees)"; else echo "result: no local claims found (PRs NOT checked)"; fi
