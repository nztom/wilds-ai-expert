# Save Inspection Helpers

These helpers support read-only Monster Hunter Wilds save interpretation without committing private save data or modifying the `ree-save-editor` submodule permanently.

## Files

- `mhwilds_interpret_save.rs`: tracked Rust helper source that is temporarily staged into the `ree-save-editor` Cargo workspace.
- `Invoke-MHWildsSaveInterpretation.ps1`: updates the submodule, copies the helper into the submodule, runs it against an already-copied save, writes expanded JSON dumps, then removes the temporary source.
- `Summarize-MHWildsSaveDump.ps1`: reads the expanded private JSON dump and writes compact private summaries for inventory, owned decorations, monsters, endemic life, fishing, progression, camps, deliveries, and equipment.
- `save-inspection.config.example.json`: tracked schema example for the ignored active-save profile config at `memory/private-save/save-inspection.config.json`.

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

After interpretation, create the smaller working summaries:

```powershell
.\tools\save-inspection\Summarize-MHWildsSaveDump.ps1 `
  -DumpDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

By default, summaries are written under `memory\private-save\summaries\<copy-id>\`. The script resolves item, monster, endemic-life, fish, and decoration names from local Wilds assets in the `ree-save-editor` submodule, then enriches decoration rows from the local normalized decoration CSVs. The generated CSV files are the friendliest source for analysis. Prefer the `*-summary.csv` outputs and avoid reading the JSON summary files unless you need lower-level debugging details.

After creating or switching a copied save, update the private config:

```text
memory/private-save/save-inspection.config.json
```

Use one profile per copied save and character slot. `active_profile_id` selects the profile future sessions should use by default; each profile binds a `save_copy_path`, `dump_dir`, `summary_dir`, `steam_id64`, and zero-based `active_character_slot_index`. Do not reuse a dump or summary folder across profiles.

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
| `slot{N}-delivery-bounty.json` | Delivery bounty state for slot N — `_DeliveryBounty` expanded to depth 5 with no array truncation | Per slot |
| `slot{N}-camp.json` | Camp unlock/placement state for slot N — `_Camp` expanded to depth 3 with no array truncation | Per slot |

Slot index N is zero-based (slot 0 = first character slot).

## Helper Internals

The Rust source has two function families:

- **Summary family** (`class_to_named_json`, `named_value_json`, `array_to_named_json`): used for `interpreted-summary.json`. Arrays are truncated to first 10 elements (`"first_values"` key, `"truncated": true` when longer).
- **Full family** (`class_to_json_full`, `named_value_full_json`, `array_to_json_full`): used for targeted passes. Arrays are never truncated (`"values"` key, all elements).

In both families, scalar values (strings, integers, booleans, enums) are always emitted as their actual value regardless of depth. The depth limit only gates recursion into `Class` and `Array` nodes; when exceeded, those nodes collapse to a shape-only preview (`kind`, `len`, `hash`, `num_fields`).

To adjust extraction depth, edit the `max_depth` literal in the relevant `extract_*` function in `mhwilds_interpret_save.rs`.

## Summary Pass

`Summarize-MHWildsSaveDump.ps1` is the preferred layer for normal questions. It keeps private data ignored, but converts the expanded JSON into smaller files that are easier to inspect directly. It removes old `.json` and `.csv` outputs from the selected summary directory before writing fresh files.

| File | Content |
|---|---|
| `index.json` | Source dump path, output path, generation time, and generated file list |
| `profile-summary.json` | Slot activity and visible profile/presence fields from `interpreted-summary.json` |
| `profile-summary.csv` | CSV form of slot activity and visible profile/presence fields |
| `slot{N}-inventory-summary.json` | Nonzero item-box entries with item IDs and quantities |
| `slot{N}-inventory-summary.csv` | CSV form of inventory entries, with item enum/name resolved where possible |
| `slot{N}-decorations-summary.json` | Loose owned decorations from `_Equip._AccessoryBox`, with type, slot level, skill details, and quantity |
| `slot{N}-decorations-summary.csv` | CSV form of owned decorations for quick build queries |
| `slot{N}-decoration-skills-summary.csv` | Skill-oriented rollup of owned decoration quantities and total known skill levels |
| `slot{N}-fishing-summary.json` | Fish records with observed state or capture counts |
| `slot{N}-fishing-summary.csv` | CSV form of fish records, with fish enum/name resolved where possible |
| `slot{N}-monster-report-summary.json` | Observed boss, small-monster, endemic, and fish report rows |
| `slot{N}-monster-report-summary.csv` | CSV form of report rows, with monster/endemic/fish enum/name resolved where possible |
| `slot{N}-endemic-summary.json` | Captured endemic entries grouped by resolved endemic ID |
| `slot{N}-endemic-summary.csv` | CSV form of grouped endemic captures, with endemic enum/name resolved where possible |
| `slot{N}-story-summary.json` | Story scalar values and nonzero arrays/bitsets |
| `slot{N}-mission-summary.json` | Mission scalar values and nonzero arrays/bitsets |
| `slot{N}-quest-record-summary.json` | Quest-record scalar values and nonzero arrays |
| `slot{N}-delivery-bounty-summary.json` | Delivery/bounty scalar values and nonzero arrays |
| `slot{N}-camp-summary.json` | Camp scalar values and nonzero arrays |
| `slot{N}-equip-summary.json` | Equipment-box entries reduced to nonzero scalar fields |

Use the expanded dump files when the summary omits a field needed for a new interpretation rule.
Empty slot CSVs are intentionally written as tiny blank files when a slot has no rows for that table.

Name resolution path:

- Items: `enumsmhwilds.json` maps fixed item IDs to enum keys; `enums_mappings_mhwilds.json` maps those keys to message GUIDs; `combined_msgs.json` provides the English display string.
- Monsters, fish, and endemic life: `enumsmhwilds.json` maps fixed enemy IDs to enum keys; `combined_msgs.json` provides `EnemyText_NAME_<enum>` English display strings.
- Decorations: `_Equip._AccessoryBox` stores decoration IDs and quantities; `enumsmhwilds.json` plus `combined_msgs.json` resolve names, and local `decorations_*_normalized.csv` files add slot type, slot level, rarity, skills, and skill levels.
