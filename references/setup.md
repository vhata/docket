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

### Setting one up

1. **Create the sidecar.** A new, empty git repository of the contributor's own, with a remote if they want one; it follows the hosted or local review rules for its own changes like any docket project. Clone the managed repository wherever the user keeps clones, if it is not cloned already. Nothing docket needs goes inside that clone.
2. **Install in sidecar mode**, from inside the sidecar:

   ```bash
   bash ~/.claude/skills/docket/install.sh --sidecar --repo owner/repo --dir ~/src/repo \
     [--base main] [--remote origin] [--push-remote fork] [--push-owner me] \
     [--branch-prefix me/] [--worktree-dir ~/src/repo-worktrees] \
     [--land-comment '<merge command>']
   ```

   This is the normal install (step 1 of the install order) plus two things. It writes `.docket-target` at the sidecar root, one `key=value` line per option given, and validates it with `docket/scripts/target.sh` before writing anything at all; a missing clone, a clone without the remote, a `--dir` that is the sidecar itself, or a sidecar created inside the managed clone or one of its worktrees stops it. It then adds a `- Managed repository:` bullet to the Docket section of `AGENTS.md`, naming the repository and saying that its CI, PR template, reviews and merge process govern work there. An existing `.docket-target` that resolves to the same settings is left alone, so the command is safe to rerun; one that names different settings is refused, with the difference shown, and is edited by hand. `install.sh --sidecar` with no options keeps the existing file, refusing before it writes anything when that file is invalid, and re-adds the bullet if it went missing. Every later `install.sh` and `install.sh --check` validates `.docket-target`, and fails while it is invalid; `--check` also warns when the Managed repository bullet is missing or names a different repository. The installer never writes into the managed clone.
3. **Fill the settings.** The usual bullets (step 2 of the install order), with the managed repository in mind: queue areas can name its directories, the concurrency cap is about what its builds cost on this machine, and the merge setting says who posts the `land_comment` or presses the merge button. Extend the Managed repository bullet, on the same line, with anything the managed repository's contribution rules require that an agent would not find in its tree: required reviewers, a PR title convention, which CI jobs are flaky. The installer keeps settings bullets one line each, so indented sub-bullets under it would be dropped on the next run. Commit `.docket-target` with the installation.
4. **Queues and review ledger.** `TODO.md` and `review/` as in steps 4 and 5. Entries can name areas and paths of the managed repository, and `Blocked by:` can name its issues and PRs as `owner/repo#123`. A full review of a large repository is rarely what anyone wants: set the source paths in the Review inputs of `docs/QUALITY.md` to the contributor's area, and run `bash docket/scripts/review-due.sh --paths "<those paths>"`, which resolves the reviewed commits in the managed clone.
5. **The sidecar's own hooks and CI.** They check only the sidecar's files: `bash docket/scripts/ci.sh` (queue hygiene, Markdown links, PR markers for the sidecar's own PRs) and whatever formatter the sidecar's Markdown uses, with `docket/` excluded from it. Install them with the sidecar's `scripts/setup.sh`, which sets `core.hooksPath` in the sidecar only. The managed repository's hooks, if it has any, are its own business. Steps 6 to 8 of the install order (CI, the change description template, protection) and `land-local.sh` do not apply to managed work, since the managed repository has its own and the sidecar copies none of them; they apply only to the sidecar's own changes, and only when it has a PR-capable remote. Without one, the sidecar's changes use local review.
6. **Own checks on managed work.** Copy `templates/scripts/check-mine.sh` to the sidecar's `scripts/` and fill in its `configure()` rules (below).
7. **Verify.** `bash docket/scripts/target.sh` prints the resolved repository, clone, base, branch names, worktree location and landing comment; `install.sh --check` is clean; the sidecar's hooks fire on a scratch commit in the sidecar and nothing changed in the managed clone (`git -C <clone> status`).

The sidecar's `docs/QUALITY.md` then describes two things. For the sidecar itself: the hygiene gates that check its Markdown and queues, where they run, and how its own changes land. For managed work: that the managed repository's CI is the authority for its gates and is not reproduced, which `check-mine.sh` rules the contributor runs on their own changes and when (before marking a PR ready), and the Review inputs scoped to the contributor's paths. Leave out build, test and coverage gates the sidecar does not run.

### The target file

```
# Managed repository for this sidecar
repo=owner/repo                  # gh slug of the managed repository
dir=~/src/repo                   # its local clone
base=main                        # default: main
remote=origin                    # default: origin
push_remote=fork                 # default: remote; a fork's remote in the clone
push_owner=me                    # default: the owner in push_remote's forge URL
branch_prefix=me/                # default: docket's <queue>/<slug>
worktree_dir=~/src/repo-worktrees  # default: <dir>-worktrees
land_comment=                    # e.g. a merge-bot command; empty: the user merges
```

`install.sh --sidecar` writes this file from its options; it can also be written by hand. `repo` and `dir` are required; the rest have the defaults shown. `push_remote` is for contributing through a fork: it names the clone's remote for the fork, which must exist; branches are pushed there and PRs opened from `<push_owner>:<branch>`, while `remote` still supplies the base. The fork owner is taken from that remote's push URL when it is a forge URL whose path, with repeated and leading slashes dropped as forges do, is exactly `<owner>/<name>` (`git@github.com:me/repo.git`, `https://github.com/me/repo`) and the owner looks like an account name: no dot and not all digits. Otherwise `push_owner` is required and the scripts say so; that covers a local path or `file://` URL (the parent directory is never taken as the owner), a nested group path such as `https://gitlab.com/group/sub/repo`, and a URL with no owner at all. An explicit `push_owner` that differs from the owner in a URL on the same host as `remote`'s is refused as a contradiction; on another host, such as a mirror or proxy, `push_owner` is taken as given. Whether or not `push_owner` is set, a `push_remote` is refused when its push URL is `remote`'s fetch or push URL (ignoring repeated and trailing slashes and a trailing `.git`), or a forge URL whose `<owner>/<name>` path is `repo`; a URL that reaches the managed repository some other way, such as another spelling of a local path or a forge redirect, is not caught, and `push_owner` without a `push_remote` other than `remote` is an error. A leading `~/` expands to the home directory, and a relative `dir` or `worktree_dir` is taken from the sidecar's main worktree (the first one `git worktree list` names), so the scripts resolve it the same way from any sidecar worktree; the installer writes a relative `--dir` as given, so give it relative to that worktree. `#` starts a comment when it begins a line or follows whitespace, so a value cannot contain ` #`. An unknown key, a repeated key, a malformed line, a missing `dir` or a clone without the named remote stops every script that reads the file, naming the file and line. `DOCKET_TARGET_FILE` points the scripts at another file, which is how one sidecar can be tried against a second clone without editing the tracked one. Set it per command (`DOCKET_TARGET_FILE=<file> bash docket/scripts/...`), never in a shell profile or an exported environment: a global value would redirect every docket script on the machine, including those of other sidecars and ordinary installations. A relative value is taken from the current directory. `docket/scripts/target.sh` is the one parser of the file, and its header is the reference for the format.

### How the scripts behave in a sidecar

With the file in place, the scripts that touch work in progress act on the managed repository:

| Script | In a sidecar |
| --- | --- |
| `claim-check.sh` | Counts only the exact branch name docket would create: `<branch_prefix><slug>`, or `<queue>/<slug>` for the queue `--queue` names (all five queue forms without it; `start-work.sh` passes its queue). It looks for that name among branches and worktrees in the managed clone and the target remote's refs, and among PRs in `repo` with `gh pr list --repo` (no body markers; the managed repository's PRs carry none). An open PR on the name is a claim, unless `--self` finds it headed by your own branch at a tip you have, from the managed repository itself or from the `push_remote` fork (its head owner is `push_owner`); a merged PR is a claim when you authored it (`gh api user`) and a note when someone else did; a closed one by someone else is a note. Backlog finding slugs still come from the sidecar's `review/BACKLOG.md`. |
| `start-work.sh` | Runs that claim check, fetches `<remote> <base>` in the clone, and creates the branch (`<branch_prefix><slug>`, or `<queue>/<slug>` without a prefix) and its worktree at `<worktree_dir>/<queue>-<slug>` from `<remote>/<base>`, and marks the branch as docket's with `git config branch.<name>.docket true` in the clone. It writes the clone's exclude file only when `worktree_dir` is inside the clone. In target mode a relative `--dir` is taken from the current directory. Its next steps name the remote to push to (`push_remote`, with `gh pr create --head <push_owner>:<branch>`, when one is set) and the `PR:` line to record. The sidecar's queue entry is the claim record. |
| `cleanup-landed.sh` | Considers only branches carrying the docket marker, on both the merged and the `--empty` paths, so the user's own branches in the clone are never touched whatever their names. It proves landing with `gh pr list --repo <repo> --head <branch> --state merged`, which matches the branch name in any fork; with `push_remote` set it takes only a PR headed in the managed repository or in that fork, so another fork's merged PR under the same name proves nothing. It measures `--empty` against `<remote>/<base>`, never deletes `<base>`, removes a deleted branch's marker with it, and with `--apply` fetches and prunes `<remote>` there. A branch made by hand can be handed to cleanup by setting the marker on it. |
| `review-due.sh` | Reads `review/README.md` from the sidecar and resolves its commits in the clone (`--repo-dir`, defaulting to `dir`; a relative path is taken from the current directory), measuring up to `<remote>/<base>`. Scope a review of a large repository to the contributor's area with `--paths`. |

Every one of them takes `--no-target` for work on the sidecar itself, such as a queue triage branch or a change to its own checks. `gh` calls in target mode always name the target with `--repo`, and `GH_REPO` is set to it, so an inherited `GH_REPO` or the current directory never redirects a query.

An agent working in a managed worktree has no `docket/` there. It runs the sidecar's scripts by absolute path, for example `bash ~/src/sidecar/docket/scripts/claim-check.sh --self <slug>` from the worktree; the scripts find the sidecar from their own location. `--self` treats an open PR headed by the worktree's branch at a tip it has as the worker's own when the PR comes from the managed repository itself or from the `push_remote` fork; a PR from any other fork on that branch name is reported as another worker's claim, as is a fork PR when no `push_remote` is set.

`check-pr-markers.sh` and `pr-labels.sh` stand down when a target is configured, printing one line and exiting 0, because the managed repository's PRs carry no markers and get no docket labels; the claim is a `PR: <repo>#<number>` line on the sidecar's queue entry (see [queues](queues.md#claiming)). `--no-target` runs them for the sidecar's own PRs, as `ci.sh` and `land-local.sh` do. `land-local.sh` lands only the sidecar's own work. See [Own checks](#own-checks-check-minesh) for checks on managed work and [Several sidecars on one clone](#several-sidecars-on-one-clone) for sharing a clone. Landing in a managed repository is described in [pr-and-landing](pr-and-landing.md#landing-in-a-managed-repository).

### Own checks: `check-mine.sh`

The managed repository's CI is the authority for its gates. A contributor often holds their own work to more than that, such as a Markdown formatter or a spell checker the repository's owners do not run, and must not apply it to everyone else's files or install it as a hook in the clone. `templates/scripts/check-mine.sh` is a skeleton for that: copy it to the sidecar's `scripts/`, keep it executable, and add rules in its `configure()` function:

```bash
configure() {
  rule '*.md' 'npx --no-install prettier --check' 'npx --no-install prettier --write'
  rule '*.sh' 'shellcheck -S warning'
}
```

Each rule is a shell pattern matched against paths from the worktree root (`*` matches across `/`), a check command and an optional fixer; the matching files are appended to the command. Run it from a managed worktree, or pass `--worktree <path>`. It reads `<remote>/<base>` from `.docket-target` through the installed `target.sh` (`--base <ref>` overrides it, and is required where there is no target file), and checks only the files that differ from the merge base of `HEAD` and that ref, committed or not, plus untracked files git does not ignore; deleted files and the base's own later changes are left out. It refuses a worktree that is not in the managed clone. By default it only checks, and fails a run whose check changed a file it was given; `--fix` runs each rule's fixer instead and lets it write. It installs nothing in the managed clone. Agents run it before marking a managed PR ready, and the result goes in the change's validation notes.

### Several sidecars on one clone

Several sidecars can share one clone, such as one per project inside the same monorepo, provided their slugs are unique across all of them. Each sidecar's `claim-check.sh` scans every worktree in the clone, whichever sidecar made it, and a worktree directory named `<queue>-<slug>` counts as a claim on that slug whatever its branch prefix; two sidecars using one slug would also share a worktree path under a shared `worktree_dir`. A distinct `branch_prefix` per sidecar (for example `me/billing/` and `me/search/`) keeps their branch names apart and makes it obvious in the clone whose branch is whose.

`cleanup-landed.sh` goes by the docket marker `start-work.sh` sets on each branch (`branch.<name>.docket`), not by prefix, so cleanup run from one sidecar also considers another sidecar's marked branches in the same clone. It still removes only branches whose PRs merged at their exact tip, or that are empty with `--empty`, and only worktrees with nothing uncommitted, so the effect is tidying the other sidecar's finished work early. Run it without `--apply` first to see the list.
