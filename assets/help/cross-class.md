# Cross-Class Forge System — Design Document
*Created: 2026-03-03*

> Steven (enhanced weapons shop) and Mahan (enhanced armor shop) offer a **cross-save meta-progression** system where class-specific gear blueprints persist across all save slots.

---

## Overview

When a player plays a particular job class, Steven and Mahan **learn** that class's blueprint. Once learned, the class-specific item becomes available for purchase in **every** save slot — not just the one it was discovered in. This rewards players who try multiple classes across multiple playthroughs.

---

## Vendors

| Vendor | Role | Crafts | Rescued |
|--------|------|--------|---------|
| Steven | `enhanced_weapons_shop` | Class-specific **weapons** | Floor 2 (with Mahan) |
| Mahan  | `enhanced_armor_shop`   | Class-specific **armor**  | Floor 2 (with Steven) |

Neither vendor buys items back — only Daniels does.

---

## Class-Specific Items

Each of the 9 job classes has a signature weapon (Steven) and signature armor (Mahan). These items:

- Grant **+3 to the class's primary stat** (capped at +3; no higher)
- **Unlock a class skill** usable by any job class equipping the item
- Are **expensive** relative to the vendor's normal stock (endgame gold sink)

### Example Items

| Class | Steven (Weapon) | Mahan (Armor) | Stat | Skill Granted |
|-------|----------------|---------------|------|---------------|
| Arcanist | Wand of Intellect | Arcanist Robes | +3 INT | *(Arcanist class skill)* |
| Scoundrel | Scoundrel Dagger | Scoundrel Leather | +3 DEX | *(Scoundrel class skill)* |
| Warrior | *(TBD)* | *(TBD)* | +3 STR | *(Warrior class skill)* |
| *(remaining 6 classes)* | *(TBD)* | *(TBD)* | *(varies)* | *(varies)* |

> Full class/item/skill mapping to be defined once all 9 classes are finalized.

---

## Cross-Save Persistence

- Blueprints are stored in a **global meta-save** (`user://meta_progress.json` or similar), separate from per-slot save files.
- When a player completes a run (or reaches a milestone) with a class, that class's blueprint is permanently unlocked.
- On visiting Steven/Mahan in any save slot, all learned blueprints appear as purchasable items.

---

## Reforge System

Steven and Mahan can **reforge** two class-specific items into one combined item.

### Rules

- Merge two class items → the result keeps **both class skills**
- **-1 stat point** is deducted from the total (the player does not choose which stat loses the point — it's random or vendor-chosen)
- The +3 cap per individual stat still applies
- Reforging can be chained: merge a 2-skill item with a 3rd class item, losing another -1 stat point but gaining the 3rd skill

### Example Reforge Chain

```
Scoundrel Dagger (+3 DEX, Scoundrel skill)
  + Arcanist Wand (+3 INT, Arcanist skill)
  = Forged Blade (+2 DEX, +3 INT, Scoundrel + Arcanist skills)
    ↑ lost 1 DEX from the merge penalty

Forged Blade (+2 DEX, +3 INT, 2 skills)
  + Warrior Sword (+3 STR, Warrior skill)
  = Master Blade (+2 DEX, +2 INT, +3 STR, 3 skills)
    ↑ lost 1 INT from the second merge penalty
```

### Endgame Goal

A player who has played all 9 classes across multiple save files can theoretically forge an **ultimate weapon** (Steven) and **ultimate armor** (Mahan) that grant access to all 9 class skills, at the cost of significantly reduced stat bonuses from the cumulative -1 penalties.

**9 classes merged = 8 merge penalties = up to 8 stat points lost across the item.**

This makes the ultimate item a versatility powerhouse (all skills) rather than a stat monster — keeping it balanced.

---

## Implementation Notes (for later)

### Data Structures

```
# meta_progress.json (global, cross-save)
{
  "learned_blueprints": ["arcanist", "scoundrel", ...],
  "forge_count": 0  # optional: track total forges for achievements
}
```

### Item Definition Fields (item_db.gd additions)

```gdscript
# New fields for class-forged items:
"grants_skill": "scoundrel_backstab",   # class skill ID unlocked by equipping
"forged_from": ["scoundrel", "arcanist"], # tracks which classes were merged
"forge_penalty": 1,                       # total stat points lost to reforging
```

### UI

- Steven/Mahan get a **"Forge" tab** alongside their regular "Buy" tab
- Forge tab shows: available blueprints, current forged items in inventory, reforge option
- Reforge confirmation dialog shows stat preview before/after

### Files Likely Affected

- `dungeon_break/data/item_db.gd` — class-specific item definitions, `grants_skill` field
- `dungeon_break/data/game_data.gd` — meta-save load/save for blueprints
- `dungeon_break/ui/shop_ui.gd` — forge tab UI for enhanced shops
- `dungeon_break/combat/combat_manager.gd` — reading `grants_skill` to enable cross-class skills in combat

---

## Open Questions

- [ ] What milestone triggers blueprint learning? (floor clear? game completion? reaching a certain level?)
- [ ] Should reforge have a gold cost on top of the stat penalty?
- [ ] Can forged items be sold or are they soulbound?
- [ ] Should there be a visual indicator (glow, special icon border) for forged items?
- [ ] Full class → stat → skill mapping for all 9 classes
