# MH Wilds Save Inspection Workflow

Last updated: 2026-05-08

This note documents the read-only workflow for interpreting a Monster Hunter Wilds save with the `tools/ree-save-editor/` submodule. Keep user-specific copied saves, dumps, and interpreted outputs under ignored `memory/private-save/`; keep only general process notes here.

## Safety Rules

- Never operate on the live Steam save directly.
- Never write to Steam userdata, Steam Cloud, a Steam library, or the MH Wilds app ID `2246340` save paths.
- First copy the live save into `memory/private-save/raw/`, then read only that copy.
- Write all dumps under `memory/private-save/dumps/`.
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

## Basic Dump

Update/build the submodule tooling first, following the repo rules:

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

Run `ree-dump` against the copied save:

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

Current caveat: `ree-dump --save-file` appears unused in the CLI path, and the `.bin` save JSON writer in `src/file/mod.rs` is commented out. Use `-f` to validate/decrypt, then use a helper binary for structured interpretation.

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
- `_Data[slot]->_Mission`: mission flags.
- `_Data[slot]->_Animal`: endemic-life capture state.
- `_Data[slot]->_EnemyReport->_AnimalFishing`: fishing records.

## Tracked Helper Pattern

The repo keeps helper source outside the submodule:

```text
tools/save-inspection/mhwilds_interpret_save.rs
tools/save-inspection/Invoke-MHWildsSaveInterpretation.ps1
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
6. Emit concise JSON such as:

```text
memory/private-save/dumps/<copy-id>/interpreted-summary.json
```

Depth-limit recursive value output. Large fields like item box and equipment can explode quickly; summaries should show names, declared types, array lengths, and first values unless a deeper targeted extraction is needed.

Run it with:

```powershell
.\tools\save-inspection\Invoke-MHWildsSaveInterpretation.ps1 `
  -SaveCopyPath .\memory\private-save\raw\data001Slot-YYYYMMDD-HHMMSS.bin `
  -SteamId64 <steamid64> `
  -OutDir .\memory\private-save\dumps\data001Slot-YYYYMMDD-HHMMSS
```

## Sanity Checks

After interpretation:

```powershell
Get-ChildItem memory\private-save\dumps\<copy-id>
git status --short --ignored
```

Expected git state:

- `memory/private-save/` ignored.
- `.cargo-home/` ignored.
- `.cargo-target/` ignored.
- No tracked public files containing hunter IDs, character names, inventory, or progression facts unless the user explicitly asks to record sanitized facts.

## Current Known Result Shape

A good interpreted summary should identify:

- Root save class: `app.savedata.cUserSaveData`.
- `_Data` as a 3-slot array of `app.savedata.cUserSaveParam`.
- Active slot via `Active = 1`.
- `_BasicData` fields such as `CharName`, `OtomoName`, `SeikretName`, and `PugeeName`.
- Presence of `_Item`, `_Equip`, `_Mission`, `_Animal`, `_Collection`, and `_EnemyReport`.

Do not copy exact user values from private output into public notes.
