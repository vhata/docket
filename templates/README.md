# Templates: where each file goes

This file is an index of the templates; do not copy it into the target repository.

Copy, then replace every `<placeholder>`. Keep headings and marker vocabulary intact; the bundled scripts parse them.

| Template | Install at | Notes |
| --- | --- | --- |
| `AGENTS.md` | `AGENTS.md` | Not a whole file: the block `install.sh` owns, between `<!-- docket:begin -->` and `<!-- docket:end -->`, plus the settings list it adds under the block on first insert. The installer appends it to an existing AGENTS.md (or creates the file) and rewrites only the block on later runs; everything else in AGENTS.md is the project's. Create `CLAUDE.md` containing the single line `@AGENTS.md`. |
| `CLAUDE.md` | `CLAUDE.md` | The import line, for Claude Code. Other harnesses: symlink to AGENTS.md. |
| `ARCHITECTURE.md` | `ARCHITECTURE.md` | Skeleton; fill from the code, never from guesswork. |
| `docs/DECISIONS.md` | `docs/DECISIONS.md` | Skeleton for dated decisions. |
| `TODO.md` | `TODO.md` | Empty staged queue. |
| `docket/` | `docket/` | Vendored verbatim by `install.sh` at the skill root; never edited in the project. See `docket/README.md`. |
| `docs/QUALITY.md` | `docs/QUALITY.md` | Fill in after the gates exist; current state only. |
| `review/README.md`, `review/BACKLOG.md` | same paths | Empty ledger. |
| `.github/pull_request_template.md` | same path | |
| `.github/workflows/ci.yml` | same path | Replace the setup steps for the language. Also expects `scripts/build.sh` and `scripts/e2e.sh`: add them or remove those steps. |
| `.github/workflows/main-validation.yml` | same path | Replace the extended checks. |
| `scripts/check.sh`, `scripts/setup.sh` | `scripts/` | Skeletons; add the per-check scripts they call. Gate scripts need the exec bit (`chmod +x scripts/*.sh`). |
