# Deferred work

Ordinary follow-ups and bugs found during other work live here. Whole-codebase review findings promoted for separate work live in [review/BACKLOG.md](review/BACKLOG.md). Follow [docket/TODO_GUIDE.md](docket/TODO_GUIDE.md) before adding, claiming, moving or resolving an entry. Entries in **Ready for separate work** are unblocked and available now; anything with an unresolved `Depends on:` belongs in an earlier stage.

## Needs triage

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized

- [GUIDES] `waiting-stage` — **Add a TODO stage for entries that are understood but blocked.** With only Needs triage, Needs proof of concept and Ready, an entry whose outcome and approach are settled but which carries a `Depends on:` or `Blocked by:` can only sit in Needs triage, so that section mixes open questions with work waiting on a dependency and readers cannot tell which entries still need a decision.
  - Source: vhata/seshat triage, commit 97d72e7, 2026-10-14
  - Seen in vhata/seshat: after triage, six of seven Needs triage entries were fully specified and prioritized, waiting only on other entries or an owner decision; the 2026-10-11 triage there did the same with `choose-github-integration`. The TODO header already says such entries belong "in an earlier stage", and the only earlier stages misdescribe them.
  - Starting point: a section such as **Waiting** (understood; blocked by a dependency or a decision) between Needs proof of concept and Ready. `check-queues.sh` accepts only the three headings (`templates/docket/scripts/check-queues.sh:70`), so it needs the new heading; it could also warn when a Waiting entry has neither `Depends on:` nor `Blocked by:`, or when its dependencies have all landed.
  - Touches the stage definitions in `references/queues.md`, `templates/docket/TODO_GUIDE.md` and `templates/TODO.md`, the validator, and the rule that a resolving PR moves dependents to Ready. Installed projects need a migration note: their existing TODO.md lacks the section, so the validator should accept its absence.

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
