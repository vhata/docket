#!/usr/bin/env bash
# Install or update the docket skill's vendored machinery in a project, or
# audit an installed copy for drift.
#
# Usage: bash install.sh [--check] [target]
#   target: a directory inside the project's git repository (default: the
#           repository containing the current directory). The files land in
#           <toplevel>/docket/.
#   --check: write nothing; compare <toplevel>/docket/ and the Docket section of
#            <toplevel>/AGENTS.md with the skill's copies and exit 1 on any
#            difference or a missing VERSION file.
#
# The same command performs the first install and every later update. Files
# present in the project's docket/ but absent from the skill are reported,
# never deleted. In AGENTS.md the installer owns only the Docket section,
# between '<!-- docket:begin -->' and '<!-- docket:end -->'. It inserts the
# section when it is missing (creating the file when there is none). On later
# runs it rewrites the heading and text, keeps each settings bullet ('- Name:
# value') the project has set, re-adds a missing setting as a placeholder, and
# keeps extra bullets. Everything outside the markers is the project's and is
# never read or written. An existing CLAUDE.md gets the line
# '@AGENTS.md' appended when it lacks one; no CLAUDE.md is created or replaced.
# Exit 2 on usage errors. Portable to bash 3.2.
set -euo pipefail

skill="$(cd "$(dirname "$0")" && pwd)"
src="$skill/templates/docket"
check=0; target=""
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
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
block "$fragment" > "$tmp/template"
# The section a project should have, given the section it has now ($1): the
# template's text verbatim; for each template bullet the project's line with
# the same name, else the placeholder; then the project's other bullets in
# their own order.
expected() {
  awk -v e="$end" -v have="$1" '
    function name(l,  s) { s = substr(l, 3); if (index(s, ":") == 0) return ""; return substr(s, 1, index(s, ":") - 1) }
    BEGIN { while ((getline l < have) > 0) if (l ~ /^- /) { k = name(l); if (k != "" && !(k in hv)) { hv[k] = l; order[m++] = k } else extra[n++] = l } }
    /^- / { k = name($0); if (k in hv) { print hv[k]; seen[k] = 1 } else print; next }
    $0 == e { for (i = 0; i < m; i++) if (!(order[i] in seen)) print hv[order[i]]; for (i = 0; i < n; i++) print extra[i]; print; next }
    { print }' "$tmp/template"
}
# Names of template settings whose line in $1 is missing or still a placeholder.
unfilled() {
  while IFS= read -r l; do
    k="${l#- }"; k="${k%%:*}"
    if ! grep -q "^- $k:" "$1"; then echo "$k (missing)"; elif grep "^- $k:" "$1" | grep -q '<[^>]*>'; then echo "$k (placeholder)"; fi
  done < <(grep '^- ' "$tmp/template")
}
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
    expected "$tmp/have" > "$tmp/want"
    diff -u --label "expected Docket section" --label "$agents" "$tmp/want" "$tmp/have" || status=1
    unfilled "$tmp/have" > "$tmp/unfilled"
    if [ -s "$tmp/unfilled" ]; then echo "install: settings not filled in $agents: $(paste -sd, "$tmp/unfilled" | sed 's/,/, /g')" >&2; status=1; fi
  elif [ $? -eq 1 ]; then
    echo "install: $agents has no Docket section ($begin ... $end)" >&2; status=1
  else
    echo "install: $agents has malformed docket markers; expected exactly one $begin before one $end" >&2; status=1
  fi
  if [ "$status" -eq 0 ]; then echo "install: $dst and the Docket section of $agents match the skill"; else echo "install: $top differs from the skill; rerun install.sh to resync" >&2; fi
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

# The project points its agents at the vendored contract through the Docket
# section of AGENTS.md. Only that section is written; the rest is left alone.
status=0; agents_note=""
if agents_state; then
  block "$agents" > "$tmp/have"
  expected "$tmp/have" > "$tmp/want"
  if cmp -s "$tmp/want" "$tmp/have"; then
    agents_note="Docket section of $agents is current"
  else
    awk -v b="$begin" -v e="$end" -v f="$tmp/want" '
      $0 == b { while ((getline l < f) > 0) print l; skip = 1; next }
      skip { if ($0 == e) skip = 0; next }
      { print }' "$agents" > "$tmp/agents"
    cp "$tmp/agents" "$agents"
    agents_note="rewrote the Docket section of $agents, keeping its settings"
  fi
  unfilled "$tmp/want" > "$tmp/unfilled"
  if [ -s "$tmp/unfilled" ]; then agents_note="$agents_note; settings to fill in: $(paste -sd, "$tmp/unfilled" | sed 's/,/, /g')"; fi
elif [ $? -eq 1 ]; then
  if [ -f "$agents" ]; then
    [ -z "$(tail -c 1 "$agents")" ] || printf '\n' >> "$agents"
    printf '\n' >> "$agents"; cat "$fragment" >> "$agents"
    agents_note="appended the Docket section to $agents; fill in its settings"
  else
    cp "$fragment" "$agents"
    agents_note="created $agents with the Docket section; fill in its settings"
  fi
else
  echo "install: $agents has malformed docket markers; expected exactly one $begin before one $end; fix it by hand" >&2; status=1
fi
# Claude Code reads CLAUDE.md, so an existing one needs the import line. The
# line is appended, never substituted for the file, and no CLAUDE.md is created.
claude_note=""
if [ -f "$top/CLAUDE.md" ] && ! grep -qx '@AGENTS.md' "$top/CLAUDE.md"; then
  [ -z "$(tail -c 1 "$top/CLAUDE.md")" ] || printf '\n' >> "$top/CLAUDE.md"
  printf '\n@AGENTS.md\n' >> "$top/CLAUDE.md"
  claude_note="appended @AGENTS.md to $top/CLAUDE.md"
fi

echo "install: copied $copied files from $src to $dst (VERSION $(cat "$dst/VERSION"))"
[ -z "$agents_note" ] || echo "install: $agents_note"
[ -z "$claude_note" ] || echo "install: $claude_note"
[ "$added_exclude" -eq 1 ] && echo "install: added .docket/ to $exclude"
echo "install: changes in $top:"
git -C "$top" status --short docket/ AGENTS.md CLAUDE.md
exit "$status"
