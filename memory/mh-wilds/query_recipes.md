# Query Recipes

These examples are optional helpers for targeted local lookups. Prefer these or the scripts in `tools/memory-query/` over opening large CSVs in full.

## Skill Sources

```powershell
.\tools\memory-query\Find-MHWildsSkillSource.ps1 -Skill "Weakness Exploit"
```

Manual equivalent:

```powershell
Import-Csv memory\mh-wilds\skill_index.csv |
  Where-Object Skill -eq 'Weakness Exploit' |
  Format-List
```

## Weapon Decoration Skills

```powershell
Import-Csv memory\mh-wilds\decorations_weapon_normalized.csv |
  Where-Object Skill -match 'Critical Eye|Attack Boost' |
  Select-Object Title,Skill,SlotLevel,Rarity
```

## Armor Pieces By Skill

```powershell
Import-Csv memory\mh-wilds\armor_normalized.csv |
  Where-Object Skills -match 'Flayer' |
  Select-Object Title,ArmorSet,Rarity,Skills,SkillDetails,Slot1,Slot2,Slot3
```

## Materials

```powershell
.\tools\memory-query\Find-MHWildsMaterial.ps1 -Name "Ajarakan Scale"
```

## Active Private Save Profile

```powershell
.\tools\memory-query\Get-MHWildsActiveSaveProfile.ps1
```
