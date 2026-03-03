# Cross-Class Forge System — Design Document
*Created: 2026-03-03 · Updated: 2026-03-03*

> Steven (enhanced weapons shop) and Mahan (enhanced armor shop) offer a **forge system** where class-specific gear is crafted from **Skyshards** — physical proof of floor mastery earned by clearing an entire floor as one class.

---

## Core Loop

1. Player enters a dungeon floor
2. Player clears **every room** on that floor as the **same class**
3. On boss kill → earns a **Class Skyshard** (tinted to class color)
4. Back at camp → bring Skyshard + gold to Steven or Mahan
5. Steven forges a **class weapon**, Mahan forges **class armor**
6. Optionally **reforge** two class items together for multi-skill gear

---

## Key Design Decisions

| Decision | Rule |
|----------|------|
| Skyshards per class | **One per class, ever.** 9 classes = 9 max skyshards. |
| Cross-save | **No.** All progression is per save file. Job-change system lets you play all 9 classes in one file. |
| How to unlock | Clear every room on a floor as the same class. Class is tracked at **room entry**. |
| Mixed-class floor | If any room is cleared as a different class → floor is **invalid** for skyshard. Player can reset the floor. |
| Floor reset | At dungeon entrance: **"Press B to Reset Floor"** — all rooms/enemies/boss respawn. Rescued NPCs stay unlocked. |
| Companions | Allowed. Only the **player's class** matters, not companion composition. |
| Skill loadout cap | **3 skills max** from the pool of forged-item skills. Selected at forge time. |
| Forged item sellable | **No.** Soulbound. Cannot be sold. |
| Forged item on companion | **Yes.** But if the companion dies → item is **permanently lost** (permadeath risk). |
| Crafting limit | **Unlimited** — gold is the only gate. |
| Reforge stat penalty | **-1 stat point** per merge (random stat on the item). |

---

## Vendors

| Vendor | Role | Forges | Rescued |
|--------|------|--------|---------|
| Steven | `enhanced_weapons_shop` | Class weapons (+ reforge weapons) | Floor 2 |
| Mahan | `enhanced_armor_shop` | Class armor (+ reforge armor) | Floor 2 |

Neither vendor buys items back — only Daniels does.

---

## Skyshards

A **Skyshard** is a tinted MISC item that drops when a floor boss is killed and the floor's class-tracking is valid.

### Skyshard Properties
- One per class, ever (tracked in `GameData.earned_skyshards`)
- Stored in player inventory as a physical item
- Cannot be sold, dropped, or given to companions
- Consumed when forging at Steven/Mahan
- Tooltip shows class origin so the player knows what it unlocks

### Skyshard Item Format
```gdscript
"vanguard_skyshard": {
    "name": "Vanguard Skyshard",
    "type": "MISC",
    "description": "Crystallized essence of the Vanguard. Bring to Steven or Mahan to forge class gear.",
    "class_origin": "VANGUARD",
    "icon": "skyshard",     # tinted to class color (red for Vanguard, etc.)
    "sellable": false,
    "price": 0
}
```

### Class Colors (for skyshard tinting)
| Class | Color | Hex |
|-------|-------|-----|
| VANGUARD | Red | `#cc3333` |
| SCOUNDREL | Purple | `#9933cc` |
| ARCANIST | Blue | `#3366cc` |
| CONFESSOR | Gold | `#ccaa33` |
| STRIDER | Green | `#33aa55` |
| MINSTREL | Pink | `#cc66aa` |
| TEMPLAR | White | `#dddddd` |
| REANIMATOR | Dark Green | `#336633` |
| TINKERER | Orange | `#cc7733` |

---

## Floor Class Tracking

### How It Works

1. **On room entry** → record `GameData.player_class` for this floor
2. **On room clear** → check if class matches the floor's tracked class
3. If mismatch → `floor_class_valid` = `false` (floor is burned for skyshard purposes)
4. If all rooms + boss cleared with same class → award skyshard

### Data Structure (GameData)
```gdscript
## Floor-level class tracking for skyshard eligibility.
## Key = floor number (int), value = Dictionary:
##   "class": int (PlayerClass enum value — set on first room entry)
##   "rooms_cleared": int (count of rooms cleared as the tracked class)
##   "valid": bool (false if any room was cleared as a different class)
var floor_class_tracking: Dictionary = {}

## Set of class enum values for which the player has already earned a skyshard.
## Persisted in save file. Prevents duplicate skyshards.
var earned_skyshards: Array[int] = []
```

### Tracking Flow (pseudocode)
```
func on_room_entered(floor_num, room_id):
    if floor_num not in floor_class_tracking:
        floor_class_tracking[floor_num] = {
            "class": GameData.player_class,
            "rooms_cleared": 0,
            "valid": true
        }
    # No action needed here — class is recorded on first room entry for this floor

func on_room_cleared(floor_num, room_id):
    var track = floor_class_tracking[floor_num]
    if GameData.player_class != track["class"]:
        track["valid"] = false   # burned — wrong class
    track["rooms_cleared"] += 1

func on_boss_killed(floor_num):
    var track = floor_class_tracking.get(floor_num, {})
    if not track.get("valid", false):
        return   # floor wasn't clean
    var cls = track["class"]
    if cls in earned_skyshards:
        return   # already have this class's skyshard
    # Award skyshard!
    earned_skyshards.append(cls)
    var shard_id = CLASS_SKYSHARD_MAP[cls]  # e.g. "vanguard_skyshard"
    GameData.add_item(shard_id)
    # Show UI notification
```

---

## Floor Reset

### Where
At the dungeon entrance portal (camp → dungeon transition).

### Controls
- **Press E** → Enter dungeon (existing behavior)
- **Press B** → Reset current floor

### What Resets
- All room states → `"uncleared"` (enemies respawn)
- Boss respawns
- `floor_class_tracking[current_floor]` is wiped
- Any loot in rooms is re-rolled

### What Does NOT Reset
- Rescued NPCs stay rescued
- Player inventory/gold/level unchanged
- Skyshards already earned are kept
- `earned_skyshards` array is untouched

### UI Messaging
When pressing B, show confirmation dialog:
> **Reset Floor [X]?**
> All rooms and the boss will respawn. Your inventory and NPCs are safe.
> To earn a Skyshard, clear every room as the same class.

---

## Class-Specific Forge Items

Each class has a signature weapon (Steven) and signature armor (Mahan).

### Properties
- Grant **+3 to the class's primary stat**
- **Contain a class skill** (baked in from the skyshard's class_origin)
- **Soulbound** — cannot be sold
- Can be equipped by **any class** (that's the point)
- Can be given to companions (with permadeath risk)

### Forge Recipe
```
1 Class Skyshard + 100 gold → Class Weapon (Steven)
                            → Class Armor  (Mahan)
```

### Skill Selection
- Happens at the forge vendor (Steven/Mahan), NOT in inventory
- Player picks which skill slot (1 of 3 max) the new skill occupies
- Can re-select skills later for a small gold fee (e.g. 50g)

### Item Format
```gdscript
"vanguard_forged_sword": {
    "name": "Vanguard Forgeblade",
    "type": "WEAPON",
    "damage": 5,
    "stat_str": 3,
    "grants_skill": "shield_wall",   # Vanguard class skill
    "forged_from": ["VANGUARD"],
    "forge_penalty": 0,
    "soulbound": true,
    "sellable": false,
    "price": 100,   # forge cost
    "description": "Forged from a Vanguard Skyshard. Grants Shield Wall."
}
```

---

## Reforge System

Steven and Mahan can **merge** two forged items into a combined item.

### Rules
- Both items must be the same type (weapon+weapon at Steven, armor+armor at Mahan)
- Result gets **both skills** (up to the 3-skill cap)
- **-1 stat point** deducted from the result (random stat on the item)
- +3 cap per individual stat still applies
- Reforging costs additional gold (e.g. 150g per merge)
- Can chain: merge a 2-skill item with a 1-skill item → 3-skill item (cap reached)

### Merge Example
```
Scoundrel Forgeblade (+3 DEX, Backstab)
  + Arcanist Forgeblade (+3 INT, Arcane Bolt)
  = Forged Blade (+2 DEX, +3 INT, Backstab + Arcane Bolt)
    ↑ lost 1 DEX from merge penalty

Forged Blade (2 skills)
  + Vanguard Forgeblade (+3 STR, Shield Wall)
  = Master Blade (+2 DEX, +2 INT, +3 STR, Backstab + Arcane Bolt + Shield Wall)
    ↑ lost 1 INT from second merge penalty — 3/3 skill slots filled
```

### 3-Skill Cap Enforcement
- At 3 skills, no more merges allowed on that item
- Player must choose wisely which 3 of 9 skills to combine
- To try a different combo → forge new base items (costs more skyshards? No — skyshards are one-per-class. See Open Questions.)

---

## Full Implementation Plan

### Phase 1: Floor Class Tracking + Floor Reset
**Files:** `game_data.gd`, `dungeon.gd`, `main.gd`, camp scene

1. **game_data.gd** — Add `floor_class_tracking: Dictionary`, `earned_skyshards: Array[int]`
2. **game_data.gd** — Add helper funcs: `track_room_entry(floor)`, `track_room_clear(floor)`, `is_floor_skyshard_eligible(floor) -> bool`, `reset_floor(floor)`
3. **game_data.gd** — Save/load `floor_class_tracking` and `earned_skyshards`
4. **dungeon.gd** — In `_trigger_room_combat()` (room entry), call `GameData.track_room_entry(current_floor)`
5. **dungeon.gd** — On room clear (when `room["state"]` flips to `"cleared"`), call `GameData.track_room_clear(current_floor)`
6. **main.gd** — In `_on_enter_dungeon()`, add "Press B" keybind for floor reset
7. **main.gd** — `reset_floor()` → wipe `cleared_rooms[floor]`, `floor_class_tracking[floor]`, reset `dungeon_seed` to force re-generation
8. **UI** — Show floor reset confirmation dialog with messaging about skyshard rules

### Phase 2: Skyshard Items + Award Logic
**Files:** `item_db.gd`, `game_data.gd`, `dungeon.gd`, `combat_manager.gd`

1. **item_db.gd** — Add 9 skyshard item definitions (one per class), all MISC type with `class_origin` field
2. **item_db.gd** — Add `CLASS_SKYSHARD_MAP: Dictionary` mapping `PlayerClass` enum → skyshard item ID
3. **game_data.gd** — `award_skyshard(floor)` function: checks `is_floor_skyshard_eligible()`, checks `earned_skyshards`, adds item to inventory
4. **dungeon.gd** or **combat_manager.gd** — On boss kill, call `GameData.award_skyshard(current_floor)`
5. **UI** — Skyshard pickup notification (big centered text + class-tinted glow effect)
6. **Inventory** — Skyshards show in inventory but have no Use/Equip/Drop buttons

### Phase 3: Forge Base Items (Steven + Mahan)
**Files:** `item_db.gd`, `shop_ui.gd`, `game_data.gd`

1. **item_db.gd** — Add 18 forged items (9 weapons + 9 armors), each with `grants_skill`, `forged_from`, `forge_penalty`, `soulbound` fields
2. **item_db.gd** — Add `CLASS_FORGE_WEAPON_MAP` and `CLASS_FORGE_ARMOR_MAP` dictionaries
3. **shop_ui.gd** — Add **"Forge" tab** to Steven and Mahan's shop UI
4. **shop_ui.gd** — Forge tab lists available forges based on skyshards in inventory
5. **shop_ui.gd** — Forge action: consume skyshard + deduct gold → add forged item to inventory
6. **shop_ui.gd** — Skill slot picker UI (which of 3 slots does this skill go in)
7. **game_data.gd** — `forge_skill_slots: Array[String]` (3 max, stores skill IDs from forged items)

### Phase 4: Reforge (Merge)
**Files:** `shop_ui.gd`, `item_db.gd`, `game_data.gd`

1. **shop_ui.gd** — "Reforge" sub-tab: pick two forged items of same type → preview result
2. **item_db.gd** — `reforge_items(item_a_id, item_b_id) -> Dictionary` — merges stats, combines `forged_from` arrays, applies -1 penalty, checks 3-skill cap
3. **shop_ui.gd** — Reforge confirmation shows stat diff (before → after)
4. **shop_ui.gd** — On confirm: remove both source items, add merged item, deduct gold
5. **game_data.gd** — Update `forge_skill_slots` if the merged item replaces skills

### Phase 5: Combat Integration
**Files:** `combat_manager.gd`, `game_data.gd`

1. **combat_manager.gd** — On combat start, read `forge_skill_slots` and make those skills available alongside the player's native class skill
2. **combat_manager.gd** — Skill button UI shows up to 3 forge skills + 1 native class skill (4 total? or forge skills replace native? — see Open Questions)
3. **combat_manager.gd** — Each forge skill uses its class's original skill logic (already implemented for all 9 classes)
4. **game_data.gd** — `get_active_forge_skills() -> Array[String]` helper

### Phase 6: Companion Forge Equip + Permadeath
**Files:** `game_data.gd`, `inventory_ui.gd`, `combat_manager.gd`

1. **inventory_ui.gd** — Allow equipping soulbound/forged items to companions
2. **game_data.gd** — Track which forged items are on which companion
3. **combat_manager.gd** — On companion death, if companion had a forged item → item is destroyed, show warning message
4. **UI** — Warning dialog when equipping forged item to companion: "If [companion] dies, this item is lost forever."

### Phase 7: Polish + Messaging
**Files:** various UI files

1. **Dungeon entrance UI** — "Press B to Reset Floor" only shows if floor has partial progress
2. **Floor HUD** — Small indicator showing current floor's class-tracking status (e.g. class icon + checkmark/X)
3. **Skyshard collection VFX** — Tinted crystal shard rising from boss corpse
4. **Forge VFX** — Anvil strike particles when forging
5. **Tooltip improvements** — Forged items show skill name + description in tooltip
6. **Tutorial message** — First time entering floor 1 after unlocking Steven/Mahan, brief tip: "Clear every room as one class to earn a Skyshard!"

---

## Open Questions

- [ ] **Skill respec at forge:** Can the player pay gold to re-pick which 3 skills are slotted? (Proposed: yes, 50g fee)
- [ ] **Forge skill vs native skill:** Do forge skills replace the class's native skill, or are they additive? (Proposed: additive — 1 native + up to 3 forge = 4 skills max)
- [ ] **Reforge undo:** Once two items are merged, can it be reversed? (Proposed: no — permanent, adds weight to the decision)
- [ ] **Skyshard re-earn:** If a player's forged item is lost (companion permadeath), can they re-earn the skyshard? (Proposed: no — that's the risk. They still have the skill unlocked, just lost the stat item.)
- [ ] **Full class → stat → skill mapping** for all 9 classes (fill in during implementation)
- [ ] **Forge gold costs** — base forge (100g?), reforge (150g?), skill respec (50g?) — tune during playtesting
- [ ] **Visual indicator for forged items** — special icon border, glow, or name color?
- [ ] **Can the player forge without equipping?** (Proposed: yes — item goes to inventory, skill slot is picked separately)
