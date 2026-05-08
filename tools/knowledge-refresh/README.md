# Knowledge Refresh Helpers

Helpers that update tracked public memory under `memory/mh-wilds/`. Read `docs/development.md` before running scripts.

## Usage

```powershell
.\tools\knowledge-refresh\Update-MHWildsArmorSkillLevels.ps1
```

`Update-MHWildsArmorSkillLevels.ps1` fetches Kiranico armor-series pages and rewrites:

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
