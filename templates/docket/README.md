# docket

This directory is the vendored copy of the docket skill's machinery: the
workflow contract, the queue and review guides, and the scripts that check
and operate them. Every file here is byte-identical to the skill's copy at
the commit named in `VERSION`.

## The rule

Never edit anything in this directory. A local edit is drift: the next resync
overwrites it, and `install.sh --check` reports it until then. Project-specific
rule text belongs in the `## Docket` section of `AGENTS.md` or in
`docs/QUALITY.md`, not here. Changes to the shared machinery go to the skill
repository and reach this project through a resync.

The installer also owns the `## Docket` section of `AGENTS.md`, between
`<!-- docket:begin -->` and `<!-- docket:end -->`. The heading and text are
rewritten on every resync; the settings bullets (`- Name: value`) hold this
project's values and are kept by name, with a missing one re-added as a
placeholder. Edit the values, not the text. `--check` reports text drift and
any setting that is missing or still a placeholder. Everything outside the
markers is the project's and is never touched.

## Resync and audit

```sh
bash ~/.claude/skills/docket/install.sh          # install or update docket/
bash ~/.claude/skills/docket/install.sh --check  # report drift, exit 1 if any
```

The same command performs the first install and every later update. It copies
the skill's files over this directory, writes `VERSION`, refreshes the Docket
section of `AGENTS.md`, and reports (but does not delete) files here that the skill no
longer ships. Commit the result.

`VERSION` holds the skill commit the files came from, as `<sha> <date>`
(UTC). A `-dirty` suffix means the skill checkout had uncommitted changes
when it was installed; resync from a clean checkout before relying on it.

## docket/ and .docket/

`docket/` is tracked and vendored. `.docket/` at the project root is local
state, excluded from git (`install.sh` adds it to `.git/info/exclude`), and
holds two kinds of content:

- `.docket/AUDIT.md`: the append-only decision log kept during unattended
  runs, one entry per load-bearing decision with an undo line.
- `.docket/pr-<slug>.md`: a prepared pull request body, saved when work is
  ready but no PR can be opened from the current environment.

## Files

| File | Purpose |
| --- | --- |
| `README.md` | This file. |
| `CONTRACT.md` | The workflow rules every agent reads first. |
| `TODO_GUIDE.md` | Capture, triage, claim and resolve deferred work in `TODO.md` and `review/BACKLOG.md`. |
| `CODE_REVIEW_GUIDE.md` | PR review and codebase review, and the review ledger under `review/`. |
| `VERSION` | The skill commit and date these files were installed from. |
| `scripts/ci.sh` | The single entry point CI calls; runs every validator below in order and stops at the first failure. |
| `scripts/check-queues.sh` | Validates the structure of `TODO.md` and `review/BACKLOG.md`: entry format, unique slugs, `Source` lines, cross-references and dependencies. |
| `scripts/check-pr-markers.sh` | Validates a pull request description's markers against the queues at the base and head commits. |
| `scripts/check-links.sh` | Checks that relative Markdown links, images and `#anchors` resolve to existing files and headings. |
| `scripts/claim-check.sh` | Looks for existing claims on a slug: open and merged pull requests, branches and worktrees. |
| `scripts/start-work.sh` | Runs the claim check, then creates the `<queue>/<slug>` branch and its worktree. |
| `scripts/cleanup-landed.sh` | Removes branches and worktrees whose pull requests have merged; a dry run unless `--apply` is given. |
| `scripts/review-due.sh` | Measures movement since the last recorded codebase review and says whether an incremental or full review is due. |

Run the scripts from anywhere inside the project as
`bash docket/scripts/<name>.sh`. Each script's header comment documents its
arguments, defaults and exit codes.
