# Dungeon Break — Project State Document (continued)
*Continued from `updated.md`. Last updated: 2026-03-02 (session 9)*

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
