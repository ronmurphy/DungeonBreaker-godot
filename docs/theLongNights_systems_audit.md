# The Long Nights → DungeonBreaker: Systems Audit & Portability Report

> Generated from full codebase analysis of `/home/brad/Documents/Godot/theLongNights-godot/project/`

---

## 1. Magic Weapon Effects & Enchantments (Skyshard Power System)

### Overview
The original game has a **Skyshard Power System** — rare materials ("skyshards") dropped from blood moon sky ruin kills are infused into items to grant powers. There are two power categories:

- **HOTBAR powers** (active, triggered on attack/hit) — managed in `Powers.gd`
- **EQUIP powers** (passive buffs) — checked directly in `character_controller.gd`

### Key Files
| File | Lines | Purpose |
|------|-------|---------|
| `long_nights/Powers.gd` | 1–851 | All HOTBAR power implementations |
| `blocky_game/player/inventory_item.gd` | 1–70 | Power storage on items |
| `blocky_game/player/character_controller.gd` | 1175–1550 | Combat + EQUIP power integration |
| `blocky_game/items/fire_staff/fire_staff.gd` | full | Meteor-spawning fire weapon |
| `blocky_game/items/ice_bow/ice_bow.gd` | full | Ice arrow projectile weapon |
| `blocky_game/items/blade_of_pursuit/blade_of_pursuit.gd` | full | Chain-attacking magical blade |
| `blocky_game/items/ring_of_thorns/ring_of_thorns.gd` | full | Auto-attacking orbiting thorns |
| `blocky_game/items/ring_of_teleportation/ring_of_teleportation.gd` | full | Teleport to cursor |
| `blocky_game/items/blood_pendant/blood_pendant.gd` | full | Blood moon damage amplifier |

### HOTBAR Powers (Active — `Powers.gd`)

```gdscript
func execute_hotbar_power(power_name: String, context: Dictionary) -> void:
    match power_name:
        "meteor_strike":    # Spawns 5 mini-meteors in X pattern (AOE)
        "lightning_chain":  # Chains damage to 3 nearby enemies (5-block radius)
        "life_steal":       # Heals 25% of damage dealt
        "ice_burst":        # Freezes enemies in 3-block radius + ice terrain
        "poison_cloud":     # 5s lingering DOT cloud (5 dmg/0.5s tick, 3-block radius)
        "knife_volley":     # Launches 3 knives at enemies within 10 blocks
        "wind_dash":        # 3-second speed boost on hit
        "return":           # Projectile retrieval after hitting entity
```

**Context dict passed to powers:**
```gdscript
{
    entity: Node,           # Entity that was hit
    position: Vector3,      # Impact position
    stack_count: int,       # Item stack count (scales damage)
    damage_dealt: int,      # Base damage that was dealt
    attacker: Node          # Who triggered the attack
}
```

### EQUIP Powers (Passive — `character_controller.gd`)

| Power | Effect | Where Applied |
|-------|--------|--------------|
| `stone_skin` | +50% defense multiplier | `character_controller.gd:1196` |
| `moon_jump` | 3× jump multiplier | `character_controller.gd:451` |
| `flame_aura` | 5 dmg/tick to enemies within 4 blocks | `character_controller.gd:1266` |
| `glide` | Slow fall + turning | `character_controller.gd:405–430` |
| `return` | Projectile recovery | Passive flag |

### Power Harmonization (Multi-Power Fusion)

Items can hold **multiple** powers via `skyshard_powers` array:
```gdscript
# inventory_item.gd
var skyshard_powers := []  # [{"name": "glide", "strength": 1.0}, ...]
# strength: 1.0 = Major (100%), 0.6 = Minor (60%)
```

### Class-Restricted Items

Several items have `ALLOWED_ROLES` restrictions:
- **Blade of Pursuit**: `["wizard", "rogue", "elf"]`
- **Ring of Thorns**: `["wizard", "healer", "rogue", "elf"]` (all except Tank)
- **Blood Pendant**: All classes

### Elemental Weapons

| Weapon | Element | Behavior |
|--------|---------|----------|
| Fire Staff | Fire | Raycasts to target, spawns meteor from sky with fire trail + explosion |
| Ice Bow | Ice | Fires ice arrow projectile with ice terrain + freeze damage |
| Blade of Pursuit | Arcane | Flying blade chains between 5 enemies (10 with power), auto-returns |
| Ring of Thorns | Nature | 3 orbiting thorn projectiles, auto-fire at enemies every 2s |

### Portability Assessment: ⭐⭐⭐⭐⭐ (Excellent)

The entire power system is **highly portable**:
- `Powers.gd` is an autoload singleton — drop-in compatible
- Power context is a simple dictionary — no voxel-terrain dependencies in the logic
- `inventory_item.gd` power storage system works with any item type
- Class restrictions via `ALLOWED_ROLES` constant — trivially adaptable
- The only voxel-specific code is `ice_burst` creating ice terrain blocks (replace with tilemap or skip)

**Recommendation:** Port `Powers.gd`, `inventory_item.gd`, and the power-checking pattern from `character_controller.gd` almost verbatim.

---

## 2. Push Block / Puzzle Mechanics

### Overview
A complete **Sokoban-style push block puzzle system** with:
- Physics-based push blocks that slide on impact
- Goal detection (push onto "test" blocks)
- Reward spawning (teleport stones appear when puzzle solved)
- Reset mechanics for failed attempts
- Sky island puzzles with fall-off-edge detection
- A dedicated "Gauntlet of Strength" item for manual block carrying

### Key Files
| File | Lines | Purpose |
|------|-------|---------|
| `blocky_game/PushBlockManager.gd` | 1–309 | Scans for push_block voxels, spawns entities, save/load |
| `blocky_game/entities/push_block.gd` | 1–445 | Push block physics, goals, rewards |
| `blocky_game/items/gauntlet_of_strength/gauntlet_of_strength.gd` | 1–432 | Manual block pickup/carry/place |

### Push Block Entity (`push_block.gd`)

**Key properties:**
```gdscript
@export var friction := 0.92        # Friction coefficient
@export var mass := 1.0             # Mass affects impulse transfer
@export var min_velocity := 0.05    # Stop threshold
@export var gravity := 20.0         # 0 = zero-G puzzle rooms

var spawn_position := Vector3.ZERO  # For reset
var puzzle_room_id := ""            # Room identifier
var is_island_puzzle := false       # Sky island variant
var island_base_y := 0.0            # Fall detection baseline
var fall_threshold := 20.0          # Respawn if fall this far
var teleport_stone_pos := Vector3i  # Reward teleport position
```

**Key functions:**
```gdscript
func apply_impulse(impulse: Vector3)     # Called by projectiles to push
func reset_to_spawn()                     # Reset for retry
func _check_goal_reached()                # Detects landing on "test" block
func _on_goal_reached()                   # Turns green, spawns teleport stone
func _spawn_teleport_stone_reward()       # Places reward voxel
```

**Physics loop** (`_physics_process`):
- Applies gravity (configurable — zero-G rooms possible)
- Applies friction to horizontal velocity only
- Uses `VoxelBoxMover` for terrain collision
- Checks goal block below after each move

### PushBlockManager (`PushBlockManager.gd`)

Manages lifecycle:
- Scans 1% of blocks around player each second for `push_block` voxel IDs
- Auto-detects puzzle rooms by proximity to "test" blocks
- Converts entities back to voxels before save
- Supports both auto-detected and manually configured puzzles

```gdscript
func spawn_puzzle_block(world_pos, has_gravity, room_id) -> Node3D  # Manual spawn
func convert_entities_to_voxels_for_save()  # Critical for persistence
func create_push_block_at(world_pos)        # Manual creation API
```

### Gauntlet of Strength

A tool item that lets players manually pick up, carry, and place push blocks:
- Raycasts to find blocks within 3 units
- Picked up blocks become invisible (carried in "hand")
- Place with second click, snapped to voxel grid
- Validates placement position is air

### Portability Assessment: ⭐⭐⭐⭐ (Very Good)

**Highly portable with modifications:**
- The puzzle logic (impulse, friction, goal detection, rewards) is completely reusable
- Replace `VoxelBoxMover` with Godot's standard `CharacterBody3D` or grid-based collision
- Replace voxel goal detection with area triggers or tilemap checks
- The gravity toggle (zero-G rooms) is a great mechanic for dungeon variety
- `PushBlockManager` scanning pattern needs rework for non-voxel world but the entity pattern is clean

**Recommendation:** Port `push_block.gd` physics and reward logic. Replace voxel-specific collision with area-based detection. The Gauntlet of Strength carry mechanic could become a dungeon key item.

---

## 3. Skill Enhancement From Items

### Overview
Items modify player capabilities through **four distinct systems**:

### A. Role-Based Stats (`PlayerData.gd`)

Base stats differ by role (class):
```gdscript
"tank":   max_hp=150, defense=20, attack_bonus=5,  luck=0
"wizard": max_hp=80,  defense=5,  attack_bonus=15, luck=0, mana=100
"healer": max_hp=100, defense=10, attack_bonus=0,  luck=0, mana=100
"rogue":  max_hp=90,  defense=8,  attack_bonus=20, luck=0
```

### B. Permanent Potion Buffs (`PlayerData.gd:22–31`)

Consumable potions permanently increase stats:
```gdscript
var bonus_max_hp: int = 0           # From HP potions
var bonus_defense: int = 0          # From DEF potions
var bonus_attack: int = 0           # From ATK potions
var bonus_luck: int = 0             # From LUCK potions
```

**Golden Potions** (rare blood moon rewards) grant special bonuses:
```gdscript
var bonus_speed_multiplier: float = 0.0   # Movement speed
var bonus_regen_multiplier: float = 1.0   # HP regen rate (3× = 3× faster)
var bonus_max_mana: int = 0               # Extra mana for casters
var permanent_glide: bool = false          # Permanent glide without equipment
```

### C. Equipment Passive Effects

**Equipped items check powers every frame/action:**
- `stone_skin` → +50% defense
- `moon_jump` → 3× jump height
- `flame_aura` → AOE fire damage aura (5 dmg, 4-block radius)
- `glide` → Slow fall + air control
- `blood_pendant` → +50% damage during blood moons

**Stack bonuses:** Weapon stack count (`inv_item.count`) directly scales damage on projectiles:
```gdscript
# fire_staff.gd
var stack_count = inv_item_or_count.count  # More stacks = more damage
```

### D. Cooking Buffs (`recipes_database.json`)

Cooked food provides healing and potential buffs:
```json
{
    "effects": {
        "healing": 15,
        "buff_type": null,
        "buff_amount": 0,
        "buff_duration": 0
    }
}
```
The buff system is defined but only healing is currently implemented. The data structure supports timed buffs.

### Companion Equipment Table (`CompanionManager.gd:620+`)

Each race/gender/role combo gets predetermined starting gear:
```gdscript
"elf_female_wizard": {
    "weapon_id": 4,        # fire_staff
    "weapon_count": 1,
    "weapon_power": "",
    "accessory_id": 2,     # wind_walker_boots
    "accessory_count": 1,
    "accessory_power": "glide"
}
```

### Portability Assessment: ⭐⭐⭐⭐⭐ (Excellent)

All systems are pure data/logic with no engine-specific dependencies:
- `PlayerData.gd` is a clean autoload singleton
- Potion buff system uses simple integer math
- Equipment power checking is a string-match pattern
- Stack-count damage scaling is a single line
- The buff_type/duration framework in recipes is ready for expansion in DungeonBreaker

**Recommendation:** Port `PlayerData.gd`, `inventory_item.gd`, and `CompanionManager.gd` stat/equipment systems directly.

---

## 4. Combat / Encounter System

### Overview
The original game uses **real-time action combat** in a 3D voxel world with:
- d20-style hit/miss rolls
- Defense-based damage reduction
- Tiered enemy progression
- Blood moon intensification events
- Depth-based biome enemy distribution

### Hit Resolution (`entity_base.gd:37`, `character_controller.gd:1175`)

```gdscript
static func roll_to_hit(attacker_luck: int = 0, defender_luck: int = 0) -> bool:
    const LUCK_CAP = 5
    var roll = randi() % 20 + 1          # Roll d20
    var hit_threshold = 10 - attacker_luck + defender_luck
    return roll >= hit_threshold           # Base 50% hit chance
```

- **Base hit threshold:** 10 (50% chance on d20)
- **Luck modifies threshold:** Each luck point = +5% hit chance, capped at ±5 (30%–80% range)

### Damage Formula (`entity_base.gd:80`)

```gdscript
var actual_damage = max(1, amount - int(amount * (defense / 100.0)))
```
- Defense acts as percentage damage reduction (defense=20 → 20% reduction)
- Minimum damage is always 1
- **Stone Skin** power multiplies defense by 1.5× before calculation

### Entity Data Structure (`entities.json`)

```json
{
    "name": "Goblin Grunt",
    "type": "enemy",
    "tier": 1,
    "hp": 65,
    "attack": 6,
    "defense": 21,
    "speed": 4,
    "abilities": ["Club Smash", "Cowardly Retreat"],
    "description": "Small green warrior with a pineapple club.",
    "craftable": true,
    "craft_materials": { "dead_wood": 3, "stone": 2 }
}
```

Enemies span 5 tiers. Sample tier spread:
- **Tier 1:** Rat (45 HP), Goblin Grunt (65 HP), Troglodyte (80 HP)
- **Tier 2:** Angry Ghost (65 HP), Zombie Crawler (95 HP), Skeleton Archer
- **Tier 3:** Mechanical Spider, Iron Golem, Skeleton Mage
- **Tier 4:** Hunting Construct, Abyss Golem
- **Tier 5:** Lich Lord Morteus, Nightmare variants (Azure/Emerald/Golden/Obsidian/Purple/Red)

### Loot Drop System (`entity_base.gd:295+`)

**Tiered pouch drops:**
```gdscript
# 20% chance on ANY enemy kill
# Pouch tier weighted by enemy tier:
# Tier 1 enemy: [100, 0, 0, 0, 0]       # only tier 1 pouches
# Tier 5 enemy: [30, 25, 25, 15, 5]      # 5% legendary pouch chance
```

**Blood moon sky ruin bonus:** Always drops 1 Skyshard + 25% chance Portal Compass

### HP Regen (`entity_base.gd:33`)
```gdscript
const REGEN_INTERVAL: float = 180.0  # 1 HP per 3 minutes (base)
```

### Death Effects (Quality-Scaled)
- **Low:** Particle puff (20 particles, 0.5s)
- **Medium:** Dissolve shader (0.8s)
- **High:** Dissolve shader (1.5s, slower wave)

### Projectile Types
Extensive projectile library in `blocky_game/projectiles/`:
| Projectile | Source | Behavior |
|-----------|--------|----------|
| `meteor.gd` | Fire Staff | Falls from sky, AOE explosion |
| `ice_arrow.gd` | Ice Bow | Freezes terrain + enemies |
| `fireball.gd` | Entities | Standard ranged attack |
| `death_bolt.gd` | Lich Lord | Necrotic damage |
| `flying_blade.gd` | Blade of Pursuit | Chains between enemies |
| `thorn.gd` | Ring of Thorns | Orbiting auto-attack |
| `boomerang.gd` | Boomerang | Curved flight, auto-return |
| `throwing_knife.gd` | Throwing Knives | Direct shot or spiral |
| `goblin_bomb.gd` | Goblin Bomb Bard | Explosive lobbed projectile |
| `scatter_shot.gd` | Enemies | Shotgun-style spread |
| `acid_spit.gd` | Enemies | Acid projectile |
| `void_bolt.gd` | Enemies | Void damage |

### Portability Assessment: ⭐⭐⭐⭐ (Very Good)

- The d20 hit system, damage formula, and tier system are completely engine-agnostic
- `entities.json` data-driven design means easy porting — just load the JSON
- Loot drop tables with weighted tiers are pure math
- Projectile systems use Godot nodes but the *logic* (chain targeting, AOE radius, damage falloff) is portable
- Replace real-time combat with turn-based by keeping the same formulas and adding turn order

**Recommendation:** Port `entity_base.gd` combat math (hit rolls, damage formula, loot tables), `entities.json` data, and the power-on-hit trigger system. The d20 system maps perfectly to dungeon crawler combat.

---

## 5. Enemy Spawning System

### Key File: `long_nights/EnemySpawner.gd` (678 lines)

### Spawn Rules

| Context | Rate | Behavior |
|---------|------|----------|
| Day (surface) | 15% chance every 2 min | Light spawning |
| Night (surface) | Every 30–60s | Normal spawning |
| Blood Moon | Every 10–20s | Intense + stat buffs |
| Cave (Y < -10) | Every 45–90s | Biome-themed enemies |
| Undervoid areas | 2× multiplier | Proximity-based boost |

### Week-Based Tier Progression
```gdscript
# Week 1: Tier 1 only
# Week 2: Tiers 1-2
# ...
# Week 5+: Tiers 1-5
max_unlocked_tier = min(TimeManager.current_week, 5)
```

### Blood Moon Scaling
```gdscript
# Enemies per wave = 1 × week_number (capped at 10)
spawn_count = 1 * min(TimeManager.current_week, 10)

# Blood moon stat buffs: +10% per tier
entity.max_hp = int(entity.max_hp * (1.0 + tier * 0.10))
entity.attack_damage = int(entity.attack_damage * (1.0 + tier * 0.10))
entity.defense = int(entity.defense * (1.0 + tier * 0.10))
```

### Depth-Based Biome Enemies
```
Y = -10 to -150:   Goblin Tunnels    → goblin_grunt, bomb_bard, shaman, troglodyte
Y = -150 to -300:  Undead Crypts     → zombie_crawler, brute, skeleton_archer/mage, wraith
Y = -300 to -400:  Mechanical Warrens → mechanical_spider, hunting_construct, iron/rust_golem
Y = -400 to -512:  The Abyss         → abyss_golem, water_elemental, kraken_spawn, alien_hunter
```
70% biome-themed, 30% random from tier pool for variety.

### Combat Ruin Spawning (`EnemySpawner.gd:370+`)
Ruins scale enemy count by area:
- Small (100 sq blocks): 3–5 enemies (mostly T1)
- Medium (400 sq): 8–12 enemies (T1–T2, maybe T3)
- Large (900+ sq): 15–25 enemies (tiered defense layout)

**Layout pattern:** Tier 3 at center, Tier 2 mid-range, Tier 1 perimeter.

### Portability Assessment: ⭐⭐⭐⭐⭐ (Excellent)

The spawning logic is pure game design math with no engine dependencies:
- Tier unlocking by week → dungeon floor unlocking
- Depth biomes → dungeon zone themes
- Combat ruin scaling → room difficulty scaling
- Blood moon buff percentages → floor modifier events

**Recommendation:** Map depth biomes to dungeon floors, week progression to dungeon depth, and blood moon to special event floors.

---

## 6. Hunting System

### Key File: `long_nights/HuntingSystem.gd` (413 lines)

Send companion on timed hunts. They return with race-weighted loot.

### Mechanics
```gdscript
func start_hunt(companion: Node, duration_hours: int) -> bool
# Companion disappears, finds items every in-game hour (80% discovery chance)
# 1-3 items per hour, weighted by companion race
# Cancel = 50% loot loss
```

### Race-Weighted Loot Table
```gdscript
"berries": {"race_weight": {"human": 1.2, "elf": 3.0, "dwarf": 0.5, "goblin": 0.8}}
"rabbit":  {"race_weight": {"human": 1.5, "elf": 1.0, "dwarf": 2.0, "goblin": 1.0}}
"iron_ore": {"race_weight": {"human": 0.0, "elf": 0.0, "dwarf": 0.0, "goblin": 2.0}}
# Only goblins find ore materials
```

### Portability Assessment: ⭐⭐⭐⭐ (Very Good)

Pure timer + weighted random system. Replace "in-game hours" with "dungeon turns" or real-time and it works directly.

---

## 7. Companion System

### Key File: `long_nights/CompanionManager.gd` (709 lines)

### Features
- **Role complementarity:** Player Tank → Companion Healer, Wizard → Tank, Healer → Rogue, Rogue → Wizard
- **Race diversity:** Companion always different race from player
- **Multi-companion roster** with swap system, individual equipment, XP/levels
- **Equipment table:** 32 race×gender×role combinations with preset gear
- **Behavior modes:** normal, guard, hunting
- **Persistent save/load** with both legacy single-companion and roster formats

### CompanionData Structure
```gdscript
class CompanionData:
    var companion_name: String
    var race: String          # human, elf, dwarf, goblin, ghost
    var gender: String
    var role: String          # healer, tank, rogue, wizard
    var equipped_weapon_id: int
    var equipped_weapon_count: int
    var equipped_weapon_power: String
    var equipped_accessory_id: int
    var equipped_accessory_power: String
    var active_title: String
    var title_emoji: String
    var behavior_mode: String
    var is_active: bool
    var level: int
    var xp: int
```

### Portability Assessment: ⭐⭐⭐⭐⭐ (Excellent)

The roster system is completely data-driven and engine-agnostic. Perfect for a dungeon party system.

---

## 8. Fishing System

### Key File: `blocky_game/fishing/FishingMinigame.gd` (325 lines)

### Mechanics
1. **Wait phase:** Random bite time (3–25 seconds)
2. **Bar minigame:** Fill bar, click when in target zone
   - 3 successes needed, 3 failures = fish escapes
   - Target zone shrinks (40% → 15%) each success
   - Bar fill speed increases (0.8 → 0.6 → 0.4)
3. **Reward:** Fish item added to inventory

### Portability Assessment: ⭐⭐⭐ (Good)

Self-contained minigame. Would need UI rework for DungeonBreaker's context (fishing room? fountain puzzle?) but the timer + reflexes mechanic is reusable.

---

## 9. Day/Night Cycle & Seasonal System

### DayNightCycle.gd (222 lines)
- Hour-based sun rotation (6am sunrise, 12pm overhead, 6pm sunset)
- Sky/light color transitions (night → dawn → day → dusk → bloodmoon)
- Underground override (caves always show night visuals)
- Fog system (thicker at night, blood-red during blood moon)

### SeasonalTextureSystem.gd (286 lines)
- 4 seasons (spring/summer/autumn/winter), 90 days each
- Dynamically swaps terrain texture tiles on season change
- JSON-configured: `seasonal_textures.json` maps block names to atlas coordinates
- Updates all terrain materials in-place for efficiency

### WinterIceSystem.gd
- Converts water blocks to ice blocks in winter
- Tracks frozen positions for thaw in spring

### Portability Assessment: ⭐⭐⭐ (Good)

The time/season framework is portable but the texture-swapping is voxel-specific. For DungeonBreaker:
- **Day/night → dungeon floor lighting themes**
- **Seasons → dungeon modifier events** (frozen floor, poison season, etc.)
- **Blood moon → special event floors** with buffed enemies

---

## 10. Additional Interesting Mechanics

### A. Cooking System (`blocky_game/cooking/recipes.gd`)
- JSON-driven recipe database with ingredient matching
- Order-independent ingredient comparison
- Effects framework: `{healing, buff_type, buff_amount, buff_duration}`
- 13+ recipes from raw materials to complex multi-ingredient meals

**Portability: ⭐⭐⭐⭐⭐** — Pure data + logic, drop-in ready for dungeon crafting.

### B. Teleport System (`blocky_game/player/teleport_system.gd`)
- Teleport stones placed in world as fast-travel points
- Ring of Teleportation for cursor-targeted teleportation with 30s cooldown

### C. Ruin/Dungeon Generation (`blocky_game/ruins/`)
- `RuinLibrary.gd`, `RuinRegistry.gd`, `RuinSpawner.gd` — procedural ruin placement
- `UndervoidEntranceGenerator.gd` — underground entrance generation
- Combat ruins with scaled enemy placement (area-based)
- Sky ruins at Y > 3000 with flying enemy variants

### D. Gravity Reduction System (`character_controller.gd:1160`)
```gdscript
# Gravity decreases the deeper underground the player goes
# Every 100 blocks down: Reduce by 0.1
# Y=-500: Gravity = 9.3 (noticeably lighter)
```
A lore-driven mechanic — Sky Ruins were gravity generators. Could be a dungeon floor modifier.

### E. Golden Potion Choice System
- Blood moon performance rewards give rare "Golden Potions"
- Player chooses from special buffs: speed boost, regen multiplier, extra mana, permanent glide
- Can apply to self OR companion

### F. Tiered Loot Pouches
- 5 tiers of loot pouches dropped by enemies
- Each tier has weighted random contents
- Mystery pouches from shops scale with week number

### G. Graphics Quality System
- Three quality profiles (low/medium/high)
- Death effects, particle counts, and fog adapt to profile
- Meteor trail intervals scale with quality

---

## Summary: Top Systems to Port

| Priority | System | Effort | Value |
|----------|--------|--------|-------|
| 🔴 HIGH | Skyshard Power System (Powers.gd + inventory_item.gd) | Low | Entire enchantment/ability framework |
| 🔴 HIGH | Combat Math (d20 rolls + damage formula + tiered enemies) | Low | Core combat engine |
| 🔴 HIGH | Entity Data System (entities.json + entity_base.gd) | Low | Data-driven enemy design |
| 🔴 HIGH | Enemy Tier Progression (week → floor, biome → zone) | Low | Difficulty scaling |
| 🟡 MED | Push Block Puzzles (push_block.gd physics + goals) | Medium | Dungeon puzzle variety |
| 🟡 MED | Companion Roster System (CompanionManager.gd) | Medium | Party management |
| 🟡 MED | Item Stat Enhancement (PlayerData bonuses + potions) | Low | Progression depth |
| 🟡 MED | Cooking/Crafting (recipes.gd + JSON database) | Low | Crafting system |
| 🟢 LOW | Hunting System (race-weighted loot) | Low | Side activity |
| 🟢 LOW | Fishing Minigame | Medium | Side activity |
| 🟢 LOW | Seasonal/Time Effects | Medium | Atmosphere |

**Total reusable code: ~5,000+ lines of game logic** that translates directly to a dungeon crawler context.
