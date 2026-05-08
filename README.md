# Monster Hunter Wilds AI Expert Memory

Local knowledge base and working context for a Monster Hunter Wilds assistant.

## Freshness

- Game memory last broadly refreshed: 2026-05-08.
- Last patch/content window represented: base-game Title Update 4 plus Ver. 1.041 / 1.041.01.
- Ver. 1.041.00.00 was released February 18, 2026 UTC.
- Verify current web sources before making strong claims about newer patches, event rotations, expansion content, or anything contradicted by in-game evidence.

## Start Here

- `AGENTS.md`: assistant operating rules, research flow, and safety boundaries.
- `memory/mh-wilds/README.md`: public memory map and data caveats.
- `docs/development.md`: prerequisites and commands for repo tooling.
- `memory/mh-wilds/save_inspection_workflow.md`: detailed read-only save-inspection workflow.

## Safety

Live saves are out of bounds. Copy saves into ignored repo-local storage such as `memory/private-save/raw/`, then run tooling only against the copy.

Never write to Steam libraries, Steam userdata, Steam Cloud directories, game install directories, or Monster Hunter Wilds save paths for app ID `2246340`.

## Private Data

`memory/private-save/`, `memory/user-reports/`, `.cargo-home/`, and `.cargo-target/` are ignored local-only paths. Do not commit private save facts, copied saves, dumps, summaries, user-reported gameplay observations, or local build caches.
