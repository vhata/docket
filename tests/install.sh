#!/usr/bin/env bash
# Regression checks for install.sh, run against disposable git repositories.
# The installer under test is a scratch clone of this checkout with the working
# tree's install.sh and templates committed on top, so uncommitted changes are
# exercised and the clone's history can be moved around for the VERSION
# comparison cases without touching this checkout.
#
# Covers: first install creating AGENTS.md; insertion after the introduction
# and before the first "## " heading, or at the end; idempotent reruns;
# settings kept by name and a deleted one re-added; --check on placeholders,
# content drift and executable bits; CLAUDE.md as a symlink, as a regular file
# and absent; the stale .feral/ exclude line; hand-copied layout, missing
# Review inputs and docs/superpowers (directory, and a bullet inside but not
# outside the Docket section or past a missing end marker) warnings; VERSION
# newer than, behind, or unknown to the checkout; a template with blank lines
# inside the markers; self-install refused without --self; --self into the
# skill's own clone (VERSION 'self', --self --check passing, failing on an
# unsynced templates/docket/ edit and on a VERSION other than 'self'), refused
# for another repository, a sibling worktree and a subtree host; any install
# into a separate clone of the skill refused, --self and --check included, and
# into a repository whose docket/ is the skill; a normal --check of a copied
# VERSION 'self'; a squashed-subtree host, reached directly and through a
# symlink, with an unrelated host change and a committed README edit under
# the skill (both clean) and a committed edit under its templates/ (dirty).
#
# Usage: bash tests/install.sh   (from anywhere; needs git and bash 3.2+)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT
log="$work/log"

skill="$work/skill"
git clone --quiet "$root" "$skill"
git -C "$skill" config user.name 'Install fixture'
git -C "$skill" config user.email 'install-fixture@example.invalid'
git -C "$skill" config core.hooksPath /dev/null
rm -rf "$skill/templates"
cp -R "$root/templates" "$skill/templates"
cp "$root/install.sh" "$skill/install.sh"
git -C "$skill" add -A
git -C "$skill" commit --quiet --allow-empty -m 'Working tree snapshot'
snapshot="$(git -C "$skill" rev-parse HEAD)"
inst="$skill/install.sh"
begin='<!-- docket:begin -->'; end='<!-- docket:end -->'

# run EXPECTED_EXIT LABEL COMMAND...: run the command, keep its output in $log.
run() {
  local want="$1" label="$2" got=0; shift 2
  "$@" > "$log" 2>&1 || got=$?
  [ "$got" -eq "$want" ] || { echo "install-test: $label exited $got, expected $want" >&2; cat "$log" >&2; exit 1; }
}
expect() { grep -Fq -- "$2" "$log" || { echo "install-test: $1" >&2; cat "$log" >&2; exit 1; }; }
refute() { if grep -Fq -- "$2" "$log"; then echo "install-test: $1" >&2; cat "$log" >&2; exit 1; fi; }
fail() { echo "install-test: $*" >&2; exit 1; }
# A fresh project repository at $work/NAME with one commit.
newproj() {
  mkdir -p "$work/$1"
  git -C "$work/$1" init --quiet
  git -C "$work/$1" symbolic-ref HEAD refs/heads/main
  git -C "$work/$1" config user.name 'Project fixture'
  git -C "$work/$1" config user.email 'project-fixture@example.invalid'
  git -C "$work/$1" config core.hooksPath /dev/null
  git -C "$work/$1" commit --quiet --allow-empty -m 'Initial commit'
}
# Replace every <placeholder> on the settings bullets of PROJECT/AGENTS.md.
fill() { sed -i.bak '/^- /s/<[^>]*>/filled/g' "$1/AGENTS.md"; rm -f "$1/AGENTS.md.bak"; }
lineof() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }

# First install into a project with no AGENTS.md and no CLAUDE.md.
newproj one; p="$work/one"
run 0 'first install' bash "$inst" "$p"
expect 'first install did not report creating AGENTS.md' "created $p/AGENTS.md"
expect 'first install did not list the settings to fill in' 'settings to fill in: Queue areas (placeholder), Concurrency cap (placeholder)'
[ -f "$p/AGENTS.md" ] || fail 'AGENTS.md was not created'
[ ! -e "$p/CLAUDE.md" ] || fail 'CLAUDE.md was created although none existed'
[ -f "$p/docket/VERSION" ] || fail 'VERSION was not written'
for f in "$p"/docket/scripts/*.sh; do [ -x "$f" ] || fail "$f is not executable after install"; done
grep -qxF '.docket/' "$p/.git/info/exclude" || fail '.docket/ was not added to the exclude file'
refute 'install warned about docs/superpowers in a project without it' 'docs/superpowers'
run 1 '--check with placeholders' bash "$inst" --check "$p"
expect '--check did not name the placeholder settings' 'settings not filled in'
fill "$p"
run 0 '--check after filling' bash "$inst" --check "$p"
expect '--check did not report a match' 'match the skill'
refute '--check warned about docs/superpowers in a project without it' 'docs/superpowers'
cp "$p/AGENTS.md" "$work/one-agents.before"
run 0 'idempotent rerun' bash "$inst" "$p"
expect 'rerun did not report the section as current' 'is current'
cmp -s "$p/AGENTS.md" "$work/one-agents.before" || fail 'rerun changed AGENTS.md'
# Settings are kept by name; a deleted one comes back as a placeholder.
sed -i.bak -e 's/^- Concurrency cap: .*/- Concurrency cap: 2 heavy builds or runs at once./' -e '/^- Environment:/d' "$p/AGENTS.md"; rm -f "$p/AGENTS.md.bak"
run 0 'rerun after editing settings' bash "$inst" "$p"
expect 'rerun did not rewrite the section' 'rewrote the Docket section'
expect 'rerun did not report the re-added setting' 'Environment (placeholder)'
grep -qxF -- '- Concurrency cap: 2 heavy builds or runs at once.' "$p/AGENTS.md" || fail 'edited setting was not kept'
grep -q '^- Environment: <' "$p/AGENTS.md" || fail 'deleted setting was not re-added as a placeholder'
[ "$(grep -c '^- ' "$p/AGENTS.md")" -eq 5 ] || fail 'settings list has the wrong number of bullets'
fill "$p"
# Drift: content, the executable bit on disk, and the committed mode.
printf '\n' >> "$p/docket/README.md"
run 1 '--check with content drift' bash "$inst" --check "$p"
expect 'content drift was not reported' 'rerun install.sh to resync'
run 0 'resync after content drift' bash "$inst" "$p"
chmod -x "$p/docket/scripts/ci.sh"
run 1 '--check with a lost executable bit' bash "$inst" --check "$p"
expect 'lost executable bit was not reported' 'ci.sh is not executable'
chmod +x "$p/docket/scripts/ci.sh"
git -C "$p" add -A
git -C "$p" update-index --chmod=-x docket/scripts/ci.sh
run 1 '--check with a non-executable committed mode' bash "$inst" --check "$p"
expect 'committed mode was not reported' 'committed as other than 100755: docket/scripts/ci.sh (100644)'
git -C "$p" update-index --chmod=+x docket/scripts/ci.sh
run 0 '--check with the committed mode fixed' bash "$inst" --check "$p"
rm "$p/docket/VERSION"
run 1 '--check without VERSION' bash "$inst" --check "$p"
expect 'missing VERSION was not reported' 'VERSION file missing'

# Existing AGENTS.md with an introduction and sections; CLAUDE.md is a symlink
# to it; the old layout left a .feral/ exclude line, scripts/workflow/ and a
# QUALITY.md without Review inputs; the superpowers plugin left
# docs/superpowers/ and a settings bullet pointing at it.
newproj two; p="$work/two"
printf '# Project\n\nIntro paragraph.\nSecond intro line.\n\n## Other\n\nOther text.\n\n## Last\n\nMore.\n' > "$p/AGENTS.md"
ln -s AGENTS.md "$p/CLAUDE.md"
printf '.feral/\nscratch/\n' >> "$p/.git/info/exclude"
mkdir -p "$p/scripts/workflow" "$p/docs"
printf '# Quality\n\n## What quality means here\n\nText.\n' > "$p/docs/QUALITY.md"
mkdir -p "$p/docs/superpowers/plans"
printf '# A plan\n' > "$p/docs/superpowers/plans/2026-01-01-a-plan.md"
run 0 'install into a project with sections' bash "$inst" "$p"
expect 'insertion point was not reported' "before '## Other'"
l_intro="$(lineof "$p/AGENTS.md" 'Second intro line.')"; l_begin="$(lineof "$p/AGENTS.md" "$begin")"; l_end="$(lineof "$p/AGENTS.md" "$end")"; l_other="$(lineof "$p/AGENTS.md" '## Other')"
[ "$l_intro" -lt "$l_begin" ] && [ "$l_begin" -lt "$l_other" ] || fail "section landed at line $l_begin, not between the introduction ($l_intro) and ## Other ($l_other)"
[ -z "$(sed -n "$((l_begin - 1))p" "$p/AGENTS.md")" ] || fail 'no blank line before the section'
[ -z "$(sed -n "$((l_end + 1))p" "$p/AGENTS.md")" ] || fail 'no blank line after the section'
[ "$(sed -n "$((l_end + 2))p" "$p/AGENTS.md")" = '## Other' ] || fail 'the section is not directly before ## Other'
grep -q '^## Last' "$p/AGENTS.md" || fail 'later sections were lost'
! grep -qx '@AGENTS.md' "$p/AGENTS.md" || fail 'the import line was written through the CLAUDE.md symlink into AGENTS.md'
[ -L "$p/CLAUDE.md" ] || fail 'the CLAUDE.md symlink was replaced'
expect 'symlinked CLAUDE.md was not recognised' 'CLAUDE.md is a symlink to AGENTS.md'
! grep -qxF '.feral/' "$p/.git/info/exclude" || fail 'stale .feral/ exclude line was kept'
grep -qxF 'scratch/' "$p/.git/info/exclude" || fail 'other exclude lines were lost'
grep -qxF '.docket/' "$p/.git/info/exclude" || fail '.docket/ was not added to the exclude file'
expect 'removed .feral/ line was not reported' 'removed the stale .feral/ line'
expect 'hand-copied layout was not reported' 'hand-copied layout still present (scripts/workflow)'
expect 'missing Review inputs was not reported' "QUALITY.md has no '## Review inputs' heading"
expect 'docs/superpowers was not reported' "$p/docs/superpowers exists"
[ -f "$p/docs/superpowers/plans/2026-01-01-a-plan.md" ] || fail 'install moved or removed docs/superpowers'
fill "$p"
sed -i.bak '/^- Environment:/a\
- Plans: `docs/superpowers/plans/YYYY-MM-DD-<slug>.md`, not `plans/`.
' "$p/AGENTS.md"; rm -f "$p/AGENTS.md.bak"
run 0 'rerun with a settings bullet naming docs/superpowers' bash "$inst" "$p"
expect 'install did not report the settings bullet naming docs/superpowers' 'names docs/superpowers'
grep -q '^- Plans: `docs/superpowers/' "$p/AGENTS.md" || fail 'install dropped the settings bullet it should only warn about'
run 0 '--check with warnings only' bash "$inst" --check "$p"
expect '--check dropped the layout warning' 'hand-copied layout still present'
expect '--check dropped the Review inputs warning' 'no '"'"'## Review inputs'"'"' heading'
refute '--check warned about a CLAUDE.md symlink to AGENTS.md' 'CLAUDE.md'
expect '--check dropped the docs/superpowers warning' "$p/docs/superpowers exists"
expect '--check did not report the settings bullet naming docs/superpowers' 'names docs/superpowers'
printf '\n## Review inputs\n\n- Focus areas: none yet.\n' >> "$p/docs/QUALITY.md"
rm -r "$p/scripts/workflow" "$p/docs/superpowers"
sed -i.bak '/^- Plans: /d' "$p/AGENTS.md"; rm -f "$p/AGENTS.md.bak"
run 0 '--check after the migration' bash "$inst" --check "$p"
refute 'Review inputs warning persisted' 'Review inputs'
refute 'layout warning persisted' 'hand-copied layout'
refute 'docs/superpowers warning persisted' 'docs/superpowers'
cp "$p/AGENTS.md" "$work/two-agents.before"
run 0 'rerun with the section in the middle' bash "$inst" "$p"
cmp -s "$p/AGENTS.md" "$work/two-agents.before" || fail 'rerun changed an AGENTS.md whose section sits in the middle'

# AGENTS.md with no "## " heading gets the section at the end; a regular
# CLAUDE.md without the import line gets it appended after a blank line.
newproj three; p="$work/three"
printf '# Project\n\nIntro only.\n' > "$p/AGENTS.md"
printf '# Claude\n\nNotes without a trailing newline.' > "$p/CLAUDE.md"
run 0 'install with no sections' bash "$inst" "$p"
expect 'appending was not reported' "appended the Docket section to $p/AGENTS.md"
[ "$(tail -1 "$p/AGENTS.md")" = "$end" ] || fail 'the section is not at the end of AGENTS.md'
l_intro="$(lineof "$p/AGENTS.md" 'Intro only.')"; l_begin="$(lineof "$p/AGENTS.md" "$begin")"
[ "$((l_intro + 2))" -eq "$l_begin" ] || fail 'the appended section is not separated by one blank line'
[ "$(printf '# Claude\n\nNotes without a trailing newline.\n\n@AGENTS.md\n')" = "$(cat "$p/CLAUDE.md")" ] || fail "CLAUDE.md was not appended to as expected: $(cat "$p/CLAUDE.md")"
expect 'CLAUDE.md append was not reported' 'appended @AGENTS.md'
run 0 'rerun with the import line present' bash "$inst" "$p"
[ "$(grep -c '^@AGENTS.md$' "$p/CLAUDE.md")" -eq 1 ] || fail 'the import line was appended twice'
fill "$p"
run 0 '--check with a regular CLAUDE.md' bash "$inst" --check "$p"
refute '--check warned about a CLAUDE.md that has the line' 'CLAUDE.md'
printf '# Claude\n' > "$p/CLAUDE.md"
run 0 '--check with the import line missing' bash "$inst" --check "$p"
expect '--check did not warn about the missing import line' "lacks the line '@AGENTS.md'"
# A bullet naming docs/superpowers outside the Docket section is the project's.
printf '\n- Old plans: `docs/superpowers/plans/`.\n' >> "$p/AGENTS.md"
run 0 '--check with a docs/superpowers bullet outside the section' bash "$inst" --check "$p"
refute '--check warned about a bullet outside the Docket section' 'docs/superpowers'
# With the end marker gone the bullet is not inside a section either.
sed -i.bak "/^$end\$/d" "$p/AGENTS.md"; rm -f "$p/AGENTS.md.bak"
run 1 '--check with malformed markers and a docs/superpowers bullet' bash "$inst" --check "$p"
expect '--check did not report the malformed markers' 'malformed docket markers'
refute '--check read a bullet past a missing end marker' 'names docs/superpowers'

# CLAUDE.md as a symlink to something else is never written through.
newproj four; p="$work/four"
printf '# Elsewhere\n' > "$p/other.md"
ln -s other.md "$p/CLAUDE.md"
run 0 'install with a foreign CLAUDE.md symlink' bash "$inst" "$p"
expect 'foreign symlink was not reported' 'is a symlink to other.md, not to AGENTS.md'
[ "$(cat "$p/other.md")" = '# Elsewhere' ] || fail 'the import line was written through a symlink to another file'
fill "$p"
run 0 '--check with a foreign CLAUDE.md symlink' bash "$inst" --check "$p"
expect '--check did not warn about the foreign symlink' 'not to AGENTS.md'

# VERSION against the skill checkout: newer, behind, unknown.
newproj five; p="$work/five"
run 0 'install for the VERSION cases' bash "$inst" "$p"
fill "$p"
git -C "$skill" checkout --quiet -b newer
printf '\n' >> "$skill/templates/docket/README.md"
git -C "$skill" commit --quiet -am 'Throwaway change in a newer skill commit'
newer="$(git -C "$skill" rev-parse --short=12 HEAD)"
git -C "$skill" checkout --quiet --detach "$snapshot"
printf '%s 2026-10-11\n' "$newer" > "$p/docket/VERSION"
run 1 '--check from a checkout behind the installed commit' bash "$inst" --check "$p"
expect 'newer installed copy was not reported' "the installed copy ($newer) is newer than this skill checkout"
refute 'a file diff was printed although the checkout is behind' 'rerun install.sh to resync'
refute 'files were compared although the checkout is behind' 'Only in'
behind="$(git -C "$skill" rev-parse --short=12 "$snapshot~1")"
printf '%s 2026-10-11\n' "$behind" > "$p/docket/VERSION"
run 0 '--check with VERSION behind HEAD and matching files' bash "$inst" --check "$p"
expect 'behind VERSION with matching files was not noted' "VERSION names $behind, behind this checkout"
expect 'behind VERSION did not still report a match' 'match the skill'
printf '%s-dirty 2026-10-11\n' "$behind" > "$p/docket/VERSION"
run 0 '--check with a -dirty VERSION behind HEAD' bash "$inst" --check "$p"
expect 'dirty suffix was not stripped before the comparison' "VERSION names $behind, behind this checkout"
printf '0123456789ab 2026-01-01\n' > "$p/docket/VERSION"
run 0 '--check with a VERSION unknown to the checkout' bash "$inst" --check "$p"
expect 'unknown VERSION was not reported' 'is not in this skill checkout'
expect 'unknown VERSION did not still diff the files' 'match the skill'
printf '\n' >> "$p/docket/README.md"
run 1 '--check with a VERSION unknown to the checkout and drift' bash "$inst" --check "$p"
expect 'unknown VERSION hid the drift' 'rerun install.sh to resync'

# Self-install is refused without --self.
run 2 'self-install by target' bash "$inst" "$skill"
expect 'self-install by target was not refused' 'refusing to install the skill into its own repository'
expect 'self-install refusal did not mention --self' 'pass --self'
run 2 'self-install from inside the skill' sh -c 'cd "$1" && bash install.sh' sh "$skill"
expect 'self-install from inside was not refused' 'refusing to install the skill into its own repository'
run 2 '--check of the skill without --self' bash "$inst" --check "$skill"
expect '--check of the skill without --self was not refused' 'refusing to install the skill into its own repository'
run 2 'target that is not a repository' bash "$inst" "$work"
expect 'non-repository target was not refused' 'is not inside a git repository'
# --self is refused for any other repository.
newproj selfother; p="$work/selfother"
run 2 '--self into another repository' bash "$inst" --self "$p"
expect '--self into another repository was not refused' "--self is only for the skill's own repository"
run 2 '--self --check of another repository' bash "$inst" --self --check "$p"
expect '--self --check of another repository was not refused' "--self is only for the skill's own repository"
[ ! -e "$p/docket" ] || fail '--self into another repository wrote docket/'

# --self vendors docket/ into the skill's own repository, in a separate clone
# so the checkout the other cases install from stays clean.
me="$work/selfskill"
git clone --quiet "$skill" "$me"
git -C "$me" checkout --quiet --detach "$snapshot"
git -C "$me" config user.name 'Self fixture'
git -C "$me" config user.email 'self-fixture@example.invalid'
git -C "$me" config core.hooksPath /dev/null
# The skill repository commits its own docket installation; remove it so the
# first --self below is a first install.
git -C "$me" rm -rq --ignore-unmatch docket AGENTS.md CLAUDE.md
git -C "$me" commit --quiet --allow-empty -m 'Remove the self installation'
run 0 '--self install' bash "$me/install.sh" --self "$me"
printf 'self\n' | cmp -s - "$me/docket/VERSION" || fail "--self wrote VERSION '$(cat "$me/docket/VERSION")', expected the line 'self'"
grep -qxF "$begin" "$me/AGENTS.md" || fail '--self did not write the Docket section of AGENTS.md'
for f in "$me"/docket/scripts/*.sh; do [ -x "$f" ] || fail "$f is not executable after --self"; done
grep -qxF '.docket/' "$me/.git/info/exclude" || fail '--self did not add .docket/ to the exclude file'
refute '--self reported a subtree' 'git-subtree-split'
refute '--self recorded a dirty tree' 'dirty'
diff -r -x VERSION "$me/templates/docket" "$me/docket" >/dev/null || fail '--self did not copy templates/docket/ byte for byte'
fill "$me"
run 0 '--self --check after install' bash "$me/install.sh" --self --check "$me"
expect '--self --check did not print the installed line' 'installed: self'
expect '--self --check did not print the skill line' 'skill:     self (templates/docket at this commit)'
expect '--self --check did not report a match' 'match the skill'
refute '--self --check compared commits' 'newer than'
refute '--self --check compared commits' 'behind'
refute '--self --check compared commits' 'not in this skill checkout'
git -C "$me" add -A
git -C "$me" commit --quiet -m 'Vendor docket into the skill repository'
run 0 '--self --check from inside, committed' sh -c 'cd "$1" && bash install.sh --self --check' sh "$me"
expect '--self --check from inside did not report a match' 'match the skill'
# An edit under templates/docket/ without a resync is drift.
printf '\n' >> "$me/templates/docket/README.md"
run 1 '--self --check after editing templates/docket' bash "$me/install.sh" --self --check "$me"
expect '--self --check did not report the unsynced template edit' 'rerun install.sh --self to resync'
run 0 '--self resync after editing templates/docket' sh -c 'cd "$1" && bash install.sh --self' sh "$me"
printf 'self\n' | cmp -s - "$me/docket/VERSION" || fail "--self resync wrote VERSION '$(cat "$me/docket/VERSION")'"
refute '--self resync with a dirty tree warned' 'dirty'
run 0 '--self --check after the resync' bash "$me/install.sh" --self --check "$me"
# VERSION must be exactly 'self'.
printf '%s 2026-10-11\n' "$(git -C "$me" rev-parse --short=12 HEAD)" > "$me/docket/VERSION"
run 1 '--self --check with a sha VERSION' bash "$me/install.sh" --self --check "$me"
expect '--self --check did not reject a sha VERSION' "VERSION is not the line 'self'"
refute '--self --check compared a sha VERSION with the checkout' 'newer than'
rm "$me/docket/VERSION"
run 1 '--self --check without VERSION' bash "$me/install.sh" --self --check "$me"
expect '--self --check did not report the missing VERSION' 'VERSION file missing'
run 0 '--self restoring VERSION' bash "$me/install.sh" --self "$me"
# A sibling worktree of the skill is the same repository, but --self only
# installs into the checkout it runs from.
git -C "$me" worktree add --quiet --detach "$work/selfwt" HEAD
run 2 '--self into a sibling worktree' bash "$me/install.sh" --self "$work/selfwt"
expect '--self into a sibling worktree was not refused' 'installs only into the checkout it runs from'
run 2 'sibling worktree without --self' bash "$me/install.sh" "$work/selfwt"
expect 'sibling worktree without --self was not refused' 'refusing to install the skill into its own repository'
# From inside the sibling worktree, targeting itself, --self is the everyday
# case for a harness that gives each task its own worktree.
run 0 '--self inside a worktree' bash "$work/selfwt/install.sh" --self "$work/selfwt"
fill "$work/selfwt"
run 0 '--self --check inside a worktree' bash "$work/selfwt/install.sh" --self --check "$work/selfwt"
# A separate clone of the skill, such as the installed copy run against the
# development repository, is refused as a target: it installs only from its
# own install.sh, so its docket/ and VERSION 'self' are left alone.
cp -R "$me/docket" "$work/selfbefore"
run 2 'install into another checkout of the skill' bash "$inst" "$me"
expect 'another checkout of the skill was not refused' 'which is another checkout of the skill'
expect 'the refusal did not name the target checkout installer' "run $me/install.sh --self there"
run 2 'install into a subdirectory of another checkout of the skill' bash "$inst" "$me/references"
expect 'a subdirectory of another checkout of the skill was not refused' 'which is another checkout of the skill'
run 2 '--check of another checkout of the skill' bash "$inst" --check "$me"
expect '--check of another checkout of the skill was not refused' 'which is another checkout of the skill'
expect 'the --check refusal did not suggest --self --check' "run $me/install.sh --self --check there"
run 2 '--self into another checkout of the skill' bash "$inst" --self "$me"
expect '--self into another checkout of the skill was not refused' "run $me/install.sh --self for $me"
run 2 'install into another checkout of the skill from inside it' sh -c 'cd "$1" && bash "$2"' sh "$me" "$inst"
expect 'another checkout of the skill from inside it was not refused' 'which is another checkout of the skill'
diff -r "$work/selfbefore" "$me/docket" >/dev/null || fail 'a refused install changed docket/ in another checkout of the skill'
# A skills repository holding the skill as its docket/ subdirectory is refused
# whether the target is the repository or the skill inside it: docket/ there
# is the skill, and an install would write the vendored files over it.
newproj skills; p="$work/skills"
git -C "$skill" archive --prefix=docket/ HEAD | tar -x -C "$p"
git -C "$p" add -A && git -C "$p" commit --quiet -m 'Add the skill under docket/'
run 2 'install into the skill inside a skills repository' bash "$inst" "$p/docket"
expect 'the skill inside a skills repository was not refused' 'whose docket/ is a copy of the skill'
run 2 'install into a skills repository' bash "$inst" "$p"
expect 'a skills repository was not refused' 'whose docket/ is a copy of the skill'
[ -z "$(git -C "$p" status --porcelain)" ] || fail "a refused install changed the skills repository: $(git -C "$p" status --porcelain)"
# Only install.sh and templates/ decide what an install writes, so uncommitted
# work in the skill repository's own docket files does not make a project's
# install dirty, while an uncommitted template edit does.
git -C "$me" add -A && git -C "$me" commit --quiet -m 'Self fixture state'
printf 'scratch\n' > "$me/scratch-notes.md"
printf '\n' >> "$me/AGENTS.md"
newproj fromself; p="$work/fromself"
run 0 'install with uncommitted non-template work in the skill' bash "$me/install.sh" "$p"
grep -q -- '-dirty' "$p/docket/VERSION" && fail "uncommitted non-template work made the install dirty: $(cat "$p/docket/VERSION")"
printf '\n' >> "$me/templates/README.md"
run 0 'install with an uncommitted template edit' bash "$me/install.sh" "$p"
grep -q -- '-dirty' "$p/docket/VERSION" || fail "an uncommitted template edit did not make the install dirty: $(cat "$p/docket/VERSION")"
git -C "$me" checkout --quiet -- templates/README.md AGENTS.md; rm -f "$me/scratch-notes.md"
# A project holding a copy of the skill's own docket/ (VERSION 'self') is
# compared on its files by a normal --check.
newproj selfcopy; p="$work/selfcopy"
run 0 'install for the copied self VERSION case' bash "$inst" "$p"
fill "$p"
printf 'self\n' > "$p/docket/VERSION"
run 0 '--check with a VERSION of self' bash "$inst" --check "$p"
expect '--check did not explain a VERSION of self' "is 'self', which only the skill's own repository records"
expect '--check with a VERSION of self did not still diff the files' 'match the skill'

# A template with a blank line after the begin marker and before the end
# marker (the shape Markdown formatters produce): a project installed from the
# unpadded template is rewritten to it with its settings kept, and the padded
# block compares equal afterwards, extra bullets included.
# Build both shapes from whichever the checkout ships: strip blank lines next
# to the markers for the unpadded copy, then add exactly one for the padded one.
cp "$skill/templates/AGENTS.md" "$work/template.orig"
awk -v b="$begin" -v e="$end" '{ l[NR] = $0 } END {
  for (i = 1; i <= NR; i++) {
    if (l[i] == "" && (l[i-1] == b || l[i+1] == e)) continue
    print l[i]
  } }' "$work/template.orig" > "$work/unpadded.md"
awk -v b="$begin" -v e="$end" '{ l[NR] = $0 } END {
  for (i = 1; i <= NR; i++) {
    if (l[i] == b) { print l[i]; if (l[i+1] != "") print ""; continue }
    if (l[i] == e) { if (l[i-1] != "") print ""; print l[i]; continue }
    print l[i]
  } }' "$work/template.orig" > "$work/padded.md"
cp "$work/unpadded.md" "$skill/templates/AGENTS.md"
newproj six; p="$work/six"
run 0 'install from the unpadded template' bash "$inst" "$p"
sed -i.bak 's/^- Concurrency cap: .*/- Concurrency cap: 3 heavy builds or runs at once./' "$p/AGENTS.md"; rm -f "$p/AGENTS.md.bak"
fill "$p"
cp "$work/padded.md" "$skill/templates/AGENTS.md"
run 0 'rerun with the padded template' bash "$inst" "$p"
expect 'padded template did not rewrite the section' 'rewrote the Docket section'
l_begin="$(lineof "$p/AGENTS.md" "$begin")"; l_end="$(lineof "$p/AGENTS.md" "$end")"
[ -z "$(sed -n "$((l_begin + 1))p" "$p/AGENTS.md")" ] || fail 'no blank line after the begin marker'
[ -z "$(sed -n "$((l_end - 1))p" "$p/AGENTS.md")" ] || fail 'no blank line before the end marker'
grep -qxF -- '- Concurrency cap: 3 heavy builds or runs at once.' "$p/AGENTS.md" || fail 'padded rewrite lost a setting'
run 0 '--check with the padded block' bash "$inst" --check "$p"
# An extra bullet directly after the template's last bullet stays there.
sed -i.bak '/^- Environment:/a\
- Extra setting: kept by the project.
' "$p/AGENTS.md"; rm -f "$p/AGENTS.md.bak"
[ "$(sed -n "$((l_end - 1))p" "$p/AGENTS.md")" = '- Extra setting: kept by the project.' ] || fail 'fixture did not place the extra bullet before the blank line'
run 0 '--check with an extra bullet in a padded block' bash "$inst" --check "$p"
cp "$p/AGENTS.md" "$work/six-agents.before"
run 0 'rerun with an extra bullet in a padded block' bash "$inst" "$p"
expect 'padded block with an extra bullet was not current' 'is current'
cmp -s "$p/AGENTS.md" "$work/six-agents.before" || fail 'rerun moved the extra bullet'
newproj seven; p="$work/seven"
run 0 'first install from the padded template' bash "$inst" "$p"
fill "$p"
run 0 '--check after a first install from the padded template' bash "$inst" --check "$p"
# The skill vendored into another repository as a squashed subtree: VERSION
# records the upstream docket commit, not the host repository's HEAD, and
# changes elsewhere in the host do not make the skill dirty.
host="$work/host"
git init --quiet "$host"; git -C "$host" symbolic-ref HEAD refs/heads/main
git -C "$host" config user.name 'Host fixture'; git -C "$host" config user.email 'host-fixture@example.invalid'
echo host > "$host/README.md"; git -C "$host" add README.md; git -C "$host" commit --quiet -m 'Host repository'
upstream="$(git -C "$skill" rev-parse HEAD)"
# Built the way `git subtree add --squash` builds it, without needing the
# git-subtree command: a squash commit with no parent whose tree is the skill
# at its root and whose message carries the git-subtree-dir and
# git-subtree-split trailers, then a two-parent merge of it into the host with
# the tree placed under the prefix and no trailer. The fetch brings the
# upstream objects into the host, as a subtree pull does.
git -C "$host" fetch --quiet "$skill" HEAD
subtree_squash() { # $1 upstream commit, $2 message; prints the squash commit and merges it under skills/docket
  local squash
  squash="$(printf '%s\n\ngit-subtree-dir: skills/docket\ngit-subtree-split: %s\n' "$2" "$1" | git -C "$host" commit-tree "$1^{tree}")"
  git -C "$host" rm -r -q --cached skills/docket 2>/dev/null || true
  rm -rf "$host/skills/docket"
  git -C "$host" read-tree --prefix=skills/docket/ -u "$squash"
  git -C "$host" update-ref HEAD "$(printf 'Merge the docket skill (%s)\n' "$2" | git -C "$host" commit-tree "$(git -C "$host" write-tree)" -p HEAD -p "$squash")"
  git -C "$host" reset -q --hard HEAD
}
subtree_squash "$upstream" 'Add the docket skill'
echo scratch > "$host/scratch.txt"
newproj eight; p="$work/eight"
run 2 '--self from a subtree host' bash "$host/skills/docket/install.sh" --self "$host"
expect '--self from a subtree host was not refused' 'needs the skill at the root of its repository'
run 0 'install from a subtree host' bash "$host/skills/docket/install.sh" "$p"
[ "$(cut -d' ' -f1 "$p/docket/VERSION")" = "$(printf '%.12s' "$upstream")" ] || { echo "install-test: VERSION from a subtree host is $(cat "$p/docket/VERSION"), expected the upstream commit $upstream" >&2; exit 1; }
grep -q -- '-dirty' "$p/docket/VERSION" && { echo 'install-test: an unrelated change in the host made the skill dirty' >&2; exit 1; }
fill "$p"
run 0 '--check from a subtree host' bash "$host/skills/docket/install.sh" --check "$p"
grep -q 'not in this skill checkout' "$log" && { echo 'install-test: --check from a subtree host did not recognise the upstream commit' >&2; exit 1; }
expect 'subtree host --check did not report a match' 'match the skill'
# A later pull --squash adds a second trailer-bearing squash commit; the newest wins.
git -C "$skill" commit --quiet --allow-empty -m 'Upstream moved on'
upstream2="$(git -C "$skill" rev-parse HEAD)"
git -C "$host" fetch --quiet "$skill" HEAD
subtree_squash "$upstream2" 'Update the docket skill'
upstream="$upstream2"
newproj eight-b; p="$work/eight-b"
run 0 'install from a subtree host after a pull' bash "$host/skills/docket/install.sh" "$p"
[ "$(cut -d' ' -f1 "$p/docket/VERSION")" = "$(printf '%.12s' "$upstream2")" ] || { echo "install-test: after a second squash VERSION is $(cat "$p/docket/VERSION"), expected $upstream2" >&2; exit 1; }
# The same host reached through a symlink: the prefix still resolves.
ln -s "$host" "$work/hostlink"
newproj nine; p="$work/nine"
run 0 'install from a subtree host through a symlink' bash "$work/hostlink/skills/docket/install.sh" "$p"
[ "$(cut -d' ' -f1 "$p/docket/VERSION")" = "$(printf '%.12s' "$upstream")" ] || { echo "install-test: VERSION through a symlinked host is $(cat "$p/docket/VERSION"), expected the upstream commit" >&2; exit 1; }
# A committed edit to the skill's README changes nothing an install writes, so
# the install stays clean.
echo 'local edit' >> "$host/skills/docket/README.md"
git -C "$host" commit --quiet -am 'Edit the skill README locally'
newproj ten-a; p="$work/ten-a"
run 0 'install from a subtree host with a committed README edit' bash "$host/skills/docket/install.sh" "$p"
grep -q -- '-dirty' "$p/docket/VERSION" && { echo "install-test: a committed README edit in the subtree made the install dirty: $(cat "$p/docket/VERSION")" >&2; exit 1; }
# A committed edit under templates/ makes the install dirty, since what it
# writes no longer matches the commit VERSION names.
echo 'local edit' >> "$host/skills/docket/templates/README.md"
git -C "$host" commit --quiet -am 'Edit the vendored skill locally'
newproj ten; p="$work/ten"
run 0 'install from a subtree host with a committed local edit' bash "$host/skills/docket/install.sh" "$p"
grep -q -- "$(printf '%.12s' "$upstream")-dirty" "$p/docket/VERSION" || { echo "install-test: a committed edit under the skill did not mark VERSION dirty: $(cat "$p/docket/VERSION")" >&2; exit 1; }
expect 'committed edit under the skill was not explained' 'differs from upstream commit'
echo 'install-test: all checks passed'
