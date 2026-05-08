# Monster Hunter Wilds AI Expert Memory

Local knowledge base and working context for a Monster Hunter Wilds assistant. It stores buildcrafting data, current meta notes, material routes, monster references, fishing/endemic-life notes, side quest unlocks, and safety rules for optional read-only save inspection.

## Freshness

- Game memory last broadly refreshed: 2026-05-08.
- Last patch/content window represented: base-game Title Update 4 plus Ver. 1.041 / 1.041.01.
- Ver. 1.041.00.00 was released February 18, 2026 UTC.
- Verify current web sources before making strong claims about newer patches, event rotations, expansion content, or anything contradicted by in-game evidence.

## Repository Layout

- `AGENTS.md`: operating instructions for the assistant, including build-advice principles and strict private-save safety rules.
- `memory/mh-wilds/`: public game memory. Start with `memory/mh-wilds/README.md` for the detailed file map.
- `memory/private-save/`: ignored local-only folder for user-specific save notes, copied raw saves, expanded JSON dumps, and compact resolved summaries/CSVs.
- `memory/private-save/save-inspection.config.json`: ignored active-save profile config. It records which copied save, dump folder, summary folder, SteamID, and zero-based character slot are currently active.
- `tools/ree-save-editor/`: submodule for RE Engine save tooling. Default use is read-only copied-save inspection.
- `tools/knowledge-refresh/`: public knowledge-base refresh helpers that update tracked data under `memory/mh-wilds/`.
- `tools/save-inspection/`: repo-owned save interpretation helpers. The runner temporarily stages helper source into the submodule, writes expanded JSON dumps under `memory/private-save/dumps/`, removes the temporary submodule file, and the summarizer writes resolved JSON/CSV summaries under `memory/private-save/summaries/`.
- `docs/development.md`: developer and tooling prerequisites, including PowerShell 7, Git submodules, Rust/Cargo, save-inspection builds, and knowledge-refresh scripts.

## Development Docs

See `docs/development.md` before running repo scripts or building save-inspection tooling.

## Public Memory Contents

The public memory currently includes:

- Skills, decorations, armor, talismans, and material CSVs.
- Buildcrafting heuristics and current base-game / TU4 meta notes.
- Gogma Artian weapon notes.
- Material and decoration farming notes.
- Fishing and broader endemic-life locations.
- Monster quick reference notes.
- Side quest walkthrough notes and unlock tables for mantles, material gatherers, Palico skills, charms, hunting assistants, and Great Hunts.

## Save Tooling Safety

Live saves are out of bounds. The workflow is:

1. Copy a save into ignored repo-local storage, such as `memory/private-save/raw/`.
2. Run read-only interpretation tooling against that copy.
3. Store expanded JSON dumps under `memory/private-save/dumps/`.
4. Store compact derived summaries and human-readable CSVs under `memory/private-save/summaries/`.

Do not write to Steam libraries, Steam userdata, Steam Cloud directories, game install directories, or Monster Hunter Wilds save paths. In particular, never write to app ID `2246340` save paths such as `remote/win64_save`, `data001Slot.bin`, or `data00-1.bin`.

## Save Inspection

The preferred workflow is documented in `memory/mh-wilds/save_inspection_workflow.md` and implemented by the scripts in `tools/save-inspection/`:

```powershell
.\tools\save-inspection\Invoke-MHWildsSaveInterpretation.ps1 `
  -SaveCopyPath .\memory\private-save\raw\data001Slot-YYYYMMDD-HHMMSS.bin `
  -SteamId64 <steamid64> `
  -OutDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS

.\tools\save-inspection\Summarize-MHWildsSaveDump.ps1 `
  -DumpDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

`Summarize-MHWildsSaveDump.ps1` resolves item, monster, endemic-life, fish, and decoration names from local Wilds assets, enriches owned decoration rows with local skill/slot data, and writes CSVs for normal inspection.

When multiple copied saves exist, check `memory/private-save/save-inspection.config.json` before reading private output. Switch `active_profile_id` only when the user asks to use a different copied save or character slot. The tracked schema example is `tools/save-inspection/save-inspection.config.example.json`.

`ree-dump` remains useful as a lower-level validation/decryption tool. Always update the submodule before building:

See `docs/development.md` for submodule, Cargo, and `ree-dump` build commands.

## Git Notes

- `.cargo-home/`, `.cargo-target/`, and `memory/private-save/` are ignored. See `docs/development.md` for tooling details.
