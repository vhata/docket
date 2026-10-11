# <Project>: agent contract

<One or two sentences on what the project is and what it is for. If it is a personal project with no deliverable, say so; priorities follow the motivation.>

## Docket

This project is run with docket. Read [docket/CONTRACT.md](docket/CONTRACT.md) before any work; it is the authoritative workflow and this section records only this project's settings.

- Queue areas: <`[AREA]`, `[AREA]`, `[TOOLING]`, `[DOCS]`>.
- Concurrency cap: <N> heavy builds or runs at once.
- Merging and releases: <the user merges unless delegated in the turn | standing delegation>.
- Optional pieces in force: <review ledger | roadmap queue | none>.
- Environment: <rules such as "the user runs the dev server">.

## Where to find what

- `README.md`: build, run, scripts.
- `ARCHITECTURE.md`: structure, shared interfaces, invariants, per-worktree isolation.
- `docs/DECISIONS.md`: non-obvious choices and their trade-offs. Read before changing a mechanism that looks odd.
- `docs/QUALITY.md`: what quality means here, the gates, and the review inputs.
- `TODO.md`, `review/`: the deferred-work queue and the review ledger.
- <Other authoritative documents: roadmap, spec, acceptance, design notes.>

Keep this file short. Add a line only when it prevents a concrete recurring mistake; details go in the guide that owns them.
