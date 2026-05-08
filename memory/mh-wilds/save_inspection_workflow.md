# MH Wilds Save Inspection Workflow

Last updated: 2026-05-08

This note documents the read-only workflow for interpreting a Monster Hunter Wilds save with the `tools/ree-save-editor/` submodule. Keep user-specific copied saves, expanded JSON dumps, compact summaries, CSVs, and interpreted outputs under ignored `memory/private-save/`; keep only general process notes here.

## Safety Rules

- Never operate on the live Steam save directly.
- Never write to Steam userdata, Steam Cloud, a Steam library, or the MH Wilds app ID `2246340` save paths.
- First copy the live save into `memory/private-save/raw/`, then read only that copy.
- Write all dumps under `memory/private-save/dumps/`.
- Write compact derived summaries under `memory/private-save/summaries/`.
- Track the active copied save and zero-based character slot in ignored `memory/private-save/save-inspection.config.json`.
- Do not run account transfer, slot transfer, resign, repack, save, or editor write operations unless the user explicitly asks and reconfirms the destination path.
- Keep Cargo cache and build output inside this repo:

```powershell
$env:CARGO_HOME = (Resolve-Path .cargo-home).Path
$env:CARGO_TARGET_DIR = (Resolve-Path .cargo-target).Path
```

## Inputs

MH Wilds character save:

```text
Steam\userdata\<steam-account-id>\2246340\remote\win64_save\data001Slot.bin
```

The Steam account folder name is the lower 32-bit account ID. For SteamID64, use:

```text
steamid64 = 76561197960265728 + steam-account-id
```

`data001Slot.bin` contains character-slot data: hunter basics, item storage, equipment, charms, Artian parts, monster/endemic/fishing records, and many progression flags.

## Active Save Profile Config

Use this ignored config to avoid blending data from multiple copied saves:

```text
memory/private-save/save-inspection.config.json
```

The tracked schema example is:

```text
tools/save-inspection/save-inspection.config.example.json
```

Each profile binds one copied raw save to its matching dump folder, summary folder, SteamID, and zero-based character slot index:

- `active_profile_id`: the profile future sessions should use by default.
- `profile_id`: stable label for one copied save plus one character slot, for example `data001Slot-YYYYMMDD-HHMMSS-slot0`.
- `copy_id`: folder/file stem shared by raw copy, dump dir, and summary dir.
- `save_copy_path`: copied save under `memory/private-save/raw/`.
- `dump_dir`: expanded JSON output for this copy.
- `summary_dir`: compact resolved JSON/CSV output for this copy.
- `active_character_slot_index`: zero-based in-game character slot to answer from.

When the user asks to switch saves or character slots, add or select a different profile and update `active_profile_id`. Do not reuse a dump or summary folder across profiles, and do not combine profile data unless the user explicitly asks for a comparison.

## Optional Low-Level Validation

`ree-dump` is useful for low-level validation/decryption, but the normal workflow uses the tracked helper runner instead. To build `ree-dump`, update/build the submodule tooling first, following the repo rules:

```powershell
git -C tools\ree-save-editor submodule update --init --recursive
git -C tools\ree-save-editor pull --ff-only
$env:CARGO_HOME = (Resolve-Path .cargo-home).Path
$env:CARGO_TARGET_DIR = (Resolve-Path .cargo-target).Path
cargo build --manifest-path tools\ree-save-editor\Cargo.toml --bin ree-dump --release --locked
```

Copy the save into the private folder:

```powershell
New-Item -ItemType Directory -Force memory\private-save\raw
Copy-Item -LiteralPath '<live data001Slot.bin path>' -Destination 'memory\private-save\raw\data001Slot-YYYYMMDD-HHMMSS.bin'
```

Run `ree-dump` against the copied save when you only need validation/decryption checks:

```powershell
Push-Location tools\ree-save-editor
..\..\.cargo-target\release\ree-dump.exe `
  -f ..\..\memory\private-save\raw\data001Slot-YYYYMMDD-HHMMSS.bin `
  --steamid <steamid64> `
  -o ..\..\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
Pop-Location
```

Expected success signs:

- `[Key/IV check] block N: passed`
- `[Checksum] block N: passed`

Current caveat: `ree-dump --save-file` appears unused in the CLI path, and the `.bin` save JSON writer in `src/file/mod.rs` is commented out. Use `-f` to validate/decrypt only, then use the helper runner below for structured interpretation.

## Interpreting Hashes

The raw save has class/field hashes. To turn those into names, load the Wilds RSZ type map:

```text
tools/ree-save-editor/assets/mhwilds/rszmhwilds.json
tools/ree-save-editor/assets/mhwilds/enumsmhwilds.json
```

Important mapping detail:

- `TypeMap::get_by_hash(hash)` resolves many type hashes.
- Some save `Class.hash` values match a `TypeInfo.crc` instead, so build a secondary `crc -> TypeInfo` lookup.
- Field names can be resolved from the parent class `TypeInfo.fields` by field hash.

Useful known paths in `data001Slot.bin`:

- `_Data`: array of 3 character slots.
- `_Data[slot]->_BasicData`: names and basic profile data.
- `_Data[slot]->_Item->_PouchItem`: item pouch.
- `_Data[slot]->_Item->_PouchShell`: ammo pouch.
- `_Data[slot]->_Item->_BoxItem`: item box.
- `_Data[slot]->_Equip->_EquipBox`: equipment storage.
- `_Data[slot]->_Equip->_ArtianPartsBox`: Artian parts.
- `_Data[slot]->_Story`: story progression.
- `_Data[slot]->_Mission`: mission flags.
- `_Data[slot]->_QuestRecord`: quest record state.
- `_Data[slot]->_DeliveryBounty`: delivery bounty state.
- `_Data[slot]->_Camp`: camp unlock/placement state.
- `_Data[slot]->_Animal`: endemic-life capture state.
- `_Data[slot]->_EnemyReport`: monster, endemic, and fish report state.
- `_Data[slot]->_EnemyReport->_AnimalFishing`: fishing records.

## Tracked Helper Pattern

The repo keeps helper source outside the submodule:

```text
tools/save-inspection/mhwilds_interpret_save.rs
tools/save-inspection/Invoke-MHWildsSaveInterpretation.ps1
tools/save-inspection/Summarize-MHWildsSaveDump.ps1
```

The PowerShell runner temporarily copies the helper into:

```text
tools/ree-save-editor/src/bin/mhwilds_interpret_save.rs
```

Then it builds/runs the helper in the submodule workspace and removes the temporary source afterward. This avoids committing local helper code to the upstream submodule while still using the submodule's lockfile and dependency graph.

The helper does this:

1. Load `TypeMap::load_from_file("assets/mhwilds/rszmhwilds.json", "assets/mhwilds/enumsmhwilds.json")`.
2. Build a `crc_map` from `type_map.types.0.values().map(|info| (info.crc, info))`.
3. Load the copied save with `SaveOptions::new(Game::MHWILDS).id(steamid64)` and `SaveFile::load`.
4. Walk `SaveFile.fields`, resolving class names via `get_by_hash` or `crc_map`.
5. Resolve each field name from the parent class `TypeInfo`.
6. Write all output files under the given `out-dir`.

Run it with:

```powershell
.\tools\save-inspection\Invoke-MHWildsSaveInterpretation.ps1 `
  -SaveCopyPath .\memory\private-save\raw\data001Slot-YYYYMMDD-HHMMSS.bin `
  -SteamId64 <steamid64> `
  -OutDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

Then run the summary/CSV pass:

```powershell
.\tools\save-inspection\Summarize-MHWildsSaveDump.ps1 `
  -DumpDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

The summary pass writes to `memory/private-save/summaries/<copy-id>/` by default. Use it for normal inspection questions, then return to the expanded dump files only when adding a new interpretation rule. It removes old `.json` and `.csv` files in the selected summary directory before writing fresh output.

The summary pass resolves display names from the local Wilds assets in the submodule.

After a successful interpretation and summary pass, update `memory/private-save/save-inspection.config.json` so the active profile points at the copied save, generated dump dir, generated summary dir, SteamID, and intended character slot.

## Output Files

The helper writes one summary file plus targeted files per character slot (slot index is zero-based). Targeted files are written for each slot where the corresponding save path resolves.

Before each run, `Invoke-MHWildsSaveInterpretation.ps1` removes its known generated files from the selected output directory:

- `interpreted-summary.json`
- `slot*-equip-box.json`
- `slot*-item-box.json`
- `slot*-mission.json`
- `slot*-endemic-captures.json`
- `slot*-fish-captures.json`
- `slot*-monster-report.json`
- `slot*-story.json`
- `slot*-quest-record.json`
- `slot*-delivery-bounty.json`
- `slot*-camp.json`

This prevents stale slot files from surviving when a later run resolves fewer paths. If you want a fully clean private output tree, remove only repo-local ignored `memory/private-save/dumps/` and `memory/private-save/summaries/`, leaving `memory/private-save/raw/` intact unless the user explicitly asks to delete copied raw saves.

### `interpreted-summary.json`

Always written. Contains:

- `source_file`, `game`, `flags`, `top_level_field_count`.
- `top_level`: full structural walk at max_depth=2. Arrays are truncated to their first 10 elements (`"first_values"` key; `"truncated": true` when longer). At the depth limit, Classes collapse to `{ kind, hash, num_fields }` and Arrays to `{ kind, len }`.
- `slots`: per-slot summaries, each with `slot_index`, `active`, hunter/Palico/Seikret/Pugee names from `_BasicData`, boolean flags for `_Item` and `_Equip` presence, and `top_fields` (slot class expanded to depth 1).

Scalar values (strings, integers, booleans, enums) are always emitted as their actual value regardless of depth. The depth limit only gates recursion into Class and Array nodes.

Typical token size: 10–30 k for a three-slot save.

### `slot{N}-equip-box.json`

Full equipment box for slot N. Path: `_Equip → _EquipBox`. Expanded to max_depth=4 with no array truncation, which is deep enough to reach decoration slots on each equipment piece:

```
depth 0  EquipBox array element (equipment piece class)
depth 1  piece fields: type ID, level, reinforcement, skill entries, deco slot array
depth 2  deco slot array elements (individual decoration class)
depth 3  decoration fields: item ID, level
depth 4  any further nesting
```

Use this file to read the hunter's full equipment storage including slotted decorations. If decoration fields appear at depth 5+, increase `max_depth` in `extract_equip_box` in `mhwilds_interpret_save.rs`.

### `slot{N}-item-box.json`

Full item box for slot N. Path: `_Item → _BoxItem`. Expanded to max_depth=2 with no array truncation. Item entries are expected to be simple (ItemId, Num); depth 2 is sufficient. Use this file to read the complete item storage. Prefer `slotN-inventory-summary.csv` for normal inventory questions because it resolves item enum keys and English display names.

### `slot{N}-mission.json`

Full mission and quest progress for slot N. Path: `_Mission`. The entire `_Mission` class is expanded to max_depth=3 with no array truncation. Quest flag arrays at depth 1 are fully emitted rather than truncated at 10, so this file captures the complete quest completion state. Use this file to determine which quests, investigations, and progression gates are cleared.

### `slot{N}-endemic-captures.json`

Full endemic-life capture state for slot N. Path: `_Animal`. The entire `_Animal` class is expanded to max_depth=3 with no array truncation. Use this file to determine which endemic life has been captured, capture counts by stage, and endemic-life mini-game/stat counters when those fields resolve.

### `slot{N}-fish-captures.json`

Full fish capture/report state for slot N. Path: `_EnemyReport → _AnimalFishing`. The `_AnimalFishing` array is expanded to max_depth=3 with no array truncation. Use this file to determine which fish have been caught and fishing report progress. Prefer `slotN-fishing-summary.csv` for normal questions because it resolves fish enum keys and English display names.

### `slot{N}-monster-report.json`

Full monster report state for slot N. Path: `_EnemyReport`. The entire `_EnemyReport` class is expanded to max_depth=3 with no array truncation. Use this file to inspect large monster, small monster, endemic, and fishing report records together. Prefer `slotN-monster-report-summary.csv` for normal questions because it resolves monster/endemic/fish enum keys and English display names.

### `slot{N}-story.json`

Story progression state for slot N. Path: `_Story`. The `_Story` class is expanded to max_depth=3 with no array truncation. Use this file to inspect guide mission, progress ID, story flags, and story package flags.

### `slot{N}-quest-record.json`

Quest record state for slot N. Path: `_QuestRecord`. The `_QuestRecord` class is expanded to max_depth=3 with no array truncation. Use this file to inspect historical quest records and clear/stat tracking where fields resolve.

### `slot{N}-delivery-bounty.json`

Delivery bounty state for slot N. Path: `_DeliveryBounty`. The `_DeliveryBounty` class is expanded to max_depth=5 with no array truncation. Use this file to inspect delivery-style unlock progress and bounty state.

### `slot{N}-camp.json`

Camp unlock/placement state for slot N. Path: `_Camp`. The `_Camp` class is expanded to max_depth=3 with no array truncation. Use this file to inspect camp unlock and placement state.

## Two-Pass Design

The Rust source has two function families:

- **Summary family** (`class_to_named_json`, `named_value_json`, `array_to_named_json`): truncates arrays to 10. Used only for `interpreted-summary.json`.
- **Full family** (`class_to_json_full`, `named_value_full_json`, `array_to_json_full`): no truncation. Used for targeted files.

Both families share `value_preview`, `field_info`, `type_name`, `get_field`, and `array_classes`. To add a new targeted extraction, write an `extract_*` function using the full family, call it inside the per-slot loop in `main`, and write its output with `write_json`.

## Third-Pass Summaries

`Summarize-MHWildsSaveDump.ps1` converts expanded dump JSON into smaller, private, queryable files under `memory/private-save/summaries/<copy-id>/`. CSV files land at the summary dir root; JSON files go into a `json/` subfolder.

**CSVs at summary dir root — read these first:**
- `profile-summary.csv`: active slots and visible profile/presence fields.
- `slotN-inventory-summary.csv`: nonzero item-box entries with item IDs, enum keys, resolved item names, and quantities.
- `slotN-equip-summary.csv`: equipment-box entries with kind, type, name, armor part, free vals, and decoration names.
- `slotN-equip-current-summary.csv`: currently equipped items mapped to named slots (weapon, head, chest, arms, waist, legs, charm).
- `slotN-fishing-summary.csv`: observed fish records and capture counts with resolved fish names.
- `slotN-monster-report-summary.csv`: observed monster/endemic/fish report records with resolved names.
- `slotN-endemic-summary.csv`: endemic capture entries grouped by resolved `EmId`, with resolved names.
- `index.json`: manifest of all files written, with separate `csv_files` and `json_files` lists.

**JSON in `json/` subfolder — open only when the user asks for more detail:**
- `profile-summary.json`, `slotN-inventory-summary.json`, `slotN-equip-summary.json`, `slotN-equip-current-summary.json`, `slotN-fishing-summary.json`, `slotN-monster-report-summary.json`, `slotN-endemic-summary.json`: structured counterparts to the CSVs above, with metadata fields (totals, caveats) not present in the flat CSV.
- `slotN-story-summary.json`, `slotN-mission-summary.json`, `slotN-quest-record-summary.json`, `slotN-delivery-bounty-summary.json`, `slotN-camp-summary.json`: scalar fields plus nonzero array entries (JSON only, no CSV counterpart).

Read the CSVs for quick answers. If detail is missing, mention the JSON files are available and wait to be asked. The expanded `dumps/` JSON remains the source of truth when a summary is too lossy. Empty slot CSVs can be tiny blank files when a slot has no rows for that table.

Name resolution uses the submodule assets:

- `enumsmhwilds.json`: fixed IDs -> enum keys such as `ITEM_0000` or `EM5317_09_0`.
- `enums_mappings_mhwilds.json`: item enum keys -> message GUIDs.
- `combined_msgs.json`: English message strings, including `EnemyText_NAME_<enum>` entries for monsters, fish, and endemic life.

## Sanity Checks

After interpretation:

```powershell
Get-ChildItem memory\private-save\dumps\<copy-id>
Get-ChildItem memory\private-save\summaries\<copy-id>
git status --short --ignored
```

Expected git state:

- `memory/private-save/` ignored.
- `.cargo-home/` ignored.
- `.cargo-target/` ignored.
- No tracked public files containing hunter IDs, character names, inventory, or progression facts unless the user explicitly asks to record sanitized facts.

Expected output files when all three slot paths resolve:

```text
interpreted-summary.json
slot0-equip-box.json
slot0-item-box.json
slot0-mission.json
slot0-endemic-captures.json
slot0-fish-captures.json
slot0-monster-report.json
slot0-story.json
slot0-quest-record.json
slot0-delivery-bounty.json
slot0-camp.json
slot1-equip-box.json
slot1-item-box.json
slot1-mission.json
slot1-endemic-captures.json
slot1-fish-captures.json
slot1-monster-report.json
slot1-story.json
slot1-quest-record.json
slot1-delivery-bounty.json
slot1-camp.json
slot2-equip-box.json
slot2-item-box.json
slot2-mission.json
slot2-endemic-captures.json
slot2-fish-captures.json
slot2-monster-report.json
slot2-story.json
slot2-quest-record.json
slot2-delivery-bounty.json
slot2-camp.json
```

Inactive/default slots can still have save containers, so targeted files may be written for all three slots even when only one slot is active.

Expected summary outputs: CSVs and `index.json` at the summary dir root; JSON versions in a `json/` subfolder. CSVs cover profile, inventory, equipment box, equipped loadout, fishing, monster report, and endemic captures. JSON also includes story, mission, quest-record, delivery-bounty, and camp summaries with no CSV counterpart.

Also verify `memory/private-save/save-inspection.config.json` points at the intended `copy_id`, `summary_dir`, and `active_character_slot_index`.

## Current Known Result Shape

### interpreted-summary.json

- Root save class: `app.savedata.cUserSaveData`.
- `_Data` as a 3-slot array of `app.savedata.cUserSaveParam`.
- Active slot via `Active = 1`.
- `_BasicData` fields such as `CharName`, `OtomoName`, `SeikretName`, and `PugeeName`.
- Presence flags for `_Item`, `_Equip`, `_Mission`, `_Animal`, `_Collection`, and `_EnemyReport`.

### slot{N}-equip-box.json

- Array of equipment piece classes, each with resolved type name, skill entries, and decoration slot arrays.
- Look for fields like `_ItemId`, `_EquipCategory`, `_SlotData`, or similar hashes to identify piece type and decoration contents.
- If decoration fields still appear as `{ kind: "Class", num_fields: N }` previews, the actual deco data is nested deeper than max_depth=4; increase depth in `extract_equip_box`.

### slot{N}-item-box.json

- Array of item entry classes, each with item ID and quantity.
- `slotN-inventory-summary.csv` resolves item IDs into enum keys and English display names where possible.

### slot{N}-mission.json

- `_Mission` class with all sub-arrays fully expanded.
- Contains quest completion arrays — look for boolean or integer flag fields alongside quest ID fields to determine cleared state.

### slot{N}-endemic-captures.json

- `_Animal` class with all sub-arrays fully expanded.
- Contains endemic-life capture state and per-stage capture counters where those fields resolve.

### slot{N}-fish-captures.json

- `_EnemyReport._AnimalFishing` array with all report entries fully expanded.
- Contains fishing capture/report state.
- `slotN-fishing-summary.csv` resolves fish IDs into enum keys and English display names where possible.

### slot{N}-monster-report.json

- `_EnemyReport` class with monster, endemic, and fishing report arrays fully expanded.
- Contains large monster and small monster record state.
- `slotN-monster-report-summary.csv` resolves monster, endemic, and fish IDs into enum keys and English display names where possible.

### slot{N}-story.json

- `_Story` class with guide mission, story progress, and story bitsets expanded.
- Useful for determining story progression and unlock gates.

### slot{N}-quest-record.json

- `_QuestRecord` class with quest records expanded.
- Useful for historical quest clear/stat tracking where fields resolve.

### slot{N}-delivery-bounty.json

- `_DeliveryBounty` class with bounty/delivery records expanded.
- Useful for delivery-style unlock progress.

### slot{N}-camp.json

- `_Camp` class with camp records expanded.
- Useful for camp unlock and placement state.

Do not copy exact user values from private output into public notes.
