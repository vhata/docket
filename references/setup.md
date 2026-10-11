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

Keep four columns as you go: what the repository's policy says, what hooks, CI and protection actually enforce, what the records prove happened and at which revision, and what you could not see (no forge access, unrun checks, undated claims). The gaps between those columns are the findings, and so is every difference `install.sh --check` reports. Then map what exists onto the records below. Preserve compatible conventions (an issue tracker instead of Markdown queues, a different area list, a different branch prefix) and keep identifiers, sources and history. Do not create a second tracker next to a working one; do not fabricate entries, reviews or acceptance claims to make files look populated. Empty sections are valid.

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
| PR shape | `.github/pull_request_template.md` | Why, what changed, markers, validation, review. |
| Audit (unattended runs) | `.docket/AUDIT.md` and `.docket/pr-<slug>.md`; the installer adds `.docket/` to `.git/info/exclude` | Append-only decisions with undo lines; prepared PR bodies. |
| Plans | `plans/YYYY-MM-DD-<slug>.md` | Dated plans for work; committed direct to main (see pr-and-landing.md). |

Every file in this table has a template under `templates/`, with placeholders in angle brackets, except `docket/` (installed verbatim by `install.sh`; not a template), the optional records, the hook config, plans and the audit files; `ARCHITECTURE.md` and `docs/DECISIONS.md` templates are skeletons to fill from the code and the conversation, never from guesswork. Copy, then edit every placeholder; a template left with placeholders is a Docs finding at the next review.

### The vendored directory

Nothing under `docket/` is edited in a project; it is byte-identical to the skill's `templates/docket/` and is resynced with one command. The Docket section of `AGENTS.md`, between `<!-- docket:begin -->` and `<!-- docket:end -->`, is the installer's too: its text is rewritten from `templates/AGENTS.md` on every run and its settings bullets are kept by name, so only the values are edited there. Project rule text goes in the Docket section of `AGENTS.md` (settings) or in `docs/QUALITY.md` (what quality means here, review inputs), which the vendored guides point to. `bash ~/.claude/skills/docket/install.sh --check` is the audit and `bash ~/.claude/skills/docket/install.sh` is the repair; `docket/VERSION` records which skill commit is installed.

## 3. Install order

1. **Install.** `bash ~/.claude/skills/docket/install.sh` from inside the repository. It copies the skill's `templates/docket/` to `docket/` (contract, guides, scripts), sets exec bits, writes `docket/VERSION`, adds `.docket/` to `.git/info/exclude`, and reports stray files under `docket/` without deleting them. In `AGENTS.md` it inserts the `## Docket` section between its markers (appending to an existing file, or creating one when there is none); on later runs it rewrites the section's text, keeps each settings bullet by name, re-adds a missing one as a placeholder and reports it, and keeps extra bullets. `--check` fails on text drift and on any setting missing or still a placeholder. If the project has a `CLAUDE.md` without the line `@AGENTS.md`, it appends that line and changes nothing else; it never creates or replaces `CLAUDE.md`. The same command updates an existing installation; `--check` diffs without writing.
2. **Settings.** Fill in the settings bullets in the Docket section of `AGENTS.md`: queue areas, concurrency cap, merge delegation, which optional pieces are in force, environment rules. The direct-to-main rule in `docket/CONTRACT.md` (work-recording documentation; housekeeping metadata on the user's say-so) is the standard one; narrow it in the settings only if the user asks. Add a bullet for any other project rule that belongs with the settings; the installer keeps it. Leave the rest of `AGENTS.md` and all of `CLAUDE.md` as the project has them; docket does not dictate their shape or length. Then the project's own scripts: `scripts/setup.sh`, `scripts/check.sh` and the per-check scripts for the repository's language (see quality-gates.md).
3. **Hooks.** One manager, config tracked, installed by `scripts/setup.sh`. Measure the pre-commit time; move anything slow to pre-push. Add `.worktrees/` and the evidence and cache directories to `.gitignore` in the install PR; until it lands, `start-work.sh` excludes `.worktrees/` locally through `.git/info/exclude`. `.docket/` is excluded by the installer through `.git/info/exclude`, so it needs no `.gitignore` entry; an audit checks that the exclusion is present (`grep -qx '.docket/' .git/info/exclude`).
4. **Queues.** `TODO.md`; the guide is the vendored `docket/TODO_GUIDE.md`. Bring known deferred work in with sources; everything starts Unprioritized in Needs triage unless evidence says otherwise. Run `bash docket/scripts/check-queues.sh --strict`.
5. **Review ledger.** `review/README.md`, `review/BACKLOG.md`; the guide is the vendored `docket/CODE_REVIEW_GUIDE.md`. Empty index; the first review is a separate task the user requests. Install it even when the repository defers reviews for now (an empty ledger costs nothing), unless the Docket section of `AGENTS.md` records that the ledger is deliberately not in use.
6. **CI.** `ci.yml` from the template: check job, optional browser or smoke job, a hygiene job that is one call to `bash docket/scripts/ci.sh`, concurrency that cancels only PR runs. Then `main-validation.yml` with whatever extended checks the project has, even if initially only the check entrypoint plus `docket/scripts/review-due.sh`.
7. **PR template.**
8. **Protection.** Propose the settings from quality-gates.md to the user; they apply them. Record the result in `docs/QUALITY.md`.
9. **Quality doc.** Describe what was built, as built. No rollout narrative, no measurements from before the gates existed. Fill the "Review inputs" section (focus areas, extra baseline commands, drift checks) that the vendored review guide points to.
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
| Quality doc describes a past state | Rewrite as current state; move history to decisions |
| Red main nobody noticed | Concurrency fix for main pushes; red-main policy; badge for the scheduled run |
| Zero review records on the forge | `## Review` section in every code PR body |
