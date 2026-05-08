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

The script updates the submodule before building, uses repo-local Cargo cache/output directories, and writes all output files to the private output directory.
Before each run, the script removes its known generated files from the selected output directory so stale slot files cannot survive from an older dump.

## Output Files

The helper writes one summary file plus targeted files per character slot. Targeted files are written for each slot where the corresponding save path resolves.

| File | Content | Always written |
|---|---|---|
| `interpreted-summary.json` | Structural overview: top-level class walk (max_depth=2, arrays truncated to 10), per-slot summaries with basic data and field-presence flags | Yes |
| `slot{N}-equip-box.json` | Full equipment box for slot N — all items in `_Equip._EquipBox`, expanded to depth 4 (reaches decoration slots on each piece) | Per slot |
| `slot{N}-item-box.json` | Full item box for slot N — all entries in `_Item._BoxItem`, expanded to depth 2 (item ID and count) | Per slot |
| `slot{N}-mission.json` | Full mission/quest flags for slot N — entire `_Mission` class expanded to depth 3 with no array truncation | Per slot |
| `slot{N}-endemic-captures.json` | Full endemic-life capture state for slot N — `_Animal` expanded to depth 3 with no array truncation | Per slot |
| `slot{N}-fish-captures.json` | Full fish capture/report state for slot N — `_EnemyReport._AnimalFishing` array expanded to depth 3 with no array truncation | Per slot |
| `slot{N}-monster-report.json` | Full monster report state for slot N — `_EnemyReport` expanded to depth 3 with no array truncation | Per slot |
| `slot{N}-story.json` | Story progression state for slot N — `_Story` expanded to depth 3 with no array truncation | Per slot |
| `slot{N}-quest-record.json` | Quest record state for slot N — `_QuestRecord` expanded to depth 3 with no array truncation | Per slot |
| `slot{N}-delivery-bounty.json` | Delivery bounty state for slot N — `_DeliveryBounty` expanded to depth 3 with no array truncation | Per slot |
| `slot{N}-camp.json` | Camp unlock/placement state for slot N — `_Camp` expanded to depth 3 with no array truncation | Per slot |

Slot index N is zero-based (slot 0 = first character slot).

## Helper Internals

The Rust source has two function families:

- **Summary family** (`class_to_named_json`, `named_value_json`, `array_to_named_json`): used for `interpreted-summary.json`. Arrays are truncated to first 10 elements (`"first_values"` key, `"truncated": true` when longer).
- **Full family** (`class_to_json_full`, `named_value_full_json`, `array_to_json_full`): used for targeted passes. Arrays are never truncated (`"values"` key, all elements).

In both families, scalar values (strings, integers, booleans, enums) are always emitted as their actual value regardless of depth. The depth limit only gates recursion into `Class` and `Array` nodes; when exceeded, those nodes collapse to a shape-only preview (`kind`, `len`, `hash`, `num_fields`).

To adjust extraction depth, edit the `max_depth` literal in the relevant `extract_*` function in `mhwilds_interpret_save.rs`.
