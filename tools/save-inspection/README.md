# Save Inspection Helpers

These helpers support read-only Monster Hunter Wilds save interpretation without committing private save data or modifying the `ree-save-editor` submodule permanently.

## Files

- `mhwilds_interpret_save.rs`: tracked Rust helper source that is temporarily staged into the `ree-save-editor` Cargo workspace.
- `Invoke-MHWildsSaveInterpretation.ps1`: copies the helper into the submodule, runs it against an already-copied save, then removes the temporary source.

## Usage

First copy the live save into `memory/private-save/raw/`; never run this against the live Steam save path.

```powershell
.\tools\save-inspection\Invoke-MHWildsSaveInterpretation.ps1 `
  -SaveCopyPath .\memory\private-save\raw\data001Slot-YYYYMMDD-HHMMSS.bin `
  -SteamId64 <steamid64> `
  -OutDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

The script updates the submodule before building, uses repo-local Cargo cache/output directories, and writes `interpreted-summary.json` to the private output directory.
