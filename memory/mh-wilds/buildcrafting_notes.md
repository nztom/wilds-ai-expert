# Monster Hunter Wilds Buildcrafting Notes

Last refreshed: 2026-05-06

## How To Think About Builds

Start every build by separating the problem into weapon-side skills and armor-side skills. Wilds makes this split stricter than older Monster Hunter games because weapon decorations and armor decorations are separate item classes. Also account for the two-weapon system: only the currently active weapon's skills and decorations count, so the inactive Seikret-carried weapon cannot be used as extra decoration storage.

For most damage builds:

1. Pick the weapon and damage model: raw, elemental, status, shelling/phial/ammo, or hybrid.
2. Lock required weapon skills first, because they compete for weapon decoration slots.
3. Use armor for universal damage and comfort: Weakness Exploit, Agitator, Maximum Might, Burst, Constitution/Stamina Surge, Evade Window/Extender, Divine Blessing, resistances, etc.
4. Choose set/group bonuses only when they beat the opportunity cost of better individual armor pieces.
5. Fill remaining slot budget with matchup tools: resistance, blight/status immunity, Tremor/Wind/Earplugs, Shockproof, Wide-Range, Speed Eating.

## Weapon-Side Skill Families

These are usually weapon decoration or weapon-native concerns:

- Raw affinity/damage: Attack Boost, Critical Eye, Critical Boost.
- Sharpness economy: Handicraft, Protective Polish, Razor Sharp, Speed Sharpening.
- Guard weapons: Guard, Guard Up, Offensive Guard.
- Charge weapons: Focus.
- Draw play: Critical Draw, Punishing Draw.
- KO/exhaust: Slugger, Stamina Thief.
- Bowguns: Ammo Up, Spare Shot, Normal/Pierce/Spread Shots, Special Ammo Boost, Ballistics, Recoil/Reload style skills where present.
- Bow: Normal Shots, Pierce Shots, Spread/Power Shots, Special Ammo Boost, charge/stamina support depending on build.
- Element/status: Fire/Water/Thunder/Ice/Dragon Attack, Poison/Paralysis/Sleep/Blast Attack, Critical Element, Critical Status, status functionality skills.

## Armor-Side Skill Families

These are usually armor decorations, armor pieces, or talismans:

- Universal offense: Weakness Exploit, Agitator, Maximum Might, Burst, Peak Performance, Resentment, Counterstrike, Adrenaline Rush, Foray, Coalescence-style uptime skills where applicable.
- Wound/hunt flow: Flayer, Partbreaker, Ambush.
- Stamina/evasion: Constitution, Stamina Surge, Evade Window, Evade Extender, Marathon Runner.
- Survival: Divine Blessing, Defense Boost, elemental resistances, Health/Stun/Poison/Paralysis/Sleep/Blast/Blight resistance.
- Utility: Quick Sheathe, Speed Eating, Free Meal, Wide-Range, Mushroomancer, Botanist, Geologist, Intimidator, Shock Absorber.

## Weapon Starting Points

- Great Sword: Focus, sharpness support, raw/crit, Quick Sheathe comfort, draw skills if playing draw-heavy.
- Long Sword: raw/crit, Quick Sheathe, evasion or comfort, sharpness support.
- Sword and Shield: raw/crit or element/status, sharpness support, comfort utility works well because SnS has flexible item use.
- Dual Blades: element/status, stamina skills, sharpness support, affinity.
- Hammer: raw/crit, Slugger if wanted, stamina comfort, sharpness support.
- Hunting Horn: raw/crit or element by horn, Slugger/Stamina Thief if leaning KO/exhaust, sharpness support.
- Lance: Guard/Guard Up/Offensive Guard, sharpness support, raw/crit, stamina comfort.
- Gunlance: Artillery/shelling support, Guard/Guard Up, Load Shells, sharpness support, then raw/crit if the shelling style benefits.
- Switch Axe: Focus/Power Prolonger-style uptime where present, sharpness support, raw/crit or element/status.
- Charge Blade: Artillery for impact phials, element skills for elemental phials, Guard/Guard Up as needed, Focus/Load Shells style acceleration if present.
- Insect Glaive: raw/crit or element, stamina/airborne only if playstyle actually uses them enough, sharpness support.
- Light Bowgun: ammo-type damage skill first, recoil/reload/ammo economy, element/status if using those ammo plans.
- Heavy Bowgun: ammo-type damage skill first, guard package if shielded, ammo economy, special ammo skills if relevant.
- Bow: shot-type skill, element, stamina economy, affinity/crit element if the set supports it.

## Refresh Checklist

Before recommending a final build:

- Check `current_meta_notes.md` for the current Ver. 1.041 / TU4 meta snapshot and endgame heuristics.
- Check `skill_index.csv` for slot class and available sources.
- Check `armor_normalized.csv` for armor pieces that provide the armor-side skills naturally.
- Check `decorations_*_normalized.csv` for slot pressure.
- Check `talismans_normalized.csv` for skill/talisman shortcuts.
- If the request is for current meta or post-expansion content, refresh web sources first.
