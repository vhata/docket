# Architecture

The docket skill has two audiences. An agent using the skill reads `SKILL.md` and `references/`; a project that adopts it receives files from `templates/` through `install.sh`. This repository is also a docket project, so it holds an installed copy of its own machinery next to the source of it.

## Parts

| Path | Role | Reaches a project how |
| --- | --- | --- |
| `SKILL.md` | Entry point for an agent using the skill: quick start, operations, the unit of work, authorisation ladder, red flags. | Never; it stays in the skill. |
| `references/` | The detailed procedures `SKILL.md` points to: setup, queues, parallel work and paired review, reviews, quality gates, PRs and landing. | Never. |
| `templates/docket/` | The vendored machinery: `CONTRACT.md`, the queue and review guides, and the scripts in `scripts/`. | Copied verbatim to `<project>/docket/` by `install.sh`; never edited there. |
| `templates/AGENTS.md` | The `## Docket` section, between `<!-- docket:begin -->` and `<!-- docket:end -->`. | Inserted into or resynced in `<project>/AGENTS.md` by `install.sh`, keeping the project's settings values. |
| Rest of `templates/` | Starting points (queues, review ledger, quality and decisions docs, CI workflows, PR template, `scripts/` skeletons), indexed in `templates/README.md`. | Copied and edited by hand during setup; `install.sh` does not sync them. |
| `install.sh` | Install, resync and `--check` drift audit; `--self` for this repository. | Run from the skill checkout against a project. |
| `tests/` | `scripts.sh` drives the vendored scripts in disposable repositories with a fake `gh`; `install.sh` drives the installer against scratch projects and clones of this checkout. | Never. |
| `agents/openai.yaml` | Codex display metadata. | Never. |
| `docket/`, `AGENTS.md`, `TODO.md`, `review/`, `docs/`, `scripts/`, `.githooks/`, `.github/` | This repository's own docket installation and gates. | Never; they describe this repository. |

## Isolation for concurrent work

- Each task gets its own git worktree, and `bash install.sh --self` runs from inside the worktree it updates; the installer refuses to target a sibling worktree.
- The test suites build every repository they need under `mktemp -d` and never touch this checkout's refs or config, so suites in different worktrees run at once without interfering.
- `core.hooksPath` is shared clone configuration: `scripts/setup.sh` sets it once for every worktree, and a worktree on a branch without `.githooks/` simply has no hooks.

## Invariants

- The vendored scripts run under bash 3.2 and need only git, plus `gh` where pull requests are involved. They act on the repository of the current directory. CI runs both fixture suites under macOS `/bin/bash` as well as Linux bash.
- `docket/` in any project, this one included, is byte-identical to `templates/docket/` at the commit its `VERSION` names (`self` here). Project rule text lives in the `AGENTS.md` settings or `docs/QUALITY.md`, never in `docket/`.
- The scripts parse the documents they validate. Marker vocabulary, queue entry format, review index columns and the `## Review inputs` heading are interfaces: a change to one changes the guide that describes it, the template that carries it and the script that reads it in the same PR, with a fixture.
- Templates are written for an unknown project. They name no repository, commit or file from the projects the skill was distilled from, and none from this one.
- Every rule has one home. `SKILL.md` and `references/` explain and link; `templates/docket/CONTRACT.md` is the rule text a project's agents follow without the skill.
- The installer writes only `docket/`, the Docket section of `AGENTS.md`, an `@AGENTS.md` line in an existing regular `CLAUDE.md`, and `.git/info/exclude`. It never deletes files and refuses to install into this repository unless `--self` is given.
