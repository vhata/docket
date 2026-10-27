# Review index

Historical codebase reviews are immutable snapshots; the newest snapshot is the current finding inventory. Fix PRs supply evidence; the next incremental review verifies and records closure. Process: [docket/CODE_REVIEW_GUIDE.md](../docket/CODE_REVIEW_GUIDE.md). Promoted work: [BACKLOG.md](BACKLOG.md). Newest first; the top row is the baseline for the next incremental review. An empty index means no review has been recorded, not that there are no defects.

| Review (UTC) | Type | Reviewed commit | Open findings at close |
| --- | --- | --- | --- |
| [2026-10-27-1626](2026-10-27-1626-full.md) | Full | `78ec5ad` | 68 |
| [2026-10-12-1702](2026-10-12-1702-full.md) | Full | `bcd87d1` | 66 |

<!-- This section must stay below the index table: review-due.sh reads the first table row with a backticked commit as the latest review. -->
## Pending reconciliation

Findings whose fix has landed with independent verification but whose closure the next review has not yet recorded. The next incremental review verifies each and clears the list.

| Finding | Fix PR and commit | Reviewer | Evidence |
| --- | --- | --- | --- |
