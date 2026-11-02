#!/usr/bin/env bash
# Claim a queue entry: run the claim check, then create the branch and its
# worktree so the provisional claim is visible to other workers immediately.
#
# Usage: docket/scripts/start-work.sh <queue> <slug> [--base main] [--dir .worktrees] [--no-check] [--local] [--no-target]
#   queue: todo | review | roadmap | fix | task (becomes the branch prefix)
#   The branch is "<queue>/<slug>" and the worktree "<dir>/<queue>-<slug>".
#
# --local uses the local base and skips forge queries; automatic without remotes.
# With a managed-repository target (.docket-target; see target.sh) the branch
# and worktree are created in the managed clone from <remote>/<base>: the
# branch is "<branch_prefix><slug>" when a prefix is set, the worktree goes in
# worktree_dir, and --base and --dir override the target's values. The new
# branch is marked with "git config branch.<name>.docket true" in the clone;
# cleanup-landed.sh touches only marked branches there. The sidecar's queue
# entry is the claim record: once the PR is open, a "PR: owner/repo#N" line
# on the entry, committed directly to the sidecar's main. The next steps name
# the push remote: push_remote when the target sets one (a fork, whose PR
# head is <push_owner>:<branch>), otherwise remote. --no-target ignores the
# target.
# A relative --dir is taken from the repository root, or in target mode from
# the current directory.
# Prints the worktree path and the next steps. Does not push anything.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
orig="$(pwd)"
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "start-work: not in a git repository" >&2; exit 2; }
[ $# -ge 2 ] || { sed -n '2,23p' "$0"; exit 2; }
queue="$1"; slug="$2"; shift 2
base=""; dir=""; check=1; local_only=0; no_target=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --dir) dir="$2"; shift 2 ;;
    --local) local_only=1; shift ;;
    --no-check) check=0; shift ;;
    --no-target) no_target=--no-target; shift ;;
    *) echo "start-work: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$queue" in
  todo|review|roadmap|fix|task) ;;
  *) echo "start-work: queue must be one of todo, review, roadmap, fix, task (got '$queue')" >&2; exit 2 ;;
esac
echo "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || { echo "start-work: slug must be lowercase kebab-case" >&2; exit 2; }
# shellcheck source=target.sh
. "$here/target.sh"
docket_target_init "$here" "$no_target" || exit 2
root="$DOCKET_SIDECAR_ROOT"
cd "$root"
if [ -n "$DOCKET_TARGET" ]; then
  # In target mode the caller may be anywhere, so a relative --dir is taken
  # from the current directory; otherwise from the root, as always.
  case "$dir" in ""|/*) ;; *) dir="$orig/$dir" ;; esac
  [ -n "$base" ] || base="$TARGET_BASE"
  [ -n "$dir" ] || dir="$TARGET_WORKTREE_DIR"
  repo_dir="$TARGET_DIR"; remote="$TARGET_REMOTE"
  branch="$(docket_target_branch "$queue" "$slug")"
else
  [ -n "$base" ] || base="main"
  [ -n "$dir" ] || dir=".worktrees"
  repo_dir="$root"; remote="origin"
  branch="$queue/$slug"
fi

[ -n "$(git -C "$repo_dir" remote)" ] || local_only=1
claim_args=()
[ "$local_only" -eq 0 ] || claim_args=(--local)
[ -z "$no_target" ] || claim_args+=(--no-target)
[ -z "$DOCKET_TARGET" ] || claim_args+=(--queue "$queue")
if [ "$check" -eq 1 ]; then
  rc=0
  "$here/claim-check.sh" ${claim_args[@]+"${claim_args[@]}"} "$slug" || rc=$?
  case "$rc" in
    0) ;;
    1) echo "start-work: resolve the existing claim first (or pass --no-check if the overlap is already coordinated)"; exit 1 ;;
    *) echo "start-work: the claim check failed (exit $rc), so ownership is unverified; fix the error above before starting" >&2; exit 2 ;;
  esac
fi

path="$dir/$queue-$slug"
# Make sure the worktree directory and the local docket state directory are
# ignored. Only directories git does not already ignore are appended, so
# repeated runs never duplicate a line. A worktree directory outside the
# repository needs no ignoring, and git cannot answer for it, so it is skipped;
# one inside is checked by its path relative to the root. In target mode the
# state directory lives in the sidecar, and the managed clone's exclude file
# is written only for a worktree directory inside that clone.
dir_abs="$(mkdir -p "$dir" && cd "$dir" && pwd -P)"
[ -z "$DOCKET_TARGET" ] || path="$dir_abs/$queue-$slug"
ensure_ignored() {
  # ensure_ignored <repository> <directory relative to it>
  local exclude
  exclude="$(cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P)/info/exclude"
  if ! git -C "$1" check-ignore -q "$2/probe" 2>/dev/null; then
    mkdir -p "$(dirname "$exclude")"
    printf '%s/\n' "$2" >> "$exclude"
    echo "start-work: $2 was not ignored; added it to the local git exclude file ($exclude). Add '$2/' to .gitignore in your next PR."
  fi
}
repo_abs="$(cd "$repo_dir" && pwd -P)"
case "$dir_abs" in
  "$repo_abs"/*) ensure_ignored "$repo_abs" "${dir_abs#"$repo_abs"/}" ;;
esac
ensure_ignored "$root" .docket
cd "$repo_dir"
start="$base"
if [ "$local_only" -eq 0 ] && git remote get-url "$remote" >/dev/null 2>&1; then
  git fetch --quiet "$remote" "$base" 2>/dev/null || true
  git rev-parse --verify --quiet "refs/remotes/$remote/$base" >/dev/null && start="$remote/$base"
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
# Mark the branch as docket's, so cleanup in the managed clone never touches
# the user's own branches there.
[ -z "$DOCKET_TARGET" ] || git config "branch.$branch.docket" true
echo "created branch $branch at $path (from $start)"
case "$queue" in
  todo) marker="Claims TODO: $slug" ;;
  review) marker="Claims review backlog: $slug" ;;
  roadmap) marker="Claims roadmap: $slug" ;;
  *) marker="" ;;
esac
if [ -n "$DOCKET_TARGET" ]; then
  case "$queue" in
    todo) entry_file="TODO.md" ;;
    review) entry_file="review/BACKLOG.md" ;;
    *) entry_file="" ;;
  esac
  echo "managed repository $TARGET_REPO: the sidecar's queue entry is the claim record; the PR body follows $TARGET_REPO's own template and carries no docket markers or Type: line."
  if [ -n "$TARGET_PUSH_OWNER" ]; then
    push_step="push to $TARGET_PUSH_REMOTE (the fork owned by $TARGET_PUSH_OWNER, never $remote) and open a draft PR with 'gh pr create --repo $TARGET_REPO --base $base --head $TARGET_PUSH_OWNER:$branch --draft'"
  else
    push_step="push to $remote and open a draft PR with 'gh pr create --repo $TARGET_REPO --base $base --draft'"
  fi
  echo "next: cd $path; commit early; $push_step after the first meaningful commit; keep the change description, the ${marker:+'$marker' marker, the }Type: line and state in the sidecar's .docket/state-$slug.md."
  if [ -n "$entry_file" ]; then
    echo "then record the claim: add '  - PR: $TARGET_REPO#<number>' to the '$slug' entry in the sidecar's $entry_file as a direct commit to the sidecar's main, and push it under the session's push authority."
  fi
elif [ "$local_only" -eq 1 ]; then
  echo "next: cd $path; run scripts/setup.sh if present; commit early; save the title in .docket/title-$slug.txt and description in .docket/change-$slug.md${marker:+ with '$marker'}; leave the branch and worktree for review and approval."
else
  echo "next: cd $path; run scripts/setup.sh if present; commit early; open a draft PR after the first meaningful commit${marker:+ with '$marker' in the body}."
fi
