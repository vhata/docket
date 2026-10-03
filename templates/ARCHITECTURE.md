# Architecture

What the structure is now, the boundaries parallel work must respect, and the invariants reviews check. Plans and unbuilt designs live elsewhere (<roadmap or spec>); this file describes the code as it is.

## Layout

<Directories or packages and what each owns, one line each.>

## Shared interfaces

<The contracts more than one component depends on: types, schemas, protocol messages, CLI surface, storage boundary. Changes here land before dependent work starts, or are stacked explicitly.>

## Invariants

<Properties the code must keep, derived from this project (e.g. "no clock or randomness in the simulation layer", "every player view is filtered before rendering", "the engine never imports the UI"). Codebase reviews check changed code against this list; add an entry when the same class of problem appears twice.>

## Isolation for concurrent work

Each worktree owns its mutable state: <virtualenv / node_modules / build directory>, caches under `.cache/`, test databases and evidence under `.runtime/` or `test-results/`, dev-server ports from <range>. All of these are ignored by git. Scripts resolve tools relative to the worktree they run in.

## Where to look first

<Two or three entry points a new agent should read before changing anything significant.>
