# Installing or adapting the workflow in a repository

Setup is complete when another agent, with no conversation history, can determine what is being worked on, what is available, what was decided, and what checks a PR must pass, from the repository alone. Adding headings is not setup.

## 1. Inspect before changing anything

```bash
ls AGENTS.md CLAUDE.md docket/ docs/ review/ TODO.md .github/workflows/ scripts/ 2>/dev/null
bash ~/.claude/skills/docket/install.sh --check   # vendored docket/ against the skill's copy
git worktree list; git branch -a; gh pr list --state open
gh api repos/{owner}/{repo}/branches/main/protection 2>/dev/null | head -c 400
cat .pre-commit-config.yaml lefthook.yml .husky/* package.json 2>/dev/null | head -80
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
| PR shape | `.github/pull_request_template.md` | Why, what changed, the `Type:` line and markers, validation, review. |
| Audit (unattended runs) | `.docket/AUDIT.md`, `.docket/pr-<slug>.md` and `.docket/review-<slug>.md`; the installer adds `.docket/` to `.git/info/exclude` and the install PR adds it to `.gitignore` (step 3) | Append-only decisions with undo lines; prepared PR bodies and review comments. |
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
6. **CI.** `ci.yml` from the template: check job, optional browser or smoke job, a hygiene job that is one call to `bash docket/scripts/ci.sh`, concurrency that cancels only PR runs. Then `main-validation.yml` with whatever extended checks the project has, even if initially only the check entrypoint plus `docket/scripts/review-due.sh`; the template's `pull_request` trigger is filtered to the workflow file and `docket/**`, so a resync exercises the scheduled workflow before it lands.
7. **PR template.** Copy `templates/.github/pull_request_template.md`. The installer does not sync it, so on repair compare the project's copy with the template (the `Type:` hint in the Markers section and the line-wrapping note at the top in particular).
8. **Protection.** Propose the settings from quality-gates.md to the user; they apply them. Record the result in `docs/QUALITY.md`.
9. **Quality doc.** Describe what was built, as built. No rollout narrative, no measurements from before the gates existed. The `## Review inputs` heading is required: it is the only anchor the vendored review guide links, and the installer warns when the file exists without it. Fill the section (focus areas, extra baseline commands, drift checks, the source paths for `review-due.sh --paths`).
10. **Verify.** `bash ~/.claude/skills/docket/install.sh --check` is clean; `bash scripts/check.sh` passes on main; hooks fire on a scratch commit; the first PR shows the required checks; `docket/scripts/ci.sh` and `docket/scripts/review-due.sh` run clean; `gh api .../protection` matches the quality doc.

Land the installation as one or a few PRs, each with the usual body. The installation PR is the first PR that follows its own rules.

## 4. Adapting to an issue tracker

Issues and labels can replace the Markdown queues when they express the same states: triage, proof of concept, ready, blocked (with the blocking issue linked), claimed (assignee plus draft PR), resolved. Identifiers are issue numbers; markers become `Claims #123` / `Resolves #123` with the same validator logic applied through the tracker's API. Review snapshots and the promoted backlog still live in the repository, because they are evidence tied to commits.

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
| Ready entries that are blocked by other entries | Add `Depends on:` lines and move them; validator enforces it |
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

### Migrating tool-named directories

Plans and design specs live where [`docket/CONTRACT.md`](../templates/docket/CONTRACT.md) says, whatever another tool's default. The superpowers plugin writes plans to `docs/superpowers/plans/` and design specs to `docs/superpowers/specs/` unless told otherwise. Move an existing tree in one PR:

1. `mkdir -p plans docs/specs`, then `git mv` the files from `docs/superpowers/plans/` to `plans/` and from `docs/superpowers/specs/` to `docs/specs/`, keeping their dated names. If the tree is untracked or ignored, move the files with plain `mv` instead. Then remove whatever is left of `docs/superpowers/`.
2. Fix links to the old paths; `bash docket/scripts/check-links.sh` finds them.
3. Drop any settings bullet in the Docket section of `AGENTS.md`, or other project rule text, that pointed at the old location.
4. Expect the installer's warning until `docs/superpowers/` is gone and no settings bullet names it.
