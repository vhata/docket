#!/usr/bin/env bash
# Derive a pull request's labels from its branch, its description and the
# work queues, so dashboards and searches can tell what kind of work a PR is
# without parsing its body, and optionally apply them.
#
# Usage:
#   docket/scripts/pr-labels.sh --body FILE [--branch NAME] [--base REF] [--head REF]
#   docket/scripts/pr-labels.sh --pr PR [--apply] [--base REF] [--head REF]
#
# PR is anything gh accepts: a number, a URL or a branch name. Defaults:
# --base origin/main (with --pr, origin/<the PR's base branch>); --head HEAD
# (with --pr, origin/<the PR's head branch> when it has been fetched);
# --branch the head's branch (with --pr, the PR's head branch); TODO.md and
# review/BACKLOG.md (--todo, --backlog).
#
# Labels:
#   docket                     every pull request made under Docket
#   type:<kind>                the description's "Type: <kind>" line; a fix/
#                              branch without one is type:fix
#   queue:todo|review|roadmap  each queue whose work the description claims or
#                              resolves, and the queue a todo/, review/ or
#                              roadmap/ branch names
#   area:<area>                the [AREA] of each claimed or resolved entry,
#                              lowercased
#   priority:p0 .. priority:p3 the highest priority among those entries; an
#                              Unprioritized entry adds none
# Entries are looked up at base first and then at head, so resolved entries
# (gone at head) and entries filed in the same PR (new at head) both count.
#
# Without --apply the labels are printed one per line. With --apply (needs
# --pr and gh) labels missing from the repository are created, while existing
# ones keep their colour and description; the derived labels are added to the
# PR; and labels of the forms above that no longer apply are removed. Other
# labels are never touched. Rerun after changing the Type line or the markers.
#
# Exit 1 when gh fails, 2 on usage errors. Portable to bash 3.2.
set -euo pipefail

orig="$PWD"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$orig" "$1" ;; esac; }

# Change types; keep in step with check-pr-markers.sh.
types="feature fix refactor perf docs test tooling review"

body=""; pr=""; base=""; head=""; branch=""; apply=0; todo="TODO.md"; backlog="review/BACKLOG.md"
while [ $# -gt 0 ]; do
  case "$1" in --body|--pr|--base|--head|--branch|--todo|--backlog)
    [ $# -ge 2 ] || { echo "pr-labels: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --body) body="$(abs "$2")"; shift 2 ;;
    --pr) pr="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --todo) todo="$2"; shift 2 ;;
    --backlog) backlog="$2"; shift 2 ;;
    --apply) apply=1; shift ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "pr-labels: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ "$apply" -eq 0 ] || [ -n "$pr" ] || { echo "pr-labels: --apply needs --pr" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "$pr" ]; then
  gh pr view "$pr" --json body -q .body > "$tmp/body.md" || { echo "pr-labels: could not read PR $pr" >&2; exit 1; }
  body="$tmp/body.md"
  refs="$(gh pr view "$pr" --json baseRefName,headRefName -q '.baseRefName + " " + .headRefName')" \
    || { echo "pr-labels: could not read the branches of PR $pr" >&2; exit 1; }
  pr_base="${refs%% *}"; pr_head="${refs#* }"
  [ -n "$base" ] || base="origin/$pr_base"
  if [ -z "$head" ]; then
    if git rev-parse --verify --quiet "origin/$pr_head^{commit}" >/dev/null; then head="origin/$pr_head"
    else
      head="HEAD"
      echo "pr-labels: note: origin/$pr_head is not fetched; reading entries filed in the PR from HEAD ($(git symbolic-ref --short -q HEAD || echo detached))" >&2
    fi
  fi
  [ -n "$branch" ] || branch="$pr_head"
fi
[ -n "$body" ] || { echo "pr-labels: --body FILE or --pr PR required" >&2; exit 2; }
[ -f "$body" ] || { echo "pr-labels: $body not found" >&2; exit 2; }
if [ -z "$base" ]; then
  base="origin/main"
  if ! git rev-parse --verify --quiet origin/main >/dev/null && git rev-parse --verify --quiet main >/dev/null; then base="main"; fi
fi
[ -n "$head" ] || head="HEAD"
for ref in "$base" "$head"; do
  git rev-parse --verify --quiet "$ref^{commit}" >/dev/null \
    || { echo "pr-labels: ref $ref not found (pass --base/--head, or fetch the branch)" >&2; exit 2; }
done
[ -n "$branch" ] || branch="$(git rev-parse --abbrev-ref "$head" 2>/dev/null || true)"

# Windows line endings, HTML comments (template hints) and fenced code blocks
# (examples and pasted output) never count.
tr -d '\r' < "$body" | awk '
  {
    line = $0; out = ""
    while (1) {
      if (incomment) {
        p = index(line, "-->")
        if (p == 0) { line = ""; break }
        line = substr(line, p + 3); incomment = 0
      } else {
        p = index(line, "<!--")
        if (p == 0) { out = out line; break }
        out = out substr(line, 1, p - 1); line = substr(line, p + 4); incomment = 1
      }
    }
    # A backtick fence never has backticks after it on the opening line, so
    # inline code such as ```x``` at the start of a line is not a fence.
    if (out ~ /^[[:space:]]*~~~/ || (out ~ /^[[:space:]]*```/ && (fence || out !~ /^[[:space:]]*```.*`/))) { fence = !fence; print ""; next }
    print (fence ? "" : out)
  }' > "$tmp/body.clean"

# entry_meta FILE SLUG -> "AREA PRIORITY" for the entry, the priority empty
# outside a P0-P3 section; nothing when the entry is absent.
entry_meta() {
  awk -v slug="$2" '
    /^##+ / { pri = ""; if ($0 ~ /^##+ P[0-3]( |$)/) { p = $0; sub(/^#+ P/, "", p); pri = substr(p, 1, 1) }; next }
    $0 ~ "^- \\[[A-Z][A-Z0-9_-]*\\] `" slug "`" { a = $0; sub(/^- \[/, "", a); sub(/\].*/, "", a); print a " " pri; exit }' "$1"
}
git show "$base:$todo" > "$tmp/todo.base" 2>/dev/null || : > "$tmp/todo.base"
git show "$head:$todo" > "$tmp/todo.head" 2>/dev/null || : > "$tmp/todo.head"
git show "$base:$backlog" > "$tmp/backlog.base" 2>/dev/null || : > "$tmp/backlog.base"
git show "$head:$backlog" > "$tmp/backlog.head" 2>/dev/null || : > "$tmp/backlog.head"

type="$({ grep -E '^Type: [a-z]+$' "$tmp/body.clean" || true; } | head -1 | sed 's/^Type: //')"
if [ -n "$type" ] && ! printf ' %s ' "$types" | grep -q " $type "; then
  echo "pr-labels: warning: unknown type \"$type\" (one of: $types); no type label" >&2
  type=""
fi
case "$branch" in fix/*) [ -n "$type" ] || type="fix" ;; esac
[ -n "$type" ] || echo "pr-labels: warning: the description has no \"Type: <kind>\" line; no type label" >&2

: > "$tmp/queues"; : > "$tmp/areas"; : > "$tmp/priorities"
case "$branch" in todo/*|review/*|roadmap/*) echo "${branch%%/*}" >> "$tmp/queues" ;; esac
{ grep -E '^(Claims|Resolves|Partially resolves) (TODO|review backlog|review finding|roadmap): [a-z0-9][a-z0-9-]*$' "$tmp/body.clean" || true; } \
  | sed -E 's/^(Claims|Resolves|Partially resolves) //' | while IFS= read -r marker; do
  namespace="${marker%%:*}"; slug="${marker##*: }"
  case "$namespace" in
    TODO) queue="todo"; file="todo" ;;
    "review backlog") queue="review"; file="backlog" ;;
    "review finding") queue="review"; file="" ;;
    roadmap) queue="roadmap"; file="" ;;
  esac
  echo "$queue" >> "$tmp/queues"
  [ -n "$file" ] || continue
  meta="$(entry_meta "$tmp/$file.base" "$slug")"
  [ -n "$meta" ] || meta="$(entry_meta "$tmp/$file.head" "$slug")"
  [ -n "$meta" ] || continue
  echo "${meta%% *}" | tr '[:upper:]' '[:lower:]' >> "$tmp/areas"
  pri="${meta#* }"
  [ -z "$pri" ] || echo "$pri" >> "$tmp/priorities"
done

{
  echo docket
  [ -z "$type" ] || echo "type:$type"
  sort -u "$tmp/queues" | sed 's/^/queue:/'
  sort -u "$tmp/areas" | sed 's/^/area:/'
  sort -n "$tmp/priorities" | head -1 | sed 's/^/priority:p/'
} > "$tmp/labels"

if [ "$apply" -eq 0 ]; then
  cat "$tmp/labels"
  exit 0
fi

colour() {
  case "$1" in
    docket) echo 5319e7 ;;
    type:*) echo 1d76db ;;
    queue:*) echo 0e8a16 ;;
    area:*) echo c5def5 ;;
    priority:p0) echo b60205 ;;
    priority:p1) echo d93f0b ;;
    priority:p2) echo fbca04 ;;
    *) echo fef2c0 ;;
  esac
}
describe() {
  case "$1" in
    docket) echo "Made under the Docket workflow" ;;
    type:*) echo "Docket change type: ${1#type:}" ;;
    queue:todo) echo "Docket: claims or resolves TODO.md work" ;;
    queue:review) echo "Docket: claims or resolves review backlog work" ;;
    queue:roadmap) echo "Docket: claims or resolves a roadmap theme" ;;
    area:*) echo "Docket queue area [$(echo "${1#area:}" | tr '[:lower:]' '[:upper:]')]" ;;
    priority:*) echo "Docket queue priority $(echo "${1#priority:}" | tr '[:lower:]' '[:upper:]')" ;;
  esac
}

gh label list --limit 1000 --json name -q '.[].name' > "$tmp/existing" || { echo "pr-labels: could not list the repository's labels" >&2; exit 1; }
while IFS= read -r label; do
  # GitHub label names are case-insensitive.
  grep -qixF "$label" "$tmp/existing" && continue
  gh label create "$label" --color "$(colour "$label")" --description "$(describe "$label")" >/dev/null \
    || { echo "pr-labels: could not create label $label" >&2; exit 1; }
  echo "pr-labels: created label $label"
done < "$tmp/labels"

gh pr view "$pr" --json labels -q '.labels[].name' > "$tmp/current" || { echo "pr-labels: could not read the labels of PR $pr" >&2; exit 1; }
managed="^(type:($(echo "$types" | tr ' ' '|'))|queue:(todo|review|roadmap)|area:[a-z0-9_-]+|priority:p[0-3])\$"
{ grep -E "$managed" "$tmp/current" || true; } | { grep -vixF -f "$tmp/labels" || true; } > "$tmp/stale"
{ grep -vixF -f "$tmp/current" "$tmp/labels" || true; } > "$tmp/new"

add="$(paste -sd, "$tmp/new")"; remove="$(paste -sd, "$tmp/stale")"
if [ -z "$add" ] && [ -z "$remove" ]; then
  echo "pr-labels: PR $pr already has $(paste -sd, "$tmp/labels" | sed 's/,/, /g')"
  exit 0
fi
set -- gh pr edit "$pr"
[ -z "$add" ] || set -- "$@" --add-label "$add"
[ -z "$remove" ] || set -- "$@" --remove-label "$remove"
"$@" >/dev/null || { echo "pr-labels: could not update the labels of PR $pr" >&2; exit 1; }
[ -z "$add" ] || echo "pr-labels: added $(echo "$add" | sed 's/,/, /g')"
[ -z "$remove" ] || echo "pr-labels: removed $(echo "$remove" | sed 's/,/, /g')"
