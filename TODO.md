# Deferred work

Ordinary follow-ups and bugs found during other work live here. Whole-codebase review findings promoted for separate work live in [review/BACKLOG.md](review/BACKLOG.md). Follow [docket/TODO_GUIDE.md](docket/TODO_GUIDE.md) before adding, claiming, moving or resolving an entry. Entries in **Ready for separate work** are unblocked and available now; an understood entry with an unresolved `Depends on:` or a `Blocked by:` goes in **Waiting** until it clears.

## Needs triage

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized

- [SCRIPTS] `review-due-gnu-dst-midnight` — **`review-due.sh` reports the day count on GNU date for a review dated on a day that starts with a DST jump.** In zones where DST begins at midnight, local midnight does not exist on that day, so `date -d "$date"` fails and the days figure is silently left out of the report; the BSD path gives 01:00 and counts correctly.
  - Source: independent review of `todo/review-due-local-midnight`, 2026-11-02
  - Starting point: the GNU branch of the day count in `templates/docket/scripts/review-due.sh`; parse `"$date 12:00"` and round, or fall back to `"$date 01:00"` on failure. Reproduce with GNU date and `TZ=America/Santiago` for 2026-09-06.
- [SCRIPTS] `review-due-large-index-sigpipe` — **`review-due.sh` reports on a review index of any length.** `latest="$(echo "$rows" | head -1)"` runs under `pipefail` and `set -e`; once the index rows outgrow a pipe buffer, `head` exits after one line, `echo` dies of SIGPIPE and the script exits 141 with no output (reproduced with a 6000-row index under bash 3.2 and 5).
  - Source: `todo/finding-membership-sigpipe` implementation, 2026-11-02
  - Starting point: `templates/docket/scripts/review-due.sh:79-80`; read the first row with `sed -n 1p` or a here-string rather than a pipe into `head`. An index that long is unlikely in practice.


## Needs proof of concept

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized

## Waiting

### P0 Critical

### P1 High

### P2 Normal

### P3 Low

### Unprioritized

## Ready for separate work

### P0 Critical

### P1 High

### P2 Normal

- [SCRIPTS] `pr-health-target-defaults` — **In a sidecar, `pr-health.sh` reports on the managed repository's PRs without being told where they are.** With a `.docket-target` loaded, `--repo` defaults to the target's `repo` and `--land-comment` to its `land_comment`; `--no-target` and explicit options override.
  - Source: `todo/pr-health` implementation, 2026-11-01
  - Starting point: the placeholder defaults at the top of `templates/docket/scripts/pr-health.sh` and `templates/docket/scripts/target.sh`; queue-marker checks need thought in target mode, where claims are `PR:` lines rather than body markers.

### P3 Low

- [SCRIPTS] `managed-repo-forks` — **Managed-repository mode works for contributors who push branches to a fork rather than to the managed repository.** Target mode expects branches on the managed repository itself; `claim-check.sh --self` reports the user's own fork PR as a competing claim, and `start-work.sh` names the managed remote for the push.
  - Source: independent review of PR #30, 2026-11-01
  - Starting point: an optional `push_remote` (or fork owner) key in `.docket-target`; accept a cross-repository head whose owner matches it in `claim-check.sh`, and name that remote in `start-work.sh`'s next steps.

### Unprioritized
