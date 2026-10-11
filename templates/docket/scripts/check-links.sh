#!/usr/bin/env bash
# Check that relative Markdown links and image references resolve to files
# that exist, and that "#fragment" anchors name a heading in the target file.
# Catches the documentation link rot that otherwise waits for a codebase
# review.
#
# Usage: docket/scripts/check-links.sh [FILE_OR_DIR ...]
#   Default: every tracked or untracked-but-not-ignored *.md file.
# Exit 1 when any link or anchor is broken.
#
# Anchors are matched against ATX headings ("# ..." to "###### ...", outside
# fenced code blocks) slugified the way GitHub does for ASCII text: lowercase,
# punctuation other than "-" and "_" dropped, spaces to "-", duplicates
# suffixed -1, -2, ...; plus explicit id="..." / name="..." attributes.
# Limitations: setext (underlined) headings and non-ASCII text are not handled.
set -euo pipefail

orig="$PWD"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
abs() { case "$1" in /*) printf '%s\n' "$1" ;; *) printf '%s/%s\n' "$orig" "$1" ;; esac; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
list="$tmp/list"
# The checking loop runs in a pipeline subshell, so it counts failures in a file.
counter="$tmp/broken"
if [ $# -eq 0 ]; then
  git ls-files --cached --others --exclude-standard '*.md' ':!:**/node_modules/**' 2>/dev/null > "$list" \
    || find . -name '*.md' -not -path '*/node_modules/*' > "$list"
else
  for a in "$@"; do
    a="$(abs "$a")"
    if [ -d "$a" ]; then find "$a" -name '*.md' >> "$list"; else echo "$a" >> "$list"; fi
  done
fi

# anchors FILE -> one anchor id per line.
anchors() {
  awk '
    function slugify(h,   s, t) {
      s = tolower(h)
      # [text](url) contributes only its text.
      while (match(s, /\[[^]]*\]\([^)]*\)/)) {
        t = substr(s, RSTART + 1, RLENGTH - 2); sub(/\]\(.*$/, "", t)
        s = substr(s, 1, RSTART - 1) t substr(s, RSTART + RLENGTH)
      }
      gsub(/[^a-z0-9 _-]/, "", s)
      gsub(/ /, "-", s)
      return s
    }
    /^(```|~~~)/ { infence = !infence; next }
    infence { next }
    /^#+[ \t]/ {
      match($0, /^#+/)
      if (RLENGTH > 6) next
      h = substr($0, RLENGTH + 1)
      sub(/^[ \t]+/, "", h); sub(/[ \t]+#*[ \t]*$/, "", h)
      s = slugify(h)
      if (s in seen) { seen[s]++; s = s "-" (seen[s] - 1) } else seen[s] = 1
      print s
    }
    {
      line = $0
      while (match(line, /(id|name)="[^"]+"/)) {
        a = substr(line, RSTART, RLENGTH); sub(/^[a-z]+="/, "", a); sub(/"$/, "", a)
        print a
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$1"
}

while IFS= read -r f; do
  [ -n "$f" ] || continue
  dir="$(dirname "$f")"
  # Extract link targets: [text](target) and ![alt](target); skip URLs and mailto.
  { grep -oE '\]\([^)]+\)' "$f" 2>/dev/null || true; } | sed -e 's/^](//' -e 's/)$//' -e 's/ ".*"$//' | while IFS= read -r target; do
    case "$target" in
      http://*|https://*|mailto:*|"") continue ;;
    esac
    path="${target%%#*}"
    frag=""; case "$target" in *\#*) frag="${target#*#}" ;; esac
    if [ -n "$path" ]; then
      case "$path" in
        /*) resolved="$root$path" ;;
        *) resolved="$dir/$path" ;;
      esac
    else
      resolved="$f"
    fi
    if [ ! -e "$resolved" ]; then
      echo "$f: broken link -> $target"
      echo broken >> "$counter"
    elif [ -n "$frag" ] && [ -f "$resolved" ]; then
      case "$resolved" in
        *.md|*.markdown)
          if ! anchors "$resolved" | grep -qxF -- "$frag"; then
            echo "$f: broken anchor -> $target"
            echo broken >> "$counter"
          fi ;;
      esac
    fi
  done
done < "$list"
if [ -f "$counter" ]; then
  broken="$(wc -l < "$counter" | tr -d ' ')"
  echo "check-links: $broken broken link(s)"
  exit 1
fi
echo "check-links: all relative links and anchors resolve"
