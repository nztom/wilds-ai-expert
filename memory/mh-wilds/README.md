# Monster Hunter Wilds Build Memory

Last refreshed: 2026-05-08

This folder is the local working memory for Monster Hunter Wilds buildcrafting, materials, monsters, side quests, endemic life, fishing, and unlock routing. The original equipment data was scraped from Gamer Guides database pages and cross-checked against current guide/planner pages that mention Ver. 1.041 / 1.041.01 as the latest base-game data window.

## Freshness

- Game memory last broadly refreshed: 2026-05-08.
- Last patch/content window represented: base-game Title Update 4 plus Ver. 1.041 / 1.041.01, with Ver. 1.041.00.00 released February 18, 2026 UTC.
- Current meta snapshot file: `current_meta_notes.md`, last refreshed 2026-05-06, with LBG-specific additions on 2026-05-07.
- Use live web verification before strong claims about newer patches, event rotations, post-Ver. 1.041 balance, expansion content, or anything contradicted by the user's in-game evidence.

## Core Wilds Build Rules

- Decorations are split by equipment type: armor decorations only go in armor slots, and weapon decorations only go in weapon slots.
- Decoration slot size is 1-3. A decoration requires a slot of at least its listed size.
- Weapon skills largely live on weapons and weapon decorations. Armor skills largely live on armor pieces, armor decorations, and talismans.
- Wilds lets hunters carry two weapons, but weapon-native skills and weapon decorations only apply from the currently active weapon. Do not count the Seikret-carried / inactive weapon's decorations toward the active skill list.
- Armor pieces can provide equipment skills plus group skills and set bonus skills. Group/set skills are build-defining but are not normal decorations.
- Talismans are separate equipment and can carry skills without consuming weapon/armor slots. Ver. 1.021 added appraised random talismans from Glowing Stones for HR100+ 9-star quests.
- Armor Transcendence, introduced later in the update cycle, can increase decoration slots on rarity 5/6 armor, so slot assumptions should account for whether a build is pre- or post-transcendence.

## Files

- `skills.csv`: Raw skill table, including equipment, food, group, and set bonus skills.
- `skills_normalized.csv`: Cleaner skill lookup with max level and level descriptions.
- `decorations_armor.csv`: Raw armor decoration table.
- `decorations_armor_normalized.csv`: Armor decoration title, skill, required slot, rarity, price.
- `decorations_weapon.csv`: Raw weapon decoration table.
- `decorations_weapon_normalized.csv`: Weapon decoration title, skill, required slot, rarity, price.
- `armor.csv`: Raw armor-piece table.
- `armor_normalized.csv`: Armor title, set, rarity, skills, slot columns, materials, unlock notes.
- `talismans.csv`: Raw talisman table.
- `talismans_normalized.csv`: Talisman title, skills, rarity, HR, materials, unlock notes.
- `skill_index.csv`: Derived lookup by skill. Use this first when answering "where can this skill go?"
- `current_meta_notes.md`: Current Ver. 1.041 / TU4 base-game meta snapshot for weapons, armor engines, Gogma Artian priorities, and hard-quest heuristics.
- `fishing_locations.md`: Aquatic life, fish locations, bait, and Kanya fishing quest notes.
- `endemic_life_locations.md`: Broader capture-net endemic life lookup, rare targets, conditions, and practical routes.
- `monster_field_guide.md`: Compact large-monster locations, elemental weaknesses, break targets, and hunt notes.
- `side_quest_notes.md`: Walkthrough notes for side quests with non-obvious objectives.
- `unlocks_and_special_items.md`: Mantles, material gatherers, Palico skills, charms, hunting assistants, Great Hunts, and other functional side-quest unlocks.
- `source_counts.json`: Source URLs and row counts from the refresh.

## Quick Query Examples

PowerShell examples from the repo root:

```powershell
Import-Csv memory\mh-wilds\skill_index.csv |
  Where-Object Skill -eq 'Weakness Exploit' |
  Format-List
```

```powershell
Import-Csv memory\mh-wilds\decorations_weapon_normalized.csv |
  Where-Object Skill -match 'Critical Eye|Attack Boost' |
  Select-Object Title,Skill,SlotLevel,Rarity
```

```powershell
Import-Csv memory\mh-wilds\armor_normalized.csv |
  Where-Object Skills -match 'Flayer' |
  Select-Object Title,ArmorSet,Rarity,Skills,Slot1,Slot2,Slot3
```

## Refresh Notes

Use current sources before making meta claims, because Wilds had active balance and equipment updates through at least February 2026, and a large expansion has been announced for summer 2026 details.

Sources used for this memory:

- Gamer Guides database: skills, armor, talismans, armor decorations, weapon decorations.
- Game8 patch/update pages: Ver. 1.041 and armor search support notes.
- Mobalytics decoration/talisman guide and build planner: decoration type/slot rules and recent planner freshness.
- RPG Site / Gematsu patch reporting: Ver. 1.021 talisman additions and Ver. 1.041 final base-game update context.
- User in-game check, 2026-05-07: inactive secondary weapon decorations do not appear in the active skill list.

Known caveat: `skill_index.csv` is a derived convenience file based on skill-name matching in the normalized scraped text. For exact material costs or edge cases involving multi-skill jewels, check the corresponding normalized decoration and armor CSVs.

## Note Boundaries

- Put exact material and farming routes in `material_locations.md`.
- Put fish, bait, and aquatic-life routing in `fishing_locations.md`.
- Put capture-net endemic life in `endemic_life_locations.md`.
- Put broad unlock tables in `unlocks_and_special_items.md`; keep quest walkthrough quirks in `side_quest_notes.md`.
- Put monster weakness/location summaries in `monster_field_guide.md`, and verify exact hitzones/rewards in-game when precision matters.
