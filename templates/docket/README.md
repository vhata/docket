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
`<!-- docket:begin -->` and `<!-- docket:end -->`. On the first install it
places the section after the file's introduction, before the first `## `
heading (or at the end when there is none); moving it anywhere else in the
file is safe, later runs find it by its markers. The heading and text are
rewritten on every resync; the settings bullets (`- Name: value`) hold this
project's values and are kept by name, with a missing one re-added as a
placeholder and extra bullets kept directly after the standard ones. Edit the
values, not the text. `--check` reports text drift and any setting that is
missing or still a placeholder. Everything outside the markers is the
project's and is never touched. A Markdown formatter that pads the markers
with blank lines changes nothing: the template already has them.

`CLAUDE.md`, when it exists as a regular file, gets the line `@AGENTS.md`
appended once. A `CLAUDE.md` that is a symlink to `AGENTS.md` already imports
it and is left alone; a symlink to any other file is never written through
(the installer warns instead).

## Resync and audit

```sh
bash ~/.claude/skills/docket/install.sh          # install or update docket/
bash ~/.claude/skills/docket/install.sh --check  # report drift, exit 1 if any
```

The path is wherever the skill is checked out; `~/.claude/skills/docket` is
the usual place. The same command performs the first install and every later
update. It copies the skill's files over this directory, writes `VERSION`,
refreshes the Docket section of `AGENTS.md`, and reports (but does not
delete) files here that the skill no longer ships. Commit the result.

`VERSION` holds the skill commit the files came from, as `<sha> <date>`
(UTC). It is always a commit of the docket repository: when the skill is
installed as a squashed subtree of another repository, the installer reads the
upstream commit from the subtree's `git-subtree-split` trailer rather than
recording the host repository's own commit. A `-dirty` suffix means the
skill's `install.sh` or `templates/` differed from that commit when it was
installed (uncommitted changes, or committed local edits in a subtree host);
resync from a clean checkout before relying on it.

`--check` compares `VERSION` with the skill commit of the checkout it runs
from (`HEAD` in a clone of the skill, the subtree's upstream commit in a
subtree host) before diffing any file. Run it from a checkout at or beyond the installed commit: when the
installed commit is newer, it prints "the installed copy (<sha>) is newer than
this skill checkout (<head>); update the skill checkout before resyncing" and
exits 1 without a file diff, because a stale checkout would otherwise report
the project's newer files as drift. When the installed commit is behind the
checkout but the files still match, `--check` passes and says so. Drift also
includes a script under `scripts/` that is not executable on disk or is
committed as other than `100755`; `install.sh` sets the bit, `git update-index
--chmod=+x` fixes the committed mode.

Both install and `--check` warn, without failing, when `docs/QUALITY.md`
exists without a `## Review inputs` heading (the vendored review guide links
it, so `check-links.sh` fails until the section exists) and when files of the
hand-copied layout that preceded `docket/` are still present
(`scripts/workflow/`, `docs/TODO_GUIDE.md`, `docs/CODE_REVIEW_GUIDE.md`), and
while `docs/superpowers/` exists or a bullet in the Docket section of
`AGENTS.md` names it (plans and design specs live where
[CONTRACT.md](CONTRACT.md) says); the setup reference in the skill has the
migration notes. Install also removes a stale `.feral/` line from
`.git/info/exclude`.

## docket/ and .docket/

`docket/` is tracked and vendored. `.docket/` at the project root is
local state, excluded from git (`install.sh` adds it to
`.git/info/exclude` of the clone it ran in; add it to `.gitignore` so
every clone agrees), and holds the review and coordination artifacts:

- `.docket/AUDIT.md`: the append-only decision log kept during unattended
  runs, one entry per load-bearing decision with an undo line.
- `.docket/title-<slug>.txt` and `.docket/change-<slug>.md`: the change
  title and description, used for local review or a PR awaiting
  publication. The title becomes the squash subject; the full
  description is its body. Older `.docket/pr-<slug>.md` drafts can be
  reused or renamed when updated.
- `.docket/review-<slug>.md`: independent review and dispositions,
  posted as a PR comment in hosted mode.
- `.docket/state-<slug>.md`: review mode, branch, base/head commits,
  checks, draft/ready status and explicit user landing approval when
  given.

After landing preserve these files and unique evidence under
`.docket/landed-<slug>/` in the retained main checkout before removing
the task worktree. Verify preservation before removing only those source
artifacts; use `rmdir` for now-empty directories, including `.docket/`.
Inspect and preserve other unique content before cleanup. Ignored
`.docket/` directories are discarded with a landed worktree, just like
known caches; the script does not archive them or verify preservation.
Blanket `--discard-ignored` is not a substitute for preserving records
elsewhere either. Local landing receipts live
separately in the common Git directory at `docket/landed/<branch>`, with an audit reference at
`refs/docket/landed/<branch>` retaining the approved commit through Git
garbage collection. These proof records survive work branch cleanup.
`land-local.sh` writes them and `cleanup-landed.sh` verifies them before
removing an exact landed tip. Branch deletion requires that tip still to
match, preserving a branch that advanced concurrently. Cleanup retains
branch-specific Git configuration; `start-work.sh` clears stale upstream
tracking when creating a branch and preserves its other settings.

## Files

| File | Purpose |
| --- | --- |
| `README.md` | This file. |
| `CONTRACT.md` | The workflow rules every agent reads first. |
| `TODO_GUIDE.md` | Capture, triage, claim and resolve deferred work in `TODO.md` and `review/BACKLOG.md`. |
| `CODE_REVIEW_GUIDE.md` | Change review and codebase review, and the review ledger under `review/`. |
| `VERSION` | The skill commit and date these files were installed from. |
| `scripts/ci.sh` | The single entry point CI calls; runs `check-queues.sh --strict`, then `check-links.sh`, then `check-pr-markers.sh --no-target` when `PR` is set, and stops at the first failure. In a sidecar it checks the sidecar's own PRs and needs no managed clone. On pull requests it reads the PR body from the event payload (`GITHUB_EVENT_PATH`, with `jq`) and falls back to `gh pr view`, which needs `pull-requests: read`. |
| `scripts/check-queues.sh` | Validates the structure of `TODO.md` and `review/BACKLOG.md`: entry format, unique slugs, `Source` lines, cross-references and dependencies, that each Waiting entry names what it waits on, and the format of `PR:` claim lines (in a sidecar, that they name the managed repository). |
| `scripts/check-pr-markers.sh` | Validates a change description's markers against the queues at the base and head commits, its `Type:` line, and its line length (prose wrapped at 72 columns). In a sidecar it stands down for the managed repository's PRs; `--no-target` checks the sidecar's own. |
| `scripts/pr-labels.sh` | Derives a pull request's labels from its branch, its `Type:` line and the queue entries it claims or resolves; `--apply` creates missing labels and sets them on the pull request. In a sidecar it stands down; `--no-target` labels the sidecar's own PRs. |
| `scripts/check-links.sh` | Checks that relative Markdown links, images and `#anchors` resolve to existing files and headings. |
| `scripts/claim-check.sh` | Looks for existing claims and local completions on a slug (landing receipts and exact resolution markers on main): open and merged pull requests (a body marker, or a head branch whose last path component is the slug), branches, worktrees, and queue entries carrying a `PR:` line. `--self` rechecks from inside the claimed worktree, ignoring the worker's own branch. |
| `scripts/start-work.sh` | Runs the claim check, then creates the `<queue>/<slug>` branch and its worktree. Local mode uses local main and skips forge/fetch operations. |
| `scripts/target.sh` | Parses and validates a sidecar's `.docket-target` file, which names a managed repository and its local clone. Sourced by `claim-check.sh`, `start-work.sh`, `cleanup-landed.sh`, `review-due.sh` and `pr-health.sh`, which then work on branches, worktrees, PRs and commits in the managed repository, by `check-pr-markers.sh` and `pr-labels.sh`, which stand down, and by `check-queues.sh`, which reads only its `repo` line (`--no-target` ignores the file). There `start-work.sh` marks the branches it creates (`branch.<name>.docket`) and `cleanup-landed.sh` touches only marked branches. Run directly, it prints the resolved settings. |
| `scripts/land-local.sh` | After explicit user approval, squash-lands the exact reviewed branch head into the clean base checkout, using the title and description and writing a landing receipt. |
| `scripts/cleanup-landed.sh` | Removes branches and worktrees proved landed by merged PRs or verified local receipts; a dry run unless `--apply` is given. Automatically discovers folded workers by checking their exact changed paths at historical landings, and reports the proof or why they are retained. Known caches and ignored `.docket/` directories are discarded with the worktree; preserve their records first. Other ignored files hold it back unless `--discard-ignored` is given. In a sidecar it also lists queue entries whose `PR:` pull requests have all closed, to resolve or release by hand. |
| `scripts/pr-health.sh` | Reports, read-only, on open pull requests (the current user's by default, or `--pr`, `--repo`): CI checks, review decision, merge state and conflicts, commits behind the base, a landing comment (`--land-comment`) on a PR that is still open, and queue markers whose entry is no longer in this checkout. `--strict` exits 1 on failing checks, changes requested or conflicts. In a sidecar `--repo` and `--land-comment` default to the target's `repo` and `land_comment`, and each managed PR lists the queue entries whose `PR:` line names it instead of its body markers (`--no-target` ignores the target). |
| `scripts/review-due.sh` | Measures movement since the last recorded codebase review and says whether an incremental or full review is due; binary assets are not counted as source. `--repo-dir` measures another repository against this one's index. |

Run the scripts from anywhere inside the project as
`bash docket/scripts/<name>.sh`. Each script's header comment documents its
arguments, defaults and exit codes.
