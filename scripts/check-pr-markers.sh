#!/usr/bin/env bash
# Validate a pull request description against the work queues.
#
# Checks: the description opens with "## Why"; every marker line uses the
# exact vocabulary; claimed slugs still exist at head; resolved slugs existed
# at base and are gone at head; partial resolutions name a remainder that
# exists at head with a "Remaining from:" link; filed discoveries exist at
# head; review-finding resolutions carry a Validation section.
#
# Usage:
#   check-pr-markers.sh --body FILE [--base REF] [--head REF] [--todo PATH] [--backlog PATH]
#   check-pr-markers.sh --pr NUMBER [--base REF] [--head REF]
#
# Defaults: --base origin/main (local main when there is no origin), --head HEAD,
# TODO.md, review/BACKLOG.md. --branch NAME (default: the head's branch) enables
# the claim rule: a branch named <queue>/<slug> must carry a marker for <slug>.
# With --pr the body is fetched with `gh pr view`; run it from the PR branch
# or pass refs explicitly. In CI on a pull_request event use --base
# "origin/$GITHUB_BASE_REF" and --head HEAD (the merge commit).
#
# Marker vocabulary (one per line, no backticks, no trailing punctuation):
#   Claims TODO: <slug>                    Resolves TODO: <slug>
#   Partially resolves TODO: <slug>        Remaining TODO: <slug>
#   Files TODO: <slug>                     (a discovery captured by this PR)
#   Claims review backlog: <slug>          Resolves review backlog: <slug>
#   Partially resolves review backlog: <slug>   Remaining review backlog: <slug>
#   Claims review finding: <slug>          Resolves review finding: <slug>
#   Claims roadmap: <slug>                 Resolves roadmap: <slug>
#
# Exit 1 on any error. Portable to bash 3.2.
set -euo pipefail

orig="$PWD"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
# Make a path given on the command line absolute relative to the caller's directory.
abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$orig" "$1" ;; esac; }

body=""; pr=""; base="origin/main"; head="HEAD"; todo="TODO.md"; backlog="review/BACKLOG.md"; branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --body) body="$(abs "$2")"; shift 2 ;;
    --pr) pr="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --todo) todo="$2"; shift 2 ;;
    --backlog) backlog="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "check-pr-markers: unknown argument $1" >&2; exit 2 ;;
  esac
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ "$base" = "origin/main" ] && ! git rev-parse --verify --quiet origin/main >/dev/null; then
  if git rev-parse --verify --quiet main >/dev/null; then base="main"; echo "note: no origin/main; comparing against local main"; fi
fi

if [ -n "$pr" ]; then
  gh pr view "$pr" --json body -q .body > "$tmp/body.md"
  body="$tmp/body.md"
fi
[ -n "$body" ] || { echo "check-pr-markers: --body FILE or --pr NUMBER required" >&2; exit 2; }
[ -f "$body" ] || { echo "check-pr-markers: $body not found" >&2; exit 2; }

errors=0
err() { echo "error: $*"; errors=$((errors + 1)); }
warn() { echo "warning: $*"; }

# Queue snapshots at base and head (empty when the file does not exist there).
snap() { git show "$1:$2" 2>/dev/null || true; }
snap "$base" "$todo" > "$tmp/todo.base"; snap "$head" "$todo" > "$tmp/todo.head"
snap "$base" "$backlog" > "$tmp/backlog.base"; snap "$head" "$backlog" > "$tmp/backlog.head"

# has_entry FILE SLUG -> 0 when "- [AREA] `slug`" is present.
has_entry() { grep -Eq "^- \[[A-Z][A-Z0-9_-]*\] \`$2\`" "$1"; }
# entry_block FILE SLUG -> prints the entry and its indented sub-lines.
entry_block() {
  awk -v slug="$2" '
    /^- / { inblock = ($0 ~ "^- \\[[A-Z][A-Z0-9_-]*\\] `" slug "`") }
    /^(##|###) / { inblock = 0 }
    inblock { print }' "$1"
}

# Strip Windows line endings (bodies edited on the web) and HTML comments
# (template hints) before checking structure.
tr -d '\r' < "$body" | sed -e 's/<!--.*-->//g' > "$tmp/body.clean"

first_heading="$(grep -m1 -E '^## ' "$tmp/body.clean" || true)"
if [ -z "$first_heading" ]; then
  warn "description has no \"## \" headings; the convention is \"## Why\" first, then changes, markers and validation"
elif ! echo "$first_heading" | grep -Eq '^## Why\b'; then
  err "first heading is \"$first_heading\"; the description must open with \"## Why\""
fi

# Exact markers.
grep -E '^(Claims|Resolves|Partially resolves|Remaining|Files) (TODO|review backlog|review finding|roadmap): [a-z0-9][a-z0-9-]*$' "$tmp/body.clean" > "$tmp/markers" || true
# Near misses: looks like a marker but is not exact (backticks, bold, case, punctuation, several slugs).
grep -Ei '^[*_ ]*(claims|resolves|partially resolves|remaining|files)[*_ ]*(todo|review backlog|review finding|roadmap)' "$tmp/body.clean" \
  | grep -Ev '^(Claims|Resolves|Partially resolves|Remaining|Files) (TODO|review backlog|review finding|roadmap): [a-z0-9][a-z0-9-]*$' > "$tmp/nearmiss" || true
while IFS= read -r line; do
  [ -n "$line" ] && err "malformed marker \"$line\" (exact form: \"Resolves TODO: my-slug\"; one slug per line, nothing after the slug, no backticks or bold; put explanations in the prose above)"
done < "$tmp/nearmiss"

if [ ! -s "$tmp/markers" ]; then
  [ -n "$branch" ] || branch="$(git rev-parse --abbrev-ref "$head" 2>/dev/null || true)"
  case "$branch" in
    todo/*|review/*|roadmap/*) err "branch $branch names queued work but the description has no marker for \`${branch#*/}\`" ;;
  esac
  if [ "$errors" -eq 0 ]; then echo "no work-tracking markers found (fine for directly requested work)"; else echo "no well-formed markers found"; fi
  [ "$errors" -eq 0 ] || exit 1
  exit 0
fi

has_validation=0
if awk '/^## Validation/{v=1; next} v && /^## /{v=0} v && NF{found=1} END{exit !found}' "$tmp/body.clean"; then has_validation=1; fi

claimed_backlog=""
while IFS= read -r line; do
  verb="${line%%:*}"; slug="${line##*: }"
  case "$verb" in
    "Claims TODO")
      has_entry "$tmp/todo.head" "$slug" || err "Claims TODO: $slug, but the entry is not in $todo at $head (claims keep the entry while work is underway)" ;;
    "Files TODO")
      has_entry "$tmp/todo.head" "$slug" || err "Files TODO: $slug, but no such entry in $todo at $head"
      has_entry "$tmp/todo.base" "$slug" && warn "Files TODO: $slug already existed at $base; use Claims or drop the marker" ;;
    "Resolves TODO")
      has_entry "$tmp/todo.base" "$slug" || err "Resolves TODO: $slug, but the entry was not in $todo at $base"
      has_entry "$tmp/todo.head" "$slug" && err "Resolves TODO: $slug, but the entry is still in $todo at $head (remove it in this PR)" ;;
    "Partially resolves TODO")
      has_entry "$tmp/todo.base" "$slug" || err "Partially resolves TODO: $slug, but the entry was not in $todo at $base"
      has_entry "$tmp/todo.head" "$slug" && err "Partially resolves TODO: $slug, but the original entry is still in $todo at $head (replace it with a remainder)"
      grep -q '^Remaining TODO: ' "$tmp/markers" || err "Partially resolves TODO: $slug has no matching \"Remaining TODO: <new-slug>\" line" ;;
    "Remaining TODO")
      if has_entry "$tmp/todo.head" "$slug"; then
        orig="$(entry_block "$tmp/todo.head" "$slug" | grep -oE 'Remaining from: `[a-z0-9-]+`' | head -1 | sed 's/.*`\([a-z0-9-]*\)`/\1/')"
        if [ -z "$orig" ]; then err "remainder \`$slug\` has no \"Remaining from: \`<original>\`\" line"
        elif ! grep -qx "Partially resolves TODO: $orig" "$tmp/markers"; then err "remainder \`$slug\` says Remaining from \`$orig\`, but there is no \"Partially resolves TODO: $orig\" marker"; fi
      else
        err "Remaining TODO: $slug, but no such entry in $todo at $head"
      fi
      has_entry "$tmp/todo.base" "$slug" && err "Remaining TODO: $slug already existed at $base; a remainder needs a new slug" ;;
    "Claims review backlog")
      claimed_backlog="$claimed_backlog $slug"
      has_entry "$tmp/backlog.head" "$slug" || err "Claims review backlog: $slug, but the entry is not in $backlog at $head" ;;
    "Resolves review backlog")
      claimed_backlog="$claimed_backlog $slug"
      has_entry "$tmp/backlog.base" "$slug" || err "Resolves review backlog: $slug, but the entry was not in $backlog at $base"
      has_entry "$tmp/backlog.head" "$slug" && err "Resolves review backlog: $slug, but the entry is still in $backlog at $head" ;;
    "Partially resolves review backlog")
      claimed_backlog="$claimed_backlog $slug"
      has_entry "$tmp/backlog.base" "$slug" || err "Partially resolves review backlog: $slug, but the entry was not in $backlog at $base"
      has_entry "$tmp/backlog.head" "$slug" && err "Partially resolves review backlog: $slug, but the original is still in $backlog at $head"
      grep -q '^Remaining review backlog: ' "$tmp/markers" || err "Partially resolves review backlog: $slug has no matching \"Remaining review backlog: <new-slug>\"" ;;
    "Remaining review backlog")
      if has_entry "$tmp/backlog.head" "$slug"; then
        orig="$(entry_block "$tmp/backlog.head" "$slug" | grep -oE 'Remaining from: `[a-z0-9-]+`' | head -1 | sed 's/.*`\([a-z0-9-]*\)`/\1/')"
        if [ -z "$orig" ]; then err "remainder \`$slug\` has no \"Remaining from: \`<original>\`\" line"
        elif ! grep -qx "Partially resolves review backlog: $orig" "$tmp/markers"; then err "remainder \`$slug\` says Remaining from \`$orig\`, but there is no \"Partially resolves review backlog: $orig\" marker"; fi
      else
        err "Remaining review backlog: $slug, but no such entry in $backlog at $head"
      fi
      has_entry "$tmp/backlog.base" "$slug" && err "Remaining review backlog: $slug already existed at $base; a remainder needs a new slug" ;;
    "Claims review finding"|"Resolves review finding")
      if [ -n "$claimed_backlog" ]; then
        found=0
        for b in $claimed_backlog; do
          entry_block "$tmp/backlog.base" "$b" | grep -q "\`$slug\`" && found=1
        done
        [ "$found" -eq 1 ] || warn "$verb: $slug is not listed in the Findings of the claimed backlog entries ($claimed_backlog)"
      else
        warn "$verb: $slug with no backlog claim; state why the direct-selection exception applies"
      fi
      if [ "$verb" = "Resolves review finding" ] && [ "$has_validation" -eq 0 ]; then
        err "Resolves review finding: $slug requires a non-empty \"## Validation\" section with a human-runnable scenario"
      fi ;;
    "Claims roadmap"|"Resolves roadmap") : ;;
    *) err "unhandled marker \"$line\"" ;;
  esac
done < "$tmp/markers"

# Every partial resolution needs a remainder at head that points back at it.
for q in "TODO:$todo:todo.head" "review backlog:$backlog:backlog.head"; do
  label="${q%%:*}"; rest="${q#*:}"; file="${rest%%:*}"; snap="${rest#*:}"
  { grep -oE "^Partially resolves $label: [a-z0-9-]+" "$tmp/markers" || true; } | sed 's/.*: //' | while IFS= read -r orig; do
    [ -n "$orig" ] || continue
    grep -q "Remaining from: \`$orig\`" "$tmp/$snap" || echo "error: Partially resolves $label: $orig, but no entry in $file at $head carries \"Remaining from: \`$orig\`\"" >> "$tmp/late-errors"
  done
done
if [ -f "$tmp/late-errors" ]; then cat "$tmp/late-errors"; errors=$((errors + $(wc -l < "$tmp/late-errors" | tr -d ' '))); fi

# Claim rule: a branch named <queue>/<slug> must carry a marker for that slug.
[ -n "$branch" ] || branch="$(git rev-parse --abbrev-ref "$head" 2>/dev/null || true)"
case "$branch" in
  todo/*|review/*|roadmap/*)
    bslug="${branch#*/}"
    grep -qE "^(Claims|Resolves|Partially resolves) (TODO|review backlog|review finding|roadmap): $bslug$" "$tmp/markers" \
      || err "branch $branch names queued work but no marker claims or resolves \`$bslug\`" ;;
esac

n="$(wc -l < "$tmp/markers" | tr -d ' ')"
echo "checked $n marker(s) against $todo and $backlog at $base..$head"
[ "$errors" -eq 0 ] || exit 1
