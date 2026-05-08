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

This script performs read-only web requests and rewrites public CSV memory files only.
