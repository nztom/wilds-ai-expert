# Development And Tooling

This document is for maintainers and agents running repo tooling. Assistant behavior, memory lookup rules, and build-advice rules stay in `AGENTS.md`.

## Prerequisites

- PowerShell 7+ (`pwsh`) is required for repo scripts. Run `.ps1` helpers from PowerShell 7, not Windows PowerShell 5.1.
- Git is required, including submodule support for `tools/ree-save-editor/`.
- Rust/Cargo is required for save inspection and low-level `ree-dump` work.
- Network access is required when updating the `ree-save-editor` submodule, fetching Cargo dependencies, or running knowledge-refresh scripts that call external sources such as Kiranico.
- Save inspection needs a copied MH Wilds save under `memory/private-save/raw/` and the matching SteamID64. Never point tooling at the live Steam save path.

## Local Build State

Keep dependency caches and build output inside this repository:

```powershell
New-Item -ItemType Directory -Force .cargo-home, .cargo-target
$env:CARGO_HOME = (Resolve-Path '.\.cargo-home').Path
$env:CARGO_TARGET_DIR = (Resolve-Path '.\.cargo-target').Path
```

Ignored local-only paths:

- `.cargo-home/`
- `.cargo-target/`
- `memory/private-save/`

## Submodule

`tools/ree-save-editor/` tracks upstream `main`, while the parent repo records a pinned submodule commit. Update it before building save tooling:

```powershell
git submodule update --remote -- tools/ree-save-editor
git -C tools\ree-save-editor submodule update --init --recursive
```

## Save Inspection

The normal save workflow is documented in `memory/mh-wilds/save_inspection_workflow.md` and implemented in `tools/save-inspection/`.

Run interpretation against a copied save only:

```powershell
.\tools\save-inspection\Invoke-MHWildsSaveInterpretation.ps1 `
  -SaveCopyPath .\memory\private-save\raw\data001Slot-YYYYMMDD-HHMMSS.bin `
  -SteamId64 <steamid64> `
  -OutDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

Create compact summaries:

```powershell
.\tools\save-inspection\Summarize-MHWildsSaveDump.ps1 `
  -DumpDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

Build `ree-dump` only when low-level validation/decryption is needed:

```powershell
cargo build --manifest-path tools\ree-save-editor\Cargo.toml --release --bin ree-dump
```

The resulting executable is:

```text
.cargo-target\release\ree-dump.exe
```

## Knowledge Refresh

Knowledge-refresh helpers live in `tools/knowledge-refresh/` and update tracked public memory under `memory/mh-wilds/`.

```powershell
.\tools\knowledge-refresh\Update-MHWildsArmorSkillLevels.ps1
```

After running refresh tooling, inspect the diff before committing:

```powershell
git diff -- memory/mh-wilds/armor.csv memory/mh-wilds/armor_normalized.csv
```

## Memory Query Helpers

Read-only helper scripts for common assistant lookups live in `tools/memory-query/`.

```powershell
.\tools\memory-query\Find-MHWildsSkillSource.ps1 -Skill "Weakness Exploit"
.\tools\memory-query\Find-MHWildsMaterial.ps1 -Name "Ajarakan Scale"
.\tools\memory-query\Find-MHWildsOwnedDecoration.ps1 -Skill "Evade Extender"
.\tools\memory-query\Resolve-MHWildsCurrentState.ps1
.\tools\memory-query\Get-MHWildsActiveSaveProfile.ps1
.\tools\memory-query\Get-MHWildsBuildContext.ps1
.\tools\memory-query\Get-MHWildsCurrentSkills.ps1 -Sources
```

Use `Add-MHWildsBuildOverride.ps1` to record user-declared build changes that are not yet reflected in a copied save summary. The agent should resolve the exact equipment slot and decoration names before calling the script. Overrides are written under ignored `memory/private-save/overrides/` and applied by `Get-MHWildsBuildContext.ps1`; generated summary CSVs are not edited.

`Summarize-MHWildsSaveDump.ps1` clears private build override files for matching profiles only when those overrides are older than the dump being summarized. Re-summarizing an old dump keeps newer user-declared overlays intact.

See `tools/memory-query/TODO.md` for the prioritized helper backlog.
