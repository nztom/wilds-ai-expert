# Knowledge Refresh Helpers

These helpers update the public Monster Hunter Wilds knowledge base under `memory/mh-wilds/`.
They are separate from `tools/save-inspection/`, which should stay focused on read-only private save interpretation.

## Files

- `Update-MHWildsArmorSkillLevels.ps1`: fetches Kiranico armor-series pages and merges per-piece armor skill levels into `memory/mh-wilds/armor.csv` and `memory/mh-wilds/armor_normalized.csv`.

## Usage

Run from the repository root:

```powershell
.\tools\knowledge-refresh\Update-MHWildsArmorSkillLevels.ps1
```

The script performs read-only web requests, caches fetched Kiranico pages under ignored `memory/mh-wilds/.cache/kiranico-armor-series/`, and rewrites public CSV memory files only:

- `memory/mh-wilds/armor.csv`
- `memory/mh-wilds/armor_normalized.csv`

Useful options:

```powershell
.\tools\knowledge-refresh\Update-MHWildsArmorSkillLevels.ps1 `
  -RequestDelayMs 750 `
  -RequestTimeoutSec 30 `
  -ThrottleLimit 1
```

After running, check the script output for matched-row counts and inspect the diff before committing:

```powershell
git diff -- memory/mh-wilds/armor.csv memory/mh-wilds/armor_normalized.csv
```
