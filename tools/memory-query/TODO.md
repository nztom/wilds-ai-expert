# Memory Query Helper TODO

Ordered by expected implementation effort, with the highest-value next helpers first. Monster-specific helpers are intentionally skipped for now.

## Next Priority

1. `Find-MHWildsOwnedDecoration.ps1` - done
   - Queries active save owned decorations by decoration name or skill.
   - Reads only `slotN-decorations-summary.csv` and optionally `slotN-decoration-skills-summary.csv`.
   - Outputs decoration name, type, slot level, quantity, and skill details.

2. `Compare-MHWildsSkillPlan.ps1`
   - Compare resolved current build skills against target skill levels.
   - Accept simple targets such as `Weakness Exploit=5`, `Critical Boost=3`, `Evade Extender=1`.
   - Use `Resolve-MHWildsCurrentState.ps1` so private build overrides are applied.
   - Output met, missing, below-target, and over-target skills.

3. `Get-MHWildsCurrentSkills.ps1` - done
   - Thin wrapper around `Resolve-MHWildsCurrentState.ps1`.
   - Prints only resolved current skill totals, max levels, overcap flags, and sources when requested.

## Later Helpers

4. `Get-MHWildsCurrentLoadout.ps1`
   - Thin wrapper around `Resolve-MHWildsCurrentState.ps1`.
   - Print only equipped weapon, armor, charm, decorations, and secondary weapons.

5. `Find-MHWildsArmorBySkill.ps1`
   - Query `armor_normalized.csv` by skill.
   - Prefer `SkillDetails` for exact per-piece levels when present.
   - Output title, armor set, rarity, slots, skill details, materials, and unlock notes.

6. `Find-MHWildsCharmBySkill.ps1`
   - Query `talismans_normalized.csv` by skill.
   - Output charm title, skills, rarity, HR/unlock notes, and materials.

7. `Search-MHWildsMemory.ps1`
   - Constrained search over `memory/mh-wilds/*.md` and selected normalized CSVs.
   - Must avoid `memory/private-save/`, `tools/ree-save-editor/`, and expanded dump JSON.
   - Limit output to concise file/line matches.

8. `Test-MHWildsCraftable.ps1`
   - Compare a target equipment/charm/material requirement against active inventory summary.
   - Higher effort because material requirements are stored as scraped text and need careful parsing.

## Explicitly Skipped For Now

- `Find-MHWildsMonster.ps1`
- `Get-MHWildsMatchupPrep.ps1`
