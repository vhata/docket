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
# the skill (both clean) and a committed edit under its templates/ (dirty);
# --sidecar: usage errors and invalid options writing nothing, the target
# file and Managed repository bullet written, a relative dir matched from a
# linked sidecar worktree, nothing written into the
# managed clone, idempotent reruns, a conflicting or invalid target file
# refused, --check failing on an invalid one and warning on a missing bullet,
# and a plain install writing neither; check-mine.sh checking only the files
# the branch touched since its merge base, failing and fixing, refusing a
# check that writes and a worktree outside the managed clone, and needing
# --base without a target file.
#
# Usage: bash tests/install.sh   (from anywhere; needs git and bash 3.2+)
set -euo pipefail
# Git exports GIT_DIR (and, in some cases, GIT_WORK_TREE and GIT_INDEX_FILE) to
# hooks; from a linked worktree GIT_DIR is absolute. Left set, every fixture
# command below would act on the repository running the hook: `git init`
# reinitialises it as bare, `git config` writes fixture settings into its
# shared config and `git symbolic-ref HEAD` moves its HEAD.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(cd "$(mktemp -d)" && pwd -P)"
# Run every script under the bash running this suite. The suite calls scripts
# as `bash <script>` and through `#!/usr/bin/env bash` shebangs, which resolve
# bash through PATH; on macOS a newer bash usually comes first there, so a
# suite started under /bin/bash (3.2, as scripts/test.sh does) would otherwise
# test the scripts under the newer one.
suitebash="$(mktemp -d)"
trap 'rm -rf "$work" "$suitebash"' EXIT
ln -s "$BASH" "$suitebash/bash"
PATH="$suitebash:$PATH"; export PATH
[ "$(bash -c 'echo "$BASH_VERSION"')" = "$BASH_VERSION" ] \
  || { echo "install-test: bash on PATH is not the suite's bash ($BASH_VERSION)" >&2; exit 1; }
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
[ ! -e "$p/.docket-target" ] || fail 'a plain install wrote .docket-target'
refute 'a plain install mentioned a sidecar' 'sidecar'
refute 'a plain install added the Managed repository bullet' 'Managed repository'
! grep -q '^- Managed repository:' "$p/AGENTS.md" || fail 'a plain install added the Managed repository bullet'
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

# Sidecar mode: a managed repository (a bare remote and a clone of it) that
# docket is never installed in, and a sidecar pointed at it.
git init --quiet --bare "$work/managed.git"
git -C "$work/managed.git" symbolic-ref HEAD refs/heads/main
git clone --quiet "$work/managed.git" "$work/managed" 2>/dev/null
m="$work/managed"
git -C "$m" config user.name 'Managed fixture'; git -C "$m" config user.email 'managed-fixture@example.invalid'
git -C "$m" config core.hooksPath /dev/null
git -C "$m" checkout --quiet -b main
printf 'a\n' > "$m/a.md"; printf 'old\n' > "$m/old.md"; printf 'same\n' > "$m/same.md"; printf 'b\n' > "$m/b.txt"; printf 'ren\n' > "$m/ren.md"
git -C "$m" add -A && git -C "$m" commit --quiet -m 'Managed repository'
git -C "$m" push --quiet origin main 2>/dev/null
git -C "$m" remote set-head origin main
m_files="$(cd "$m" && ls -A | sort)"; m_config="$(git -C "$m" config --list --local | sort)"
newproj side; s="$work/side"
# Usage errors write nothing.
run 2 'target options without --sidecar' bash "$inst" --repo owner/managed --dir ../managed "$s"
expect 'target options without --sidecar were accepted' 'need --sidecar'
run 2 '--sidecar with --repo but no --dir' bash "$inst" --sidecar --repo owner/managed "$s"
expect '--sidecar without --dir was accepted' 'needs both --repo and --dir'
run 2 '--sidecar without options or a target file' bash "$inst" --sidecar "$s"
expect '--sidecar without a target file was accepted' 'needs an existing'
run 2 '--sidecar with --self' bash "$inst" --sidecar --self "$s"
run 2 '--check with target options' bash "$inst" --check --sidecar --repo owner/managed --dir ../managed "$s"
run 2 '--sidecar with a missing clone' bash "$inst" --sidecar --repo owner/managed --dir ../nowhere "$s"
expect 'a missing clone was not reported by target.sh' 'does not exist'
expect 'invalid options were not reported as the options' 'the options: dir'
refute 'invalid options were reported by their temporary path' 'docket-install.'
expect 'a refused sidecar install did not say nothing was written' 'nothing was written'
run 2 '--sidecar pointing at the sidecar itself' bash "$inst" --sidecar --repo owner/managed --dir . "$s"
expect 'the sidecar as its own clone was accepted' 'is the sidecar repository itself'
run 2 '--sidecar with a comment in a value' bash "$inst" --sidecar --repo owner/managed --dir ../managed --land-comment 'merge #now' "$s"
[ ! -e "$s/docket" ] && [ ! -e "$s/.docket-target" ] && [ ! -e "$s/AGENTS.md" ] || fail 'a refused sidecar install wrote files'
# A sidecar inside the managed clone's working tree, or inside another of its
# worktrees, is refused: its files would sit in someone else's checkout.
git init --quiet "$m/nested"
run 2 '--sidecar nested in the managed clone' bash "$inst" --sidecar --repo owner/managed --dir .. "$m/nested"
expect 'a sidecar inside the managed clone was accepted' 'inside the managed clone'
[ ! -e "$m/nested/docket" ] || fail 'a refused nested sidecar install wrote docket/'
rm -rf "$m/nested"
git -C "$m" worktree add --quiet --detach "$work/managed-wt-nest" HEAD
git init --quiet "$work/managed-wt-nest/sub"
run 2 '--sidecar nested in a managed worktree' bash "$inst" --sidecar --repo owner/managed --dir ../../managed "$work/managed-wt-nest/sub"
expect 'a sidecar inside a managed worktree was accepted' 'inside the managed clone'
git -C "$m" worktree remove --force "$work/managed-wt-nest"
run 1 '--check --sidecar before any install' bash "$inst" --check --sidecar "$s"
# The install writes the target file, as given, and the settings bullet.
run 0 'sidecar install' sh -c 'cd "$1" && bash "$2" --sidecar --repo owner/managed --dir ../managed --branch-prefix me/ --land-comment=/merge' sh "$s" "$inst"
expect 'sidecar install did not report the target file' "wrote $s/.docket-target"
expect 'sidecar install did not report the bullet' 'added the Managed repository bullet'
expect 'sidecar install did not point at the sidecar setup' 'check-mine.sh'
[ "$(cat "$s/.docket-target")" = "$(printf '# Managed repository for this sidecar; the format is in docket/scripts/target.sh.\nrepo=owner/managed\ndir=../managed\nbranch_prefix=me/\nland_comment=/merge')" ] || fail "unexpected .docket-target: $(cat "$s/.docket-target")"
[ "$(grep -c '^- Managed repository: work happens in `owner/managed`' "$s/AGENTS.md")" -eq 1 ] || fail 'the Managed repository bullet is missing or repeated'
l_bullet="$(lineof "$s/AGENTS.md" '- Managed repository:')"; l_env="$(lineof "$s/AGENTS.md" '- Environment:')"
[ "$l_bullet" -eq $((l_env + 1)) ] || fail 'the Managed repository bullet does not follow the template bullets'
(cd "$s" && bash docket/scripts/target.sh) > "$log" 2>&1 || fail "the installed target.sh rejected the written file: $(cat "$log")"
expect 'the written file did not resolve the branch prefix' 'branches: me/<slug>'
[ "$(cd "$m" && ls -A | sort)" = "$m_files" ] || fail 'the sidecar install wrote into the managed clone'
[ "$(git -C "$m" config --list --local | sort)" = "$m_config" ] || fail 'the sidecar install changed the managed clone config'
[ -z "$(git -C "$m" status --porcelain)" ] || fail 'the sidecar install left changes in the managed clone'
fill "$s"
run 0 '--check of a sidecar' bash "$inst" --check "$s"
expect '--check of a sidecar did not match' 'match the skill'
run 0 '--check --sidecar of a sidecar' bash "$inst" --check --sidecar "$s"
# Idempotent: the same settings, spelled differently, change nothing.
cp "$s/AGENTS.md" "$work/side-agents.before"; cp "$s/.docket-target" "$work/side-target.before"
run 0 'sidecar rerun with the same settings' bash "$inst" --sidecar --repo owner/managed --dir "$m" --branch-prefix me/ --land-comment /merge --base main "$s"
expect 'sidecar rerun did not report a valid target' 'is valid'
run 0 'sidecar rerun without options' bash "$inst" --sidecar "$s"
# A relative dir is the sidecar's, whatever the current directory.
run 0 'sidecar rerun from an unrelated directory' sh -c 'cd / && bash "$1" --sidecar --repo owner/managed --dir ../managed --branch-prefix me/ --land-comment /merge "$2"' sh "$inst" "$s"
expect 'a relative dir from an unrelated directory did not match' 'is valid'
cmp -s "$s/AGENTS.md" "$work/side-agents.before" || fail 'sidecar rerun changed AGENTS.md'
cmp -s "$s/.docket-target" "$work/side-target.before" || fail 'sidecar rerun changed .docket-target'
# From a linked worktree of the sidecar, a relative dir still resolves against
# the main worktree, so the same options match the committed file.
git -C "$s" add -A && git -C "$s" commit --quiet -m 'Install docket as a sidecar'
mkdir -p "$work/wts"; git -C "$s" worktree add --quiet --detach "$work/wts/side-wt" HEAD
run 0 'sidecar rerun from a linked worktree' sh -c 'cd "$1" && bash "$2" --sidecar --repo owner/managed --dir ../managed --branch-prefix me/ --land-comment /merge' sh "$work/wts/side-wt" "$inst"
expect 'a linked worktree did not resolve dir against the main worktree' 'is valid'
cmp -s "$work/wts/side-wt/.docket-target" "$work/side-target.before" || fail 'a rerun from a linked worktree changed .docket-target'
git -C "$s" worktree remove --force "$work/wts/side-wt"
# A conflicting target file is refused, and left alone.
run 2 'sidecar install with a different repo' bash "$inst" --sidecar --repo owner/other --dir ../managed --branch-prefix me/ --land-comment /merge "$s"
expect 'a conflicting target file was not refused' 'refusing to overwrite'
expect 'the refusal did not show the difference' '+repo: owner/other'
cmp -s "$s/.docket-target" "$work/side-target.before" || fail 'a refused sidecar install changed .docket-target'
# An invalid target file fails --check and an install, which still resyncs.
printf 'bogus=1\n' >> "$s/.docket-target"
run 1 '--check with an invalid target file' bash "$inst" --check "$s"
expect '--check did not name the invalid key' "unknown key 'bogus'"
expect '--check did not report the invalid target file' '.docket-target is invalid'
run 1 'install with an invalid target file' bash "$inst" "$s"
expect 'install did not report the invalid target file' '.docket-target is invalid'
run 2 'sidecar install over an invalid target file' bash "$inst" --sidecar --repo owner/managed --dir ../managed "$s"
expect 'an invalid existing target file was not reported' 'exists and is invalid'
# --sidecar without options refuses an invalid file before writing anything.
rm "$s/docket/README.md"
run 2 'sidecar install without options over an invalid target file' bash "$inst" --sidecar "$s"
expect 'an invalid existing target file was not reported without options' 'exists and is invalid'
[ ! -e "$s/docket/README.md" ] || fail '--sidecar over an invalid target file wrote docket/'
run 1 'resync with an invalid target file' bash "$inst" "$s"
cp "$work/side-target.before" "$s/.docket-target"
# A dangling symlink or a directory is named as such, not as DOCKET_TARGET_FILE.
rm "$s/.docket-target"; ln -s nowhere "$s/.docket-target"
run 1 '--check with a dangling .docket-target symlink' bash "$inst" --check "$s"
expect 'a dangling .docket-target was not explained' 'is not a regular file'
refute 'a dangling .docket-target was blamed on DOCKET_TARGET_FILE' 'DOCKET_TARGET_FILE'
rm "$s/.docket-target"; mkdir "$s/.docket-target"
run 2 '--sidecar with a .docket-target directory' bash "$inst" --sidecar "$s"
expect 'a .docket-target directory was not explained' 'is not a regular file'
refute 'a .docket-target directory was blamed on DOCKET_TARGET_FILE' 'DOCKET_TARGET_FILE'
rmdir "$s/.docket-target"; cp "$work/side-target.before" "$s/.docket-target"
# A bullet naming another repository than the target file is a warning.
sed -i.bak 's/^- Managed repository: work happens in `owner\/managed`/- Managed repository: work happens in `owner\/elsewhere`/' "$s/AGENTS.md"; rm -f "$s/AGENTS.md.bak"
run 0 '--check with a bullet naming another repository' bash "$inst" --check "$s"
expect '--check did not warn about a bullet naming another repository' 'does not name owner/managed'
cp "$work/side-agents.before" "$s/AGENTS.md"
# A missing bullet is a warning, added back only with --sidecar.
sed -i.bak '/^- Managed repository:/d' "$s/AGENTS.md"; rm -f "$s/AGENTS.md.bak"
run 0 '--check without the Managed repository bullet' bash "$inst" --check "$s"
expect '--check did not warn about the missing bullet' "no '- Managed repository:' bullet"
run 0 'plain install in a sidecar without the bullet' bash "$inst" "$s"
expect 'plain install did not warn about the missing bullet' 'rerun with --sidecar'
! grep -q '^- Managed repository:' "$s/AGENTS.md" || fail 'a plain install added the Managed repository bullet'
run 0 'sidecar install re-adding the bullet' bash "$inst" --sidecar "$s"
cmp -s "$s/AGENTS.md" "$work/side-agents.before" || fail 'the re-added bullet differs from the original'
[ "$(cd "$m" && ls -A | sort)" = "$m_files" ] || fail 'a sidecar rerun wrote into the managed clone'

# check-mine.sh, the diff-scoped own-checks skeleton, copied into the sidecar
# with rules: a checker that logs its arguments and fails on BAD, a fixer
# that replaces it, and a check that writes, which must fail the run.
mkdir -p "$s/scripts"
cp "$skill/templates/scripts/check-mine.sh" "$s/scripts/check-mine.sh"
run 0 'check-mine with no rules' sh -c 'cd "$1" && bash "$2/scripts/check-mine.sh"' sh "$m" "$s"
expect 'check-mine without rules did not say so' 'no rules configured'
printf '#!/bin/sh\nfor f; do echo "$f" >> "%s/checked.log"; done\n! grep -l BAD "$@"\n' "$work" > "$work/checker.sh"
printf '#!/bin/sh\nfor f; do sed s/BAD/good/ "$f" > "$f.new" && mv "$f.new" "$f"; done\n' > "$work/fixer.sh"
printf '#!/bin/sh\nfor f; do echo more >> "$f"; done\n' > "$work/writer.sh"
awk -v w="$work" -v q="'" '{ print } /^configure\(\) \{$/ {
  print "  rule " q "*.md" q " " q "sh " w "/checker.sh" q " " q "sh " w "/fixer.sh" q
  print "  rule " q "*.txt" q " " q "sh " w "/checker.sh" q
}' "$skill/templates/scripts/check-mine.sh" > "$s/scripts/check-mine.sh"
awk -v w="$work" -v q="'" '{ print } /^configure\(\) \{$/ { print "  rule " q "*.txt" q " " q "sh " w "/writer.sh" q }' \
  "$skill/templates/scripts/check-mine.sh" > "$s/scripts/check-writer.sh"
# A managed worktree whose branch edits a.md, deletes old.md and adds new.md
# and -dash.md (untracked) and renames ren.md to a spaced name, while the
# base moves on to change same.md: only those are the user's, and a name
# starting with - is passed as ./-dash.md.
wt="$work/managed-worktrees/mine"
git -C "$m" worktree add --quiet --no-track -b me/mine "$wt" origin/main
printf 'a2\n' > "$wt/a.md"; git -C "$wt" rm --quiet old.md; git -C "$wt" mv ren.md 're named.md'
git -C "$wt" commit --quiet -am 'My change'
printf 'new\n' > "$wt/new.md"; printf 'dash\n' > "$wt/-dash.md"
git -C "$m" clone --quiet "$work/managed.git" "$work/managed-other" 2>/dev/null
printf 'moved\n' > "$work/managed-other/same.md"
git -C "$work/managed-other" -c user.name=o -c user.email=o@example.invalid commit --quiet -am 'Base moves on'
git -C "$work/managed-other" push --quiet origin HEAD:main 2>/dev/null
git -C "$m" fetch --quiet origin
rm -f "$work/checked.log"
run 0 'check-mine in a managed worktree' sh -c 'cd "$1" && bash "$2/scripts/check-mine.sh"' sh "$wt" "$s"
expect 'check-mine did not report passing' 'all rules passed'
[ "$(sort "$work/checked.log" | paste -sd'|' -)" = './-dash.md|a.md|new.md|re named.md' ] || fail "check-mine checked $(sort "$work/checked.log" | paste -sd'|' -), expected ./-dash.md|a.md|new.md|re named.md"
printf 'BAD\n' > "$wt/new.md"
run 1 'check-mine with a failing file' bash "$s/scripts/check-mine.sh" --worktree "$wt"
expect 'check-mine did not name the failing rule' 'failed on *.md'
grep -qx BAD "$wt/new.md" || fail 'check-mine changed a file without --fix'
run 0 'check-mine --fix' bash "$s/scripts/check-mine.sh" --fix --worktree "$wt"
grep -qx good "$wt/new.md" || fail 'check-mine --fix did not run the fixer'
run 0 'check-mine after the fix' bash "$s/scripts/check-mine.sh" --worktree "$wt"
run 2 'check-mine from the sidecar without --worktree' sh -c 'cd "$1" && bash scripts/check-mine.sh' sh "$s"
expect 'check-mine accepted a worktree outside the managed clone' 'is not a worktree of the managed clone'
printf 'b2\n' > "$wt/b.txt"
run 1 'check-mine with a check that writes' bash "$s/scripts/check-writer.sh" --worktree "$wt"
expect 'a writing check was not caught' 'changed files it was only to check'
# Without a target file the base must be given.
newproj plainmine; p="$work/plainmine"
mkdir -p "$p/scripts"; cp "$s/scripts/check-mine.sh" "$p/scripts/"
printf 'x\n' > "$p/x.md"
run 2 'check-mine without a target or --base' sh -c 'cd "$1" && bash scripts/check-mine.sh' sh "$p"
expect 'check-mine without a base did not ask for one' 'pass --base'
rm -f "$work/checked.log"
run 0 'check-mine with --base and no target' sh -c 'cd "$1" && bash scripts/check-mine.sh --base main' sh "$p"
[ "$(cat "$work/checked.log")" = 'x.md' ] || fail "check-mine without a target checked $(cat "$work/checked.log")"
diff <(echo "$m_config") <(git -C "$m" config --list --local | sort) >&2 || fail "check-mine changed the managed clone config"
echo 'install-test: all checks passed'
