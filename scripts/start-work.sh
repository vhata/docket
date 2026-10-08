#!/usr/bin/env bash
# Claim a queue entry: run the claim check, then create the branch and its
# worktree so the provisional claim is visible to other workers immediately.
#
# Usage: start-work.sh <queue> <slug> [--base main] [--dir .worktrees] [--no-check]
#   queue: todo | review | roadmap | fix | feature (becomes the branch prefix)
#   The branch is "<queue>/<slug>" and the worktree "<dir>/<queue>-<slug>".
#
# Prints the worktree path and the next steps. Does not push anything.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "start-work: not in a git repository" >&2; exit 2; }
cd "$root"
[ $# -ge 2 ] || { sed -n '2,10p' "$0"; exit 2; }
queue="$1"; slug="$2"; shift 2
base="main"; dir=".worktrees"; check=1
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --no-check) check=0; shift ;;
    *) echo "start-work: unknown argument $1" >&2; exit 2 ;;
  esac
done
echo "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || { echo "start-work: slug must be lowercase kebab-case" >&2; exit 2; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$check" -eq 1 ]; then
  "$here/claim-check.sh" "$slug" || { echo "start-work: resolve the existing claim first (or pass --no-check if the overlap is already coordinated)"; exit 1; }
fi

branch="$queue/$slug"
path="$dir/$queue-$slug"
if ! git check-ignore -q "$dir/probe" 2>/dev/null; then
  exclude="$(git rev-parse --git-common-dir)/info/exclude"
  mkdir -p "$(dirname "$exclude")"
  printf '%s/\n' "$dir" >> "$exclude"
  echo "start-work: $dir was not ignored; added it to the local git exclude file ($exclude). Add '$dir/' to .gitignore in your next PR."
fi
git fetch --quiet origin "$base" 2>/dev/null || true
start="origin/$base"; git rev-parse --verify --quiet "$start" >/dev/null || start="$base"
git worktree add --quiet -b "$branch" "$path" "$start"
echo "created branch $branch at $path (from $start)"
case "$queue" in
  todo) marker="Claims TODO: $slug" ;;
  review) marker="Claims review backlog: $slug" ;;
  roadmap) marker="Claims roadmap: $slug" ;;
  *) marker="" ;;
esac
echo "next: cd $path; run the repo's setup script if it exists (scripts/setup.sh); commit early; open a draft PR after the first meaningful commit${marker:+ with '$marker' in the body}."
