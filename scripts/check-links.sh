#!/usr/bin/env bash
# Check that relative Markdown links and image references resolve to files
# that exist. Catches the documentation link rot that otherwise waits for a
# codebase review.
#
# Usage: check-links.sh [FILE_OR_DIR ...]   (default: all tracked *.md files)
# Exit 1 when any link is broken.
set -euo pipefail

orig="$PWD"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$orig" "$1" ;; esac; }
list="$(mktemp)"
trap 'rm -f "$list"' EXIT
if [ $# -eq 0 ]; then
  git ls-files '*.md' ':!:**/node_modules/**' 2>/dev/null > "$list" || find . -name '*.md' -not -path '*/node_modules/*' > "$list"
else
  for a in "$@"; do
    a="$(abs "$a")"
    if [ -d "$a" ]; then find "$a" -name '*.md' >> "$list"; else echo "$a" >> "$list"; fi
  done
fi

broken=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  dir="$(dirname "$f")"
  # Extract link targets: [text](target) and ![alt](target); skip URLs, anchors, mailto.
  { grep -oE '\]\([^)]+\)' "$f" 2>/dev/null || true; } | sed -e 's/^](//' -e 's/)$//' -e 's/ ".*"$//' | while IFS= read -r target; do
    case "$target" in
      http://*|https://*|mailto:*|\#*|"") continue ;;
    esac
    path="${target%%#*}"
    [ -n "$path" ] || continue
    case "$path" in
      /*) resolved="$root$path" ;;
      *) resolved="$dir/$path" ;;
    esac
    if [ ! -e "$resolved" ]; then
      echo "$f: broken link -> $target"
      echo broken >> "$root/.check-links.$$"
    fi
  done
done < "$list"
if [ -f "$root/.check-links.$$" ]; then
  broken="$(wc -l < "$root/.check-links.$$" | tr -d ' ')"
  rm -f "$root/.check-links.$$"
  echo "check-links: $broken broken link(s)"
  exit 1
fi
echo "check-links: all relative links resolve"
