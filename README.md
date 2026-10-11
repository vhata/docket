# docket

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
| `agents/openai.yaml` | Display metadata so the skill shows up in Codex. |

## Installing the skill

Copy or clone this directory into your agent's skills directory so that `SKILL.md` sits at the top of it:

```bash
# Claude Code
git clone git@github.com:vhata/docket.git ~/.claude/skills/docket

# Codex
git clone git@github.com:vhata/docket.git ~/.codex/skills/docket
```

Restart the agent, or start a new session, and the skill is available as `docket`.

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

From inside the project, run `bash ~/.claude/skills/docket/install.sh` (or let the agent do it as part of "Use docket to set up this project"). It copies `templates/docket/` to `docket/` at the project root, writes `docket/VERSION`, excludes the local `.docket/` working directory from git, and adds a `## Docket` section, delimited by `<!-- docket:begin -->` and `<!-- docket:end -->`, to the project's `AGENTS.md` (creating the file if there is none). Fill in the settings bullets in that section (queue areas, concurrency cap, merge delegation, optional pieces in force, environment rules); later runs rewrite the section's text, keep the settings by name and re-add any that went missing. Everything outside the markers is the project's and the installer never touches it. If the project has a `CLAUDE.md`, the installer appends the line `@AGENTS.md` when it is missing and leaves the rest of that file alone; it never creates or replaces `CLAUDE.md`. Rerun the same command whenever the skill changes; it resyncs `docket/` and the Docket section, and `--check` reports drift in either, including a setting left as a placeholder.

## Running the scripts by hand

In a project where docket is installed, the scripts live under `docket/scripts/`, which is the path agents, hooks and CI use:

```bash
bash docket/scripts/check-queues.sh --strict      # validate TODO.md and review/BACKLOG.md
bash docket/scripts/claim-check.sh <slug>         # who already claims this entry?
bash docket/scripts/start-work.sh <queue> <slug>  # branch + worktree for a task
bash docket/scripts/check-pr-markers.sh --pr N    # validate Claims/Resolves markers on a PR
bash docket/scripts/review-due.sh                 # is a review due?
bash docket/scripts/cleanup-landed.sh --apply     # remove worktrees and branches for merged PRs
bash docket/scripts/check-links.sh                # relative Markdown links resolve
bash docket/scripts/ci.sh                         # what CI runs: check-queues --strict, check-links, and check-pr-markers on PRs
```

The copies in this repository's `templates/docket/scripts/` are what you edit when developing the skill; they reach a project only through `install.sh`, and `bash ~/.claude/skills/docket/install.sh --check` shows where a project's `docket/` has drifted from them. The scripts act on the repository of the current directory, so run them from inside the project.

## Licence

MIT. See `LICENSE`.
