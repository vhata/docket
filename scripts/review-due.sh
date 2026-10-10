#!/usr/bin/env bash
# Report how far the codebase has moved since the last recorded codebase
# review and say whether an incremental or full review is due.
#
# Usage: review-due.sh [--index review/README.md] [--paths "src crates"] [--base main]
#
# Reads the review index for the latest review and the latest FULL review
# (first table rows with a backticked commit), measures commits, changed files
# and inserted lines since the latest review, and source churn since the latest
# full review so that frequent incrementals cannot hide cumulative change.
# A reviewed commit that is missing or not an ancestor of the base is reported
# as a lost baseline; figures are then merge-base approximations only.
# Thresholds (override with environment variables):
#   REVIEW_DUE_COMMITS=25     commits since last review -> incremental due
#   REVIEW_DUE_DAYS=21        days since last review    -> incremental due
#   REVIEW_FULL_FRACTION=0.33 changed source lines / current source lines -> full due
#
# Always exits 0 (it is a report, not a gate) except on usage errors.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
index="review/README.md"; paths=""; base="HEAD"
while [ $# -gt 0 ]; do
  case "$1" in
    --index) index="$2"; shift 2 ;;
    --paths) paths="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "review-due: unknown argument $1" >&2; exit 2 ;;
  esac
done
: "${REVIEW_DUE_COMMITS:=25}" "${REVIEW_DUE_DAYS:=21}" "${REVIEW_FULL_FRACTION:=0.33}"

if [ ! -f "$index" ]; then
  echo "no review index at $index: no codebase review has been recorded. A full review is due."
  exit 0
fi

rows="$(grep -E '^\|' "$index" | grep -E '`[0-9a-f]{7,40}`' || true)"
if [ -z "$rows" ]; then
  echo "review index has no row with a reviewed commit: treat as no review recorded. A full review is due."
  exit 0
fi
latest="$(echo "$rows" | head -1)"
latest_full="$(echo "$rows" | grep -iE '\|[[:space:]]*full[[:space:]]*\|' | head -1 || true)"
field() { echo "$1" | grep -oE '`[0-9a-f]{7,40}`' | head -1 | tr -d '\`'; }
datef() { echo "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || true; }
rev="$(field "$latest")"; date="$(datef "$latest")"
type="$(echo "$latest" | grep -oiE '\b(full|incremental)\b' | head -1 || echo unknown)"
full_rev=""; full_date=""
if [ -n "$latest_full" ]; then full_rev="$(field "$latest_full")"; full_date="$(datef "$latest_full")"; fi

echo "latest review: $type at $rev${date:+ on $date}"
[ -n "$full_rev" ] && [ "$full_rev" != "$rev" ] && echo "latest full review: $full_rev${full_date:+ on $full_date}"
[ -z "$full_rev" ] && echo "no full review recorded in the index"

exact=1
for r in $rev $full_rev; do
  if ! git cat-file -e "$r^{commit}" 2>/dev/null; then
    echo "reviewed commit $r is not in this repository (deleted branch, or never fetched). Its exact tree cannot be compared."
    exact=0
  elif ! git merge-base --is-ancestor "$r" "$base"; then
    echo "reviewed commit $r is not an ancestor of $base (reviews of unmerged branches are squashed away). The exact delta since it cannot be measured from history."
    exact=0
  fi
done
if [ "$exact" -eq 0 ]; then
  echo "verdict: BASELINE LOST. Either compare the reviewed tree exactly (git diff <reviewed-tree> $base, with the tree retrieved from a bundle or the PR) and record the correspondence, or reset with a FULL review. Figures below, if any, are merge-base approximations only."
  # Fall through with merge-base so the reader still sees the size of the problem.
  git cat-file -e "$rev^{commit}" 2>/dev/null || exit 0
  rev="$(git merge-base "$rev" "$base")" || { echo "reviewed commit shares no history with $base: no approximation is possible."; exit 0; }
  if [ -n "$full_rev" ] && git cat-file -e "$full_rev^{commit}" 2>/dev/null; then full_rev="$(git merge-base "$full_rev" "$base")" || full_rev=""; else full_rev=""; fi
fi

commits="$(git rev-list --count "$rev..$base")"
files="$(git diff --name-only "$rev" "$base" | wc -l | tr -d ' ')"
stat="$(git diff --shortstat "$rev" "$base" || true)"
ins="$(echo "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)"
del="$(echo "$stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)"

# Source lines: tracked files under --paths (or everything) minus docs, lockfiles and queue files.
if [ -n "$paths" ]; then
  # shellcheck disable=SC2086
  list="$(git ls-files $paths)"
else
  list="$(git ls-files)"
fi
src_files="$(echo "$list" | grep -Ev '(^|/)(docs|review|plans|\.github)/|\.md$|\.lock$|lock\.(json|yaml)$|\.sum$|\.svg$|\.png$|\.jpg$' || true)"
src_lines=0
if [ -n "$src_files" ]; then
  src_lines="$(echo "$src_files" | tr '\n' '\0' | { xargs -0 cat 2>/dev/null || true; } | wc -l | tr -d ' ')"
fi
# grep exits 1 when no source file changed; under pipefail that would abort the script.
churn_since() { git diff --numstat "$1" "$base" -- $( [ -n "$paths" ] && echo "$paths" ) | { grep -Ev '(^|/)(docs|review|plans|\.github)/|\.md$|\.lock$|lock\.(json|yaml)$|\.sum$' || true; } | awk '{ if ($1 != "-") s += $1 } END { print s + 0 }'; }
changed_src="$(churn_since "$rev")"
changed_since_full="$changed_src"; [ -n "$full_rev" ] && changed_since_full="$(churn_since "$full_rev")"

days=""
if [ -n "$date" ]; then
  if then_s="$(date -j -f %Y-%m-%d "$date" +%s 2>/dev/null || date -d "$date" +%s 2>/dev/null)"; then
    days=$(( ( $(date +%s) - then_s ) / 86400 ))
  fi
fi

echo "since then: $commits commits, $files files changed, +$ins/-$del lines${days:+, $days days}"
if [ "$src_lines" -gt 0 ]; then
  frac="$(awk -v a="$changed_since_full" -v b="$src_lines" 'BEGIN { printf "%.2f", a / b }')"
  echo "source churn since latest review: $changed_src inserted source lines; since latest full review: $changed_since_full, against $src_lines current source lines (ratio $frac)"
else
  frac=0
fi

merged_fixes="$(git log --oneline "$rev..$base" --grep='Resolves review finding:' | wc -l | tr -d ' ')"
[ "$merged_fixes" -gt 0 ] && echo "$merged_fixes merged commit(s) claim to resolve review findings; closure is unverified until the next incremental review."

verdict="no review due"
if awk -v f="$frac" -v t="$REVIEW_FULL_FRACTION" 'BEGIN { exit !(f + 0 >= t + 0) }'; then
  verdict="FULL review due (source churn since the last full review, ratio $frac >= $REVIEW_FULL_FRACTION)"
elif [ "$commits" -ge "$REVIEW_DUE_COMMITS" ]; then
  verdict="INCREMENTAL review due ($commits commits >= $REVIEW_DUE_COMMITS)"
elif [ -n "$days" ] && [ "$days" -ge "$REVIEW_DUE_DAYS" ]; then
  verdict="INCREMENTAL review due ($days days >= $REVIEW_DUE_DAYS)"
elif [ "$merged_fixes" -gt 0 ]; then
  verdict="INCREMENTAL review suggested to verify claimed finding closures"
fi
if [ "$exact" -eq 0 ]; then echo "approximate verdict (merge-base figures): $verdict"; else echo "verdict: $verdict"; fi
