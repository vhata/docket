#!/usr/bin/env bash
# Claim a queue entry: run the claim check, then create the branch and its
# worktree so the provisional claim is visible to other workers immediately.
#
# Usage: docket/scripts/start-work.sh <queue> <slug> [--base main] [--dir .worktrees] [--no-check] [--local]
#   queue: todo | review | roadmap | fix | task (becomes the branch prefix)
#   The branch is "<queue>/<slug>" and the worktree "<dir>/<queue>-<slug>".
#
# --local uses the local base and skips forge queries; automatic without remotes.
# Prints the worktree path and the next steps. Does not push anything.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "start-work: not in a git repository" >&2; exit 2; }
cd "$root"
[ $# -ge 2 ] || { sed -n '2,10p' "$0"; exit 2; }
queue="$1"; slug="$2"; shift 2
base="main"; dir=".worktrees"; check=1; local_only=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --local) local_only=1; shift ;;
    --no-check) check=0; shift ;;
    *) echo "start-work: unknown argument $1" >&2; exit 2 ;;
  esac
done
echo "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || { echo "start-work: slug must be lowercase kebab-case" >&2; exit 2; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "$(git remote)" ] || local_only=1
claim_args=()
[ "$local_only" -eq 0 ] || claim_args=(--local)
if [ "$check" -eq 1 ]; then
  "$here/claim-check.sh" ${claim_args[@]+"${claim_args[@]}"} "$slug" || { echo "start-work: resolve the existing claim first (or pass --no-check if the overlap is already coordinated)"; exit 1; }
fi

branch="$queue/$slug"
path="$dir/$queue-$slug"
# Make sure the worktree directory and the local docket state directory are
# ignored. Only directories git does not already ignore are appended, so
# repeated runs never duplicate a line. A worktree directory outside the
# repository needs no ignoring, and git cannot answer for it, so it is skipped;
# one inside is checked by its path relative to the root.
exclude="$(git rev-parse --git-path info/exclude)"
ignore=(".docket")
root_abs="$(pwd -P)"
dir_abs="$(mkdir -p "$dir" && cd "$dir" && pwd -P)"
case "$dir_abs" in
  "$root_abs"/*) ignore=("${dir_abs#"$root_abs"/}" "${ignore[@]}") ;;
esac
for ignored in "${ignore[@]}"; do
  if ! git check-ignore -q "$ignored/probe" 2>/dev/null; then
    mkdir -p "$(dirname "$exclude")"
    printf '%s/\n' "$ignored" >> "$exclude"
    echo "start-work: $ignored was not ignored; added it to the local git exclude file ($exclude). Add '$ignored/' to .gitignore in your next PR."
  fi
done
start="$base"
if [ "$local_only" -eq 0 ] && git remote get-url origin >/dev/null 2>&1; then
  git fetch --quiet origin "$base" 2>/dev/null || true
  git rev-parse --verify --quiet "refs/remotes/origin/$base" >/dev/null && start="origin/$base"
fi
git worktree add --quiet --no-track -b "$branch" "$path" "$start"
# Atomic cleanup preserves branch metadata to avoid erasing a concurrent
# recreation's settings. A reused name may therefore inherit an old upstream
# despite --no-track. Only clear tracking on the branch just created here.
for setting in remote merge; do
  if git config --get-all "branch.$branch.$setting" >/dev/null; then
    git config --unset-all "branch.$branch.$setting"
  fi
done
echo "created branch $branch at $path (from $start)"
case "$queue" in
  todo) marker="Claims TODO: $slug" ;;
  review) marker="Claims review backlog: $slug" ;;
  roadmap) marker="Claims roadmap: $slug" ;;
  *) marker="" ;;
esac
if [ "$local_only" -eq 1 ]; then
  echo "next: cd $path; run scripts/setup.sh if present; commit early; save the title in .docket/title-$slug.txt and description in .docket/change-$slug.md${marker:+ with '$marker'}; leave the branch and worktree for review and approval."
else
  echo "next: cd $path; run scripts/setup.sh if present; commit early; open a draft PR after the first meaningful commit${marker:+ with '$marker' in the body}."
fi
