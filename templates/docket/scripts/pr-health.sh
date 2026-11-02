#!/usr/bin/env bash
# Report the health of open pull requests: CI checks, review decision,
# mergeability, how far the head is behind the base, a requested landing that
# has not happened, and whether the queue entries the PR names still exist.
# Read-only: it never comments, labels, pushes or merges.
#
# Usage: docket/scripts/pr-health.sh [--repo OWNER/REPO] [--pr N]... [--land-comment TEXT] [--strict]
#   --repo OWNER/REPO    query that repository; passed to every gh call.
#                        Without it the repository is the current directory's
#                        remote and an inherited GH_REPO is ignored
#   --pr N               report this PR (repeatable); default: every open PR
#                        authored by the current gh user
#   --land-comment TEXT  a comment whose whole body is TEXT (surrounding
#                        whitespace ignored on both), such as a merge-bot
#                        command,
#                        requests landing; an open PR that carries one is
#                        reported with its time, and flagged when its checks
#                        are failing (the merge attempt failed or expired)
#   --strict             exit 1 when any reported PR has failing checks,
#                        changes requested, or merge conflicts. Every check in
#                        the rollup counts, required or not: the rollup does
#                        not say which checks branch protection requires
#
# Per PR: number, head branch, draft or ready; checks (passing, failing with
# the failing names, pending, or none; a failed, errored, timed-out,
# cancelled, action-required or startup-failure check fails, a stale or
# unfinished one is pending); review decision; merge state (clean,
# behind, dirty, blocked, unstable, unknown) and conflicts; commits behind the
# base; landing requested; queue markers. Markers use the vocabulary of
# check-pr-markers.sh. For an open PR, a Claims, Resolves or Partially
# resolves marker for TODO or review backlog must name an entry still present
# in TODO.md or review/BACKLOG.md of this checkout; a missing one is warned
# about, since the queue and the PR then disagree. Run it from a checkout of
# the base branch: a task worktree has already removed the entries it resolves.
#
# Exit 0 (a report), 1 with --strict when a PR needs attention, 2 on usage
# errors or a failed gh query. Needs gh; portable to bash 3.2.
set -euo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"

# The two inputs a managed-repository target would supply as defaults.
repo=""
land_comment=""

prs=""; strict=0
while [ $# -gt 0 ]; do
  case "$1" in --repo|--pr|--land-comment)
    [ $# -ge 2 ] || { echo "pr-health: $1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --pr)
      [ -n "$2" ] || { echo "pr-health: --pr needs a PR number" >&2; exit 2; }
      # Checked here, before word splitting can drop a blank value.
      case "$2" in *[!0-9]*) echo "pr-health: --pr takes a PR number, not '$2'" >&2; exit 2 ;; esac
      prs="$prs $2"; shift 2 ;;
    --land-comment)
      # Trimmed as comment bodies are, so the comparison is like for like.
      land_comment="$2"
      while :; do
        case "$land_comment" in
          [[:space:]]*) land_comment="${land_comment#?}" ;;
          *[[:space:]]) land_comment="${land_comment%?}" ;;
          *) break ;;
        esac
      done
      [ -n "$land_comment" ] || { echo "pr-health: --land-comment needs non-empty text" >&2; exit 2; }
      shift 2 ;;
    --strict) strict=1; shift ;;
    -h|--help) sed -n '2,37p' "$0"; exit 0 ;;
    *) echo "pr-health: unknown argument $1" >&2; exit 2 ;;
  esac
done
for n in $prs; do
  case "$n" in ''|*[!0-9]*) echo "pr-health: --pr takes a PR number, not $n" >&2; exit 2 ;; esac
done
if [ -n "$repo" ]; then
  echo "$repo" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' \
    || { echo "pr-health: --repo takes OWNER/REPO, not $repo" >&2; exit 2; }
fi
case "$land_comment" in
  *[[:cntrl:]]*) echo "pr-health: --land-comment must be a single line of text" >&2; exit 2 ;;
esac
command -v gh >/dev/null 2>&1 || { echo "pr-health: gh is not installed" >&2; exit 2; }

# Without --repo, never let an inherited GH_REPO redirect queries to another
# repository; with it, every call names the repository explicitly.
if [ -z "$repo" ]; then unset GH_REPO; fi
ghr() { if [ -n "$repo" ]; then gh "$@" --repo "$repo"; else gh "$@"; fi; }
if [ -n "$repo" ]; then api_repo="$repo"; else api_repo='{owner}/{repo}'; fi
where="${repo:-this repository}"
fail_query() { echo "pr-health: gh query failed ($1)" >&2; exit 2; }

if [ -z "$prs" ]; then
  prs="$(ghr pr list --author @me --state open --limit 200 --json number --jq '.[].number')" \
    || fail_query "listing your open PRs in $where"
  if [ -z "$prs" ]; then echo "no open PRs authored by you in $where"; exit 0; fi
fi

# One jq program (gh's built-in jq) flattens each PR into tab-separated lines.
# A check is "fail" for a failed, errored, timed-out, cancelled,
# action-required or startup-failure run or status, "pending" while it has
# not completed or when it is stale (superseded, awaiting a rerun), and
# "pass" otherwise (success, neutral, skipped).
land_jq=""
if [ -n "$land_comment" ]; then
  # Embed the text as a jq string literal: escape backslashes and quotes.
  lit="$(printf '%s' "$land_comment" | sed 's/[\\"]/\\&/g')"
  land_jq=', ([(.comments // [])[] | select(((.body // "") | gsub("^\\s+|\\s+$"; "")) == "'"$lit"'")] | last | select(. != null) | "land\t\(.createdAt)")'
fi
prog='def flat: gsub("[\t\r\n]"; " ");
def cls:
  if .__typename == "StatusContext" or (has("state") and (has("status") | not)) then
    (if .state == "SUCCESS" then "pass" elif (.state == "PENDING" or .state == "EXPECTED") then "pending" else "fail" end)
  elif (.status // "") != "COMPLETED" or .conclusion == "STALE" then "pending"
  elif ((.conclusion // "") | test("^(FAILURE|TIMED_OUT|CANCELLED|ACTION_REQUIRED|STARTUP_FAILURE|ERROR)$")) then "fail"
  else "pass" end;
"state\t\(.state)", "draft\t\(.isDraft)", "head\t\(.headRefName)", "base\t\(.baseRefName)",
"sha\t\(.headRefOid)", "review\t\(.reviewDecision // "")", "mergeable\t\(.mergeable // "")",
"mergestate\t\(.mergeStateStatus // "")", "title\t\(.title // "" | flat)",
((.statusCheckRollup // [])[] | "check\t\(cls)\t\((.name // .context // "unnamed") | flat)"),
((.body // "") | split("\n")[] | sub("\r$"; "")
  | select(test("^(Claims|Resolves|Partially resolves|Remaining|Files) (TODO|review backlog|review finding|roadmap): [a-z0-9][a-z0-9-]*$"))
  | "marker\t\(.)")'"$land_jq"
fields="state,isDraft,headRefName,baseRefName,headRefOid,reviewDecision,mergeable,mergeStateStatus,title,statusCheckRollup,body"
[ -z "$land_comment" ] || fields="$fields,comments"

# has_entry FILE SLUG: the queue entry "- [AREA] `slug`" is present.
has_entry() { [ -f "$1" ] && grep -Eq "^- \[[A-Z][A-Z0-9_-]*\] \`$2\`" "$1"; }

tab="$(printf '\t')"
total=0; attention=0; warnings=0
for n in $prs; do
  info="$(ghr pr view "$n" --json "$fields" --jq "$prog")" || fail_query "reading PR #$n in $where"
  state=""; draft=""; head=""; base=""; sha=""; review=""; mergeable=""; mstate=""; title=""
  fails=""; npass=0; nfail=0; npend=0; landed_at=""; markers=""
  while IFS= read -r line; do
    key="${line%%"$tab"*}"; val="${line#*"$tab"}"
    case "$key" in
      state) state="$val" ;;
      draft) draft="$val" ;;
      head) head="$val" ;;
      base) base="$val" ;;
      sha) sha="$val" ;;
      review) review="$val" ;;
      mergeable) mergeable="$val" ;;
      mergestate) mstate="$val" ;;
      title) title="$val" ;;
      check)
        cls="${val%%"$tab"*}"; name="${val#*"$tab"}"
        case "$cls" in
          fail) nfail=$((nfail + 1)); fails="${fails:+$fails, }$name" ;;
          pending) npend=$((npend + 1)) ;;
          *) npass=$((npass + 1)) ;;
        esac ;;
      land) landed_at="$val" ;;
      marker) markers="$markers$val$tab" ;;
    esac
  done <<EOF
$info
EOF
  total=$((total + 1)); needs=0
  [ "$draft" = true ] && kind="draft" || kind="ready"
  if [ "$state" != OPEN ]; then
    echo "#$n $head [$(echo "$state" | tr '[:upper:]' '[:lower:]')] $title"
    continue
  fi
  echo "#$n $head [$kind] $title"

  if [ "$nfail" -gt 0 ]; then checks="failing ($fails)"; needs=1
  elif [ "$npend" -gt 0 ]; then checks="pending ($npend of $((npass + npend)))"
  elif [ "$npass" -gt 0 ]; then checks="passing ($npass)"
  else checks="none"; fi
  echo "  checks: $checks"

  case "$review" in
    APPROVED) rv="approved" ;;
    CHANGES_REQUESTED) rv="changes requested"; needs=1 ;;
    REVIEW_REQUIRED) rv="review required" ;;
    *) rv="none" ;;
  esac
  echo "  review: $rv"

  case "$mstate" in
    CLEAN) ms="clean" ;;
    BEHIND) ms="behind" ;;
    DIRTY) ms="dirty" ;;
    BLOCKED) ms="blocked" ;;
    UNSTABLE) ms="unstable" ;;
    HAS_HOOKS) ms="clean (has hooks)" ;;
    DRAFT) ms="draft" ;;
    *) ms="unknown" ;;
  esac
  # Conflicts: GitHub reports them as mergeable CONFLICTING, state DIRTY.
  if [ "$mergeable" = CONFLICTING ] || [ "$mstate" = DIRTY ]; then
    ms="$ms, conflicting"; needs=1
  elif [ "$mergeable" != MERGEABLE ]; then
    ms="$ms, mergeability not yet computed"
  fi
  behind=""
  if [ -n "$sha" ] && [ -n "$base" ]; then
    behind="$(gh api "repos/$api_repo/compare/$base...$sha" --jq .behind_by 2>/dev/null || true)"
  fi
  case "$behind" in
    '') bh="behind base: unknown" ;;
    0) bh="up to date with $base" ;;
    *[!0-9]*) bh="behind base: unknown" ;;
    *) bh="behind $base by $behind commit(s)" ;;
  esac
  echo "  merge: $ms; $bh"

  if [ -n "$landed_at" ]; then
    if [ "$nfail" -gt 0 ]; then
      echo "  landing: requested $landed_at, still open with failing checks; the merge attempt failed or expired"
    else
      echo "  landing: requested $landed_at, still open"
    fi
  fi

  # Queue cross-reference.
  rest="$markers"
  while [ -n "$rest" ]; do
    m="${rest%%"$tab"*}"; rest="${rest#*"$tab"}"
    slug="${m##*: }"; verb="${m%: *}"
    echo "  queue: $m"
    case "$verb" in
      "Claims TODO"|"Resolves TODO"|"Partially resolves TODO") file="TODO.md" ;;
      "Claims review backlog"|"Resolves review backlog"|"Partially resolves review backlog") file="review/BACKLOG.md" ;;
      *) continue ;;
    esac
    if ! has_entry "$file" "$slug"; then
      echo "  warning: $m, but $file here has no entry \`$slug\`; the queue and the PR disagree"
      warnings=$((warnings + 1))
    fi
  done
  [ "$needs" -eq 0 ] || attention=$((attention + 1))
done

echo "summary: $total PR(s) in $where; $attention need attention (failing checks, changes requested or conflicts); $warnings queue warning(s)"
if [ "$strict" -eq 1 ] && [ "$attention" -gt 0 ]; then exit 1; fi
exit 0
