# Memory Query Helpers

Small read-only helpers for common local lookups. Use these from the repo root with PowerShell 7.

```powershell
.\tools\memory-query\Find-MHWildsSkillSource.ps1 -Skill "Weakness Exploit"
.\tools\memory-query\Find-MHWildsSkillSource.ps1 -Skill "Exploit" -Contains
.\tools\memory-query\Find-MHWildsMaterial.ps1 -Name "Ajarakan Scale"
.\tools\memory-query\Get-MHWildsActiveSaveProfile.ps1
```

These scripts only read repo-local CSVs or ignored private config. They do not inspect live saves.
