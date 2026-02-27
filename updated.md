# Dungeon Break — Project State Document
*Last updated: 2026-02-27 (session 2)*

---

## What Is This Game?

**Dungeon Break** is a 3D isometric dungeon crawler built in Godot 4, ported from an earlier JavaScript/Three.js prototype that was kept but abandoned. The Godot version is the active codebase. The JS version lives at `/home/brad/Documents/dungeon-break/` and is kept only as a reference.

Core loop:
- Start in **camp** (floor 0 — a persistent overworld island with NPCs)
- Enter the **dungeon** via a portal in camp
- Explore BSP-generated floors, trigger room combat, find loot, descend
- Return to camp between runs (future: upgrades, story, NPCs)

Genre feel: Tactics + dungeon crawler. Think Final Fantasy Tactics combat on Diablo-style generated floors.

---

## Tech Stack

| Thing | Version/Detail |
|---|---|
| Engine | Godot 4 (GDScript, strict mode) |
| Voxel terrain | Zylann's `godot_voxel` addon |
| MCP integration | `godot_mcp` addon (dev tooling only) |
| 3D models | GLB files in `assets/art/entities/` |
| Enemy data | `assets/art/entities/entities.json` |
| Music/SFX | MusicManager autoload |

Note: The godot ide is actually a custom Zylann build of Godot with 'godot_voxel' baked inside, so we don't use an actual addon.

---

## Project Layout

```
project/
  dungeon_break/
    main.gd / main.tscn        ← Entry point, manages scene transitions
    game.gd / game.tscn        ← Camp scene
    dungeon.gd / dungeon.tscn  ← Dungeon scene
    combat/
      combat_manager.gd        ← FFT-style tactical combat logic
      combat_ui.gd             ← Combat overlay (tracker, log, enemy info)
      tactical_grid.gd         ← 3D tile markers on the dungeon floor
    data/
      game_data.gd             ← Autoload: all player state, stats, inventory
      enemy_db.gd              ← Autoload: loads entities.json, portrait paths
      item_db.gd               ← Autoload: item definitions, equip/use logic
      music_manager.gd         ← Autoload: background music
      graphics_manager.gd      ← Autoload: quality/graphics settings
    entities/
      entity_manager.gd        ← Autoload: spawns/despawns 3D entity GLBs
      wanderer_controller.gd   ← Camp NPC wandering logic
    generator/
      bsp_dungeon.gd           ← BSP room splitter
      dungeon_terrain_gen.gd   ← Voxel terrain carver for dungeon floors
      dungeon_stamper.gd       ← Places rooms into voxel grid
      camp_builder.gd          ← Builds camp structures (bonfire, spire, etc.)
      camp_generator.gd        ← Camp terrain shape
    player/
      player.tscn              ← Player scene (CharacterBody3D + camera)
      player_controller.gd     ← WASD + click-to-move, combat_locked bool
      isometric_camera.gd      ← Follows player; Q/E to rotate, scroll to zoom
    ui/
      game_hud.gd              ← Minimal HUD: time bar + hero panel in dungeon
      inventory_ui.gd          ← Full inventory overlay (I / TAB to open)
    world/
      day_night_cycle.gd       ← Drives sun angle + environment from GameData.world_time
  blocky_game/blocks/          ← Zylann template blocks (kept for voxel lib/textures)
  common/                      ← Zylann utility scripts (grid, util, etc.)
  assets/
    art/
      entities/                ← GLB models + entities.json + portrait images
      time/                    ← sun.png, dusk.png, moon.png for HUD clock
```

---

## Scene Flow

```
main.tscn  (always in tree)
  └─ game.tscn (Camp)  ←→  dungeon.tscn (Dungeon Floor)
```

`main.gd` owns scene transitions:
- On start → loads `game.tscn` (camp)
- Camp emits `enter_dungeon` signal → `main.gd` loads `dungeon.tscn`
- Dungeon emits `return_to_camp` → back to camp
- Dungeon emits `advance_floor` → `GameData.advance_floor()` then reload dungeon with new floor number

`EntityManager` is told to `despawn_all()` on every scene change.

---

## Autoloads (Singletons)

| Name | File | Role |
|---|---|---|
| `GameData` | `data/game_data.gd` | All player state: stats, HP, inventory, floor, gold, class |
| `EnemyDB` | `data/enemy_db.gd` | Enemy definitions, portrait path lookup |
| `ItemDB` | `data/item_db.gd` | Item creation, equipping, backpack management |
| `MusicManager` | `data/music_manager.gd` | `play_camp()`, `play_dungeon()`, etc. |
| `GraphicsManager` | `data/graphics_manager.gd` | Quality presets, display settings |
| `EntityManager` | `entities/entity_manager.gd` | GLB spawn/despawn, LOD camera |

> **Validator gotcha:** The MCP script validator cannot resolve autoloads — it reports "Identifier not found: GameData" etc. These are false positives; everything works fine at runtime. Always check `get_errors()` after validation and ignore these specific ones.

---

## Player State (GameData)

```gdscript
player_class: PlayerClass   # enum: VANGUARD, SCOUNDREL, ARCANIST, CONFESSOR,
                             #       STRIDER, MINSTREL, TEMPLAR, REANIMATOR, TINKERER
player_name: String
stat_str / stat_dex / stat_int / stat_lck: int
hp / hp_max: int
ac: int                      # base 10 + armor
gold: int
current_floor: int
torch_fuel: int              # 0–100, burns in dungeon
backpack: Array              # item dicts, max BACKPACK_SIZE (24)
hotbar: Array                # max HOTBAR_SIZE (6)
equip_weapon / equip_helm / equip_chest / equip_legs / equip_boots: Dictionary
```

HP formula: `25 + stat_str * 4`
ATK formula: `max(stat_str, stat_dex) + weapon.attack_bonus`
AC formula: `10 + all armor ac_bonus + ac_bonus_temp`
Clash roll: power maps to largest fitting die (d20/d12/d10/d8/d6/d4) + remainder as flat bonus.

---

## Classes

| Class | STR | DEX | INT | LCK | Identity |
|---|---|---|---|---|---|
| Vanguard | 5 | 2 | 1 | 2 | Tank |
| Scoundrel | 2 | 5 | 1 | 3 | DPS |
| Arcanist | 1 | 2 | 5 | 2 | Mage |
| Confessor | 1 | 2 | 4 | 3 | Healer |
| Strider | 3 | 4 | 1 | 2 | Ranger |
| Minstrel | 1 | 3 | 3 | 4 | Bard |
| Templar | 4 | 1 | 3 | 2 | Paladin |
| Reanimator | 1 | 2 | 5 | 2 | Necro |
| Tinkerer | 2 | 4 | 3 | 1 | Engineer |

---

## Combat System

### Trigger
`dungeon.gd._trigger_room_combat(room, enemies)`:
1. Creates `CombatManager` node, calls `start_combat()`
2. Creates `CombatUI` node, calls `ui.setup(manager)`
3. Locks player input (`player_controller.combat_locked = true`)

**Critical order:** `combat_started` signal fires *inside* `start_combat()`, before `ui.setup()` connects. So `_build_enemy_cards()` must be called directly in `setup()`, not from `_on_combat_started()`.

### Phases
```
IDLE → MOVE → ACT → RESOLVING → (ENEMY_THINKING) → back to MOVE for next unit → ENDED
```

### Initiative
`SPD + d6` for each unit. Stored in `_turn_order[]` as sorted indices into `_units[]`.

### Units Array
`_units[0]` = player, `_units[1..]` = enemies.
Each unit dict:
```gdscript
{
  "type": "player"/"enemy",
  "entity": Node3D,
  "grid_pos": Vector2i,
  "name": String,
  "hp": int, "hp_max": int,
  "attack": int, "defense": int,
  "speed": int, "move_range": int, "attack_range": int,
  "alive": bool,
  "has_moved": bool, "has_acted": bool,
  "entity_key": String,   # enemy DB key
  "variant": String,      # enemy variant
}
```
No `unit_idx` stored inside the dict — always use `get_units().find()` or array index.

### Ranges
- Player: move 4 tiles, attack 1 tile (melee)
- Enemy: move 3 tiles, attack 1 tile

### Tactical Grid
`tactical_grid.gd` places 3D colored tile markers:
- Blue = reachable move tiles
- Orange = enemy position
- Green = player position
- White cursor = dedicated `_cursor_mesh` (not stored in `_markers` dict — avoids a bug where clearing cursor erased blue tiles)

---

## UI Systems

### Game HUD (`game_hud.gd`)
Always visible CanvasLayer. Two modes:

**Camp mode** (default):
- Top-right: time icon + clock text + ⚙ settings button

**Dungeon mode** (`set_dungeon_mode(true)` called in `dungeon.gd._build_dungeon()`):
- Same top-right bar
- Bottom-right hero panel (248×88px): portrait, "Name · Class · Floor N", HP bar (border color reacts to HP ratio), "HP x/y  AC z  ATK w  Weapon"

Prompt label (center-bottom) shown via `show_prompt(text)` / `hide_prompt()` when player is near interactions.

### Combat UI (`combat_ui.gd`)
Overlay active only during combat. Features:

**Portrait tracker (left side):**
- Enemies listed top, player at bottom
- Each card has a 10×10 colored dot (UNIT_COLORS palette assigned sequentially; player always PLAYER_COLOR green)
- Active unit card: indented 8px right + 2px border in its assigned color
- `_set_active_card(unit_idx)` drives this each turn

**Enemy info panel (bottom-left, 312×84px):**
- Shows on enemy turn start: portrait (64×64), name, HP bar, "AC N  ATK N"
- Hidden during player turn

**Target selection cards:**
- 56×56 portrait, name, HP bar per targetable enemy
- PanelContainer with `gui_input` click handler

**Combat log:**
- Positioned above enemy panel (offset_top=-238, offset_bottom=-100)

**Turn bar:** removed; `_update_turn_bar` is a no-op stub kept for signal compatibility.

HP bar color logic: >60% green, >30% yellow, else red.

### Inventory UI (`inventory_ui.gd`)
Full-screen overlay. Toggle: `I` or `TAB`. Close: `ESC` or ✕ button.

**Three-column layout (850×550px centered panel):**

Left — Paper Doll (195px):
- Equipment slots: Head, Weapon, Chest, Legs, Boots arranged around a 72×72 portrait frame
- Each slot is a 58×58 Button with pre-created TextureRect child (shown/hidden on refresh)
- Slot borders brighten + 2px wider when filled
- Gold label at bottom

Centre — Backpack (flexible):
- 6×4 GridContainer = 24 slots (BACKPACK_SIZE)
- Click slot → select; click again or click action button → use/equip/drop
- Detail panel below grid: item name (gold), description (gray, autowrap), stats (green), action buttons

Right — Character Stats (175px):
- Player name (large), class (green), "Floor N  ◆ N gold"
- 2×2 stat grid: STR (orange), DEX (green), INT (blue), LCK (purple)
- HP bar + label, AC/ATK combat stats

**Hotkeys (when inventory closed):**
- `F` — quick-use first consumable in backpack
- `1`–`6` — quick-use backpack slot by index

---

## GDScript Strict Mode — Known Gotchas

### Dictionary.get() returns Variant
```gdscript
# BAD — triggers "Warning treated as error"
var name := item.get("name", "")

# GOOD
var name: String = item.get("name", "")
```
This applies to any dict `.get()` call assigned with `:=`.

### Preload cascade errors
If `game_hud.gd` has a compile error, `dungeon.gd` (which preloads it) will report its own "Compilation failed" — the error message will point to dungeon.gd lines, but the real problem is in game_hud.gd. **Always check the preloaded file first.**

### event.keycode is Variant
```gdscript
var kc: int = event.keycode   # explicit int required
```

### Autoload false positives in validator
MCP's `validate_script` cannot resolve autoloads (GameData, MusicManager, etc.) and reports "Identifier not found." These are runtime-only; ignore them. Only real parse/type errors matter.

---

## What Has Been Built (Completed Features)

### Core Engine
- [x] Voxel terrain (Zylann addon) — camp island + dungeon floors
- [x] BSP dungeon generation with room-to-room corridors
- [x] Scene transition system (camp ↔ dungeon ↔ advance floor)
- [x] Player: WASD movement, click-to-pathfind, isometric camera (Q/E rotate, scroll zoom)
- [x] Day/night cycle (10 real minutes = 1 full in-game day)
- [x] EntityManager for GLB spawning/despawning with LOD

### Camp
- [x] Camp island built from voxels (bonfire, spire, azure flame, dungeon portal)
- [x] NPC wanderers walking around
- [x] Portal interaction (E to enter dungeon)
- [x] Azure Flame interaction (E to refuel torch)
- [x] Starter gear given on first run

### Dungeon
- [x] BSP floor generation with voxel carving
- [x] Enemy entities spawned in rooms
- [x] Room entry triggers combat
- [x] Torch fuel ticks down while exploring
- [x] Return to camp / advance floor signals
- [x] Room size increased (72–82% of BSP chunk, inset 10–15%) for better combat visibility
- [x] Room elevation: 30% of eligible rooms raised 1–2 blocks (start/boss/bonfire/merchant/fountain always flat)
- [x] Wall-only material split (`terrain_material_wall.tres`) — log_y, stone_bricks, void_stone_bricks use separate material from floors so walls can be toggled independently
- [x] Combat wall transparency — walls fade to 8% opacity on combat start, restore on combat end (0.35s tween)

### Combat
- [x] FFT-style tactical grid combat
- [x] Initiative order (SPD + d6)
- [x] Move phase: blue tiles shown, click to move
- [x] Act phase: attack, defend actions
- [x] Clash roll damage system
- [x] Enemy AI: approach + attack
- [x] Combat ends on player win/loss
- [x] Player input locked during combat

### UI
- [x] Game HUD: time clock, hero panel in dungeon
- [x] Combat UI: portrait tracker with colored dots, active unit highlight, enemy info panel, combat log, target cards
- [x] Inventory: paper doll + 6×4 backpack grid + character stats panel
- [x] Quick-use hotkeys (F, 1–6)
- [x] Toast notifications for inventory actions

### Data Systems
- [x] GameData: full player state, class system, save/load dict
- [x] ItemDB: item creation, equipping, backpack management
- [x] EnemyDB: entities.json loading, portrait paths
- [x] 9 player classes with distinct base stats

---

## Planned / Not Yet Built

### Camp NPCs (Story)
The camp is meant to be populated with named characters:
- **Joe** — soul broker, retired adventurer, first NPC met. "You look new."
- **Mira** — cartographer, self-mapping mini-map mechanic
- **Old Pell** — healer, tends the Azure Flame. "A necromancer is just a cleric that arrived a bit too late." (no elaboration)
- Tutorial quest: find the duck chest (duck.glb) surrounded by enemies

### Visual Novel Cutscenes
Gothic fantasy painted art panels + text below, click to advance. 3–5 scene panels + character busts reused across dialogue beats.

### Companion System
- Ghost enemies on death have a chance to become companions
- `spawnPet()` system (exists in JS version, not yet ported to Godot)
- Tints by class: Necromancer = pale red, Cleric = pale gold, others = green

### Class-Specific Mechanics
- **Reanimator**: companions cap at player level; shades auto-attack at start of enemy phase
- **Confessor**: Exorcism skill (3-unit blast, damage = ghost HP ÷ targets, heals player 25%)

### Helix Zone (Floor Transition)
- CA-generated spiral descent zone (visual descent between floors)
- Currently just a scene reload. JS version had a fade veil with "FLOOR N / The Depths Await"

### Inventory
- True drag-and-drop (currently click-to-select + click-to-equip)
- Hotbar slot management UI

### Save System
- `GameData.to_save_dict()` / `from_save_dict()` exists but no file I/O wired yet

---

## Asset Notes

- Enemy portraits: `assets/art/entities/*.jpeg` / `*.png`
- `entities.json`: each enemy has `sprite_portrait` field pointing to filename
- `EnemyDB.get_portrait_path(key)` returns the full `res://` path
- Player portrait: TBD (currently placeholder frame in inventory)
- Time icons: `assets/art/time/sun.png`, `dusk.png`, `moon.png`

---

## Development Notes

- **JS prototype location:** `/home/brad/Documents/dungeon-break/` — kept as reference, not active
- **Godot project location:** `/home/brad/Documents/Godot/DungeonBreak/project/`
- **Why Godot?** The JS version kept breaking under complexity (3D rendering, combat state, UI all fighting each other). Godot gives proper scene tree, signals, and typed GDScript.
- **Zylann template cleanup:** The blocky_terrain, smooth_terrain, multipass_generator, and grid_pathfinding template folders were deleted. Kept: `blocky_game/blocks/` (for voxel library/textures) and `common/` (utility scripts). `addons/` kept in full.
- **Wall material split:** `blocky_game/blocks/terrain_material_wall.tres` is a separate StandardMaterial3D (same texture atlas as `terrain_material.tres`) assigned only to the three dungeon wall block types (log_y, stone_bricks, void_stone_bricks) in `voxel_library.tres`. This gives walls their own mesh surface so `dungeon.gd` can fade them independently during combat via `_set_wall_combat_mode()`. Floor blocks (planks, ruin_stone, void_stone, dirt, stone, etc.) continue using the original `terrain_material.tres`.
