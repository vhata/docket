# Templates: where each file goes

Copy, then replace every `<placeholder>`. Keep headings and marker vocabulary intact; the bundled scripts parse them.

| Template | Install at | Notes |
| --- | --- | --- |
| `AGENTS.md` | `AGENTS.md` | Contract. Create `CLAUDE.md` containing the single line `@AGENTS.md`. |
| `CLAUDE.md` | `CLAUDE.md` | The import line, for Claude Code. Other harnesses: symlink to AGENTS.md. |
| `ARCHITECTURE.md` | `ARCHITECTURE.md` | Skeleton; fill from the code, never from guesswork. |
| `docs/DECISIONS.md` | `docs/DECISIONS.md` | Skeleton for dated decisions. |
| `TODO.md` | `TODO.md` | Empty staged queue. |
| `docs/TODO_GUIDE.md` | `docs/TODO_GUIDE.md` | Queue rules. Edit the area list. |
| `docs/CODE_REVIEW_GUIDE.md` | `docs/CODE_REVIEW_GUIDE.md` | Review rules, including the snapshot skeleton. Edit the baseline commands. |
| `docs/QUALITY.md` | `docs/QUALITY.md` | Fill in after the gates exist; current state only. |
| `review/README.md`, `review/BACKLOG.md` | same paths | Empty ledger. |
| `.github/pull_request_template.md` | same path | |
| `.github/workflows/ci.yml` | same path | Replace the setup steps for the language. |
| `.github/workflows/main-validation.yml` | same path | Replace the extended checks. |
| `scripts/check.sh`, `scripts/setup.sh` | `scripts/` | Skeletons; add the per-check scripts they call. |
| `../scripts/*.sh` (the skill's tools) | `scripts/workflow/` | So hooks, CI and skill-less agents can run them. |
