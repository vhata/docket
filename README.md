# repo-workflow

An agent skill for running a repository with many coding agents working on it at once, without them tripping over each other.

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
| `scripts/` | Portable bash tools (bash 3.2, git, and `gh` where PRs are involved): queue validation, PR marker checks, claim checks, branch and worktree creation, review drift, and post-merge cleanup. |
| `templates/` | Files the skill installs into a repository: `AGENTS.md`, `CLAUDE.md`, queue and review guides, CI workflows, a PR template, and `scripts/check.sh` and `scripts/setup.sh` skeletons. See `templates/README.md` for where each one goes. |
| `agents/openai.yaml` | Display metadata so the skill shows up in Codex. |

## Installing the skill

Copy or clone this directory into your agent's skills directory so that `SKILL.md` sits at the top of it:

```bash
# Claude Code
git clone git@github.com:vhata/repo-workflow.git ~/.claude/skills/repo-workflow

# Codex
git clone git@github.com:vhata/repo-workflow.git ~/.codex/skills/repo-workflow
```

Restart the agent, or start a new session, and the skill is available as `repo-workflow`.

## Using it

You do not need to know the internals. Open a session in the repository you want to work on and say one of these:

| Say | What happens |
| --- | --- |
| "Use repo-workflow to set up this repo" | The agent inspects the repository. A repository with no workflow gets the contract, queues, scripts, CI and review ledger installed on a branch. An empty repository gets initialised first. |
| "Use repo-workflow to audit this repo" | Same inspection, but against an existing workflow. Drift between what the docs say, what CI enforces, and what the records prove becomes a list of findings and repairs. |
| "Use repo-workflow to do a full review" / "an incremental review" | A codebase review landed as its own PR, recorded in the review ledger. |
| "Use repo-workflow to fan out the ready TODOs" / "run overnight" | The agent acts as coordinator: one writer and one reviewer per ready queue entry, each in its own worktree, with the autonomy mode stated up front. |
| "Use repo-workflow to triage the queues" | Sort new entries into stages and priorities, split batches, reconcile stale claims. |
| "Use repo-workflow to clean up after the merged PRs" | Remove worktrees and branches whose PRs have landed. |

Branch protection settings are proposed, never applied; you apply them yourself on the hosting side.

Once a repository has been set up, ordinary single-task work does not need this skill. The installed `AGENTS.md` and guides carry the rules, and the scripts are copied into `scripts/workflow/` so agents without the skill run the same tools. Just say "grab a TODO" or describe the task.

## Running the scripts by hand

In a repository where the workflow is installed, the scripts live under `scripts/workflow/`, which is the path agents, hooks and CI use:

```bash
bash scripts/workflow/check-queues.sh --strict      # validate TODO.md and review/BACKLOG.md
bash scripts/workflow/claim-check.sh <slug>         # who already claims this entry?
bash scripts/workflow/start-work.sh <queue> <slug>  # branch + worktree for a task
bash scripts/workflow/check-pr-markers.sh --pr N    # validate Claims/Resolves markers on a PR
bash scripts/workflow/review-due.sh                 # is a review due?
bash scripts/workflow/cleanup-landed.sh --apply     # remove worktrees and branches for merged PRs
bash scripts/workflow/check-links.sh                # relative Markdown links resolve
```

The copies in this repository's `scripts/` are the source for that install step and are what you edit when developing the skill. When one has to run against a repository that does not have the installed copies yet (the install itself, or an audit), run it from inside that repository by its path in the skill directory, for example `bash ~/.claude/skills/repo-workflow/scripts/check-queues.sh --strict`. The scripts act on the repository of the current directory, so do not `cd` into the skill directory to run them.

## Licence

MIT. See `LICENSE`.
