# Installing or adapting the workflow in a repository

Setup is complete when another agent, with no conversation history, can
determine what is being worked on, what is available, what was decided,
and what checks a change must pass, from the repository alone. Adding
headings is not setup.

First determine the review mode from the repository's actual remote
capabilities and policy. No remote, or a non-PR remote, uses local
review; missing credentials or a temporary forge failure does not change
a hosted repository's policy. Local setup needs Git and the project's
own check tools, not `gh`, a new remote, hosting, hosted CI or branch
protection. Record the mode and applicable local gates in
`docs/QUALITY.md`, and use the [local review and landing
procedure](pr-and-landing.md#local-review-and-approved-landing).

## 1. Inspect before changing anything

```bash
ls AGENTS.md CLAUDE.md docket/ docs/ review/ TODO.md .github/workflows/ scripts/ 2>/dev/null
bash ~/.claude/skills/docket/install.sh --check   # vendored docket/ against the skill's copy
git remote -v
git worktree list
git branch -a
cat .pre-commit-config.yaml lefthook.yml .husky/* package.json 2>/dev/null | head -80
```

For a PR-capable remote, also inspect hosted claims and protection:

```bash
gh pr list --state open
gh api repos/{owner}/{repo}/branches/main/protection 2>/dev/null | head -c 400
```

The skill path is wherever the skill is installed; `~/.claude/skills/docket` is the Claude Code default. `--check` compares against the skill checkout it runs from, which must be at or beyond the commit in `docket/VERSION` (see [The vendored directory](#the-vendored-directory)). `VERSION` always names a docket commit: from a squashed subtree the installer reads it from the subtree's `git-subtree-split` trailer, so copies installed from a subtree and from a clone of the skill compare correctly.

Keep four columns as you go: what the repository's policy says, what hooks, CI and protection actually enforce, what the records prove happened and at which revision, and what you could not see (no forge access, unrun checks, undated claims). The gaps between those columns are the findings, and so is every difference `install.sh --check` reports. Then map what exists onto the records below. Preserve compatible conventions (an issue tracker instead of Markdown queues, a different area list, a different branch prefix) and keep identifiers, sources and history. Tool-named directories such as `docs/superpowers/` are migrated, not preserved (see [Migrating tool-named directories](#migrating-tool-named-directories)). Do not create a second tracker next to a working one; do not fabricate entries, reviews or acceptance claims to make files look populated. Empty sections are valid.

Also check what lives outside the repository: harness memory files and the user's global instructions often hold rules (reviewer per writer, no merge commits, overnight branches stay local) that a different agent or a human will never see. Move anything another worker needs into the Docket section of `AGENTS.md` or the relevant project doc, never into `docket/`.

## 2. Records and their homes

| Record | Default home | Purpose |
| --- | --- | --- |
| Agent contract | Generic rules in `docket/CONTRACT.md`, read first by every agent; the project's settings (queue areas, concurrency cap, merge delegation, optional pieces in force, environment rules) as bullets in the `## Docket` section of `AGENTS.md`, which `install.sh` inserts between `<!-- docket:begin -->` and `<!-- docket:end -->` and keeps current without losing the values; the rest of `AGENTS.md` is the project's and is never dictated; an existing `CLAUDE.md` imports it with a `@AGENTS.md` line and is otherwise left as the project has it; other harnesses symlink or copy | One authoritative home per rule, linked not restated. |
| Decisions | `docs/DECISIONS.md` | Non-obvious choices with their trade-offs, dated. Read before changing a mechanism that looks odd. Autonomous choices made under delegation are recorded here for review. |
| Architecture and contracts | `ARCHITECTURE.md` or `docs/ARCHITECTURE.md` | Boundaries, shared interfaces, invariants that parallel work must respect, per-worktree isolation requirements. |
| Scope and acceptance (optional) | `SPEC.md`, `ACCEPTANCE.md` | Only for projects with a promised outcome. A hobby project with no deliverable does not need a specification; it needs decisions and a roadmap. Never invent requirements. |
| Roadmap (optional) | `docs/ROADMAP.md` | Themes and direction in prose. A third queue when the repository wants vision-sized items claimable. |
| Deferred work | `TODO.md`, `docket/TODO_GUIDE.md` | Stages, priorities, entry format, claims, markers, resolution. |
| Review ledger | `review/README.md`, `review/BACKLOG.md`, `review/<timestamp>-<type>.md`, `docket/CODE_REVIEW_GUIDE.md`; project review inputs in `docs/QUALITY.md` | Snapshots, inventory, promoted work, closure rules. |
| Quality | `docs/QUALITY.md`, `scripts/*.sh`, `docket/scripts/ci.sh`, hook config (no template; see quality-gates.md), `.github/workflows/ci.yml`, `.github/workflows/main-validation.yml` | What runs where, current state only. |
| Change description | `.github/pull_request_template.md` | Why, what changed, the `Type:` line and markers, validation; independent review is a separate record. |
| Audit (unattended runs) | `.docket/AUDIT.md`, title/change/review/state files; the installer adds `.docket/` to `.git/info/exclude` and the install PR adds it to `.gitignore` (step 3) | Append-only decisions with undo lines; prepared change descriptions and independent review records. |
| Plans | `plans/YYYY-MM-DD-<slug>.md` | Dated plans for work; may be committed direct to main (see pr-and-landing.md). |
| Design specs | `docs/specs/YYYY-MM-DD-<slug>.md` | Dated designs written ahead of the work; may be committed direct to main (see pr-and-landing.md). |

Every file in this table has a template under `templates/`, with placeholders in angle brackets, except `docket/` (installed verbatim by `install.sh`; not a template), the optional records, the hook config, plans, design specs and the audit files; `ARCHITECTURE.md` and `docs/DECISIONS.md` templates are skeletons to fill from the code and the conversation, never from guesswork. Copy, then edit every placeholder; a template left with placeholders is a Docs finding at the next review.

### The vendored directory

Nothing under `docket/` is edited in a project; it is byte-identical to the skill's `templates/docket/` and is resynced with one command. The Docket section of `AGENTS.md`, between `<!-- docket:begin -->` and `<!-- docket:end -->`, is the installer's too: its text is rewritten from `templates/AGENTS.md` on every run and its settings bullets are kept by name, so only the values are edited there. Project rule text goes in the Docket section of `AGENTS.md` (settings) or in `docs/QUALITY.md` (what quality means here, review inputs), which the vendored guides point to. `bash ~/.claude/skills/docket/install.sh --check` is the audit and `bash ~/.claude/skills/docket/install.sh` is the repair; `docket/VERSION` records which skill commit is installed. Both compare against the skill checkout they run from, so run them from a checkout at or beyond that commit: when the installed commit is a descendant of the checkout's skill commit (`HEAD` in a clone, the subtree's upstream commit in a subtree host; see [Installing the skill](../README.md#installing-the-skill)), `--check` prints "the installed copy (<sha>) is newer than this skill checkout (<head>); update the skill checkout before resyncing" and exits 1 without a file diff, so a project that was resynced from a newer checkout is not misreported as drifted. When the installed commit is unknown to the checkout the installer says so and still diffs; when the files match but `VERSION` is behind that commit it prints an informational line and exits 0.

The skill's own repository vendors its `docket/` the same way, with `bash install.sh --self` from the checkout root; the installer refuses its own repository without that flag, and refuses any other checkout of the skill outright, so the copy in `~/.claude/skills/docket/` run against a development clone stops before it overwrites `docket/` there. A repository whose `docket/` is itself the skill, such as `~/.claude/skills` holding it under that prefix, is refused for the same reason. There `docket/VERSION` is the fixed line `self`, since `templates/docket/` at the same commit is the source and a sha would change on every branch, and its CI runs `bash install.sh --self --check`, which skips the commit comparison but fails whenever `docket/` or the Docket section of `AGENTS.md` lags `templates/`.

## 3. Install order

1. **Install.** `bash ~/.claude/skills/docket/install.sh` from inside the repository. It copies the skill's `templates/docket/` to `docket/` (contract, guides, scripts), sets exec bits, writes `docket/VERSION`, adds `.docket/` to `.git/info/exclude`, and reports stray files under `docket/` without deleting them. In `AGENTS.md` it inserts the `## Docket` section between its markers: after the leading heading and intro paragraph of an existing file, before its first `## ` heading (or at the end if the file has no `## ` heading), or as the body of a new file when there is no `AGENTS.md`. On later runs it rewrites the section's text, keeps each settings bullet by name, re-adds a missing one as a placeholder and reports it, and keeps extra bullets; on the first insert it lists the settings still to fill. `--check` fails on text drift and on any setting missing or still a placeholder. If the project has a `CLAUDE.md` without the line `@AGENTS.md`, it appends that line and changes nothing else; a `CLAUDE.md` that is a symlink to `AGENTS.md` already satisfies the import and is never written through; it never creates or replaces `CLAUDE.md`. It warns when `docs/QUALITY.md` exists without a `## Review inputs` heading (step 9), removes a stale `.feral/` line from `.git/info/exclude` left by the hand-copied layout, and warns while that layout's files are still present (section 6). It also warns while `docs/superpowers/` exists or a bullet in the Docket section names it ([Migrating tool-named directories](#migrating-tool-named-directories)). The same command updates an existing installation; `--check` diffs without writing.
2. **Settings.** Fill in the settings bullets in the Docket section of `AGENTS.md`: queue areas, concurrency cap, merge delegation, which optional pieces are in force, environment rules. The direct-to-main rule in `docket/CONTRACT.md` (work-recording documentation; housekeeping metadata on the user's say-so) is the standard one; narrow it in the settings only if the user asks. Add a bullet for any other project rule that belongs with the settings; the installer keeps it. The section sits after the file's intro paragraph; move it anywhere in the file if the project reads better that way, the installer finds it by its markers. Leave the rest of `AGENTS.md` and all of `CLAUDE.md` as the project has them; docket does not dictate their shape or length. Then the project's own scripts: `scripts/setup.sh`, `scripts/check.sh` and the per-check scripts for the repository's language (see quality-gates.md).
3. **Hooks.** One manager, config tracked, installed by `scripts/setup.sh`. Measure the pre-commit time; move anything slow to pre-push. Add `.worktrees/`, `.docket/` and the evidence and cache directories to `.gitignore` in the install PR; until it lands, `start-work.sh` excludes `.worktrees/` locally and the installer excludes `.docket/` through `.git/info/exclude`, which covers only the clone where install ran, so every other clone and worktree needs the `.gitignore` entry. A Markdown formatter hook must exclude `docket/`, which is vendored byte-for-byte; the Docket section of `AGENTS.md` is written so Prettier leaves it unchanged (see quality-gates.md).
4. **Queues.** `TODO.md`; the guide is the vendored `docket/TODO_GUIDE.md`. Bring known deferred work in with sources; everything starts Unprioritized in Needs triage unless evidence says otherwise. Run `bash docket/scripts/check-queues.sh --strict`.
5. **Review ledger.** `review/README.md`, `review/BACKLOG.md`; the guide is the vendored `docket/CODE_REVIEW_GUIDE.md`. Empty index; the first review is a separate task the user requests. Install it even when the repository defers reviews for now (an empty ledger costs nothing), unless the Docket section of `AGENTS.md` records that the ledger is deliberately not in use.
6. **CI (hosted mode).** `ci.yml` from the template: check job, optional
   browser or smoke job, a hygiene job that is one call to `bash
   docket/scripts/ci.sh`, concurrency that cancels only PR runs. Then
   `main-validation.yml` with whatever extended checks the project has,
   even if initially only the check entrypoint plus
   `docket/scripts/review-due.sh`; the template's `pull_request` trigger
   is filtered to the workflow file and `docket/**`, so a resync
   exercises the scheduled workflow before it lands.
7. **Change description template.** In hosted mode copy
   `templates/.github/pull_request_template.md`. The installer does not
   sync it, so on repair compare the project's copy with the template
   (the `Type:` hint in the Markers section and the line-wrapping note
   at the top in particular).
8. **Protection (hosted mode).** Propose the settings from
   quality-gates.md to the user; they apply them. Record the result in
   `docs/QUALITY.md`.
9. **Quality doc.** Describe what was built, as built. No rollout narrative, no measurements from before the gates existed. The `## Review inputs` heading is required: it is the only anchor the vendored review guide links, and the installer warns when the file exists without it. Fill the section (focus areas, extra baseline commands, drift checks, the source paths for `review-due.sh --paths`).
10. **Verify.** In either mode, `bash ~/.claude/skills/docket/install.sh
    --check` is clean; `bash scripts/check.sh` passes on the
    installation branch and after landing on main; hooks fire on a
    scratch commit. In hosted mode the first PR shows the required
    checks; `docket/scripts/ci.sh` and `docket/scripts/review-due.sh`
    run clean; `gh api .../protection` matches the quality doc.

Land the installation as one or a few reviewed changes, each with the
usual description. It follows its own hosted or local review rules. In
local mode validate the description with `check-pr-markers.sh --body
<file> --base main --strict`, keep the branch/worktree for approval,
then squash-land and clean up. Do not create CI files or request a
remote just to satisfy setup; document hosted-only steps as not
applicable.

## 4. Adapting to an issue tracker

Issues and labels can replace the Markdown queues when they express the same states: triage, proof of concept, waiting (with the blocking issue or decision linked), ready, claimed (assignee plus draft PR), resolved. Identifiers are issue numbers; markers become `Claims #123` / `Resolves #123` with the same validator logic applied through the tracker's API. Review snapshots and the promoted backlog still live in the repository, because they are evidence tied to commits.

## 5. What not to import

- Another project's domain checklist (its invariants, its headless commands, its coverage number). Derive the repository's own.
- A specification for a project with no promised outcome.
- Tooling as a hardening project. Add a gate when a concrete failure mode calls for it and record the failure mode in the quality doc.
- Commit hashes or file names from the repositories this skill was distilled from. They mean nothing elsewhere.

## 6. Repairing a drifted installation

Symptoms and the fix, from the studied repositories:

| Symptom | Fix |
| --- | --- |
| Rules exist only in harness memory or a global instruction file | Move them into the Docket section of `AGENTS.md` or the relevant project doc in a docs PR |
| `AGENTS.md` and `CLAUDE.md` are divergent copies | Make one the import of the other |
| Ready entries that are blocked by other entries | Add `Depends on:` lines and move them to Waiting; validator enforces it |
| Needs triage full of settled entries that are only blocked | Move them to Waiting ([Adding the Waiting stage](#adding-the-waiting-stage)) |
| Claim markers never used, PRs not opened as drafts | Put `start-work.sh` and the draft rule into the contract; add the marker validator to CI so a missing or malformed marker is visible |
| Review index stale for months | Run `review-due.sh` in the scheduled workflow; request the review |
| Stale worktrees and placeholder branches | `bash docket/scripts/cleanup-landed.sh --apply --empty` at the end of every session; `.worktrees/` inside the repo |
| `install.sh --check` reports differences in `docket/` or in the Docket section of `AGENTS.md` | Rerun `install.sh`; fill in any setting it reports; move project rule text to the settings bullets or to `docs/QUALITY.md` |
| `install.sh --check` says the installed copy is newer than the skill checkout | Update the skill checkout (`git -C ~/.claude/skills/docket pull`), then rerun; the project is not drifted |
| `docs/QUALITY.md` has no `## Review inputs` heading | Add the section from the template; `check-links.sh` fails on the guide's link until it exists |
| A formatting hook rewrites `docket/` or the Docket section | Exclude `docket/` from the formatter; resync to restore the files |
| Quality doc describes a past state | Rewrite as current state; move history to decisions |
| Red main nobody noticed | Concurrency fix for main pushes; red-main policy; badge for the scheduled run |
| Zero review records on the forge | A review comment on every code PR |

### Migrating from the hand-copied layout

Repositories set up before the vendored `docket/` directory existed carry copies of the guides and scripts under their own paths. Bring one across in a single PR:

1. Run `install.sh`, then remove `scripts/workflow/`, `docs/TODO_GUIDE.md` and `docs/CODE_REVIEW_GUIDE.md`; the vendored copies replace them.
2. Move project rule text that had been edited into those copies to the Docket section of `AGENTS.md` (settings) or to Review inputs in `docs/QUALITY.md`.
3. Repoint everything that named the old paths: CI workflows, hook config, `scripts/check.sh`, the PR template, `TODO.md`, `review/README.md` and `review/BACKLOG.md`. `bash docket/scripts/check-links.sh` finds the stragglers.
4. Swap `.feral/` and a root `AUDIT.md` for `.docket/` (the installer removes the stale `.feral/` exclude line); add `.docket/` to `.gitignore`.
5. Leave review snapshots untouched; they are evidence tied to commits.
6. Expect the installer's warnings about the hand-copied layout until the removal lands.

### Adding the Waiting stage

`TODO.md` belongs to the project, so a resync does not add the Waiting stage to one written before it existed; the vendored guide and validator describe it, and `check-queues.sh` accepts a file without the section. Add it in the next triage, or the first time an entry needs it:

1. Insert `## Waiting` with the five priority subsections between Needs proof of concept and Ready for separate work, as in the skill's `templates/TODO.md`.
2. Update the header paragraph to the template's wording, which says where blocked entries go.
3. Move each entry in Needs triage whose outcome and approach are settled and which carries a `Depends on:` or `Blocked by:` line to Waiting, keeping its priority. Run `bash docket/scripts/check-queues.sh --strict`.

It lands as a direct commit to `main`, like any triage.

### Migrating tool-named directories

Plans and design specs live where [`docket/CONTRACT.md`](../templates/docket/CONTRACT.md) says, whatever another tool's default. The superpowers plugin writes plans to `docs/superpowers/plans/` and design specs to `docs/superpowers/specs/` unless told otherwise. Move an existing tree in one PR:

1. `mkdir -p plans docs/specs`, then `git mv` the files from `docs/superpowers/plans/` to `plans/` and from `docs/superpowers/specs/` to `docs/specs/`, keeping their dated names. If the tree is untracked or ignored, move the files with plain `mv` instead. Then remove whatever is left of `docs/superpowers/`.
2. Fix links to the old paths; `bash docket/scripts/check-links.sh` finds them.
3. Drop any settings bullet in the Docket section of `AGENTS.md`, or other project rule text, that pointed at the old location.
4. Expect the installer's warning until `docs/superpowers/` is gone and no settings bullet names it.

## 7. A sidecar for a managed repository

Some repositories cannot take a docket installation: a large shared monorepo has its own owners, CI, PR template, hooks and merge process, and one contributor cannot add `docket/`, `TODO.md` or a review ledger to it. Install docket in a small repository of the contributor's own instead, the sidecar, and point it at the managed repository. The sidecar holds the queues, plans, decisions, review ledger and audit; branches, worktrees, PRs and CI stay in the managed repository. Never copy docket, queues or hooks into the managed clone: one careless `git add -A` would commit them to someone else's repository.

1. Create the sidecar repository and install docket in it as usual (steps 1 to 5, 9 and 10). Its own hooks and CI check only its own files: queue hygiene, Markdown links and formatting. It needs no PR template for the managed repository and no local landing of managed work.
2. Clone the managed repository wherever the user keeps clones. Nothing docket needs goes inside it.
3. Write `.docket-target` at the sidecar's root and commit it:

   ```
   # Managed repository for this sidecar
   repo=owner/repo                  # gh slug of the managed repository
   dir=~/src/repo                   # its local clone
   base=main                        # default: main
   remote=origin                    # default: origin
   branch_prefix=me/                # default: docket's <queue>/<slug>
   worktree_dir=~/src/repo-worktrees  # default: <dir>-worktrees
   land_comment=                    # e.g. a merge-bot command; empty: the user merges
   ```

   `repo` and `dir` are required; the rest have the defaults shown. A leading `~/` expands to the home directory, and a relative `dir` or `worktree_dir` is taken from the sidecar's main worktree (the parent of its git common directory), so the scripts resolve it the same way from any sidecar worktree. `#` starts a comment when it begins a line or follows whitespace. An unknown key, a repeated key, a malformed line, a missing `dir` or a clone without the named remote stops every script that reads the file, naming the file and line. `DOCKET_TARGET_FILE` points the scripts at another file, which is how one sidecar can be tried against a second clone without editing the tracked one. Set it per command (`DOCKET_TARGET_FILE=<file> bash docket/scripts/...`), never in a shell profile or an exported environment: a global value would redirect every docket script on the machine, including those of other sidecars and ordinary installations. A relative value is taken from the current directory.
4. Run `bash docket/scripts/target.sh` from the sidecar. It validates the file and prints the resolved repository, clone, base, branch names, worktree location and landing comment.
5. Record the arrangement in an environment bullet in the Docket section of the sidecar's `AGENTS.md`: which repository it manages, that `.docket-target` is the authority for the target, and anything the managed repository's own contribution rules require (its PR template, required reviewers, how merges happen).

With the file in place, the scripts that touch work in progress act on the managed repository:

| Script | In a sidecar |
| --- | --- |
| `claim-check.sh` | Counts only the exact branch name docket would create: `<branch_prefix><slug>`, or `<queue>/<slug>` for the queue `--queue` names (all five queue forms without it; `start-work.sh` passes its queue). It looks for that name among branches and worktrees in the managed clone and the target remote's refs, and among PRs in `repo` with `gh pr list --repo` (no body markers; the managed repository's PRs carry none). An open PR on the name is a claim; a merged PR is a claim when you authored it (`gh api user`) and a note when someone else did; a closed one by someone else is a note. Backlog finding slugs still come from the sidecar's `review/BACKLOG.md`. |
| `start-work.sh` | Runs that claim check, fetches `<remote> <base>` in the clone, and creates the branch (`<branch_prefix><slug>`, or `<queue>/<slug>` without a prefix) and its worktree at `<worktree_dir>/<queue>-<slug>` from `<remote>/<base>`, and marks the branch as docket's with `git config branch.<name>.docket true` in the clone. It writes the clone's exclude file only when `worktree_dir` is inside the clone. A relative `--dir` is taken from the current directory. The sidecar's queue entry is the claim record. |
| `cleanup-landed.sh` | Considers only branches carrying the docket marker, on both the merged and the `--empty` paths, so the user's own branches in the clone are never touched whatever their names. It proves landing with `gh pr list --repo <repo> --head <branch> --state merged`, measures `--empty` against `<remote>/<base>`, never deletes `<base>`, removes a deleted branch's marker with it, and with `--apply` fetches and prunes `<remote>` there. A branch made by hand can be handed to cleanup by setting the marker on it. |
| `review-due.sh` | Reads `review/README.md` from the sidecar and resolves its commits in the clone (`--repo-dir`, defaulting to `dir`; a relative path is taken from the current directory), measuring up to `<remote>/<base>`. Scope a review of a large repository to the contributor's area with `--paths`. |

Every one of them takes `--no-target` for work on the sidecar itself, such as a queue triage branch or a change to its own checks. `gh` calls in target mode always name the target with `--repo`, and `GH_REPO` is set to it, so an inherited `GH_REPO` or the current directory never redirects a query.

An agent working in a managed worktree has no `docket/` there. It runs the sidecar's scripts by absolute path, for example `bash ~/src/sidecar/docket/scripts/claim-check.sh --self <slug>` from the worktree; the scripts find the sidecar from their own location. `--self` needs the branch to be pushed to the managed repository itself: target mode does not yet support contributing through a fork, and a fork PR on the branch name is reported as another worker's claim.

`check-pr-markers.sh`, `pr-labels.sh` and `land-local.sh` still act on the sidecar: never run them against the managed repository's PRs, and never create docket labels there. The managed repository's own CI is the authority for its gates; run the contributor's own checks on the files the change touches before marking a PR ready. Several sidecars can share one clone only when their slugs are unique across all of them, not just their `branch_prefix` values: a prefix keeps branch names apart, but the claim check's worktree scan also matches a `<queue>-<slug>` directory name, so two sidecars using one slug see each other's work as a claim. Landing in a managed repository is described in [pr-and-landing](pr-and-landing.md#landing-in-a-managed-repository).
