# Memory Query Helpers

Small read-only helpers for common local lookups. Use these from the repo root with PowerShell 7.

```powershell
.\tools\memory-query\Find-MHWildsSkillSource.ps1 -Skill "Weakness Exploit"
.\tools\memory-query\Find-MHWildsSkillSource.ps1 -Skill "Exploit" -Contains
.\tools\memory-query\Find-MHWildsMaterial.ps1 -Name "Ajarakan Scale"
.\tools\memory-query\Resolve-MHWildsCurrentState.ps1
.\tools\memory-query\Get-MHWildsActiveSaveProfile.ps1
.\tools\memory-query\Get-MHWildsBuildContext.ps1
```

These scripts only read repo-local CSVs or ignored private config. They do not inspect live saves.

## Current State Resolution

Use `Resolve-MHWildsCurrentState.ps1` as the first stop for save-aware answers. It:

1. Reads the active profile from `memory/private-save/save-inspection.config.json`.
2. Reads summary CSVs from that profile's `summary_dir`.
3. Applies ignored private build overrides from `memory/private-save/overrides/<profile_id>.json` when present.
4. Returns the resolved current state without editing generated summaries or live saves.

## Private Build Overrides

When the user reports a current-build change that is not yet reflected in the copied save summary, record it as an ignored private overlay:

```powershell
.\tools\memory-query\Add-MHWildsBuildOverride.ps1 `
  -EquipmentSlot arms `
  -FromDecoration "Mighty Jewel [2]" `
  -ToDecoration "Jumping Jewel [2]" `
  -Note "User said they swapped one Mighty Jewel for Jumping Jewel."
```

`Get-MHWildsBuildContext.ps1` applies these overlays at read time. Generated save summaries are left unchanged so they still reflect the copied save.

For natural-language user notes, the agent should resolve the exact equipment slot and decoration names, then call `Add-MHWildsBuildOverride.ps1` explicitly.

When `Summarize-MHWildsSaveDump.ps1` generates a summary, it clears only private build overrides that are older than the dump being summarized. Re-summarizing an old dump keeps newer user-declared overlays intact; summarizing a newly dumped save clears stale overlays after the copied save catches up.
