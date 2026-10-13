#!/usr/bin/env bash
# Install or update the docket skill's vendored machinery in a project, or
# audit an installed copy for drift.
#
# Usage: bash install.sh [--check] [--self] [target]
#   target: a directory inside the project's git repository (default: the
#           repository containing the current directory). The files land in
#           <toplevel>/docket/.
#   --check: write nothing; compare <toplevel>/docket/ and the Docket section of
#            <toplevel>/AGENTS.md with the skill's copies and exit 1 on any
#            difference, a missing VERSION file, a script that is not
#            executable (on disk, or committed as other than 100755), or an
#            installed commit newer than this skill checkout (update the
#            checkout before resyncing). Run it from a checkout at or beyond
#            the commit named in docket/VERSION. That commit is always a
#            docket commit: from a squashed subtree the installer reads the
#            upstream commit in the subtree's git-subtree-split trailer.
#   --self: install into, or with --check audit, the skill's own repository,
#           which is otherwise refused. Valid only there, from the checkout
#           whose root holds this install.sh. docket/VERSION is then the fixed
#           line 'self' (templates/docket/ at the same commit is the source),
#           and --check requires that line and skips the commit comparison.
#           Any other checkout of the skill (a root holding install.sh,
#           templates/docket/ and templates/AGENTS.md) is refused as a target,
#           with or without --self: it installs only from its own install.sh.
#           So is a repository whose docket/ is such a checkout (a skills
#           repository holding the skill under the prefix docket).
#
# The same command performs the first install and every later update. Files
# present in the project's docket/ but absent from the skill are reported,
# never deleted. In AGENTS.md the installer owns only the Docket section,
# between '<!-- docket:begin -->' and '<!-- docket:end -->'. When the section
# is missing it is inserted before the first '## ' heading (after the leading
# H1 and its introduction), or at the end when there is none; the file is
# created when there is none. Moving the section is safe: later runs find it
# wherever it is. On later runs it rewrites the heading and text, keeps each
# settings bullet ('- Name: value') the project has set, re-adds a missing
# setting as a placeholder, and keeps extra bullets. Everything outside the
# markers is the project's and is never read or written. An existing regular
# CLAUDE.md gets the line '@AGENTS.md' appended when it lacks one; a CLAUDE.md
# that is a symlink to AGENTS.md already imports it, any other symlink is
# never written through; no CLAUDE.md is created or replaced.
#
# Warnings (never failures): docs/QUALITY.md without a '## Review inputs'
# heading, which the vendored review guide links; files of the hand-copied
# layout that preceded docket/ (scripts/workflow/, docs/TODO_GUIDE.md,
# docs/CODE_REVIEW_GUIDE.md); a docs/superpowers/ directory, or a bullet in
# the Docket section naming it, since plans and design specs live in plans/
# and docs/specs/. Nothing is moved. A stale '.feral/' line in
# .git/info/exclude is removed on install.
# Exit 2 on usage errors. Portable to bash 3.2.
set -euo pipefail

skill="$(cd "$(dirname "$0")" && pwd)"
src="$skill/templates/docket"

# Drift is shown with colordiff when it is installed and the output is a
# terminal; otherwise with diff, so logs and pipes stay plain. Either way the
# exit status is diff's.
if command -v colordiff >/dev/null 2>&1 && [ -t 1 ]; then
  show_diff() { colordiff "$@"; }
else
  show_diff() { diff "$@"; }
fi
check=0
self=0
target=""
for arg in "$@"; do
  case "$arg" in
  --check) check=1 ;;
  --self) self=1 ;;
  -h | --help)
    sed -n '2,51p' "$0"
    exit 0
    ;;
  -*)
    echo "install: unknown option $arg" >&2
    exit 2
    ;;
  *)
    [ -z "$target" ] || {
      echo "install: only one target may be given" >&2
      exit 2
    }
    target="$arg"
    ;;
  esac
done
fragment="$skill/templates/AGENTS.md"
[ -d "$src" ] && [ -f "$fragment" ] || {
  echo "install: $src or $fragment is missing; the skill checkout is incomplete" >&2
  exit 2
}

: "${target:=.}"
[ -d "$target" ] || {
  echo "install: $target is not a directory" >&2
  exit 2
}
top="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "install: $target is not inside a git repository" >&2
  exit 2
}
# A directory is a skill checkout when it holds what this installer reads from
# its own: install.sh, templates/docket/ and templates/AGENTS.md.
is_skill() { [ -f "$1/install.sh" ] && [ -d "$1/templates/docket" ] && [ -f "$1/templates/AGENTS.md" ]; }
skill_top="$(git -C "$skill" rev-parse --show-toplevel 2>/dev/null || echo "$skill")"
common="$(cd "$top" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
skill_common="$(cd "$skill" && cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .)" && pwd -P)"
prefix="$(git -C "$skill" rev-parse --show-prefix 2>/dev/null || true)"; prefix="${prefix%/}"
if [ "$top" = "$skill_top" ] || [ "$common" = "$skill_common" ]; then
  if [ "$self" -eq 0 ]; then
    echo "install: refusing to install the skill into its own repository ($top); pass --self to vendor docket/ there deliberately" >&2
    exit 2
  fi
  # Self mode copies templates/docket/ to docket/ within one working tree, so
  # the target must be the checkout this install.sh runs from, with the skill
  # at its root: not a host holding it as a subtree, not a sibling worktree.
  if [ -n "$prefix" ]; then
    echo "install: --self needs the skill at the root of its repository; $skill is a subdirectory of $skill_top" >&2
    exit 2
  fi
  if [ "$top" != "$skill_top" ]; then
    echo "install: --self installs only into the checkout it runs from ($skill_top); run $top/install.sh --self for $top" >&2
    exit 2
  fi
elif is_skill "$top"; then
  # Another checkout of the skill, such as the development repository reached
  # from the installed copy in ~/.claude/skills. Its docket/ comes from its own
  # templates/docket/ with VERSION 'self', so an install from here would
  # overwrite both with this checkout's copy.
  again=--self; hint="there to vendor docket/ from its own templates/"
  [ "$check" -eq 0 ] || { again="--self --check"; hint="there to audit docket/ against its own templates/"; }
  if [ "$self" -eq 1 ]; then
    echo "install: --self installs only into the checkout it runs from ($skill_top); run $top/install.sh $again for $top" >&2
  else
    echo "install: refusing to install into $top, which is another checkout of the skill; run $top/install.sh $again $hint" >&2
  fi
  exit 2
elif is_skill "$top/docket"; then
  # A repository holding the skill as its docket/ subdirectory, the layout of
  # ~/.claude/skills with the skill added under the prefix docket: an install
  # there would write the vendored files over the skill itself.
  echo "install: refusing to install into $top, whose docket/ is a copy of the skill; the install would overwrite the skill with its own templates/docket/" >&2
  exit 2
elif [ "$self" -eq 1 ]; then
  echo "install: --self is only for the skill's own repository ($skill_top); $top is another repository" >&2
  exit 2
fi
dst="$top/docket"

# VERSION records the docket commit, not the commit of whatever repository
# holds this copy of the skill. A squashed subtree (git subtree add --squash)
# has commit ids of its own; the newest "git-subtree-split:" trailer for the
# subtree's prefix names the upstream commit, so that is used when the skill
# lives in a subdirectory of a larger repository, and HEAD otherwise. The
# prefix (computed above) comes from git so a path reached through a symlink
# still resolves. In the skill's own repository (--self) VERSION is the fixed
# line 'self' instead: a sha there would change, and usually be -dirty, on
# every branch, and says nothing templates/docket/ at that commit does not.
# Newest git-subtree-split for prefix $2 in repository $1. The trailers sit on
# the squash commit, whose tree holds the skill at its root and so never
# touches the prefix, so the whole history is read (no path filter); exact
# line matches, so no regex metacharacters. awk stops at the first hit and
# git may then die of SIGPIPE, which is not an error here.
split_for_prefix() {
  git -C "$1" log --format='%n@@docket-commit@@%n%b' 2>/dev/null | awk -v want="git-subtree-dir: $2" '
    $0 == "@@docket-commit@@" { dir = 0; next }
    $0 == want { dir = 1; next }
    dir && index($0, "git-subtree-split: ") == 1 { print substr($0, 20, 40); exit }' || true
}
head_sha=""; from_subtree=0
if [ "$self" -eq 1 ]; then
  head_sha=self
  sha=self
else
  [ -z "$prefix" ] || head_sha="$(split_for_prefix "$skill_top" "$prefix")"
  case "$head_sha" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) from_subtree=1 ;; *) head_sha="" ;; esac
  if [ -z "$head_sha" ]; then
    [ -z "$prefix" ] || echo "install: $skill is a subdirectory of $skill_top with no git-subtree-split trailer for it; recording that repository's HEAD" >&2
    head_sha="$(git -C "$skill" rev-parse HEAD 2>/dev/null || echo unknown)"
  fi
  sha=unknown
  [ "$head_sha" = unknown ] || sha="$(printf '%.12s' "$head_sha")"
  # Dirty means what an install writes differs from the commit VERSION will
  # name: uncommitted changes to install.sh or templates/, or, in a subtree
  # host, those paths no longer matching the upstream commit (committed local edits, or a subtree
  # pull made without --squash, which leaves no new trailer). Unrelated work
  # elsewhere in a host repository is not dirt, and neither is the skill
  # repository's own docket installation (docket/, AGENTS.md, TODO.md and the
  # rest): only install.sh and templates/ decide what an install writes.
  if [ "$sha" != unknown ]; then
    if [ -n "$(git -C "$skill" status --porcelain -- install.sh templates 2>/dev/null)" ]; then
      sha="$sha-dirty"
    elif [ "$from_subtree" -eq 1 ] && git -C "$skill_top" cat-file -e "$head_sha^{commit}" 2>/dev/null \
      && ! git -C "$skill_top" diff --quiet "$head_sha" "HEAD:$prefix" -- install.sh templates 2>/dev/null; then
      echo "install: install.sh or templates/ in $skill differs from upstream commit $sha (committed local edits, or a subtree pull without --squash); recording it as dirty" >&2
      sha="$sha-dirty"
    fi
  fi
fi

begin='<!-- docket:begin -->'
end='<!-- docket:end -->'
agents="$top/AGENTS.md"
claude="$top/CLAUDE.md"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/docket-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
# Print the lines from the begin marker to the end marker, inclusive.
block() { awk -v b="$begin" -v e="$end" '$0 == b { p = 1 } p { print } $0 == e { p = 0 }' "$1"; }
block "$fragment" >"$tmp/template"
# The section a project should have, given the section it has now ($1): the
# template's text verbatim (blank lines included, so a formatter that pads the
# markers changes nothing); for each template bullet the project's line with
# the same name, else the placeholder; then, directly after the template's
# last bullet, the project's other bullets in their own order.
expected() {
  awk -v e="$end" -v have="$1" '
    function name(l,  s) { s = substr(l, 3); if (index(s, ":") == 0) return ""; return substr(s, 1, index(s, ":") - 1) }
    function flush(  i) {
      if (flushed) return
      flushed = 1
      for (i = 0; i < m; i++) if (!(order[i] in seen)) print hv[order[i]]
      for (i = 0; i < n; i++) print extra[i]
    }
    BEGIN { while ((getline l < have) > 0) if (l ~ /^- /) { k = name(l); if (k != "" && !(k in hv)) { hv[k] = l; order[m++] = k } else extra[n++] = l } }
    /^- / { k = name($0); if (k in hv) { print hv[k]; seen[k] = 1 } else print; bullets = 1; next }
    bullets || $0 == e { flush() }
    { print }' "$tmp/template"
}
# Names of template settings whose line in $1 is missing or still a placeholder.
unfilled() {
  while IFS= read -r l; do
    k="${l#- }"
    k="${k%%:*}"
    if ! grep -q "^- $k:" "$1"; then echo "$k (missing)"; elif grep "^- $k:" "$1" | grep -q '<[^>]*>'; then echo "$k (placeholder)"; fi
  done < <(grep '^- ' "$tmp/template")
}
# 0: one well-formed block; 1: no block; 2: malformed markers. Missing file counts as no block.
agents_state() {
  [ -f "$agents" ] || return 1
  local nb ne
  nb="$(grep -cxF "$begin" "$agents" || true)"
  ne="$(grep -cxF "$end" "$agents" || true)"
  if [ "$nb" -eq 0 ] && [ "$ne" -eq 0 ]; then return 1; fi
  if [ "$nb" -ne 1 ] || [ "$ne" -ne 1 ]; then return 2; fi
  [ "$(grep -nxF "$begin" "$agents" | cut -d: -f1)" -lt "$(grep -nxF "$end" "$agents" | cut -d: -f1)" ] || return 2
}
# Physical path of $1, following symlinks (macOS has no realpath -m).
realpath_of() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(dirname "$p")"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || {
    printf '%s\n' "$p"
    return
  }
  printf '%s/%s\n' "$d" "$(basename "$p")"
}
# 0 when CLAUDE.md is a symlink that resolves to AGENTS.md.
claude_links_agents() {
  [ -L "$claude" ] && [ "$(realpath_of "$claude")" = "$(realpath_of "$agents")" ]
}
# Warnings shared by install and --check; none of them changes the exit status.
warn_layout() {
  local quality="$top/docs/QUALITY.md" old="" f
  if [ -f "$quality" ] && ! grep -qE '^## Review inputs[[:space:]]*$' "$quality"; then
    echo "install: warning: $quality has no '## Review inputs' heading; the vendored review guide links it, so check-links fails until the section exists" >&2
  fi
  for f in scripts/workflow docs/TODO_GUIDE.md docs/CODE_REVIEW_GUIDE.md; do
    [ -e "$top/$f" ] && old="$old${old:+, }$f"
  done
  [ -z "$old" ] || echo "install: warning: hand-copied layout still present ($old); see the migration notes in the setup reference" >&2
  # Plans and design specs have conventional homes (docket/CONTRACT.md); a
  # directory named after the tool that wrote them is migrated by hand.
  [ ! -e "$top/docs/superpowers" ] || echo "install: warning: $top/docs/superpowers exists; move its plans to plans/ and its specs to docs/specs/ (see the setup reference)" >&2
  if agents_state && block "$agents" | grep '^- .*docs/superpowers' >/dev/null; then
    echo "install: warning: a bullet in the Docket section of $agents names docs/superpowers; plans and design specs live where docket/CONTRACT.md says, so drop it" >&2
  fi
}
exclude="$(git -C "$top" rev-parse --git-path info/exclude)"
case "$exclude" in /*) ;; *) exclude="$top/$exclude" ;; esac

if [ "$check" -eq 1 ]; then
  status=0
  if [ ! -d "$dst" ]; then
    echo "install: $dst does not exist; nothing is installed" >&2
    exit 1
  fi
  installed=""
  if [ -f "$dst/VERSION" ]; then
    echo "installed: $(cat "$dst/VERSION")"
    installed="$(cut -d' ' -f1 "$dst/VERSION")"
    installed="${installed%-dirty}"
    if [ "$self" -eq 1 ] && ! printf 'self\n' | cmp -s - "$dst/VERSION"; then
      echo "install: $dst/VERSION is not the line 'self' that the skill's own repository records; rerun install.sh --self" >&2
      status=1
    fi
  else
    echo "installed: VERSION file missing" >&2
    status=1
  fi
  if [ "$self" -eq 1 ]; then
    echo "skill:     self (templates/docket at this commit)"
  else
    echo "skill:     $sha"
  fi
  # Compare the installed commit with this checkout's HEAD before diffing: a
  # checkout behind the project would report the project's newer files as drift.
  # In self mode the source is in the same tree, so there is nothing to compare.
  behind=0
  if [ "$self" -eq 0 ] && [ "$installed" = self ]; then
    echo "install: $dst/VERSION is 'self', which only the skill's own repository records; comparing the files anyway" >&2
  elif [ "$self" -eq 0 ] && [ "$head_sha" != unknown ] && [ -n "$installed" ] && [ "$installed" != unknown ]; then
    if ! git -C "$skill" cat-file -e "$installed^{commit}" 2>/dev/null; then
      echo "install: the installed commit ($installed) is not in this skill checkout (fetch it, or the copy came from another fork); comparing the files anyway" >&2
    elif [ "$(git -C "$skill" rev-parse "$installed^{commit}")" = "$head_sha" ]; then
      :
    elif git -C "$skill" merge-base --is-ancestor "$head_sha" "$installed"; then
      echo "install: the installed copy ($installed) is newer than this skill checkout ($sha); update the skill checkout before resyncing" >&2
      exit 1
    elif git -C "$skill" merge-base --is-ancestor "$installed" "$head_sha"; then
      behind=1
    else
      echo "install: the installed commit ($installed) and this skill checkout ($sha) have diverged; comparing the files anyway" >&2
    fi
  fi
  show_diff -u -r -x VERSION "$src" "$dst" || status=1
  # diff -r ignores modes; start-work.sh runs claim-check.sh directly, so a
  # lost executable bit is drift too, on disk and in the committed mode.
  for f in "$dst"/scripts/*.sh; do
    [ -x "$f" ] || {
      echo "install: $f is not executable (chmod +x it)" >&2
      status=1
    }
  done
  modes="$(git -C "$top" ls-files -s -- docket/scripts 2>/dev/null | awk '$4 ~ /\.sh$/ && $1 != "100755" { print $4 " (" $1 ")" }')"
  [ -z "$modes" ] || {
    echo "install: committed as other than 100755: $(echo "$modes" | paste -sd, - | sed 's/,/, /g') (git update-index --chmod=+x)" >&2
    status=1
  }
  if agents_state; then
    block "$agents" >"$tmp/have"
    expected "$tmp/have" >"$tmp/want"
    show_diff -u --label "expected Docket section" --label "$agents" "$tmp/want" "$tmp/have" || status=1
    unfilled "$tmp/have" >"$tmp/unfilled"
    if [ -s "$tmp/unfilled" ]; then
      echo "install: settings not filled in $agents: $(paste -sd, "$tmp/unfilled" | sed 's/,/, /g')" >&2
      status=1
    fi
  elif [ $? -eq 1 ]; then
    echo "install: $agents has no Docket section ($begin ... $end)" >&2
    status=1
  else
    echo "install: $agents has malformed docket markers; expected exactly one $begin before one $end" >&2
    status=1
  fi
  if [ -e "$claude" ] || [ -L "$claude" ]; then
    if claude_links_agents; then
      :
    elif [ -L "$claude" ]; then
      echo "install: warning: $claude is a symlink to $(readlink "$claude"), not to AGENTS.md; make sure it imports AGENTS.md" >&2
    elif ! grep -qx '@AGENTS.md' "$claude"; then
      echo "install: warning: $claude lacks the line '@AGENTS.md'; rerun install.sh to append it" >&2
    fi
  fi
  { grep -qxF '.feral/' "$exclude" 2>/dev/null; } && echo "install: warning: stale '.feral/' line in $exclude; rerun install.sh to remove it" >&2
  warn_layout
  if [ "$status" -eq 0 ]; then
    echo "install: $dst and the Docket section of $agents match the skill"
    [ "$behind" -eq 0 ] || echo "install: VERSION names $installed, behind this checkout ($sha), but the files match; rerun install.sh to record the current commit"
  else
    if [ "$self" -eq 1 ]; then
      echo "install: $top differs from templates/; rerun install.sh --self to resync" >&2
    else
      echo "install: $top differs from the skill; rerun install.sh to resync" >&2
    fi
  fi
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
if [ "$self" -eq 1 ]; then
  printf 'self\n' >"$dst/VERSION"
else
  printf '%s %s\n' "$sha" "$(date -u +%Y-%m-%d)" >"$dst/VERSION"
fi

# Local, uncommitted docket state lives in .docket/; keep it out of git. The
# layout before docket/ used .feral/ for the same purpose; drop its line.
mkdir -p "$(dirname "$exclude")"
added_exclude=0
removed_exclude=0
if ! { grep -qxF '.docket/' "$exclude" 2>/dev/null; }; then
  printf '.docket/\n' >>"$exclude"
  added_exclude=1
fi
if { grep -qxF '.feral/' "$exclude" 2>/dev/null; }; then
  { grep -vxF '.feral/' "$exclude" || true; } >"$tmp/exclude"
  cp "$tmp/exclude" "$exclude"
  removed_exclude=1
fi

# Report, but never remove, files the skill no longer ships.
while IFS= read -r rel; do
  rel="${rel#./}"
  [ "$rel" = VERSION ] && continue
  [ -f "$src/$rel" ] || echo "install: warning: $dst/$rel is not part of the skill; remove it by hand if it is obsolete" >&2
done < <(cd "$dst" && find . -type f | sort)

# The project points its agents at the vendored contract through the Docket
# section of AGENTS.md. Only that section is written; the rest is left alone.
status=0
agents_note=""
if agents_state; then
  block "$agents" >"$tmp/have"
  expected "$tmp/have" >"$tmp/want"
  if cmp -s "$tmp/want" "$tmp/have"; then
    agents_note="Docket section of $agents is current"
  else
    awk -v b="$begin" -v e="$end" -v f="$tmp/want" '
      $0 == b { while ((getline l < f) > 0) print l; skip = 1; next }
      skip { if ($0 == e) skip = 0; next }
      { print }' "$agents" >"$tmp/agents"
    cp "$tmp/agents" "$agents"
    agents_note="rewrote the Docket section of $agents, keeping its settings"
  fi
  unfilled "$tmp/want" >"$tmp/unfilled"
elif [ $? -eq 1 ]; then
  if [ -f "$agents" ]; then
    # Insert before the first "## " heading outside fenced code, so the section
    # follows the H1 and its introduction; append when there is no such heading.
    awk -v f="$tmp/template" '
      function insert() { while ((getline l < f) > 0) print l; done = 1 }
      /^(```|~~~)/ { fence = !fence }
      !fence && !done && /^## / { if (NR > 1 && prev != "") print ""; insert(); print "" }
      { print; prev = $0 }
      END { if (!done) { if (NR > 0 && prev != "") print ""; insert() } }' "$agents" >"$tmp/agents"
    cp "$tmp/agents" "$agents"
    where="$(grep -nxF "$begin" "$agents" | cut -d: -f1)"
    after="$(sed -n "$(($(grep -nxF "$end" "$agents" | cut -d: -f1) + 2))p" "$agents")"
    if [ -n "$after" ]; then
      agents_note="inserted the Docket section into $agents at line $where, before '$after' (moving it is safe)"
    else agents_note="appended the Docket section to $agents (moving it is safe)"; fi
  else
    cp "$fragment" "$agents"
    agents_note="created $agents with the Docket section"
  fi
  unfilled "$tmp/template" >"$tmp/unfilled"
else
  echo "install: $agents has malformed docket markers; expected exactly one $begin before one $end; fix it by hand" >&2
  status=1
  : >"$tmp/unfilled"
fi
if [ -s "$tmp/unfilled" ]; then agents_note="$agents_note; settings to fill in: $(paste -sd, "$tmp/unfilled" | sed 's/,/, /g')"; fi
# Claude Code reads CLAUDE.md, so an existing one needs the import line. The
# line is appended to a regular file, never through a symlink, and no CLAUDE.md
# is created. A symlink to AGENTS.md already imports it.
claude_note=""
if [ -L "$claude" ]; then
  if claude_links_agents; then
    claude_note="$claude is a symlink to AGENTS.md; nothing to add"
  else echo "install: warning: $claude is a symlink to $(readlink "$claude"), not to AGENTS.md; not writing through it, add '@AGENTS.md' to the target by hand" >&2; fi
elif [ -f "$claude" ] && ! grep -qx '@AGENTS.md' "$claude"; then
  [ -z "$(tail -c 1 "$claude")" ] || printf '\n' >>"$claude"
  printf '\n@AGENTS.md\n' >>"$claude"
  claude_note="appended @AGENTS.md to $claude"
fi

echo "install: copied $copied files from $src to $dst (VERSION $(cat "$dst/VERSION"))"
[ -z "$agents_note" ] || echo "install: $agents_note"
[ -z "$claude_note" ] || echo "install: $claude_note"
[ "$added_exclude" -eq 1 ] && echo "install: added .docket/ to $exclude"
[ "$removed_exclude" -eq 1 ] && echo "install: removed the stale .feral/ line from $exclude"
warn_layout
echo "install: changes in $top:"
git -C "$top" status --short docket/ AGENTS.md CLAUDE.md
exit "$status"
