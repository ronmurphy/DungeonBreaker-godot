# Dungeon Break — Project State Document (continued)
*Continued from `updated.md`. Last updated: 2026-03-04 (session 12)*

> This file picks up where `updated.md` left off. See that file for the base project overview, tech stack, combat system, class table, and room type reference.

---

## Session 6 Summary — What Was Built

### 1. Bonfire Rest Mechanic

The campfire in camp now has an interaction zone. When the player stands near it, the HUD shows **"[E] Rest (restores HP, advances 8 hrs)"**. Pressing E:
- Heals the player to full HP
- Calls `GameData.heal_companions()` — restores all companions to full HP
- Advances `GameData.world_time` by `8.0 / 24.0` (fmod-wrapped to keep in 0–1 range)

A `_bonfire_rest_pending: bool` flag in `game.gd` prevents the time from advancing every frame while E is held.

**Files changed:**
- `dungeon_break/generator/camp_builder.gd` — `_build_bonfire()` now adds an `Area3D` with `set_meta("interaction", "bonfire")` and a 5×4×5 BoxShape3D, matching the azure flame pattern
- `dungeon_break/game.gd` — added `_bonfire_rest_pending` flag and bonfire branch in `_check_portal_interactions()`
- `dungeon_break/data/game_data.gd` — added `heal_companions()` method

---

### 2. Save Slot UI Portraits

The save/load screen now shows **two portraits per occupied slot**:
- **Left**: hero portrait (`{g}{r}_port.png` — e.g. `mh_port.png` for male human)
- **Right**: first active companion's portrait (falls back to ready-pose image if no portrait exists)
- **Centre**: name, class, location (unchanged)

A compact HP bar and gold count appear below.

**Portrait resolution order (companion):**
1. `EnemyDB.get_portrait_path(key)` → reads `sprite_portrait` from `entities.json`
2. `EnemyDB.get_ready_texture_path(key)` → reads `sprite_ready` from `entities.json`
3. Dim placeholder `ColorRect` if neither exists

**Critical bug fixed:** `active_companions` in the save file is an `Array` of `String` keys, not an Array of Dictionaries. The old code checked `active[0] is Dictionary` which always returned false, leaving `first_companion_key` empty. Fixed to `if active[0] is String`.

**Files changed:**
- `dungeon_break/data/save_manager.gd` — `get_slot_info()` now returns `player_race`, `player_gender`, `first_companion_key`; fixed active_companions type check
- `dungeon_break/ui/save_slot_ui.gd` — `_build_occupied_slot()` restructured with portrait row; added `_make_portrait(path, size)` helper

---

### 3. Companion Roster UI — Portraits Added

The companion roster (opened from the Azure Flame in camp) previously had no artwork. Both the **active party** cards and **bench** cards now show a 44px portrait on the left, with name/stats on the right.

Uses the same portrait → ready-pose fallback as the save screen. The `_make_portrait(key, size)` helper takes an entity key and resolves the path internally.

**Files changed:**
- `dungeon_break/ui/companion_roster_ui.gd` — `_build_active_card()` and `_build_bench_card()` restructured; `_make_portrait(key, size)` added

---

### 4. Dungeon Loading Screen — Two-Shader Transition

Replaced the blank grey dungeon loading screen with an animated fractal sequence.

#### Shaders (both from godotshaders.com, CC0)
| File | Shader | Used for |
|---|---|---|
| `dungeon_break/ui/dungeon_load_bg.gdshader` | Pixelated Warped Fractal Noise | Animated loading background |
| `dungeon_break/ui/dungeon_load_transition.gdshader` | Fractal Noise Scene Transition | Diagonal wipe reveal |

#### Visual sequence
1. Player enters dungeon portal → loading bg appears instantly (dark blue/purple animated pixelated fractal)
2. Dungeon generates in the background (voxels, rooms, enemies, player spawn)
3. `dungeon_ready` signal fires from `dungeon.gd`
4. Wipe transition plays: fractal noise band sweeps diagonally across (0.75s wipe-in)
5. At midpoint (full screen coverage): loading bg hidden, dungeon is now live behind it
6. Band continues sweeping off screen (0.75s wipe-out), revealing the dungeon
7. All overlay rects hidden — zero shader cost at runtime

#### Implementation
Three stacked `ColorRect` nodes in one `CanvasLayer` (layer 64, above game, below screenshot toast):

| Rect | Shader | Purpose |
|---|---|---|
| `_load_solid_rect` | none — solid `Color(0.02, 0.01, 0.06)` | Blocks grey dungeon through vignette-transparent edges of bg shader |
| `_load_bg_rect` | `dungeon_load_bg.gdshader` | Animated fractal loading screen |
| `_load_wipe_rect` | `dungeon_load_transition.gdshader` | Diagonal fractal wipe reveal |

All three are `visible = false` when not active (Godot 4: invisible CanvasItems do not run their shaders — zero GPU cost).

The wipe shader's `progress` uniform sweeps a diagonal fractal band:
- `progress = 0.0` → transparent (nothing visible)
- `progress = 0.5` → band covers full screen
- `progress = 1.0` → transparent again (dungeon fully revealed)

**Files changed:**
- `dungeon_break/ui/dungeon_load_bg.gdshader` *(new)*
- `dungeon_break/ui/dungeon_load_transition.gdshader` *(new)*
- `dungeon_break/dungeon.gd` — added `signal dungeon_ready()`, emitted at end of `_build_dungeon()`
- `dungeon_break/main.gd` — `_build_load_overlay()`, `_show_load_overlay()`, `_hide_load_overlay()` added; `_load_dungeon()` now calls `_show_load_overlay()` and connects `dungeon_ready → _hide_load_overlay` with `CONNECT_ONE_SHOT`

---

## Current State After Session 6

### Camp
- Terrain island with voxel buildings, wandering NPCs
- **Bonfire**: Press E to rest — full heal + companion heal + +8 hours world time
- **Azure Flame**: Opens companion roster UI (manage active party / bench)
- **Portal**: Enter dungeon (triggers fractal loading screen)
- Day/night cycle driven by `GameData.world_time`

### Save / Load Screen
- Three slot cards with hero portrait (left), name/class/location (centre), companion portrait (right)
- HP bar, gold count, timestamp
- New Game / Load / Overwrite confirmation

### Companion System
- `GameData.companions`: Array of dicts (key, name, hp, hp_max, attack, defense, tactic)
- `GameData.active_companions`: Array of String keys (max slots based on floor)
- `GameData.get_companion_slots()`: 2 slots floor 1–2, 3 slots floor 3–5, 4 slots floor 6+
- Tactics: balanced / healer / berserker / defender (set per companion in roster UI)
- Companion follower entities trail behind player in dungeon (despawn on combat, respawn after)
- `heal_companions()`: restores all companions to `hp_max`

### Dungeon
- BSP-generated floors with upper rooms (floor_height=3, staircase approach)
- Room types: start, normal, treasure, boss, vault, corridor
- `dungeon_ready` signal fires when fully built (used by loading screen)
- Wall material fades to 8% alpha on combat start, restores after

### Combat
- FFT-style tactical grid, phase-based
- Companion units participate in combat alongside player
- Defeated enemies can be recruited as companions (ghost conversion)

---

---

## Session 6 (continued) — Camp Visual Overhaul

All changes are in `dungeon_break/generator/camp_builder.gd` only.

### New block constants added
`TALL_GRASS = 8`, `DEAD_SHRUB = 26`, `STONE_BRICKS = 63`

### `_build_markers()` → `_build_trees()`
Replaced 5 identical stick posts with 10 proper multi-block trees in natural-feeling clusters (NW, N, NE, S, SW, E). Each tree:
- 4-block `LOG_Y` trunk
- 3×3 `LEAVES` canopy at trunk top and one block above
- Single `LEAVES` cap block

Positions stored in `TREE_POSITIONS` const (replaces `MARKER_POSITIONS`).

### `_build_paths()` + `_stamp_path()`
Stone brick paths connecting all three landmarks via a central hub:
- Bonfire (-9,-9) → Plaza (-2,-2)
- Plaza (2,2) → Spire (9,9)
- Plaza (2,0) → Azure Flame (31,0)

Uses float lerp stepping, stamps `STONE_BRICKS` at `_surface_y` per step.

### `_build_central_plaza()` + `_build_well()`
5×5 `STONE_BRICKS` hub at (0,0) where all paths converge. Well at its centre:
- 3×3 stone base, stone ring with open shaft, two `LOG_Y` posts, `PLANKS` beam
- Soft blue-white `OmniLight3D` (energy 0.8, range 6)

### `_build_dock()`
Wooden pier east of the Azure Flame (x=35→46, z=-1..1):
- `PLANKS` deck, `LOG_Y` support pillars at x=35/39/43
- Amber `OmniLight3D` lantern at the pier end (energy 1.5, range 8)

### `_scatter_foliage()`
Seeded RNG (seed=42, reproducible) scatters across open GRASS:
- 30 × `TALL_GRASS` (anywhere on island, radius 0–38)
- 15 × `DEAD_SHRUB` (island edges, radius 20–38)

Skips: structure zones, non-GRASS surfaces (paths/plaza/dock auto-excluded).

### `build_camp()` call order
```
_build_bonfire → _build_spire → _build_azure_flame
→ _build_trees → _build_paths → _build_central_plaza → _build_dock → _scatter_foliage
```
Paths run before foliage so STONE_BRICKS surfaces are already in place when foliage checks for GRASS.

---

## Session 6 (continued) — Well Position Fix

Player spawns at world origin (0,0) in camp. The well was centred at (0,0) inside the 5×5 plaza, so the player landed on top of it on every load.

**Fix**: moved well 3 blocks north — `_build_well(0, -3, _surface_y(0, -3))` in `_build_central_plaza()`. The plaza floor remains at (0,0) as the path hub; the well sits just north of centre, still visually inside the plaza but clear of the spawn point.

**File changed**: `dungeon_break/generator/camp_builder.gd`

---

## Known Pending Work

| Item | Priority | Notes |
|---|---|---|
| Camp NPC dialogue | High | Joe, Mira, Old Pell — interaction zones exist, no dialogue tree yet |
| Camp NPC shop buildings | Medium | Small market stalls near the plaza for each NPC — blacksmith, alchemist, trader |
| Vault room loot pass | Medium | Currently has chest + gold ore; needs richer decoration and varied loot |
| Stair block rotation | Low | Direction-aware stair block facing — geometry works, rotation deferred |
| Class-specific mechanics | Medium | Reanimator (raise dead), Confessor (faith buffs) unimplemented |
| Visual novel cutscenes | Low | Planned for story beats (rescue sequences, boss defeat, floor transitions) |
| Helix zone transitions | Low | Animated floor transition visual between dungeon floors |
| Drag-and-drop inventory | Low | Current inventory is click-to-equip only |
| Companion tactics UI | Medium | Tactic selector (balanced/healer/berserker/defender) in roster UI — wired but untested in combat |
| Save slot delete | Low | No way to clear a save slot from the UI |
| World map / floor select | Low | Show dungeon floors reached, allow revisiting earlier floors |
| Sloped / wedge blocks | Low | Triangular prism shapes for ramps and rooftops. Requires 4 block IDs per slope (N/S/E/W variants) + custom mesh and collision per entry in voxel_library.tres. Direction-aware stamping logic needed (same problem as stair rotation). Water's 3-ID family is existing precedent for multi-ID block groups. |

---

## File Index (additions since updated.md)

```
dungeon_break/
  ui/
    companion_roster_ui.gd      ← portraits added to active + bench cards
    save_slot_ui.gd             ← hero + companion portraits on save cards
    dungeon_load_bg.gdshader    ← NEW: pixelated warped fractal loading bg
    dungeon_load_transition.gdshader  ← NEW: fractal noise diagonal wipe
  data/
    save_manager.gd             ← get_slot_info() extended; active_companions bug fix
    game_data.gd                ← heal_companions() added
  generator/
    camp_builder.gd             ← bonfire Area3D; full visual overhaul (trees, paths, plaza, well, dock, foliage); well moved north
  game.gd                       ← bonfire rest handler + _bonfire_rest_pending flag
  dungeon.gd                    ← signal dungeon_ready() added
  main.gd                       ← two-shader loading overlay system
```

---

## Session 7 Summary — Jobs, Buff Rules, Lighting, and UI Polish

### 1. Consumables Changed to Combat-Only Temporary Buffs

Food and potion usage now follows a strict combat-only buff rule:
- Outside combat: consumables cannot be used (UI toast explains why)
- In combat: consumables apply temporary combat buffs (STR/DEX/INT/LCK/SPD/ATK/AC), then are consumed
- Buffs are cleared when combat ends via `GameData.clear_combat_buffs()`

This replaces the previous recovery-first behavior and keeps long-term progression reserved for the future leveling system.

**Files touched:**
- `dungeon_break/data/item_db.gd`
- `dungeon_break/data/game_data.gd`
- `dungeon_break/ui/inventory_ui.gd`
- `dungeon_break/combat/combat_manager.gd`

### 2. Interaction Input Standardized to Single-Press

Camp and dungeon station interactions now use edge-triggered key handling (`just pressed`) instead of hold-to-repeat behavior.

**Examples:**
- Bonfire rest
- Azure Flame rest/refuel
- Dungeon stations (brew/chest/door style interactions)

**Files touched:**
- `dungeon_break/game.gd`
- `dungeon_break/dungeon.gd`

### 3. Graphics Presets + Low/Medium Lighting Fallback

Graphics presets were aligned to the intended SDFGI behavior:
- **Low:** SDFGI OFF, SSAO OFF, Glow OFF
- **Medium:** SDFGI OFF, SSAO ON, Glow ON
- **High:** SDFGI ON, SSAO ON, Glow ON

To keep dungeon readability when SDFGI is disabled, low/medium now use subtle fallback lighting:
- Slight ambient boost
- Small non-SDFGI fill light to lift wall visibility without flattening the scene

**Files touched:**
- `dungeon_break/data/graphics_manager.gd`
- `dungeon_break/dungeon.gd`
- `dungeon_break/ui/game_hud.gd` (preset descriptions)

### 4. Azure Flame Job System (FFT-Style, Simplified)

Implemented a class-job progression and switching loop centered on the Azure Flame:
- Press **C** near Azure Flame to open the **Job Change** modal
- Jobs have rank progression (rank increases on combat wins with current job)
- FFT-style dependency unlocks for advanced jobs
- Job change updates base stats and max HP for the run
- Job progression persists in save data (`unlocked_jobs`, `job_rank`)

**Files touched:**
- `dungeon_break/data/game_data.gd`
- `dungeon_break/game.gd`
- `dungeon_break/dungeon.gd`
- `dungeon_break/ui/job_change_ui.gd` (new)

### 5. Job Art Integration + UI Scaling Fixes

Integrated `assets/art/jobs/` into gameplay UI:
- Job symbols shown in inventory stat panel near class label
- Job symbol shown on job change buttons
- Job dummy artwork shown in job preview panel

Large source assets are now proportionally downscaled at runtime for consistent UI fit.

**Files touched:**
- `dungeon_break/ui/job_change_ui.gd`
- `dungeon_break/ui/inventory_ui.gd`
- `dungeon_break/data/game_data.gd` (job symbol/dummy path helpers)

### 6. In-Game Job Unlock Toast + Themed Screenshot Toast

Added themed in-game feedback for job progression:
- On post-combat unlock, HUD shows toast for newly unlocked jobs

Redesigned screenshot toast to better match game UI styling while preserving click-to-open-folder behavior.

**Files touched:**
- `dungeon_break/dungeon.gd`
- `dungeon_break/ui/game_hud.gd`
- `dungeon_break/main.gd`

### 7. Slopes Status

Slope/wedge terrain work was prototyped, then rolled back.  
Current build state: **no slope terrain changes active**.

---

## Session 8 Summary — Camp Cloud Shadows, Consumable Fixes, Item Normalization, and Shop Selling

### 1. Lightweight Camp/Lowlands Cloud Shadow Caster

Added an iGPU-friendly cloud shadow system for camp/lowlands using one large high-altitude shadow-only mesh:
- Uses a simple spatial shader + scrolling noise texture
- Casts moving cloud-shaped shadows onto terrain/trees
- Applies in camp/lowlands only (not dungeon)

This avoids heavy full-screen or procedural sky shader cost.

**Files touched:**
- `dungeon_break/world/cloud_shadow_caster.gdshader` (new)
- `dungeon_break/game.gd` (cloud caster build + runtime noise texture setup)

### 2. Combat Consumables: Healing Restored + Companion Self-Use Fix

Combat consumables now correctly apply healing again:
- `heal_amount` on food/potions is applied in combat
- Buff effects still apply as before

Also fixed companion AI self-use behavior:
- When a companion uses a consumable on self, healing is redirected to that companion instead of the player

**Files touched:**
- `dungeon_break/data/item_db.gd`
- `dungeon_break/combat/combat_manager.gd`
- `dungeon_break/ui/inventory_ui.gd` (updated empty-effect messaging in combat)

### 3. Item Type Reliability Pass (Legacy/Backup Save Compatibility)

Added canonical item type resolution and normalization so old/backup item entries still behave correctly:
- New helpers in `ItemDB`: `resolve_item_type`, `is_consumable`, `is_weapon`, `is_armor`
- New normalizers: `normalize_item`, `normalize_item_array`
- Save-load path now normalizes backpack/hotbar/equipment item dictionaries
- Combat and inventory checks were switched to resolver/helpers instead of brittle raw `item["type"]` checks

This fixes cases where consumables existed in inventory but failed to appear/use in combat due to missing/inconsistent `type` fields.

**Files touched:**
- `dungeon_break/data/item_db.gd`
- `dungeon_break/data/game_data.gd`
- `dungeon_break/combat/combat_ui.gd`
- `dungeon_break/combat/combat_manager.gd`
- `dungeon_break/ui/inventory_ui.gd`

### 4. Daniels/Conner Shop Selling Added

Daniels (`armor_shop`) and Conner (`potion_shop`) now buy items from the player backpack:
- New `Sell From Backpack` section in shop UI
- Items are grouped by stack for display
- Sell price formula: **half buy value, rounded up** (`ceil(value / 2)`)
- Selling updates gold and backpack immediately and refreshes shop list

**Files touched:**
- `dungeon_break/ui/shop_ui.gd`

---

## Session 9 Summary — iGPU-Safe Lowlands Grass Wind + Foliage Density Pass

### 1. Lowlands-Only Wind Grass Layer (iGPU-Safe)

Added a lightweight wind-driven grass render pass for the lowlands using one `MultiMeshInstance3D`:
- Uses existing `tall_grass` assets (`tall_grass.obj` + `tall_grass_sprite.png`)
- Single draw-style instancing with no grass shadow casting
- Alpha scissor cutout shader for low overdraw cost
- Spawn ring constrained to lowlands middle ring (outside camp plateau)
- Per-preset caps and distance scaling kept for low/medium safety

Final visual tuning made the layer visible on low-end hardware:
- Reduced alpha cutoff
- Increased per-instance scale variation
- Adjusted Y placement so blades anchor into terrain better

**Files touched:**
- `dungeon_break/world/lowland_billboard_grass.gdshader` (new)
- `dungeon_break/game.gd`

### 2. Lowlands Voxel Foliage Changed to Multi-Block Patches

Lowland voxel foliage generation was upgraded from sparse singles to clustered patches:
- `TALL_GRASS` now spawns in multi-block patch groups across lowlands
- `DEAD_SHRUB` remains as lighter single scatter for variety
- Existing avoid-zones for arch and lowland trees are preserved

This gives the lowlands a denser, more natural grass read without forcing higher graphics presets.

**Files touched:**
- `dungeon_break/generator/camp_builder.gd`

### 3. Debug Logging Cleanup

Temporary `LowlandGrass:` spawn/quality debug prints were removed after validation.

**Files touched:**
- `dungeon_break/game.gd`

---

## Session 10 Summary — Bug Fixes, XP/Level System, Class Skills, Visual Polish, and Magic Weapons

### 1. Death Screen Fix

Fixed death screen appearing off-screen and "New Run" button not dismissing it.
- Repositioned to center-anchored layout
- Added `ds.queue_free()` on button press

**Files touched:**
- `dungeon_break/ui/death_screen.gd` (or equivalent)

### 2. Flee Bug Fix

Fleeing from combat was showing the death screen. Added `fled: bool` parameter to `combat_ended` signal and routed flee outcomes to return-to-camp instead of death handling.

**Files touched:**
- `dungeon_break/combat/combat_manager.gd`
- `dungeon_break/dungeon.gd`

### 3. Companion Count Bug

Run summary showed 0 companions recruited because `active_companions` was already cleared before the count was read. Added `run_companions_recruited` counter that increments on recruitment and is read before cleanup.

**Files touched:**
- `dungeon_break/data/game_data.gd`

### 4. XP / Level System + Class Stat Growth

Implemented player leveling:
- `player_level`, `player_xp` in GameData
- `grant_xp(amount)` → returns number of levels gained
- `xp_to_next_level()` → `50 + (level - 1) * 25` scaling
- `signal level_up(new_level: int)`
- `CLASS_LEVEL_GROWTH` dict — per-class stat gains on level up (HP, STR, DEX, INT, SPD, AC)
- Companion levels sync to player level

XP sources: 10 + floor×5 base per enemy kill, bosses give double.

**Files touched:**
- `dungeon_break/data/game_data.gd`
- `dungeon_break/combat/combat_manager.gd`

### 5. Nine Unique Job Special Skills

Each of the 9 classes now has a unique combat skill (2-turn cooldown after use):

| Class | Skill | Effect |
|-------|-------|--------|
| VANGUARD | Shield Wall | +3 AC for 2 turns |
| SCOUNDREL | Shadowstep | Teleport to any unoccupied walkable tile |
| ARCANIST | Arcane Blast | d8 AoE damage to all enemies in 2-tile radius of target |
| CONFESSOR | Bless | Heal self d6 + grant +2 ATK for 2 turns |
| STRIDER | Steady Shot | Next ranged attack deals +d6 bonus damage |
| MINSTREL | War Song | All companions get +2 ATK for 2 turns |
| TEMPLAR | Holy Smite | d10 damage to target + heal self for half |
| REANIMATOR | Soul Drain | d6 damage + heal self equal to damage dealt |
| TINKERER | Shock Mine | d6 damage + stun (freeze 1 turn) to nearest enemy |

Implemented via `_do_skill_*` functions in `combat_manager.gd` and `JOB_SPECIAL_SKILL` dict in `game_data.gd`. Cooldown tracked via `GameData.skill_cooldown`. UI shows greyed-out button with countdown.

Shadowstep fix: changed `is_blocked()` to `is_walkable()` + occupancy check.

**Files touched:**
- `dungeon_break/data/game_data.gd`
- `dungeon_break/combat/combat_manager.gd`
- `dungeon_break/combat/combat_ui.gd`

### 6. Default Font Change

Set `Cinzel-VariableFont_wght.ttf` as the default project font via `project.godot` `[gui]` section.

**Files touched:**
- `project.godot`

### 7. Six Visual Polish Features

#### a. Damage Float Text Scale-Pop
Float text now punches up 1.5× scale then settles to 1.0× before fading, making hits feel punchier.

#### b. Player Footstep Dust Particles
GPUParticles3D attached to player that emits brown-grey puffs during movement. Disabled on LOW graphics preset.

#### c. Torch/Campfire Flicker Lights
Campfire and torch lights now flicker via looping tween that wobbles `light_energy` and `omni_range` ±15%.

#### d. Sprite Drop Shadows
Player, NPC, and entity sprites get a semi-transparent dark PlaneMesh shadow below them. Disabled on LOW.

#### e. Level-Up Screen Flash
On `GameData.level_up` signal: golden flash overlay + "LEVEL UP!" banner with tween animation on the HUD.

#### f. Combat Entry Vignette
Custom `combat_vignette.gdshader` — screen-edge darkening that pulses in on combat start and fades out on combat end.

**Files touched:**
- `dungeon_break/combat/combat_manager.gd` (float text tween)
- `dungeon_break/player/player_controller.gd` (dust particles)
- `dungeon_break/generator/camp_builder.gd` (flicker lights)
- `dungeon_break/entities/entity_manager.gd` (drop shadows)
- `dungeon_break/entities/npc_sprite.gd` (NPC drop shadows)
- `dungeon_break/entities/character_sprite.gd` (player drop shadow)
- `dungeon_break/ui/game_hud.gd` (level-up flash)
- `dungeon_break/dungeon.gd` (combat vignette system)
- `dungeon_break/ui/combat_vignette.gdshader` (new)

### 8. Five New Magic Weapons

Ported enchantment concepts from "The Long Nights" (original game) as 5 new magic weapons with unique on-hit effects, projectile visuals, impact FX, and combat log verbs.

| Weapon | Art | ATK | Range | On-Hit Effect | Price | Loot Floors |
|--------|-----|-----|-------|---------------|-------|-------------|
| **Poison Dart** | dart.png | +2 | +3 | Poison: 2 dmg/turn for 2 turns | 12g | 1–4 |
| **Crystal Wand** | cryatal.png | +3 | +3 | Armor Pierce: halves target's AC for the clash roll | 18g | 1–4 |
| **Shuriken** | shuriken.png | +2 | +2 | Ricochet: bounces to up to 2 nearby enemies for 1/3 dmg | 30g | 3–6 |
| **Skull Wand** | skull.png | +4 | +2 | Life Steal: heals attacker 25% of damage dealt | 55g | 4+ |
| **Storm Staff** | stick_2.png | +5 | +3 | Chain Lightning: half dmg bounces to 1 adjacent enemy | 75g | 6+ |

#### Shop Availability
- **Poison Dart**: Conner (T0, from game start) + Zara (T0)
- **Crystal Wand**: Daniels (T0, always stocked as an extra item) + Zara (T0)
- **Shuriken**: Zara (T1, floors 2+)
- **Skull Wand**: Zara (T2, floors 5+)
- **Storm Staff**: Zara (T2, floors 5+)

#### New Combat Systems Added
- **Poison tick system**: Enemies take `poison_dmg` per turn for `poison_turns` turns, processed at start of enemy turn (before freeze check). Green float text "−X Poison" + combat log message. Poison can kill.
- **Crystal wand AC pierce**: Target's defense is halved before the clash roll (`effective_defense = max(1, defense / 2)`).
- **Shuriken ricochet**: After primary hit, attempts to bounce to up to 2 additional enemies within Manhattan distance 2, dealing 1/3 damage each.
- **Skull wand life steal**: After dealing damage, heals attacker for 25% (min 1) via `GameData.heal()`. Green "+X HP" float text on attacker.
- **Storm staff chain lightning**: After primary hit, chains half damage to the nearest adjacent enemy (Manhattan distance ≤1). Visual chain lightning arc (`_fx_chain_lightning`) connects the two targets.

#### New Impact FX Functions
- `_fx_poison_impact()` — green droplets + green light flash
- `_fx_arcane_impact()` — purple crystal shards + purple light flash
- `_fx_life_drain_impact()` — dark expanding sphere + inward-spiraling tendrils + purple-red flash
- `_fx_lightning_impact()` — 8 electric arcs radiating outward + bright blue-white flash
- `_fx_chain_lightning(from, to)` — cylinder beam with glow sleeve, flicker animation, auto-cleanup

#### Projectile Visuals
Each weapon has a unique projectile tint and texture in `_fx_projectile()`:
- Poison Dart: spark_06 texture, toxic green
- Crystal Wand: circle_01 texture, purple arcane
- Shuriken: star_05 texture, bright silver, fastest travel (0.18s)
- Skull Wand: magic_01 texture, dark purple
- Storm Staff: spark_01 texture, electric blue, fast travel (0.16s)

**Files touched:**
- `dungeon_break/data/item_db.gd` — 5 weapon definitions + loot table entries
- `dungeon_break/combat/combat_manager.gd` — poison tick system, AC pierce, 5 impact callbacks, 5 projectile visuals, 5 ranged verbs, 5 log suffixes, 5 new FX functions
- `dungeon_break/ui/shop_ui.gd` — `MAGIC_WEAPON_IDS` updated, Daniels extras, Conner T0 list, Zara tiered lists, potion_shop tier logic fix

---

## "The Long Nights" Systems Audit

Full audit of the original game (`/home/brad/Documents/Godot/theLongNights-godot/project/`) was completed and documented in `docs/theLongNights_systems_audit.md`. Key reusable systems identified:

| Priority | System | Effort | Status |
|----------|--------|--------|--------|
| 🔴 HIGH | Skyshard Power System (on-hit enchantments) | Low | **Partially ported** — 5 new weapons use the pattern |
| 🔴 HIGH | Combat math (d20 rolls, damage formula) | Low | Already adapted in DungeonBreaker |
| 🟡 MED | Push block puzzles (Sokoban rooms) | Medium | Researched, not yet ported |
| 🟡 MED | Accessory passive effects (rings, pendants) | Low | **Next priority** |
| 🟡 MED | Permanent stat elixirs | Low | **Next priority** |
| 🟡 MED | Companion roster equipment system | Medium | Deferred |
| 🟢 LOW | Hunting system (race-weighted companion loot) | Low | Deferred |
| 🟢 LOW | Fishing minigame | Medium | Deferred |

### Available Unused Art Assets for Future Items
`skyshard.png`, `pheonix_crystal.png`, `pheonix_feather.png`, `pheonix_hourglass.png`, `red_ring_1.png`, `red_ring_2.png`, `ring_silver_green.png`, `gauntlet_of_strength.png`, `hatchet.png`, `machete.png`, `machete_2.png`, `limited_potion_*.png` (9 colors)

### Next Planned Items
- **6 Accessories**: Ring of Thorns, Ring of Vampirism, Ring of Fortitude, Phoenix Crystal, Gauntlet of Might, Hourglass of Haste
- **4 Permanent Elixirs**: Power (+1 STR), Iron (+1 AC), Vitality (+2 HP), Speed (+1 SPD)
- **Fire Staff nerf**: Exclude friendly units from AoE splash

---

## Known Pending Work (Updated)

| Item | Priority | Notes |
|---|---|---|
| Accessories with passive effects | High | 6 rings/pendants with on-hit/on-kill/per-turn effects |
| Permanent stat elixirs | High | Rare dungeon rewards using limited_potion art |
| Fire staff AoE nerf | High | Exclude friendly units from splash damage |
| Push block puzzle rooms | Medium | Sokoban-style rooms in dungeon — researched from original game |
| Camp NPC dialogue | Medium | Joe, Mira, Old Pell — interaction zones exist, no dialogue tree yet |
| Vault room loot pass | Medium | Currently has chest + gold ore; needs richer decoration and varied loot |
| Class-specific mechanics | Medium | Reanimator (raise dead), Confessor (faith buffs) partially done via skills |
| Gamepad support | Medium | Needs InputMap refactor + UI focus chains |
| Visual novel cutscenes | Low | Planned for story beats |
| Drag-and-drop inventory | Low | Current inventory is click-to-equip only |
| Save slot delete | Low | No way to clear a save slot from the UI |

---

## File Index (additions since session 9)

```
dungeon_break/
  combat/
    combat_manager.gd    ← flee fix, XP/kill, 9 class skills, skill cooldowns,
                           Shadowstep fix, float text pop, 5 magic weapon effects,
                           poison tick system, 5 new FX functions,
                           chain lightning visual
  data/
    game_data.gd         ← run_companions_recruited, player_level/xp,
                           grant_xp(), xp_to_next_level(), level_up signal,
                           JOB_SPECIAL_SKILL, CLASS_LEVEL_GROWTH,
                           skill_cooldown, steady_shot_bonus, taunt_active
    item_db.gd           ← 5 new magic weapons (poison_dart, crystal_wand,
                           shuriken, skull_wand, storm_staff) + loot entries
  entities/
    entity_manager.gd    ← drop shadows on entities
    npc_sprite.gd        ← NPC drop shadows
    character_sprite.gd  ← player drop shadow
  generator/
    camp_builder.gd      ← torch/campfire flicker lights
  player/
    player_controller.gd ← footstep dust particles
  ui/
    combat_vignette.gdshader  ← NEW: screen-edge darkening shader
    game_hud.gd               ← level-up flash overlay
    shop_ui.gd                ← 5 new magic weapons in shop tiers,
                                DANIELS_EXTRAS + CONNER T0 updates,
                                potion_shop tier logic fix
  dungeon.gd             ← combat vignette system
  main.gd                ← (no changes this session)
docs/
  theLongNights_systems_audit.md  ← NEW: full audit of original game systems
project.godot            ← Cinzel font as default
```

---

## Session 10 Notes — Vendor Rework & Cross-Class Forge Design
*2026-03-03*

### Vendor Reorganization

- **Daniels** (`armor_shop`) — renamed to "General Store". Sells T0 weapons, T0 armor, and signature extras (crystal wand, poison dart, boomerang). Only vendor that buys items back.
- **Steven** (`enhanced_weapons_shop`) — **NEW NPC**. Rescued alongside Mahan on Floor 2. Sells mid-to-high tier weapons (T1+). Does not buy items.
- **Mahan** (`enhanced_armor_shop`) — role changed from `weapon_shop`. Sells mid-to-high tier armor (T1+). Does not buy items.
- **Conner** — poison dart moved out of his shop; now Daniels-only.
- Rescue system changed from flat sequence to floor → NPC map (`NPC_UNLOCK_MAP`) to support multiple rescues per floor.

### Cross-Class Forge System (Design — not yet implemented)

Steven and Mahan will offer a **cross-save meta-progression** forge system:

- Playing a job class teaches Steven/Mahan that class's blueprint (persists in a global meta-save across all save slots)
- Class-specific items: +3 to primary stat + unlocks that class's skill for any job class
- **Reforge**: merge two class items into one — keeps both skills but loses 1 stat point per merge
- Endgame: all 9 classes learned → ultimate weapon/armor with all class skills but reduced stats
- Steven forges weapons, Mahan forges armor — 2× grind incentive

Full design doc: `assets/help/cross-class.md`

---

## Session 11 Summary — Accessories, Elixirs, Puzzle Rooms, Combat SFX, Forge System, and Minimap
*2026-03-03*

### 1. Accessory System + Equip Slot

Added a full accessory equipment system with a new `equip_accessory` slot and 8 unique accessories with passive effects:

| Accessory | Icon | Passive | Effect | Value | Loot Floor |
|-----------|------|---------|--------|-------|------------|
| **Blood Pendant** | blood_pendant.png | `on_kill_heal` | Gain 1 HP per kill | 50g | 3+ |
| **Ancient Amulet** | ancientAmulet.png | `all_stats` | +1 to all stats while equipped | 100g | 5+ |
| **Ring of Thorns** | red_ring_1.png | `thorns` | Reflect 2 damage back to melee attackers | 55g | 4+ |
| **Ring of Vampirism** | red_ring_2.png | `vampirism` | Heal 25% of melee damage dealt | 65g | 4+ |
| **Ring of Fortitude** | ring_silver_green.png | `fortitude` | +2 AC and +5 max HP while equipped | 70g | 5+ |
| **Phoenix Crystal** | pheonix_crystal.png | `phoenix` | Revive once per dungeon run at 50% HP | 120g | 7+ |
| **Gauntlet of Might** | gauntlet_of_strength.png | `atk_bonus` | +3 ATK while equipped | 80g | 6+ |
| **Hourglass of Haste** | pheonix_hourglass.png | `spd_bonus` | +2 SPD while equipped | 75g | 6+ |

#### Implementation Details
- New `ItemType.ACCESSORY` enum value added to `ItemDB`
- New `equip_accessory` equipment slot in `EQUIP_SLOTS`
- `_apply_accessory_stats(item, equipping)` handles stat add/remove on equip/unequip
- Passive data stored as `"passive"` and `"passive_value"` keys on item dicts (replaces old ad-hoc `on_kill_heal` / `all_stats_bonus` fields)
- Blood Pendant and Ancient Amulet migrated from `ItemType.MISC` to `ItemType.ACCESSORY`
- `is_accessory()` helper added to `ItemDB`
- Combat manager applies accessory on-hit/on-kill effects during damage resolution
- Inventory UI shows accessory slot in equipment panel

### 2. Permanent Stat Elixirs

Four rare permanent stat upgrade consumables, usable anywhere (including outside combat):

| Elixir | Icon | Stat | Amount | Value | Loot Floor |
|--------|------|------|--------|-------|------------|
| **Elixir of Power** | limited_potion_red.png | STR | +1 | 60g | 4+ |
| **Elixir of Iron** | limited_potion_grey.png | AC | +1 | 60g | 4+ |
| **Elixir of Vitality** | limited_potion_green.png | max HP | +5 | 60g | 5+ |
| **Elixir of Speed** | limited_potion_blue.png | SPD | +1 | 60g | 5+ |

- New `ItemType.ELIXIR` enum value — stackable, consumed on use
- `use_item()` handles elixir usage with permanent stat application
- Vitality elixir also heals the +5 HP immediately

**Files touched:**
- `dungeon_break/data/item_db.gd` — 8 accessories, 4 elixirs, new types/slots, `_apply_accessory_stats()`, `is_accessory()`
- `dungeon_break/data/game_data.gd` — `equip_accessory` slot
- `dungeon_break/combat/combat_manager.gd` — accessory passive effect hooks
- `dungeon_break/ui/inventory_ui.gd` — accessory slot display, elixir usage
- `dungeon_break/ui/shop_ui.gd` — accessory/elixir shop integration

---

### 3. Sokoban Push-Block Puzzle Rooms

Implemented a full puzzle room system ported from "The Long Nights" concept:

#### BSP Integration
- New `"puzzle"` room type assigned on **floors 3+** (one puzzle room per floor)
- Puzzle rooms forced flat (`floor_height = 0`) to avoid elevation issues
- Excluded from enemy spawning and clearable room counts

#### Puzzle Templates (6 hand-designed layouts)
| # | Name | Blocks | Difficulty |
|---|------|--------|------------|
| 0 | Straight Shot | 2 | Easy |
| 1 | L-Push | 2 | Easy-Medium |
| 2 | Trio | 3 | Medium |
| 3 | Diamond | 3 | Medium |
| 4 | Corner Trap | 3 | Medium-Hard |
| 5 | Cross | 4 | Hard |

Templates are randomly mirrored (50% X-flip) for variety. Template selection filters by room inner area to ensure fit.

#### Push Block (`push_block.gd`)
- `Node3D` script with grid-snapped movement
- `try_push(dir, voxel_tool)` — checks destination for floor + air + no other block
- `try_pull(dest, voxel_tool)` — allows pulling blocks (toggle with **F** key)
- `moved` signal fires after each 0.15s tween slide
- Visual: 0.9³ brown `BoxMesh` + drop shadow `QuadMesh`
- Turns green when sitting on a target tile
- `reset()` returns block to spawn position

#### Player Push/Pull Controls
- Player detects adjacent push blocks via grid position
- Movement toward a block pushes it; **F** toggles pull mode
- HUD shows current mode (PUSH/PULL) when in a puzzle room
- Pull mode auto-resets when leaving puzzle rooms

#### Puzzle Room Decoration
- Pressure plates stamped as `RUNE_CORE` voxels at target positions (glowing look)
- Soft blue-purple `OmniLight3D` at room centre
- Room-wide `Area3D` with `puzzle_reset` interaction — **[R] Reset Puzzle** prompt

#### Solve Logic
- `_check_puzzle_solved()` checks all targets covered by blocks
- On solve: room marked cleared, blocks freed, chest voxel spawned at room centre
- Reward: `15 + floor×5` gold + `10 + floor×3` XP
- Toast: "Puzzle solved! +Xg +Y XP"

#### Dungeon Infrastructure Improvements
- `VoxelViewer` kept alive for entire dungeon session (`_chunk_keeper`) — fixes chunks unloading and erasing stamped walls
- View distance scaled per floor tier: 56 (floors 1–3), 72 (floors 4–6), 96 (floors 7+)
- `refresh_voxel_tool()` added to `DungeonStamper` — ensures set_voxel works after terrain loads
- Longer initial wait for larger floors (2s → 3s → 4s)
- `_wait_for_terrain_editable()` extended to 600 frames with diagnostics
- New floor theme tier: floors 4–6 use **sandstone crypt** palette (`SAND` floor, `SAND_STONE` walls)
- Corridor width reduced from 2 to 1 tile
- Deeper floors get slightly wider torch range and ambient boost
- Read-back verification pass after stamping to detect voxel write failures

**Files touched:**
- `dungeon_break/world/push_block.gd` *(new)* — push block Node3D script
- `dungeon_break/dungeon.gd` — puzzle spawn/solve/reset logic, chunk keeper, voxel tool refresh, new floor themes, wider torch range
- `dungeon_break/generator/dungeon_stamper.gd` — `_build_puzzle_room()`, 6 puzzle templates, `refresh_voxel_tool()`, sandstone block constants, stamp verification
- `dungeon_break/generator/bsp_dungeon.gd` — puzzle room type assignment (floors 3+), corridor width → 1
- `dungeon_break/player/player_controller.gd` — push/pull block input handling
- `dungeon_break/ui/game_hud.gd` — block mode indicator (PUSH/PULL)

---

### 4. Procedural Combat Sound Effects

Created a Python tool (`tools/generate_sfx.py`) for procedural combat SFX generation and integrated 7 new sound effects:

| SFX | File | Used For |
|-----|------|----------|
| `slash.ogg` | `assets/sfx/combat/slash.ogg` | Swords, axes, blades, knives |
| `blunt.ogg` | `assets/sfx/combat/blunt.ogg` | Clubs, morningstars, spears |
| `magic.ogg` | `assets/sfx/combat/magic.ogg` | Staves, wands, darts |
| `ranged.ogg` | `assets/sfx/combat/ranged.ogg` | Bows, crossbows, boomerangs |
| `roar.ogg` | `assets/sfx/combat/roar.ogg` | Enemy/companion unarmed attacks |
| `miss.ogg` | `assets/sfx/combat/miss.ogg` | Dodge/whiff |
| `block_push.ogg` | `assets/sfx/combat/block_push.ogg` | Sokoban block scraping |

#### Generator (`tools/generate_sfx.py`)
- Pure Python + NumPy procedural audio synthesis
- ADSR envelope system
- Generates WAV then converts to OGG via ffmpeg
- Reproducible outputs, no external audio assets needed

#### Combat Integration
- `_get_weapon_sfx(weapon_id)` maps each weapon to its SFX category
- `_current_hit_sfx` tracks per-attack SFX for consistent weapon sounds
- All ranged weapon impact callbacks now use weapon-category SFX instead of generic `_SFX_HIT`
- Companion attacks use `_SFX_ROAR`; companion misses use `_SFX_COMBAT_MISS`
- Poison tick damage uses `_SFX_MAGIC`

**Files touched:**
- `tools/generate_sfx.py` *(new)* — procedural SFX generator
- `assets/sfx/combat/*.ogg` *(new, 7 files)* — generated combat SFX
- `dungeon_break/combat/combat_manager.gd` — weapon SFX mapping, per-attack SFX routing

---

### 5. Cross-Class Forge System (Full Implementation)

The forge design from Session 10 is now fully implemented as a working system:

#### Skyshard Earning
- Clearing a full dungeon floor **as a single class** (no class switching mid-floor) earns that class's **Skyshard**
- `ForgeSystem` autoload tracks class per floor via `track_room_entry()` / `track_room_clear()`
- Skyshard awarded on boss kill if floor is eligible (`try_award_skyshard()`)
- Each class skyshard can only be earned once

#### Forge Crafting (Steven = weapons, Mahan = armor)
- 9 class weapons + 9 class armors, each costing **100g + 1 Skyshard**
- Every forged item grants its class's combat skill (e.g., Vanguard Forgeblade grants Shield Wall)
- +5 ATK (weapons) or +3–5 AC (armor) + class-primary stat bonuses (+3 main stat)

| Class | Forged Weapon | Forged Armor |
|-------|---------------|--------------|
| Vanguard | Vanguard Forgeblade (+5 ATK, +3 STR) | Tower Shield Plate (+5 AC, +3 STR) |
| Scoundrel | Shadow Daggers (+5 ATK, +3 DEX) | Nightshade Leathers (+4 AC, +3 DEX) |
| Arcanist | Arcane Staff (+5 ATK, +3 INT) | Spellweave Robes (+3 AC, +3 INT) |
| Confessor | Holy Mace (+5 ATK, +2 INT/+1 LCK) | Blessed Vestments (+3 AC, +2 INT/+1 LCK) |
| Strider | Ranger's Longbow (+5 ATK, +2 DEX/+1 STR) | Scout's Chainmail (+4 AC, +2 DEX/+1 STR) |
| Minstrel | Songblade Rapier (+5 ATK, +2 LCK/+1 INT) | Bardic Mantle (+3 AC, +2 LCK/+1 INT) |
| Templar | Consecrated Blade (+5 ATK, +2 STR/+1 INT) | Paladin Cuirass (+5 AC, +2 STR/+1 INT) |
| Reanimator | Bone Sceptre (+5 ATK, +3 INT) | Necromancer's Shroud (+3 AC, +3 INT) |
| Tinkerer | Repeater Crossbow (+5 ATK, +2 DEX/+1 INT) | Cogwork Harness (+4 AC, +2 DEX/+1 INT) |

#### Reforge (Merge Two Forged Items)
- Costs **150g** — merges two forged items of the same type (both weapons or both armor)
- Combined item keeps both class skills but loses 1 random stat point per merge
- Max 3 class skills per merged item (`MAX_FORGE_SKILLS`)
- 2-merge items named "Forged Blade/Armor", 3-merge named "Master Blade/Armor"
- `preview_reforge()` shows what the result would be without committing

#### Forge Skill Slots
- Up to 3 forge skill actions can be slotted from forged items in backpack/equipment
- `slot_forge_skill()` / `unslot_forge_skill()` / `replace_forge_skill()`
- Active forge skills available in combat alongside the player's native job skill

#### Forge UI (`forge_ui.gd`)
- Modal overlay opened by interacting with Steven or Mahan in camp
- Shows available skyshards with class colors
- Forge, reforge, and skill slot management sections
- Feedback label with timed messages
- ESC to close

#### Save/Load Integration
- `ForgeSystem.to_save_dict()` / `from_save_dict()` — persists floor tracking, earned skyshards, and skill slots
- `reset_all()` for new game
- `reset_floor()` — wipes cleared rooms and tracking for retry

#### Art Assets
- 9 forged weapon art files in `assets/art/tools/weapon_*.png`
- 9 forged armor art files in `assets/art/tools/armor_*.png`

**Files touched:**
- `dungeon_break/data/forge_system.gd` *(new)* — full forge autoload (568 lines)
- `dungeon_break/ui/forge_ui.gd` *(new)* — forge modal UI (534 lines)
- `dungeon_break/data/item_db.gd` — 9 skyshards, 9 forged weapons, 9 forged armors
- `dungeon_break/data/game_data.gd` — forge state fields
- `dungeon_break/game.gd` — forge NPC interaction hookup
- `dungeon_break/dungeon.gd` — skyshard award on boss kill, room tracking calls
- `dungeon_break/combat/combat_manager.gd` — forge skill usage in combat
- `dungeon_break/combat/combat_ui.gd` — forge skill buttons
- `dungeon_break/player/isometric_camera.gd` — camera adjustments
- `dungeon_break/player/player_controller.gd` — forge NPC interaction key
- `project.godot` — `ForgeSystem` autoload registered
- `assets/art/tools/*.png` *(new, 18 files)* — forged weapon/armor art

---

### 6. Dungeon Minimap Overlay

Added a real-time minimap in the top-left corner of the dungeon HUD:

#### Visual Design
- 200×200px semi-transparent overlay (layer on top of game)
- Toggle with **[M]** key
- Floor label ("F1", "F2", etc.) in top-left; "[M] Map" hint in bottom-right

#### Room Rendering
- Rooms drawn as coloured rectangles with uniform-scale aspect-ratio-preserving mapping
- Colour key:
  - **Dark gray** — undiscovered
  - **Yellow** — visited but not cleared
  - **Green** — cleared
  - **Cyan pulsing border** — current room
  - **Red tint** — boss room
  - **Blue tint** — puzzle room
  - **White tint** — start room
- Corridor tiles drawn as small filled squares (only near visited rooms for fog-of-war effect)

#### Player Tracking
- White pulsing dot with cyan outer ring tracks player position in real-time
- Position clamped inside map bounds
- Pulse animation via sine wave on `_process`

#### Data Flow
- `dungeon.gd` calls `minimap.set_dungeon_data()` after BSP stamping with room array, grid, dimensions, and offsets
- `update_player_pos()` called every frame with player world position
- `mark_visited()` / `mark_cleared()` / `set_current_room()` called on room state changes
- Minimap hidden during combat via `combat_ui.gd` integration

**Files touched:**
- `dungeon_break/ui/minimap.gd` *(new)* — full minimap Control (271 lines)
- `dungeon_break/dungeon.gd` — minimap data feeding and state updates
- `dungeon_break/combat/combat_ui.gd` — hide/show minimap during combat

---

### 7. New Entity Sprites (Batch Import)

Added 26 new enemy/creature sprite images for the entity bestiary:

alien_hunter, angry_ghost, bubble_fish, corrupted_citizen, dire_wolf, goblin, goblin_bomb_bard, goblin_grunt, goblin_killdozer, goblin_king_krogg, goblin_shaman, goblin_shamanka, goblin_war_chieftan, hunting_construct, iron_golem, kraken_spawn, lich_lord_morteus, mechanical_spider, rat, scatterer, scolopendra_spawn, skeleton_archer, skeleton_mage, troglodyte, tunnel_rat, urban_predator-cat, vine_creeper, water_elemental, wraith, zombie_brute, zombie_crawler

All placed in `assets/art/entities/` with `.import` configs.

---

## Current State After Session 11

### Accessories & Elixirs
- 8 equippable accessories with passive effects (thorns, vampirism, fortitude, phoenix revive, stat bonuses)
- 4 permanent stat elixirs (STR, AC, HP, SPD) — rare dungeon loot
- New `ACCESSORY` and `ELIXIR` item types

### Puzzle Rooms
- Sokoban push-block puzzles on floors 3+ (6 templates, random mirror)
- Push (**WASD**) and pull (**F** toggle) mechanics
- Pressure plate targets, reset prompt, gold + XP rewards on solve
- Sandstone crypt floor theme (floors 4–6)

### Cross-Class Forge
- Earn skyshards by clearing floors as a single class
- Steven forges weapons, Mahan forges armor (100g + skyshard)
- 9 class weapons and 9 class armors, each granting their class skill
- Reforge system merges two forged items (150g, skills combine, -1 stat penalty)
- Up to 3 forge skill slots for combat
- Full save/load support

### Combat SFX
- 7 procedural combat sound effects (slash, blunt, magic, ranged, roar, miss, block_push)
- Per-weapon SFX category mapping

### Minimap
- Real-time 200×200px overlay with room states, player dot, fog-of-war corridors
- Color-coded room types (boss=red, puzzle=blue, start=white)
- Toggle with [M]

### Dungeon Infrastructure
- Persistent chunk keeper prevents voxel unloading
- View distance scaled per floor tier
- Voxel tool refresh after terrain load
- Stamp verification pass
- Corridor width reduced to 1

---

## Known Pending Work (Updated)

| Item | Priority | Notes |
|---|---|---|
| Fire staff AoE nerf | High | Exclude friendly units from splash damage |
| Forge skill integration in combat | High | Forge skills appear as extra buttons in combat UI — needs testing |
| Push block SFX in combat | Medium | `block_push.ogg` generated but not yet wired to puzzle push events |
| Camp NPC dialogue | Medium | Joe, Mira, Old Pell — interaction zones exist, no dialogue tree yet |
| Vault room loot pass | Medium | Currently has chest + gold ore; needs richer decoration and varied loot |
| Gamepad support | Medium | Needs InputMap refactor + UI focus chains |
| Visual novel cutscenes | Low | Planned for story beats |
| Drag-and-drop inventory | Low | Current inventory is click-to-equip only |
| Save slot delete | Low | No way to clear a save slot from the UI |

---

## File Index (additions since session 10)

```
dungeon_break/
  combat/
    combat_manager.gd     ← accessory passive hooks, weapon SFX mapping,
                             forge skill usage, per-attack SFX routing
    combat_ui.gd          ← forge skill buttons, minimap hide/show
  data/
    forge_system.gd       ← NEW: cross-class forge autoload (skyshards,
                             forging, reforging, skill slots, save/load)
    game_data.gd          ← equip_accessory slot, forge state fields
    item_db.gd            ← 8 accessories, 4 elixirs, 9 skyshards,
                             9 forged weapons, 9 forged armors,
                             ACCESSORY/ELIXIR types, _apply_accessory_stats()
  entities/
    entity_manager.gd     ← minor fix
  generator/
    bsp_dungeon.gd        ← puzzle room type (floors 3+), corridor width → 1
    dungeon_stamper.gd    ← _build_puzzle_room(), 6 puzzle templates,
                             refresh_voxel_tool(), sandstone blocks,
                             stamp verification, floor theme tiers
  player/
    isometric_camera.gd   ← camera adjustments
    player_controller.gd  ← push/pull block input, forge NPC interaction
  ui/
    forge_ui.gd           ← NEW: forge modal UI (534 lines)
    game_hud.gd           ← block mode indicator (PUSH/PULL)
    inventory_ui.gd       ← accessory slot, elixir usage
    minimap.gd            ← NEW: dungeon minimap overlay (271 lines)
    shop_ui.gd            ← accessory/elixir shop integration
  world/
    push_block.gd         ← NEW: sokoban push block (176 lines)
  dungeon.gd              ← puzzle spawn/solve/reset, chunk keeper,
                             voxel tool refresh, minimap data feed,
                             skyshard award, sandstone theme, torch scaling
  game.gd                 ← forge NPC interaction hookup
  main.gd                 ← minor cleanup
tools/
  generate_sfx.py         ← NEW: procedural combat SFX generator
assets/
  art/entities/*.png      ← 26+ new entity sprites
  art/tools/*.png         ← 18 forged weapon/armor art files
  sfx/combat/*.ogg        ← 7 new combat sound effects
project.godot             ← ForgeSystem autoload registered
```

---

## Session 12 Summary — Combat VFX, Entity Audit, Companion Bug Fix, Inventory Companion Roster

### 1. Tilt-Shift Shader System

Added a screen-space tilt-shift blur shader for depth-of-field effect during exploration and combat.

- **Shader:** `dungeon_break/ui/tilt_shift.gdshader` — horizontal blur with configurable focus band position and width
- **GraphicsManager integration:** LOW/MEDIUM/HIGH presets control blur strength; exploration vs combat have separate settings (combat sharpens focus)
- **Dungeon hooks:** `tilt_shift_enter_combat()` / `tilt_shift_exit_combat()` on `main.gd` for smooth transitions
- **HUD toggle:** settings gear lets the player toggle tilt-shift on/off

**Files changed:**
- `dungeon_break/ui/tilt_shift.gdshader` — NEW
- `dungeon_break/data/graphics_manager.gd` — tilt-shift preset values
- `dungeon_break/main.gd` — tilt-shift overlay CanvasLayer + combat tween methods
- `dungeon_break/ui/game_hud.gd` — toggle UI in settings
- `dungeon_break/dungeon.gd` — combat enter/exit hooks

---

### 2. Combat VFX Enhancements (6 features)

Added visual identity to the tactical combat system:

| Feature | Description |
|---|---|
| **Bigger Floating Text** | Font size 32→44, outline 8→12, pixel_size 0.008→0.009, pop scale 1.4→1.8, rise 1.8→2.2, delay 0.22→0.35 |
| **Active Unit Glow** | Pulsing `circle_01.png` flat under active unit's feet — green (player), blue (companion), red (enemy) |
| **Death Poof Effect** | Star flash + 6 smoke puffs expanding outward + camera shake on enemy/companion death |
| **Combat Start/End Banners** | Full-width dark banner at 32% screen height: "⚔ COMBAT! ⚔" (gold), "⚔ VICTORY! ⚔" (green), "☠ DEFEAT ☠" (red) |
| **Round Transition Banners** | "— Round X —" banner for rounds 2+ (light blue, 0.8s hold) |
| **Environmental Combat Lighting** | Warm amber `OmniLight3D` (energy 0.55, range 14) spawned above room center during combat |

**Files changed:**
- `dungeon_break/combat/combat_manager.gd` — new signal `round_started`, new vars `_active_glow`, `_combat_light`; new methods `_fx_death_poof()`, `_show_active_glow()`, `_hide_active_glow()`, `_update_active_glow_pos()`, `_spawn_combat_light()`, `_remove_combat_light()`
- `dungeon_break/combat/combat_ui.gd` — `_show_banner()` method, `_on_round_started()`, banner calls in `_on_combat_started()` and `_on_combat_ended()`

---

### 3. Entity Sprite Audit & Fixes

Audited `entities.json` against on-disk sprite files to fix invisible enemies appearing in the combat tracker.

**Root cause:** `EntityManager.spawn_entity()` does NOT return null for missing textures — it creates an entity with an empty `Sprite3D` (invisible but present in combat). Enemies with no sprite files showed up in the tracker but were invisible in the 3D scene.

**Fixes applied:**
| Issue | Resolution |
|---|---|
| `goblin_engineer` — zero sprite files on disk | Removed from `entities.json` entirely |
| `goblin_shamanka` — portrait was `.png`, JSON expected `.jpeg` | Converted PNG → JPEG |
| `goblin_war_chieftain` — typo in filename (`chieftan` vs `chieftain`) | Copied file with correct name |
| `urban_predator` — portrait filename mismatch (`urban_predator-cat.jpeg`) | Copied as `urban_predator.jpeg` |

12 remaining missing `sprite_attack` entries are all `type: "companion"` race templates (human/elf/dwarf/goblin variants) — don't spawn in combat, non-issue.

**Files changed:**
- `assets/art/entities/entities.json` — `goblin_engineer` entry removed
- `assets/art/entities/` — 3 portrait files created/copied

---

### 4. Companion Combat Bug — Diagnosis & Fix

**Bug report:** Companions sometimes don't show up in combat even though they should be alive.

**Root cause:** Two issues working together:
1. **Silent skip with zero logging** — In both `_trigger_room_combat()` and `_spawn_companion_followers()`, if `GameData.get_companion(key)` or `EnemyDB.get_enemy(key)` returns empty, the companion is silently skipped with a bare `continue` — no warning, no log.
2. **Permadeath too quiet** — When a companion dies in combat, a single line scrolls past in the combat log: `"[Name] has fallen! (Permadeath)"`. No banner, no pause, no post-combat summary. Easy to miss in fast combats.

**Fixes applied:**

| Fix | Description |
|---|---|
| **Companion death banner** | `combat_ui.gd` — orange "☠ [Name] has fallen! ☠" banner (1.5s) on companion death, same style as victory/defeat banners |
| **Post-combat loss toast** | `dungeon.gd` — snapshots `active_companions` before combat; after combat diffs against current roster and shows HUD toast: "[Name] was lost in battle." |
| **`push_warning` on silent skips** | Both `_trigger_room_combat()` and `_spawn_companion_followers()` now log warnings with the key and which lookup failed |
| **Debug print at combat start** | Prints full `active_companions` roster to console for troubleshooting |

**Files changed:**
- `dungeon_break/combat/combat_ui.gd` — `_on_unit_defeated()` now shows death banner for companions
- `dungeon_break/dungeon.gd` — new `_pre_combat_companions` var, snapshot logic in `_trigger_room_combat()`, loss report in `_on_combat_ended()`, `push_warning` in both companion spawn paths

---

### 5. Inventory Companion Roster Panel

Added a companion roster section to the bottom-right of the inventory screen, below the CHARACTER stats column.

**Layout per card:**
- Dark panel with green border (active) or muted border (benched)
- **Portrait** (32×32) from `EnemyDB.get_portrait_path()`
- **Name** — bright for active, dimmed for benched
- **HP bar** — color-coded green/yellow/red by health ratio
- **HP text** — e.g. "HP 5/20"
- **Equipment line** — "⚔ Weapon Name  🛡 Armor Name" (only shown if equipped, font size 8, light blue tint)
- **Status badge** — "ACTIVE" (green) or "BENCHED" (muted), right-aligned

Section header "COMPANIONS" with separator. Hidden when roster is empty. Max 3 cards (matches the companion slot cap). Refreshes on every inventory open.

**Files changed:**
- `dungeon_break/ui/inventory_ui.gd` — new `_companion_container` var, companion section in `_build_stats_col()`, `_refresh_companions()` method called from `_refresh()`

---

### File Change Summary

```
dungeon_break/
  combat/
    combat_manager.gd     ← 6 VFX features (glow, poof, light, banners, text),
                             round_started signal, active glow lifecycle
    combat_ui.gd          ← banner system, round banners, companion death banner
  data/
    graphics_manager.gd   ← tilt-shift preset values
  ui/
    tilt_shift.gdshader   ← NEW: screen-space tilt-shift blur
    game_hud.gd           ← tilt-shift toggle
    inventory_ui.gd       ← companion roster panel with equipment display
  dungeon.gd              ← tilt-shift hooks, companion loss tracking,
                             push_warning on silent skips, debug prints
  main.gd                 ← tilt-shift overlay + combat transitions
assets/
  art/entities/entities.json  ← goblin_engineer removed
  art/entities/*.jpeg         ← 3 portrait files fixed/created
```
