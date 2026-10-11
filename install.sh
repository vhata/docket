#!/usr/bin/env bash
# Install or update the docket skill's vendored machinery in a project, or
# audit an installed copy for drift.
#
# Usage: bash install.sh [--check] [target]
#   target: a directory inside the project's git repository (default: the
#           repository containing the current directory). The files land in
#           <toplevel>/docket/.
#   --check: write nothing; compare <toplevel>/docket/ and the docket block in
#            <toplevel>/AGENTS.md with the skill's copies and exit 1 on any
#            difference or a missing VERSION file.
#
# The same command performs the first install and every later update. Files
# present in the project's docket/ but absent from the skill are reported,
# never deleted. In AGENTS.md the installer owns only the block between
# '<!-- docket:begin -->' and '<!-- docket:end -->'; it inserts the block when
# it is missing (creating the file when there is none, and adding the settings
# list under it on first insert) and rewrites it on every run. Everything else
# in AGENTS.md is the project's. Exit 2 on usage errors. Portable to bash 3.2.
set -euo pipefail

skill="$(cd "$(dirname "$0")" && pwd)"
src="$skill/templates/docket"
check=0; target=""
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    -*) echo "install: unknown option $arg" >&2; exit 2 ;;
    *) [ -z "$target" ] || { echo "install: only one target may be given" >&2; exit 2; }; target="$arg" ;;
  esac
done
fragment="$skill/templates/AGENTS.md"
[ -d "$src" ] && [ -f "$fragment" ] || { echo "install: $src or $fragment is missing; the skill checkout is incomplete" >&2; exit 2; }

: "${target:=.}"
[ -d "$target" ] || { echo "install: $target is not a directory" >&2; exit 2; }
top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || { echo "install: $target is not inside a git repository" >&2; exit 2; }
skill_top="$(git -C "$skill" rev-parse --show-toplevel 2>/dev/null || echo "$skill")"
common="$(cd "$top" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
skill_common="$(cd "$skill" && cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .)" && pwd -P)"
if [ "$top" = "$skill_top" ] || [ "$common" = "$skill_common" ]; then
  echo "install: refusing to install the skill into its own repository ($top)" >&2; exit 2
fi
dst="$top/docket"

sha="$(git -C "$skill" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
if [ "$sha" != unknown ] && [ -n "$(git -C "$skill" status --porcelain 2>/dev/null)" ]; then sha="$sha-dirty"; fi

begin='<!-- docket:begin -->'; end='<!-- docket:end -->'
agents="$top/AGENTS.md"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/docket-install.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
# Print the lines from the begin marker to the end marker, inclusive.
block() { awk -v b="$begin" -v e="$end" '$0 == b { p = 1 } p { print } $0 == e { p = 0 }' "$1"; }
block "$fragment" > "$tmp/want"
# 0: one well-formed block; 1: no block; 2: malformed markers. Missing file counts as no block.
agents_state() {
  [ -f "$agents" ] || return 1
  local nb ne
  nb="$(grep -cxF "$begin" "$agents" || true)"; ne="$(grep -cxF "$end" "$agents" || true)"
  if [ "$nb" -eq 0 ] && [ "$ne" -eq 0 ]; then return 1; fi
  if [ "$nb" -ne 1 ] || [ "$ne" -ne 1 ]; then return 2; fi
  [ "$(grep -nxF "$begin" "$agents" | cut -d: -f1)" -lt "$(grep -nxF "$end" "$agents" | cut -d: -f1)" ] || return 2
}

if [ "$check" -eq 1 ]; then
  status=0
  if [ ! -d "$dst" ]; then
    echo "install: $dst does not exist; nothing is installed" >&2; exit 1
  fi
  if [ -f "$dst/VERSION" ]; then
    echo "installed: $(cat "$dst/VERSION")"
  else
    echo "installed: VERSION file missing" >&2; status=1
  fi
  echo "skill:     $sha"
  diff -r -x VERSION "$src" "$dst" || status=1
  if agents_state; then
    block "$agents" > "$tmp/have"
    diff -u --label "skill AGENTS.md block" --label "$agents block" "$tmp/want" "$tmp/have" || status=1
  elif [ $? -eq 1 ]; then
    echo "install: $agents has no docket block ($begin ... $end)" >&2; status=1
  else
    echo "install: $agents has malformed docket markers; expected exactly one $begin before one $end" >&2; status=1
  fi
  if [ "$status" -eq 0 ]; then echo "install: $dst and the $agents block match the skill"; else echo "install: $top differs from the skill; rerun install.sh to resync" >&2; fi
  exit "$status"
fi

# Copy every file, preserving the subtree. Plain cp keeps the dependency list
# at coreutils and git.
copied=0
while IFS= read -r rel; do
  rel="${rel#./}"
  mkdir -p "$dst/$(dirname "$rel")"
  cp "$src/$rel" "$dst/$rel"
  copied=$((copied + 1))
done < <(cd "$src" && find . -type f | sort)
chmod +x "$dst"/scripts/*.sh
printf '%s %s\n' "$sha" "$(date -u +%Y-%m-%d)" > "$dst/VERSION"

# Local, uncommitted docket state lives in .docket/; keep it out of git.
exclude="$(git -C "$top" rev-parse --git-path info/exclude)"
case "$exclude" in /*) ;; *) exclude="$top/$exclude" ;; esac
mkdir -p "$(dirname "$exclude")"
added_exclude=0
if ! { grep -qxF '.docket/' "$exclude" 2>/dev/null; }; then printf '.docket/\n' >> "$exclude"; added_exclude=1; fi

# Report, but never remove, files the skill no longer ships.
while IFS= read -r rel; do
  rel="${rel#./}"
  [ "$rel" = VERSION ] && continue
  [ -f "$src/$rel" ] || echo "install: warning: $dst/$rel is not part of the skill; remove it by hand if it is obsolete" >&2
done < <(cd "$dst" && find . -type f | sort)

# The project points its agents at the vendored contract through one block in
# AGENTS.md. Only that block is written; the rest of the file is left alone.
status=0; agents_note=""
if agents_state; then
  block "$agents" > "$tmp/have"
  if cmp -s "$tmp/want" "$tmp/have"; then
    agents_note="docket block in $agents is current"
  else
    awk -v b="$begin" -v e="$end" -v f="$tmp/want" '
      $0 == b { while ((getline l < f) > 0) print l; skip = 1; next }
      skip { if ($0 == e) skip = 0; next }
      { print }' "$agents" > "$tmp/agents"
    cp "$tmp/agents" "$agents"
    agents_note="rewrote the docket block in $agents"
  fi
elif [ $? -eq 1 ]; then
  if [ -f "$agents" ]; then
    [ -z "$(tail -c 1 "$agents")" ] || printf '\n' >> "$agents"
    printf '\n' >> "$agents"; cat "$fragment" >> "$agents"
    agents_note="appended the docket block and settings list to $agents; fill in the settings"
  else
    cp "$fragment" "$agents"
    agents_note="created $agents with the docket block and settings list; fill in the settings"
  fi
else
  echo "install: $agents has malformed docket markers; expected exactly one $begin before one $end; fix it by hand" >&2; status=1
fi
if [ -f "$top/CLAUDE.md" ] && ! grep -qx '@AGENTS.md' "$top/CLAUDE.md"; then
  echo "install: warning: $top/CLAUDE.md does not contain the line '@AGENTS.md'" >&2
fi

echo "install: copied $copied files from $src to $dst (VERSION $(cat "$dst/VERSION"))"
[ -z "$agents_note" ] || echo "install: $agents_note"
[ "$added_exclude" -eq 1 ] && echo "install: added .docket/ to $exclude"
echo "install: changes in $top:"
git -C "$top" status --short docket/ AGENTS.md
exit "$status"
