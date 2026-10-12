#!/usr/bin/env bash
# Validate the structure of the Markdown work queues (TODO.md and
# review/BACKLOG.md): entry format, unique stable slugs, required Source
# lines, resolvable cross-references, explicit dependencies, and the
# one-finding-one-backlog-entry rule. A `repo:slug` reference names an entry in
# another repository's queue; Blocked by and Related lines may carry one and it
# is not resolved here, while Depends on names only this repository's slugs.
#
# Usage: docket/scripts/check-queues.sh [--todo PATH] [--backlog PATH] [--strict]
#   Defaults: TODO.md and review/BACKLOG.md relative to the repo root when
#   they exist. --strict turns warnings into errors.
#
# Output is "path:line: level: message". Exit 1 when any error was reported.
# Portable to bash 3.2 and POSIX awk.
set -euo pipefail

orig="$PWD"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
# Make a path given on the command line absolute relative to the caller's directory.
abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$orig" "$1" ;; esac; }

todo=""
backlog=""
strict=0
while [ $# -gt 0 ]; do
  case "$1" in
    --todo) todo="$(abs "$2")"; shift 2 ;;
    --backlog) backlog="$(abs "$2")"; shift 2 ;;
    --strict) strict=1; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "check-queues: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -z "$todo" ] && [ -f TODO.md ] && todo=TODO.md
[ -z "$backlog" ] && [ -f review/BACKLOG.md ] && backlog=review/BACKLOG.md
if [ -z "$todo" ] && [ -z "$backlog" ]; then
  echo "check-queues: no queue files found (TODO.md, review/BACKLOG.md)" >&2
  exit 2
fi

# Pass the queue files as separate arguments so paths with spaces survive.
set --
[ -n "$todo" ] && set -- "$@" "$todo"
[ -n "$backlog" ] && set -- "$@" "$backlog"

awk -v strict="$strict" -v backlog_path="$backlog" '
function report(level, file, line, msg) {
  if (level == "warning" && strict) level = "error"
  if (level == "error") errors++
  printf "%s:%d: %s: %s\n", file, line, level, msg
}
# Pull every `slug` out of a string into arr; return count.
function slugs_in(str, arr,   n, s, pos) {
  n = 0; s = str
  while (match(s, /`[^`]+`/)) {
    n++; arr[n] = substr(s, RSTART + 1, RLENGTH - 2)
    s = substr(s, RSTART + RLENGTH)
  }
  return n
}
# A `repo:slug` (or `owner/repo:slug`) names an entry in another repository.
function is_foreign(t) {
  return t ~ /^[A-Za-z0-9._\/-]+:[a-z0-9][a-z0-9-]*$/
}
function is_priority(h) {
  return h ~ /^(P0 Critical|P1 High|P2 Normal|P3 Low|Unprioritized)$/
}
function is_stage(h) {
  return h ~ /^(Needs triage|Needs proof of concept|Ready for separate work)$/
}
# Ready entries may not carry blockers or unresolved dependencies. The review
# backlog has no stages: every entry there is ready by construction.
function is_ready(s) {
  return estage[s] ~ /^Ready/ || is_backlog[s]
}
function where(s) {
  return is_backlog[s] ? "is in the review backlog, which is ready by construction," : "is in Ready for separate work"
}
function finish_entry() {
  if (cur == "") return
  if (!has_source[cur]) report("error", efile[cur], eline[cur], "entry `" cur "` has no \"Source:\" line")
  if (is_backlog[cur] && !has_findings[cur]) report("error", efile[cur], eline[cur], "review backlog entry `" cur "` has no \"Findings:\" line")
  cur = ""
}
FNR == 1 { finish_entry(); stage = ""; priority = ""; file_is_backlog = (FILENAME == backlog_path); FILENAMES = FILENAMES (FILENAMES == "" ? "" : " and ") FILENAME }
/^## / {
  finish_entry()
  h = substr($0, 4); sub(/[ \t]+$/, "", h)
  if (is_priority(h)) { priority = h; stage = "" }
  else if (is_stage(h)) { stage = h; priority = "" }
  else report("warning", FILENAME, FNR, "unknown section heading \"" h "\" (expected a stage or a priority)")
  next
}
/^### / {
  finish_entry()
  h = substr($0, 5); sub(/[ \t]+$/, "", h)
  if (is_priority(h)) priority = h
  else report("warning", FILENAME, FNR, "unknown subsection heading \"" h "\" (expected a priority)")
  next
}
/^- / {
  finish_entry()
  if (match($0, /^- \[[A-Z][A-Z0-9_-]*\] `[a-z0-9][a-z0-9-]*`/)) {
    s = $0; sub(/^- \[[A-Z][A-Z0-9_-]*\] `/, "", s); sub(/`.*/, "", s)
    if (s in efile) {
      report("error", FILENAME, FNR, "duplicate slug `" s "` (first seen at " efile[s] ":" eline[s] ")")
      cur = ""; next
    }
    cur = s; efile[s] = FILENAME; eline[s] = FNR
    estage[s] = stage; epriority[s] = priority; is_backlog[s] = file_is_backlog
    if (stage == "" && priority == "" ) report("warning", FILENAME, FNR, "entry `" s "` is outside any stage/priority section")
    if ($0 !~ /\*\*[^*]+\*\*/) report("warning", FILENAME, FNR, "entry `" s "` has no bold outcome sentence")
  } else {
    report("error", FILENAME, FNR, "entry does not match \"- [AREA] `slug` ...\" (area is UPPERCASE, slug is lowercase kebab-case)")
    cur = ""
  }
  next
}
/^  - [A-Za-z][A-Za-z ]*:/ && cur != "" {
  key = $0; sub(/^  - /, "", key); sub(/:.*/, "", key)
  val = $0; sub(/^  - [A-Za-z][A-Za-z ]*:[ \t]*/, "", val)
  if (key == "Source") { has_source[cur] = 1; if (val == "") report("error", FILENAME, FNR, "empty Source line for `" cur "`") }
  else if (key == "Findings") {
    has_findings[cur] = 1
    n = slugs_in(val, tmp)
    if (n == 0) report("error", FILENAME, FNR, "Findings line for `" cur "` names no `finding-slug`")
    for (i = 1; i <= n; i++) {
      if (tmp[i] in finding_owner && finding_owner[tmp[i]] != cur)
        report("error", FILENAME, FNR, "finding `" tmp[i] "` is mapped by both `" finding_owner[tmp[i]] "` and `" cur "`; one finding maps to at most one backlog entry")
      finding_owner[tmp[i]] = cur
    }
  }
  else if (key == "Depends on") {
    n = slugs_in(val, tmp)
    if (n == 0) report("warning", FILENAME, FNR, "Depends on line for `" cur "` names no `slug`; use \"Blocked by:\" for decisions or external conditions")
    for (i = 1; i <= n; i++) {
      if (is_foreign(tmp[i])) { report("error", FILENAME, FNR, "`" cur "` depends on `" tmp[i] "` in another repository; Depends on names only slugs in these queues, so use \"Blocked by:\""); continue }
      nd++; dep_from[nd] = cur; dep_to[nd] = tmp[i]; dep_file[nd] = FILENAME; dep_line[nd] = FNR
    }
  }
  else if (key == "Blocked by") {
    # A decision, a person or an external condition, in prose; any local `slug` in it is also a dependency.
    if (val == "" || val ~ /^[Nn]one\.?$/) ;
    else {
      if (is_ready(cur)) report("error", FILENAME, FNR, "`" cur "` " where(cur) " but is Blocked by: " val "; " (is_backlog[cur] ? "clear the blocker before promoting it (the backlog holds only ready work)" : "move it out of Ready until the blocker clears"))
      n = slugs_in(val, tmp)
      for (i = 1; i <= n; i++) if (!is_foreign(tmp[i])) { nd++; dep_from[nd] = cur; dep_to[nd] = tmp[i]; dep_file[nd] = FILENAME; dep_line[nd] = FNR }
    }
  }
  else if (key == "Related") {
    n = slugs_in(val, tmp)
    for (i = 1; i <= n; i++) if (!is_foreign(tmp[i])) { nr++; rel_from[nr] = cur; rel_to[nr] = tmp[i]; rel_file[nr] = FILENAME; rel_line[nr] = FNR }
  }
  # Remaining from / Split from / Starting point / Evidence and any other key are free-form.
  next
}
/^  - / && cur != "" { next }  # free-form supporting context is allowed
END {
  finish_entry()
  for (i = 1; i <= nr; i++) if (!(rel_to[i] in efile))
    report("warning", rel_file[i], rel_line[i], "Related slug `" rel_to[i] "` is not in any queue; repair or drop the reference")
  for (i = 1; i <= nd; i++) {
    if (!(dep_to[i] in efile)) {
      report("error", dep_file[i], dep_line[i], "`" dep_from[i] "` depends on `" dep_to[i] "` which is not in any queue; if it landed, drop the line and reassess the stage")
    } else if (is_ready(dep_from[i])) {
      report("error", dep_file[i], dep_line[i], "`" dep_from[i] "` " where(dep_from[i]) " but depends on unresolved `" dep_to[i] "`; " (is_backlog[dep_from[i]] ? "land the dependency before promoting it (the backlog holds only ready work)" : "move it out of Ready until the dependency lands"))
    }
  }
  n = 0; for (s in efile) n++
  if (errors) exit 1
  printf "check-queues: %d entries across %s, no errors\n", n, FILENAMES
}
' "$@"
