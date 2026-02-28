# Dungeon Break — Project State Document
*Last updated: 2026-02-28 (session 4)*

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

## Dungeon Room Types

| Type | State | Elevation | Notes |
|---|---|---|---|
| `start` | cleared | flat | Shrine marker (GLASS block), player spawns here |
| `boss` | uncleared | flat or `floor_height=3` if upper room | Red light, void-stone pillars, floor portal (enabled after boss dies) |
| `bonfire` | cleared | flat | Safe rest area |
| `merchant` | cleared | flat | Shop (not yet implemented) |
| `fountain` | cleared | flat | Healing fountain (not yet implemented) |
| `trap` | uncleared | varies | Trap room |
| `alchemy` | cleared | varies | Alchemy room |
| `locked` | uncleared | varies | Needs a key (not yet implemented) |
| `vault` | cleared | `floor_height=3` | Decoy elevated room; chest + gold ore flanking + warm golden light; rewards exploration without combat |
| `normal` | uncleared | varies | Standard enemy room |

**Upper room selection:** `_select_upper_rooms()` runs after BSP placement. 2 upper rooms on floors < 12 rooms, 3 on larger floors. Picks far-edge rooms (outer 25% of smaller dimension) sorted by edge score. Marked `is_upper = true` with `floor_height = WALL_HEIGHT (3)`. Boss prefers these; leftover upper rooms become `vault`.

**Staircase generation:** `_build_staircases()` places stair blocks in corridor tiles adjacent to elevated rooms. elev=1: no stairs. elev=2: 1 stair tile (Y=1 in adjacent corridor). elev=3: 2 stair tiles — adjacent tile Y=2, next tile out Y=1. Solid fill-blocks placed below each step so stairs don't float.

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

`setup_room()` receives the room's `floor_height` so tile markers are placed at the correct world Y.

### Combat Camera (`isometric_camera.gd`)
On combat start (`set_combat_mode(true)`):
- Saves current `pitch_degrees` and `distance`
- Snaps pitch to 40° (good overhead angle for tactical grid)
- Tweens `distance` → `COMBAT_DISTANCE = 18.0` over 0.45s (cubic ease-in-out)
- Disables mouse-scroll zoom and R/T pitch keys

On combat end (`set_combat_mode(false)`):
- Restores saved `pitch_degrees` immediately
- Zoom-out is **deferred**: `dungeon.gd` calls `camera.restore_zoom()` inside the wall-fade tween callback, after walls are fully opaque again (0.6s cubic ease-in-out back to pre-combat distance)

Q/E yaw rotation: snaps `_current_yaw` immediately (not just `_target_yaw`) so frustum culling is correct mid-tween.

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
- [x] Room elevation: 30% of eligible rooms raised 1–2 blocks; start/bonfire/merchant/fountain always flat
- [x] Upper rooms: 2–3 far-edge rooms per floor marked `is_upper = true` with `floor_height = 3` (WALL_HEIGHT); boss prefers these, remaining upper rooms become `vault` decoy rooms
- [x] Vault room type: decoy elevated room (chest + gold ore flanking + warm golden light); `state = "cleared"` so no combat, rewards exploration
- [x] Multi-step staircases: elev=2 → 1 stair step; elev=3 → 2 stair steps with solid fill-block support below each (no floating stairs)
- [x] Boss room keeps its elevation when it's an upper room; decorations (pillars, portal, light) placed relative to `floor_y`
- [x] Wall-only material split (`terrain_material_wall.tres`) — log_y, stone_bricks, void_stone_bricks use separate material from floors so walls can be toggled independently
- [x] Combat wall transparency — walls fade to 8% opacity on combat start, restore on combat end (0.35s tween); material restored to TRANSPARENCY_DISABLED after fade-out completes
- [x] Dungeon darkness — DirectionalLight3D killed (energy 0.0) at build time; ambient set to 0.05; rooms start with all lights hidden (`visible = false`, grouped as `room_lights_N`)
- [x] Room light reveal — player entering a room for the first time enables its light group; start room pre-revealed; rooms stay lit once visited
- [x] Player torch — OmniLight3D parented to player; range 1.5→10, energy 0.15→1.8 lerped from `torch_fuel` (0–100); burns at 0.15/sec while exploring (paused during combat)
- [x] Combat ambient boost — tweens ambient 0.05→0.35 on combat start (alongside wall fade), back to 0.05 on combat end

### Combat
- [x] FFT-style tactical grid combat
- [x] Initiative order (SPD + d6)
- [x] Move phase: blue tiles shown, click to move
- [x] Act phase: attack, defend, counter, guts, wait, flee actions
- [x] Clash roll damage system
- [x] Enemy AI: approach + attack
- [x] Combat ends on player win/loss
- [x] Player input locked during combat
- [x] Tactical grid floor height fix — `setup_room()` now receives correct `floor_height` (was always 0)
- [x] Combat camera: on combat start, pitch snaps to 40° and camera zooms to distance 18 (0.45s cubic tween); scroll/pitch keys (R/T) locked; Q/E yaw snaps immediately for correct frustum culling
- [x] Zoom restore: after combat ends, zoom-out (0.6s cubic tween) is deferred until after the wall-opacity fade completes so the reveal feels intentional

**Tactical Grid Highlights:**
- Blue = move range, Orange = enemy, Green = player, White cursor = dedicated `_cursor_mesh` (not in `_markers` dict)
- Teal diamond = ranged weapon attack zone (replaces red for ranged weapons, `COLOR_RANGED_ZONE`)
- Bright cyan = active projectile flight path (`COLOR_RANGED_PATH`) — shown on launch, cleared when projectile lands
- Boomerang path tiles use same Bezier parameters as the visual arc, sampling both outbound + return arcs

**Combat FX System (`combat_manager.gd`):**
- Screen shake: `isometric_camera.gd:shake(trauma)` — trauma-decay quadratic falloff
- Impact sprites: Sprite3D (slash/spark) scale-up + fade-out (0.26s); secondary spark burst offset randomly
- Slash shader sweep: `slash_effect.gdshader` — billboarded QuadMesh, `blend_add + unshaded`, scrolling UV mask using slash sprite, `fade` uniform for clean fade-out via `tween_method`; layered on every slash-type impact
- Floating damage numbers: Label3D rises 1.8m + fades over 0.65s (delayed 0.22s)
- Guts burst: two expanding magic circles + 6-way star spray
- SFX: `Craft.ogg` = hit, `Select.ogg` = miss/dodge, `Fire.ogg` = guts unleash (pitch-varied)

**Ranged Combat:**
- `attack_range` = `PLAYER_ATTACK_RANGE(1) + equip_weapon.range_bonus`
- Crossbow (range 3): bolt sprite, 0.20s travel
- Fire Staff (range 4): fireball sprite, 0.28s travel + AoE splash on land
- Ice Bow (range 4): frost bolt, 0.22s travel + freeze on land
- Boomerang (range 3): 3D V-shaped mesh, two BoxMesh arms, OmniLight blue glow; Bezier outbound arc (LEFT) 0.40s → `on_land` callback → return arc (RIGHT) 0.32s; tween owned by `boom` node (survives combat_manager cleanup)
- Throwing Knives (range 3): 3 silver BoxMesh knives in sequence (0/90/180ms delay, 180ms each); pierce mechanic hits all enemies on Bresenham line for half damage

**Special Weapon Mechanics:**
- **Ice Bow**: `on_land` triggers `_fx_ice_impact()` (8 BoxMesh shards ring + blue OmniLight) + sets `target["frozen_turns"] = 1`; frozen enemy's next `_start_enemy_turn()` skips AI entirely, shows "FROZEN!" float text, decrements counter
- **Fire Staff**: `on_land` triggers `_fx_fire_impact()` (expanding SphereMesh + 8 ember sparks + orange OmniLight) + loops `_units` for Manhattan dist ≤ 1, applies `dmg/2` to each adjacent unit
- **Throwing Knives**: 3 knives via `_fx_throwing_knives()`; pierce in `on_land` callback — Bresenham line, half damage to non-primary enemies on path
- **Boomerang**: No special mechanic; visual only (arc flight, blue glow)

**Projectile Robustness (session 4 fix):**
- All projectile meshes own their own tweens (`node.create_tween()` not `self.create_tween()`) so they survive combat_manager being freed after combat ends
- Each projectile has a fallback `get_tree().create_timer()` that frees the mesh and fires `on_land` if the tween is interrupted mid-flight
- `landed` bool guard in `_fx_projectile()` prevents `on_land` firing twice

**Key combat_manager.gd signal/callback order:**
- `combat_started` fires inside `start_combat()` before `ui.setup()` connects → `_build_enemy_cards()` must be called directly in `setup()`, not from `_on_combat_started()`
- `impact_cb` for ranged attacks owns path-tile clearing, FX, and special-effect logic; fires when projectile tween completes
- `_advance_turn()` called 0.5s after `player_act()` resolves (fixed delay, independent of projectile animation length)

**Input isolation fix (session 4):**
- `combat_ui._unhandled_input()` now calls `get_viewport().set_input_as_handled()` after every combat key (1-6 for actions, S for skip, ESC for cancel target); previously these leaked to `inventory_ui._unhandled_input()` which uses 1-6 for quick-equip, causing silent item equips during combat

### UI
- [x] Game HUD: time clock, hero panel in dungeon
- [x] Combat UI: portrait tracker with colored dots, active unit highlight, enemy info panel, combat log, target cards
- [x] Inventory: paper doll + 6×4 backpack grid + character stats panel
- [x] Quick-use hotkeys (F, 1–6)
- [x] Toast notifications for inventory actions
- [x] Save button (💾) in inventory header → `SaveManager.save_game(slot)` → toast feedback
- [x] Character select screen (race/gender/class picker before new game)

### Player Sprites
- [x] `CharacterSprite` node (`character_sprite.gd`) — individual PNGs from `assets/art/player_avatars/`
- [x] Prefix pattern: `res://assets/art/player_avatars/{race}_{gender}` (e.g. `human_male`)
- [x] Poses: idle, `_back`, `_run`, `_run_back`, `_attack`, `_ready`, `_sad`, `_worried`, `_happy`, `_angry`, `_thumbs_up`, `_jumping`, `_jumping_back`
- [x] Walk animation: flip_h toggled every 0.25s for diagonal dirs; sideways is static
- [x] pixel_size = 0.0045 for player (433×688px); enemies use `EntityManager.ENTITY_PIXEL_SIZE_FULL = 0.003`
- [x] Portraits: `assets/art/player_avatars/{g}{r}_port.png` (g=m/f, r=h/e/d/g)
- [x] `GameData.get_portrait_path()` + `GameData.player_sprite_prefix`

### NPC Shop System
- [x] Daniels (armor) + Conner (potion) always available in camp from game start
- [x] Zara (magic), Michelle (structure), Mahan (weapon), Claude (sage) rescued 1-per-floor-cleared
- [x] Shop UI (`ui/shop_ui.gd`): tiered inventory by floor (0-1 / 2-4 / 5+) via `_get_shop_tier()`
- [x] Sage UI (`ui/sage_ui.gd`): mechanic hints, "Another Hint" button
- [x] `rescued_npcs` saved/restored in GameData's save dict
- [x] NPC UI open flag (`_npc_ui_open`) prevents stacking

### Data Systems
- [x] GameData: full player state, class system, save/load dict
- [x] ItemDB: item creation, equipping, backpack management; 40+ items across weapons/armor/food/potions
- [x] EnemyDB: entities.json loading, portrait paths
- [x] 9 player classes with distinct base stats
- [x] Weapons with ranged mechanics: crossbow, fire_staff, ice_bow, boomerang, throwing_knives

### Save System
- [x] `SaveManager` autoload — `save_game(slot)`, `load_game(slot)`, `get_slot_info(slot)`, `delete_slot(slot)`
- [x] Files: `user://dungeon_break_save_N.json` (N = 0..2, MAX_SLOTS=3)
- [x] `dungeon_seed` in GameData — set before `build_dungeon()`, reset to 0 on `_on_advance_floor()` for fresh layouts
- [x] `scene_state` ("camp"/"dungeon") determines where to restore on load
- [x] Save slot UI (`ui/save_slot_ui.gd`): name/class/floor/HP/timestamp per slot, overwrite confirmation
- [x] Flow: main.gd → SaveSlotUI (3 cards) → New Game (char select) OR Load (restores GameData → camp or dungeon)

---

## Planned / Not Yet Built

### Camp NPCs (Story)
The camp is meant to be populated with named characters:
- **Joe** — soul broker, retired adventurer, first NPC met. "You look new."
- **Mira** — cartographer, self-mapping mini-map mechanic
- **Old Pell** — healer, tends the Azure Flame. "A necromancer is just a cleric that arrived a bit too late." (no elaboration)
- Joe/Mira/Old Pell have no dialogue yet (NPC shops Daniels/Conner/etc. are working)
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

### Advanced Weapon Mechanics (not yet wired)
- Ice Bow slow (currently freezes 1 turn — could add move-range reduction)
- Rocket launcher AoE (item exists in reference project at `items/rocket_launcher/`)
- Grappling hook repositioning (item exists in reference project)

### Inventory
- True drag-and-drop (currently click-to-select + click-to-equip)
- Hotbar slot management UI

---

## Asset Notes

- Enemy portraits: `assets/art/entities/*.jpeg` / `*.png`
- `entities.json`: each enemy has `sprite_portrait` field pointing to filename
- `EnemyDB.get_portrait_path(key)` returns the full `res://` path
- Player portrait: TBD (currently placeholder frame in inventory)
- Time icons: `assets/art/time/sun.png`, `dusk.png`, `moon.png`

---

## Reference Project (Effects Goldmine)

A second full Godot game at `/home/brad/Documents/Godot/theLongNights-godot/project/` shares the same art assets and is a source for combat effects code to adapt:

- **Projectiles:** `blocky_game/projectiles/` — boomerang, ice_arrow, fireball, throwing_knife, flying_blade, arrow, goblin_bomb, scatter_shot, spear_projectile, plasma_shot, energy_beam, necrotic_bolt, void_bolt, meteor, thorn, acid_spit, thrown_torch
- **Item scripts:** `blocky_game/items/` — boomerang/, ice_bow/, fire_staff/, crossbow/, throwing_knives/, grappling_hook/, rocket_launcher/
- **FX shaders:** `blocky_game/items/impact_effect.gdshader`, `slash_effect.gdshader`, `spatial_slash_effect.gdshader`
- **Art:** Same `assets/art/textures/` (slash_01-05, spark_01-07, star_01-07, magic_01-05, circle_01-05), also has `assets/art/effects/` and unique tool art (`iceShard.png`, `ice_bow.png`, `fire_staff.png`, `fire_01.png`, `fire_02.png`)

---

## Development Notes

- **JS prototype location:** `/home/brad/Documents/dungeon-break/` — kept as reference, not active
- **Godot project location:** `/home/brad/DungeonBreaker-godot/`
- **Why Godot?** The JS version kept breaking under complexity (3D rendering, combat state, UI all fighting each other). Godot gives proper scene tree, signals, and typed GDScript.
- **Zylann template cleanup:** The blocky_terrain, smooth_terrain, multipass_generator, and grid_pathfinding template folders were deleted. Kept: `blocky_game/blocks/` (for voxel library/textures) and `common/` (utility scripts). `addons/` kept in full.
- **Wall material split:** `blocky_game/blocks/terrain_material_wall.tres` is a separate StandardMaterial3D (same texture atlas as `terrain_material.tres`) assigned only to the three dungeon wall block types (log_y, stone_bricks, void_stone_bricks) in `voxel_library.tres`. This gives walls their own mesh surface so `dungeon.gd` can fade them independently during combat via `_set_wall_combat_mode()`. Floor blocks (planks, ruin_stone, void_stone, dirt, stone, etc.) continue using the original `terrain_material.tres`.
- **Projectile robustness pattern:** All projectile meshes must own their tweens via `node.create_tween()` (NOT `self.create_tween()` on the combat_manager). Otherwise, when combat ends and the combat_manager is freed, the tween dies and the mesh sits frozen in world space. Each projectile also has a fallback `get_tree().create_timer()` (SceneTree-owned, survives any node being freed) that cleans up the mesh and fires `on_land` if the tween is interrupted.
- **Slash shader (`dungeon_break/combat/slash_effect.gdshader`):** `blend_add, unshaded, cull_disabled, depth_draw_never`; vertex shader handles billboarding (preserves node scale); `fade` uniform (0→1) animated via `tween_method` + `smat.set_shader_parameter()` since `MeshInstance3D` has no `modulate` property (that's CanvasItem only). Shader cached once in `_init_fx()` via `_slash_shader: Shader`; each use creates a fresh `ShaderMaterial` with the shared shader.
- **GDScript lambda capture:** `get_tree().create_timer()` timers survive node cleanup — safe for deferred callbacks. `node.create_tween()` tweens die when the node is freed — don't use `self.create_tween()` for long-lived visuals spawned as children of another node.
