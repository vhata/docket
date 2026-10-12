#!/usr/bin/env bash
# Look for existing claims on one or more work slugs before starting them:
# open pull requests, local and remote branches, worktrees, and merged PRs
# (already done). For a review backlog slug, also checks every finding slug
# it maps.
#
# Usage: docket/scripts/claim-check.sh [--self | --exclude-branch NAME] <slug> [slug...]
#   --self                 recheck from inside the claimed worktree: ignore the
#                          branch checked out here and its worktree, plus remote
#                          copies and same-repository open PRs of that branch
#                          whose tip is already in its local history
#   --exclude-branch NAME  the same exclusion for a named local branch
# A remote ref or PR with the same branch name but commits you do not have (or
# from a fork) is another worker's claim and is still reported.
# A branch, worktree or PR head branch counts when its last path component is
# the slug (todo/<slug>, origin/fix/<slug>, <slug>); a longer name that merely
# contains the slug does not. A PR body counts when a marker line names the slug.
# Slugs are lowercase kebab-case ([a-z0-9-]); anything else is rejected.
# Exit 1 when any claim or prior completion is found, 0 when all are free, 2
# when a forge query fails (ownership is then unverified).
# Needs git; uses gh when available and says so when it is not.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
usage() { sed -n '2,21p' "$0"; exit 2; }
self=""
while [ $# -gt 0 ]; do
  case "$1" in
    --self)
      self="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
      [ -n "$self" ] || { echo "claim-check: --self needs a checked-out branch, but no branch is checked out here (detached HEAD)" >&2; exit 2; }
      shift ;;
    --exclude-branch)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      self="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "claim-check: unknown argument $1" >&2; usage ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || usage
case "$self" in *\"*|*\\*) echo "claim-check: unsupported character in branch name $self" >&2; exit 2 ;; esac
tab="$(printf '\t')"

# Own-branch exclusion. A ref or PR tip is "owned" when it is a commit of the
# own branch that the base branch lacks: the worker's own push. A tip carrying
# foreign commits, or nothing beyond the base, may be another worker's claim
# under the same name and is still reported.
self_tip=""; base_tip=""
if [ -n "$self" ]; then
  self_tip="$(git rev-parse --verify --quiet "refs/heads/$self^{commit}" || true)"
  for b in refs/remotes/origin/HEAD refs/remotes/origin/main refs/heads/main; do
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

have_gh=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && gh repo view >/dev/null 2>&1; then have_gh=1; fi
[ "$have_gh" -eq 1 ] || echo "note: no authenticated gh for this repository (no remote, not logged in, or gh missing); pull requests were NOT checked, so this claim check covers branches and worktrees only"

expand() {
  # Print the slug plus any finding slugs its backlog entry maps.
  echo "$1"
  if [ -f review/BACKLOG.md ]; then
    awk -v slug="$1" '
      /^- / { inblock = ($0 ~ "^- \\[[A-Z][A-Z0-9_-]*\\] `" slug "`") }
      inblock && /^  - Findings:/ { s = $0; while (match(s, /`[^`]+`/)) { print substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) } }
    ' review/BACKLOG.md
  fi
}

# Open PRs headed by the own branch are tagged "own<TAB>sha<TAB>repo<TAB>" by
# jq; drop_own removes them only for this repository and an owned tip.
own_pre=""; own_post=""; this_repo=""
if [ -n "$self" ] && [ "$have_gh" -eq 1 ]; then
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
fail_query() { echo "claim-check: hosted PR query failed; ownership remains unverified" >&2; exit 2; }

claims=0
for requested in "$@"; do
  for slug in $(expand "$requested"); do
    # The slug is interpolated into jq programs and regular expressions below;
    # only kebab-case is safe there, and only kebab-case is a valid slug.
    echo "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || { echo "claim-check: slug '$slug' is not lowercase kebab-case" >&2; exit 2; }
    [ "$slug" = "$requested" ] && label="$slug" || label="$slug (finding mapped by $requested)"
    echo "== $label"
    if [ "$have_gh" -eq 1 ]; then
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
    # Branches whose last path component is the slug (todo/<slug>, origin/fix/<slug>, <slug>).
    # Whole-component matching: a slug that is a substring of another branch name is not a claim.
    # With --self, refs/heads/<self> is skipped always and a remote copy only when its tip is owned.
    branches="$(git for-each-ref --format='%(refname)%09%(objectname)' refs/heads refs/remotes 2>/dev/null | while IFS="$tab" read -r ref sha; do
      short="${ref#refs/heads/}"; short="${short#refs/remotes/}"
      echo "$short" | grep -Eq "(^|/)${slug}\$" || continue
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
    wts="$(git worktree list --porcelain | awk -v brre="^refs/heads/([^/]+/)?${slug}\$" -v dirre="^((todo|review|roadmap|fix|task)-)?${slug}\$" -v own="${self:+refs/heads/$self}" '
      function flush(   n, parts) {
        if (p == "") return
        n = split(p, parts, "/")
        if (!(own != "" && b == own) && (b ~ brre || (!ismain && parts[n] ~ dirre))) print p (b != "" ? " [" substr(b, 12) "]" : " (detached)")
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
