# Save Inspection Helpers

Read-only Monster Hunter Wilds save interpretation helpers.

## Files

- `Invoke-MHWildsSaveInterpretation.ps1`: runs interpretation against an already-copied save and writes expanded private JSON dumps.
- `Summarize-MHWildsSaveDump.ps1`: reads expanded private JSON dumps and writes compact private summaries/CSVs.
- `mhwilds_interpret_save.rs`: tracked Rust helper source used by the runner.
- `save-inspection.config.example.json`: tracked schema example for `memory/private-save/save-inspection.config.json`.

## Usage

Read `docs/development.md` before running scripts. First copy the live save into `memory/private-save/raw/`; never run this against the live Steam save path.

```powershell
.\tools\save-inspection\Invoke-MHWildsSaveInterpretation.ps1 `
  -SaveCopyPath .\memory\private-save\raw\data001Slot-YYYYMMDD-HHMMSS.bin `
  -SteamId64 <steamid64> `
  -OutDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS

.\tools\save-inspection\Summarize-MHWildsSaveDump.ps1 `
  -DumpDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

Detailed workflow and output notes live in `memory/mh-wilds/save_inspection_workflow.md`.
