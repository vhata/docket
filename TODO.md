# Deferred work

Ordinary follow-ups and bugs found during other work live here. Whole-codebase review findings promoted for separate work live in [review/BACKLOG.md](review/BACKLOG.md). Follow [docket/TODO_GUIDE.md](docket/TODO_GUIDE.md) before adding, claiming, moving or resolving an entry. Entries in **Ready for separate work** are unblocked and available now; anything with an unresolved `Depends on:` belongs in an earlier stage.

## Needs triage

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized

## Needs proof of concept

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized

## Ready for separate work

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

- [SCRIPTS] `review-due-local-midnight` — **`review-due.sh` counts days from midnight of the review date on macOS as it does on GNU.** BSD `date -j -f %Y-%m-%d` takes the time of day from the clock, so west of UTC a review dated today can report `-1 days`; the verdict is unaffected.
  - Source: review/fix-review-due-fixture-dates (PR #22), 2026-10-12
  - Starting point: `templates/docket/scripts/review-due.sh:124`; parse `"$date 00:00:00"` with `-f '%Y-%m-%d %H:%M:%S'`, or clamp `days` at 0.

### Unprioritized
