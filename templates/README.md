# Templates: where each file goes

This file is an index of the templates; do not copy it into the target repository.

Copy, then replace every `<placeholder>`. Keep headings and marker vocabulary intact; the bundled scripts parse them.

| Template | Install at | Notes |
| --- | --- | --- |
| `AGENTS.md` | `AGENTS.md` | Not a whole file: the `## Docket` section `install.sh` owns, between `<!-- docket:begin -->` and `<!-- docket:end -->`. The installer inserts it into an existing AGENTS.md after the leading heading and intro paragraph, before the first `## ` heading (at the end when there is none), or creates the file; moving the section elsewhere in the file is safe, the installer finds it by its markers. On later runs it rewrites the heading and text, keeps each settings bullet by its name, re-adds a missing one as a placeholder, and keeps extra bullets; `--check` fails while a setting is missing or still a placeholder. Everything outside the markers is the project's and is never touched. If the project has a `CLAUDE.md`, the installer appends the line `@AGENTS.md` when it is missing and changes nothing else in it. A `CLAUDE.md` that is a symlink to `AGENTS.md` already counts as the import and is left untouched. |
| `ARCHITECTURE.md` | `ARCHITECTURE.md` | Skeleton; fill from the code, never from guesswork. |
| `docs/DECISIONS.md` | `docs/DECISIONS.md` | Skeleton for dated decisions. |
| `TODO.md` | `TODO.md` | Empty staged queue. |
| `docket/` | `docket/` | Vendored verbatim by `install.sh` at the skill root; never edited in the project. See `docket/README.md`. |
| `docs/QUALITY.md` | `docs/QUALITY.md` | Fill in after the gates exist; current state only. Keep the `## Review inputs` heading: the vendored review guide links it and the installer warns when it is missing. |
| `review/README.md`, `review/BACKLOG.md` | same paths | Empty ledger. |
| `.github/pull_request_template.md` | same path | |
| `.github/workflows/ci.yml` | same path | Replace the setup steps for the language. Also expects `scripts/build.sh` and `scripts/e2e.sh`: add them or remove those steps. |
| `.github/workflows/main-validation.yml` | same path | Replace the extended checks. |
| `scripts/check.sh`, `scripts/setup.sh` | `scripts/` | Skeletons; add the per-check scripts they call. Gate scripts need the exec bit (`chmod +x scripts/*.sh`). |
