#!/usr/bin/env bash
# Run your own checks over only the files your change touches in a managed
# repository, the one a docket sidecar's .docket-target names. The managed
# repository's CI stays the authority for its gates; this is for the checks
# you hold yourself to (a Markdown formatter, a spell checker) and that its
# owners do not run. Nothing is installed into the managed clone, its hooks
# or its config: run this by hand, or have agents run it, before marking a
# PR ready.
#
# Usage: bash scripts/check-mine.sh [--fix] [--worktree PATH] [--base REF]
#   --worktree PATH  the managed worktree to check (default: the current
#                    directory's repository)
#   --base REF       compare with this ref (default: <remote>/<base> from the
#                    sidecar's .docket-target; required without one)
#   --fix            run each rule's fixer instead of its check, letting it
#                    write; rules without a fixer still run their check
#
# The changed files are those differing from the merge base of HEAD and the
# base ref, committed or not, plus untracked files git does not ignore;
# deleted files are left out. Each rule below names a shell pattern matched
# against the path from the worktree root (* also matches /), a check
# command, and optionally a fixer; the matching files are appended to the
# command as arguments (a name starting with - as ./name), run from the
# worktree root. A check that changes a file it was given fails the run, so
# checks stay read-only.
#
# Exit 0 when every rule passes (or no file matches), 1 when a rule fails,
# 2 on usage errors. Portable to bash 3.2; needs git.
set -euo pipefail

# Rules: rule '<pattern>' '<check command>' ['<fix command>']
# Edit these for your own checks, for example:
#   rule '*.md' 'npx --no-install prettier --check' 'npx --no-install prettier --write'
#   rule '*.sh' 'shellcheck -S warning'
configure() {
  : # rule '<pattern>' '<check command>' '<fix command>'
}

pats=()
checks=()
fixes=()
# shellcheck disable=SC2329 # called from configure() once rules are added
rule() {
  pats+=("$1")
  checks+=("$2")
  fixes+=("${3:-}")
}

here="$(cd "$(dirname "$0")" && pwd)"
fix=0
wt=""
base_ref=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  --fix) fix=1 ;;
  --worktree | --base)
    [ "$#" -gt 1 ] || { echo "check-mine: $1 needs a value" >&2; exit 2; }
    if [ "$1" = --worktree ]; then wt="$2"; else base_ref="$2"; fi
    shift
    ;;
  -h | --help)
    awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$0"
    exit 0
    ;;
  *) echo "check-mine: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

given="${wt:-.}"
wt="$(git -C "$given" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "check-mine: $given is not inside a git working tree" >&2
  exit 2
}

# The sidecar is the repository holding this script; its target file names
# the managed clone and its base. Without docket's target.sh or a target file,
# --base is required and any repository can be checked.
sidecar="$(git -C "$here" rev-parse --show-toplevel 2>/dev/null || true)"
loader="$sidecar/docket/scripts/target.sh"
DOCKET_TARGET=""
if [ -n "$sidecar" ] && [ -f "$loader" ]; then
  # shellcheck source=/dev/null
  . "$loader"
  docket_target_load "$sidecar" || exit 2
fi
if [ -n "$DOCKET_TARGET" ]; then
  if ! docket_target_contains "$wt"; then
    echo "check-mine: $wt is not a worktree of the managed clone $TARGET_DIR; run from one, or pass --worktree" >&2
    exit 2
  fi
  : "${base_ref:=$TARGET_REMOTE/$TARGET_BASE}"
fi
[ -n "$base_ref" ] || {
  echo "check-mine: no .docket-target to read the base from; pass --base <ref>" >&2
  exit 2
}
mb="$(git -C "$wt" merge-base HEAD "$base_ref" 2>/dev/null)" || {
  echo "check-mine: no merge base between HEAD and $base_ref in $wt (fetch it first?)" >&2
  exit 2
}

configure
if [ "${#pats[@]}" -eq 0 ]; then
  echo "check-mine: no rules configured; edit configure() in $0"
  exit 0
fi

files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(
  git -C "$wt" diff -z --name-only --diff-filter=ACMRT "$mb"
  git -C "$wt" ls-files -z --others --exclude-standard
)
if [ "${#files[@]}" -eq 0 ]; then
  echo "check-mine: no changed files since $base_ref (merge base $(printf '%.12s' "$mb"))"
  exit 0
fi

cd "$wt"
# Checksum of the given files, to catch a check that writes.
sums() { local f; for f in "$@"; do if [ -f "$f" ]; then cksum <"$f"; else echo "missing $f"; fi; done; }
failed=0
i=0
while [ "$i" -lt "${#pats[@]}" ]; do
  pat="${pats[$i]}"
  cmd="${checks[$i]}"
  mode=check
  if [ "$fix" -eq 1 ] && [ -n "${fixes[$i]}" ]; then cmd="${fixes[$i]}"; mode=fix; fi
  i=$((i + 1))
  matched=()
  for f in "${files[@]}"; do
    # shellcheck disable=SC2254
    case "$f" in
    $pat)
      # A name starting with - would read as an option.
      case "$f" in -*) f="./$f" ;; esac
      matched+=("$f")
      ;;
    esac
  done
  [ "${#matched[@]}" -gt 0 ] || continue
  echo "==> $pat ($mode, ${#matched[@]} file(s)): $cmd"
  before="$(sums "${matched[@]}")"
  if ! bash -c "$cmd"' "$@"' check-mine "${matched[@]}"; then
    echo "check-mine: '$cmd' failed on $pat" >&2
    failed=1
  fi
  if [ "$mode" = check ] && [ "$(sums "${matched[@]}")" != "$before" ]; then
    echo "check-mine: '$cmd' changed files it was only to check; give the rule a fixer and use --fix" >&2
    failed=1
  fi
done
if [ "$failed" -eq 0 ]; then echo "check-mine: all rules passed"; fi
exit "$failed"
