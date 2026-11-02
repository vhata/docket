#!/usr/bin/env bash
# Managed-repository target: lets a sidecar repository's docket scripts work
# in a separate repository (the managed repository) that docket is not
# installed in. Sourced by start-work.sh, claim-check.sh, cleanup-landed.sh,
# review-due.sh and pr-health.sh, which act on the managed repository; by
# check-pr-markers.sh and pr-labels.sh, which stand down there; and by
# check-queues.sh, which reads only the repo key. Run directly, it validates
# the target file and prints the resolved settings.
#
# Usage: bash docket/scripts/target.sh [--no-target]
#
# The target file is .docket-target at the sidecar's git toplevel, tracked in
# the sidecar; DOCKET_TARGET_FILE names another path. Without the file, every
# script behaves as in an ordinary installation. Format: key=value lines; '#'
# starts a comment (a whole line, or trailing after whitespace); blank lines
# are ignored; whitespace around keys and values is trimmed; a leading ~/ in a
# value expands to $HOME, and a relative dir or worktree_dir is resolved
# against the sidecar's main worktree (the first one git worktree list
# names), so every sidecar worktree resolves it to the same place. A
# relative DOCKET_TARGET_FILE is taken from the current directory; set it per
# command, never globally. Keys:
#   repo=owner/repo       required: the managed repository on the forge
#   dir=~/src/repo        required: its local clone (an existing git repository)
#   base=main             its base branch
#   remote=origin         the clone's remote for the managed repository
#   push_remote=          the clone's remote that branches are pushed to,
#                         for contributing through a fork; default: remote
#   push_owner=           the fork's owner on the forge; default: the owner
#                         in push_remote's push URL when that is a forge URL
#                         whose path (repeated and leading slashes dropped,
#                         as forges do) is exactly owner/name and whose owner
#                         is an account name (no dot, not all digits);
#                         required otherwise (a local path, a file:// URL,
#                         a nested group path). Only with a push_remote
#                         other than remote; refused when that URL is on
#                         the same host as remote's and shows another owner
#   branch_prefix=        empty: docket's <queue>/<slug> branch names; set
#                         (ending in '/', e.g. me/): <branch_prefix><slug>
#   worktree_dir=         default <dir>-worktrees, outside the clone
#   land_comment=         a comment that asks the managed repository's merge
#                         process to land a PR; empty: the user merges
# An unknown key, a repeated key, a malformed line or a missing required key
# is an error naming the file and line. A push_remote is refused, with or
# without push_owner, when its push URL is remote's fetch or push URL
# (ignoring repeated and trailing slashes and a trailing .git), or is a
# forge URL whose owner/name path is repo. A URL that names the managed
# repository some other way (another spelling of a local path, a redirect)
# is not detected.
#
# Functions (bash 3.2; git only):
#   docket_target_init <script_dir> [--no-target]
#     Settles the sidecar root, then loads as below. The root is the current
#     toplevel, unless that has no .docket-target (or DOCKET_TARGET_FILE is
#     set) and the repository holding <script_dir> is a different one with a
#     target in play: then the scripts' own repository is the sidecar, so a
#     script run by absolute path from a managed worktree still finds it.
#     Sets DOCKET_SIDECAR_ROOT. Returns 2 after printing an error.
#   docket_target_load <sidecar-root>
#     Loads DOCKET_TARGET_FILE (made absolute and exported, so child scripts
#     see the same file) or <sidecar-root>/.docket-target. Sets
#     DOCKET_TARGET (1, or empty without a file) and TARGET_REPO, TARGET_DIR
#     (the clone's absolute toplevel), TARGET_BASE, TARGET_REMOTE,
#     TARGET_BRANCH_PREFIX, TARGET_WORKTREE_DIR (absolute),
#     TARGET_LAND_COMMENT, TARGET_PUSH_REMOTE (remote unless push_remote
#     names another) and TARGET_PUSH_OWNER (the fork owner, or empty when
#     branches are pushed to the managed repository itself). Returns 2 after
#     printing an error.
#   docket_target_repo <sidecar-root>
#     Prints the repo value of DOCKET_TARGET_FILE or
#     <sidecar-root>/.docket-target, or nothing without a file or a repo
#     line. Validates nothing else and needs no clone, so CI can use it.
#   docket_target_branch <queue> <slug>
#     Prints the branch name for a unit of work in target mode.
#   docket_target_contains <path>
#     Succeeds when <path> is inside a worktree of the managed clone.
#   docket_target_url_repo <url>
#     Prints owner/name from a forge remote URL (scp-style or scheme://),
#     or nothing when the path is not exactly owner/name with an account
#     name as owner, or the URL is a local path or file:// URL.
#   docket_target_url_host <url>
#     Prints the lowercased host of a forge remote URL, or nothing.
#   docket_target_own_head <cross-repository> <head-owner>
#     Succeeds when a PR head in the target with these fields is in the
#     managed repository itself, or in the configured fork.

# The variables are consumed by the scripts that source this file.
# shellcheck disable=SC2034

docket_target_reset() {
  DOCKET_TARGET=""; DOCKET_TARGET_SOURCE=""
  TARGET_REPO=""; TARGET_DIR=""; TARGET_BASE=""; TARGET_REMOTE=""
  TARGET_BRANCH_PREFIX=""; TARGET_WORKTREE_DIR=""; TARGET_LAND_COMMENT=""
  TARGET_PUSH_REMOTE=""; TARGET_PUSH_OWNER=""
}

docket_target_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Absolute, symlink-resolved form of a path value, a relative path taken
# against the target file's directory. The path need not exist.
docket_target_path() {
  local value="$1" from="$2" parent leaf
  case "$value" in
    /*) ;;
    *) value="$from/$value" ;;
  esac
  value="${value%/}"
  if [ -d "$value" ]; then (cd "$value" && pwd -P); return; fi
  parent="$(dirname "$value")"; leaf="$(basename "$value")"
  if [ -d "$parent" ]; then printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$leaf"; else printf '%s\n' "$value"; fi
}

docket_target_load() {
  local root="$1" file line n key value seen from err common side
  docket_target_reset
  if [ -n "${DOCKET_TARGET_FILE:-}" ]; then
    case "$DOCKET_TARGET_FILE" in /*) ;; *) DOCKET_TARGET_FILE="$(pwd)/$DOCKET_TARGET_FILE" ;; esac
    export DOCKET_TARGET_FILE
  fi
  file="${DOCKET_TARGET_FILE:-$root/.docket-target}"
  if [ ! -f "$file" ]; then
    if [ -n "${DOCKET_TARGET_FILE:-}" ]; then
      echo "docket target: DOCKET_TARGET_FILE names $file, which is not a file" >&2
      return 2
    fi
    return 0
  fi
  # Relative paths resolve against the sidecar's main worktree: the first
  # entry git lists, which holds for a --separate-git-dir or .git-file layout.
  from="$(git -C "$root" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p' || true)"
  if [ -n "$from" ] && [ -d "$from" ]; then from="$(cd "$from" && pwd -P)"; else from="$(cd "$root" && pwd -P)"; fi
  n=0; seen=" "; err=""
  local repo="" dir="" base="main" remote="origin" prefix="" wtdir="" land="" push="" powner="" url urlrepo uhost rurl
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line="$(docket_target_trim "$line")"
    case "$line" in ""|"#"*) continue ;; esac
    line="${line%%[[:space:]]#*}"
    case "$line" in
      *=*) ;;
      *) err="$file:$n: expected key=value, got '$line'"; break ;;
    esac
    key="$(docket_target_trim "${line%%=*}")"
    value="$(docket_target_trim "${line#*=}")"
    case "$seen" in *" $key "*) err="$file:$n: '$key' is set twice"; break ;; esac
    seen="$seen$key "
    case "$value" in \~/*) value="$HOME/${value#\~/}" ;; esac
    case "$key" in
      repo)
        printf '%s\n' "$value" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ||
          { err="$file:$n: repo must be owner/repo, got '$value'"; break; }
        repo="$value" ;;
      dir) [ -n "$value" ] || { err="$file:$n: dir is empty"; break; }; dir="$value" ;;
      base)
        [ -n "$value" ] && git check-ref-format "refs/heads/$value" ||
          { err="$file:$n: base '$value' is not a valid branch name"; break; }
        base="$value" ;;
      remote)
        [ -n "$value" ] && git check-ref-format "refs/remotes/$value/x" ||
          { err="$file:$n: remote '$value' is not a valid remote name"; break; }
        remote="$value" ;;
      push_remote)
        [ -n "$value" ] && git check-ref-format "refs/remotes/$value/x" ||
          { err="$file:$n: push_remote '$value' is not a valid remote name"; break; }
        push="$value" ;;
      push_owner)
        printf '%s\n' "$value" | grep -Eq '^[A-Za-z0-9_.-]+$' ||
          { err="$file:$n: push_owner must be a forge account name, got '$value'"; break; }
        powner="$value" ;;
      branch_prefix)
        if [ -n "$value" ]; then
          case "$value" in
            */) git check-ref-format "refs/heads/${value}x" ||
                  { err="$file:$n: branch_prefix '$value' does not form valid branch names"; break; } ;;
            *) err="$file:$n: branch_prefix must end in '/' (for example '$value/'), got '$value'"; break ;;
          esac
        fi
        prefix="$value" ;;
      worktree_dir) [ -n "$value" ] || { err="$file:$n: worktree_dir is empty (omit it for the default)"; break; }; wtdir="$value" ;;
      land_comment) land="$value" ;;
      *) err="$file:$n: unknown key '$key' (known: repo, dir, base, remote, push_remote, push_owner, branch_prefix, worktree_dir, land_comment)"; break ;;
    esac
  done < "$file"
  if [ -z "$err" ]; then
    if [ -z "$repo" ]; then err="$file: required key 'repo' is missing"
    elif [ -z "$dir" ]; then err="$file: required key 'dir' is missing"
    elif [ -n "$powner" ] && { [ -z "$push" ] || [ "$push" = "$remote" ]; }; then
      err="$file: push_owner needs a push_remote other than the remote '$remote'"
    fi
  fi
  if [ -z "$err" ]; then
    dir="$(docket_target_path "$dir" "$from")"
    if [ ! -d "$dir" ]; then err="$file: dir $dir does not exist"
    elif ! TARGET_DIR="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || [ -z "$TARGET_DIR" ]; then
      err="$file: dir $dir is not a git working tree"
    else
      TARGET_DIR="$(cd "$TARGET_DIR" && pwd -P)"
      common="$(docket_target_common "$TARGET_DIR")"
      side="$(docket_target_common "$root")"
      if [ -n "$side" ] && [ "$common" = "$side" ]; then
        err="$file: dir $dir is the sidecar repository itself; it must be a clone of the managed repository"
      elif ! git -C "$TARGET_DIR" remote get-url "$remote" >/dev/null 2>&1; then
        err="$file: the clone at $TARGET_DIR has no remote '$remote' (set remote= to the one for $repo)"
      elif [ -n "$push" ] && [ "$push" != "$remote" ]; then
        # A fork: its owner names the PR heads that are the worker's own.
        if ! url="$(git -C "$TARGET_DIR" remote get-url --push "$push" 2>/dev/null)"; then
          err="$file: the clone at $TARGET_DIR has no remote '$push' (push_remote names the fork's remote there)"
        else
          urlrepo="$(docket_target_url_repo "$url")"
          rurl="$(docket_target_url_norm "$(git -C "$TARGET_DIR" remote get-url "$remote")")"
          if [ "$(docket_target_url_norm "$url")" = "$rurl" ] ||
             [ "$(docket_target_url_norm "$url")" = "$(docket_target_url_norm "$(git -C "$TARGET_DIR" remote get-url --push "$remote")")" ]; then
            err="$file: push_remote '$push' ($url) has the URL of remote '$remote', not a fork's; omit push_remote to push there"
          elif [ -n "$urlrepo" ] && [ "$(docket_target_lower "$urlrepo")" = "$(docket_target_lower "$repo")" ]; then
            err="$file: push_remote '$push' ($url) is $repo itself, not a fork; omit push_remote to push there"
          elif [ -z "$powner" ]; then
            if [ -z "$urlrepo" ]; then
              err="$file: cannot tell the fork owner from push_remote '$push' ($url); set push_owner="
            else
              powner="${urlrepo%%/*}"
            fi
          elif [ -n "$urlrepo" ] && [ "$(docket_target_lower "${urlrepo%%/*}")" != "$(docket_target_lower "$powner")" ]; then
            # On the managed repository's own forge the URL's owner is the
            # fork's; elsewhere (a mirror or proxy) push_owner is the word.
            uhost="$(docket_target_url_host "$url")"
            if [ -n "$uhost" ] && [ "$uhost" = "$(docket_target_url_host "$(git -C "$TARGET_DIR" remote get-url "$remote")")" ]; then
              err="$file: push_owner '$powner' differs from the owner '${urlrepo%%/*}' in push_remote '$push' ($url); fix one of them"
            fi
          fi
        fi
      else
        push=""
      fi
    fi
  fi
  if [ -n "$err" ]; then
    docket_target_reset
    echo "docket target: $err" >&2
    return 2
  fi
  if [ -n "$wtdir" ]; then wtdir="$(docket_target_path "$wtdir" "$from")"; else wtdir="$TARGET_DIR-worktrees"; fi
  DOCKET_TARGET=1; DOCKET_TARGET_SOURCE="$file"
  TARGET_REPO="$repo"; TARGET_BASE="$base"; TARGET_REMOTE="$remote"
  TARGET_BRANCH_PREFIX="$prefix"; TARGET_WORKTREE_DIR="$wtdir"; TARGET_LAND_COMMENT="$land"
  TARGET_PUSH_REMOTE="${push:-$remote}"; TARGET_PUSH_OWNER="$powner"
  return 0
}

docket_target_repo() {
  local file="${DOCKET_TARGET_FILE:-$1/.docket-target}" line key
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(docket_target_trim "$line")"
    case "$line" in ""|"#"*) continue ;; esac
    line="${line%%[[:space:]]#*}"
    case "$line" in *=*) ;; *) continue ;; esac
    key="$(docket_target_trim "${line%%=*}")"
    [ "$key" = repo ] || continue
    printf '%s\n' "$(docket_target_trim "${line#*=}")"
    return 0
  done < "$file"
}

docket_target_init() {
  local script_dir="$1" no_target="${2:-}" here_top script_top
  docket_target_reset
  here_top="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  DOCKET_SIDECAR_ROOT="$here_top"
  [ "$no_target" = --no-target ] && return 0
  # Settle the root before loading: the load checks that the clone is not the
  # sidecar, which must already be the right repository.
  if [ -n "${DOCKET_TARGET_FILE:-}" ] || [ ! -f "$here_top/.docket-target" ]; then
    script_top="$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$script_top" ] && [ "$(docket_target_common "$script_top")" != "$(docket_target_common "$here_top")" ] &&
       { [ -n "${DOCKET_TARGET_FILE:-}" ] || [ -f "$script_top/.docket-target" ]; }; then
      DOCKET_SIDECAR_ROOT="$script_top"
    fi
  fi
  docket_target_load "$DOCKET_SIDECAR_ROOT" || return 2
  return 0
}

docket_target_branch() {
  if [ -n "$TARGET_BRANCH_PREFIX" ]; then printf '%s%s\n' "$TARGET_BRANCH_PREFIX" "$2"; else printf '%s/%s\n' "$1" "$2"; fi
}

# The absolute git common directory of the repository holding <path>, or
# nothing when <path> is not in one.
docket_target_common() {
  (cd "$1" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || true
}

docket_target_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# The repository path of a forge remote URL: what follows the host in
# scheme://[user@]host[:port]/path or scp-style [user@]host:path, with
# repeated and leading slashes dropped, or nothing for a local path (a '/'
# before any ':') or a file:// URL.
docket_target_url_path() {
  local u="$1" p
  case "$u" in
    [Ff][Ii][Ll][Ee]://*) return 0 ;;
    *://*) p="${u#*://}"; case "$p" in */*) p="${p#*/}" ;; *) return 0 ;; esac ;;
    *:*) case "${u%%:*}" in *[/\\]*) return 0 ;; esac; p="${u#*:}" ;;
    *) return 0 ;;
  esac
  # Forges ignore repeated and leading slashes in the path.
  p="$(printf '%s' "$p" | tr -s /)"; p="${p#/}"
  printf '%s\n' "$p"
}

# A URL with repeated and trailing slashes and a trailing .git dropped, for
# telling whether two remotes name the same place.
docket_target_url_norm() {
  local u
  u="$(printf '%s' "$1" | sed 's#\([^/:]\)//*#\1/#g; s#/*$##; s#\.git$##; s#/*$##')"
  printf '%s\n' "$u"
}

docket_target_url_host() {
  local u="$1" h
  [ -n "$(docket_target_url_path "$u")" ] || return 0
  case "$u" in
    *://*) h="${u#*://}"; h="${h%%/*}"; h="${h##*@}"; h="${h%:*}" ;;
    *) h="${u%%:*}"; h="${h##*@}" ;;
  esac
  docket_target_lower "$h"
}

docket_target_url_repo() {
  local p owner name
  p="$(docket_target_url_path "$1")"
  p="${p%/}"; p="${p%.git}"
  # Exactly owner/name: a nested group path names no single owner.
  case "$p" in */*/*) return 0 ;; */*) ;; *) return 0 ;; esac
  owner="${p%/*}"; name="${p#*/}"
  [ -n "$owner" ] && [ -n "$name" ] || return 0
  # An account name: no host-like (a dot), port-like (digits only) or
  # otherwise unusual owner, which would more likely be a misparse.
  printf '%s\n' "$owner" | grep -Eq '^[A-Za-z0-9_-]+$' || return 0
  printf '%s\n' "$owner" | grep -Eq '^[0-9]+$' && return 0
  printf '%s/%s\n' "$owner" "$name"
}

docket_target_own_head() {
  [ "$1" = false ] && return 0
  [ "$1" = true ] && [ -n "$TARGET_PUSH_OWNER" ] || return 1
  [ "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$TARGET_PUSH_OWNER" | tr '[:upper:]' '[:lower:]')" ]
}

docket_target_contains() {
  local a
  [ -n "$TARGET_DIR" ] || return 1
  a="$(docket_target_common "$1")"
  [ -n "$a" ] && [ "$a" = "$(docket_target_common "$TARGET_DIR")" ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  opt=""
  case "${1:-}" in
    --no-target) opt=--no-target ;;
    "") ;;
    *) sed -n '2,10p' "$0"; exit 2 ;;
  esac
  docket_target_init "$(cd "$(dirname "$0")" && pwd)" "$opt" || exit 2
  if [ -z "$DOCKET_TARGET" ]; then
    echo "no managed-repository target: the scripts act on the repository of the current directory ($DOCKET_SIDECAR_ROOT)"
    exit 0
  fi
  echo "target file: $DOCKET_TARGET_SOURCE"
  echo "sidecar: $DOCKET_SIDECAR_ROOT"
  echo "repo: $TARGET_REPO"
  echo "dir: $TARGET_DIR"
  echo "base: $TARGET_REMOTE/$TARGET_BASE"
  echo "branches: $(docket_target_branch '<queue>' '<slug>')"
  echo "worktrees: $TARGET_WORKTREE_DIR/<queue>-<slug>"
  echo "land_comment: ${TARGET_LAND_COMMENT:-(none; the user merges)}"
  if [ -n "$TARGET_PUSH_OWNER" ]; then
    echo "push: $TARGET_PUSH_REMOTE, the fork owned by $TARGET_PUSH_OWNER"
  else
    echo "push: $TARGET_PUSH_REMOTE, the managed repository itself"
  fi
fi
