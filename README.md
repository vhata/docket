<img src="assets/docket.svg" alt="Docket ledger icon" width="80" height="80">

# docket

**A shared plan for coding agents.**

An agent skill for running a project with many coding agents working on it at once, without them tripping over each other. A docket is the list of work to be heard and the record of what happened to each item; this one keeps that list for a software project.

It gives Claude Code (and Codex, via `agents/openai.yaml`) a documented way to adopt, audit and operate a workflow built on:

- **Queues, not tangents.** Deferred work lives in `TODO.md` and a review backlog, with sources and exact slugs. Ideas get filed immediately and the current task continues.
- **One branch, one worktree, one draft PR per task.** Claims are visible in the PR body, so two agents never race on the same entry.
- **Paired review.** Every code-writing agent gets a separate reviewer agent before a PR is called ready.
- **Gates everywhere.** Fast hooks, full CI on PRs and main, scheduled extended runs, and branch protection that makes merging safe rather than ceremonial.
- **A review ledger.** Full and incremental codebase reviews record what was looked at, at which commit, and what was found.

The user stays in charge of the one-way doors: merging, force-pushing, tagging, releasing, and changing CI or protection all need an explicit go-ahead.

## What is in here

| Path | What it is |
| --- | --- |
| `SKILL.md` | The skill itself. The entry point an agent reads, with the quick-start phrases, the unit-of-work procedure, the authorisation ladder and the red flags. |
| `references/` | The deeper documents: `setup.md` (installing and auditing), `queues.md`, `parallel-work.md` (including paired review), `reviews.md`, `quality-gates.md` and `pr-and-landing.md` (PRs, stacking, landing, cleanup). |
| `install.sh` | Copies `templates/docket/` into a project as `docket/`, verbatim, and with `--check` reports any drift between the two. The same command is first install and update. |
| `templates/` | Files the skill installs into a repository, laid out as they land there. `templates/docket/` is vendored as `docket/` and never edited in the project: the generic contract, the queue and review guides, and portable bash tools (bash 3.2, git, and `gh` where PRs are involved) for queue validation, PR marker checks, claim checks, branch and worktree creation, review drift, post-merge cleanup, and the CI entry point. The rest are starting points edited per project: the Docket section the installer adds to `AGENTS.md`, CI workflows, a PR template, and `scripts/check.sh` and `scripts/setup.sh` skeletons. See `templates/README.md` for where each one goes. |
| `tests/` | `scripts.sh` checks the vendored scripts against a disposable git repository, with a fake forge for the pull request cases; `install.sh` runs the installer against a scratch project and a scratch clone of this checkout. CI runs both under Linux bash and macOS `/bin/bash` 3.2. |
| `agents/openai.yaml` | Display metadata so the skill shows up in Codex. |
| `docket/`, `AGENTS.md`, `CLAUDE.md`, `ARCHITECTURE.md`, `TODO.md`, `review/`, `docs/`, `scripts/`, `.githooks/`, `.github/`, `.gitignore` | This repository's own docket installation: it is run with docket like any adopting project. `docket/` is generated from `templates/docket/` by `bash install.sh --self` and CI fails when the two differ. These files describe this repository only and are not installed anywhere. See `ARCHITECTURE.md`. |

## Installing the skill

The skill is a directory with `SKILL.md` at its top, placed where your agent looks for skills: `~/.claude/skills/<name>` for Claude Code, `~/.codex/skills/<name>` for Codex, `~/.agents/skills/<name>` for harnesses that read the shared location. Three ways to put it there:

```bash
# 1. A clone, when the skills directory is not itself a repository.
git clone git@github.com:vhata/docket.git ~/.claude/skills/docket

# 2. A squashed subtree, when your skills directory is a repository you version.
cd ~/.claude/skills
git remote add docket git@github.com:vhata/docket.git
git subtree add --prefix=docket docket main --squash -m 'Add the docket skill'
#    Later, to update (-m replaces the "Merge commit 'abc123'" message git would write):
git subtree pull --prefix=docket docket main --squash -m 'Update the docket skill'

# 3. A symlink from the other harnesses' skill directories to one copy.
ln -s ~/.claude/skills/docket ~/.codex/skills/docket
```

Restart the agent, or start a new session, and the skill is available as `docket`.

Two things follow from how it is installed. `install.sh --check` compares a project against the copy it runs from, so update the clone or pull the subtree before resyncing a project, or the project's newer files are reported as drift (the installer stops with "the installed copy is newer than this skill checkout" when it can tell). And `docket/VERSION` always names a commit of this repository: from a subtree the installer reads the upstream commit from the subtree's `git-subtree-split` trailer, so copies installed from a clone and from a subtree compare correctly. A subtree pulled without `--squash` leaves no trailer, so the installer records the last squashed commit it can find and marks the install dirty.

## Using it

You do not need to know the internals. Open a session in the repository you want to work on and say one of these:

| Say | What happens |
| --- | --- |
| "Use docket to set up this project" | The agent inspects the repository. A repository with no workflow gets the contract, queues, scripts, CI and review ledger installed on a branch. An empty repository gets initialised first. |
| "Use docket to audit this project" | Same inspection, but against an existing workflow. Drift between what the docs say, what CI enforces, and what the records prove becomes a list of findings and repairs. |
| "Use docket to do a full review" / "an incremental review" | A codebase review landed as its own PR, recorded in the review ledger. |
| "Use docket to fan out the ready TODOs" / "run overnight" | The agent acts as coordinator: one writer and one reviewer per ready queue entry, each in its own worktree, with the autonomy mode stated up front. |
| "Use docket to triage the queues" | Sort new entries into stages and priorities, split batches, reconcile stale claims. |
| "Use docket to clean up after the merged PRs" | Remove worktrees and branches whose PRs have landed. |

Branch protection settings are proposed, never applied; you apply them yourself on the hosting side.

Once a repository has been set up, ordinary single-task work does not need this skill. `AGENTS.md`, `docket/CONTRACT.md` and the vendored guides carry the rules, and the scripts are vendored into `docket/scripts/` so agents without the skill run the same tools. Just say "grab a TODO" or describe the task.

## Installing into a project

From inside the project, run `bash ~/.claude/skills/docket/install.sh` (or let the agent do it as part of "Use docket to set up this project"); the path is wherever you installed the skill, and `~/.claude/skills/docket` is the Claude Code default. It copies `templates/docket/` to `docket/` at the project root, writes `docket/VERSION`, excludes the local `.docket/` working directory from git, and inserts a `## Docket` section, delimited by `<!-- docket:begin -->` and `<!-- docket:end -->`, into the project's `AGENTS.md` after its intro paragraph (creating the file if there is none; moving the section elsewhere in the file is safe). Fill in the settings bullets in that section (queue areas, concurrency cap, merge delegation, optional pieces in force, environment rules); later runs rewrite the section's text, keep the settings by name and re-add any that went missing. Everything outside the markers is the project's and the installer never touches it. If the project has a `CLAUDE.md`, the installer appends the line `@AGENTS.md` when it is missing and leaves the rest of that file alone; a `CLAUDE.md` that is a symlink to `AGENTS.md` already counts as the import and is left untouched. It never creates or replaces `CLAUDE.md`. Rerun the same command whenever the skill changes; it resyncs `docket/` and the Docket section, and `--check` reports drift in either, including a setting left as a placeholder. Both compare against the skill checkout they run from, so keep it at or beyond the commit recorded in `docket/VERSION`; from an older checkout `--check` says the installed copy is newer and asks you to update the checkout first.

## Running the scripts by hand

In a project where docket is installed, the scripts live under `docket/scripts/`, which is the path agents, hooks and CI use:

```bash
bash docket/scripts/check-queues.sh --strict      # validate TODO.md and review/BACKLOG.md
bash docket/scripts/claim-check.sh <slug>         # who already claims this entry?
bash docket/scripts/start-work.sh <queue> <slug>  # branch + worktree for a task
bash docket/scripts/check-pr-markers.sh --pr N    # validate Claims/Resolves markers on a PR
bash docket/scripts/pr-labels.sh --pr N --apply   # label a PR by type, queue, area and priority
bash docket/scripts/review-due.sh                 # is a review due?
bash docket/scripts/cleanup-landed.sh --apply     # remove worktrees and branches for merged PRs
bash docket/scripts/check-links.sh                # relative Markdown links resolve
bash docket/scripts/ci.sh                         # what CI runs: check-queues --strict, check-links, and check-pr-markers on PRs
```

The copies in this repository's `templates/docket/scripts/` are what you edit when developing the skill, and this repository's own `docket/` is regenerated from them with `bash install.sh --self`. They reach a project only through `install.sh`, and `bash ~/.claude/skills/docket/install.sh --check` shows where a project's `docket/` has drifted from them. The scripts act on the repository of the current directory, so run them from inside the project.

## Licence

MIT. See `LICENSE`.
