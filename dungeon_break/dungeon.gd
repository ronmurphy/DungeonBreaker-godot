extends Node
## Dungeon scene — BSP dungeon floor with enemies and combat.
##
## Manages dungeon terrain, stamping, enemy spawning, and transition back.

const PlayerScene = preload("res://dungeon_break/player/player.tscn")
const DungeonStamperScript = preload("res://dungeon_break/generator/dungeon_stamper.gd")
const CombatManagerScript = preload("res://dungeon_break/combat/combat_manager.gd")
const CombatUIScript = preload("res://dungeon_break/combat/combat_ui.gd")
const GameHudScript = preload("res://dungeon_break/ui/game_hud.gd")
const InventoryUIScript = preload("res://dungeon_break/ui/inventory_ui.gd")

signal return_to_camp()
signal advance_floor()
signal dungeon_ready()
signal player_defeated()

@onready var _terrain: VoxelTerrain = $VoxelTerrain
@onready var _players: Node = $Players
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _dir_light: DirectionalLight3D = $DirectionalLight3D

var _player: Node3D = null
var _camera: Camera3D = null
var _dungeon_stamper = null
var _dungeon_objects: Node3D = null
var _combat_manager: Node = null

var _floor_num: int = 1
var _combat_active: bool = false
var _hud: CanvasLayer = null
var _combat_floor_height: int = 0  # elevation of the active combat room
var _terrain_mat: StandardMaterial3D = null
var _wall_tween: Tween = null
var _e_was_pressed: bool = false
var _chunk_keeper: VoxelViewer = null  # keeps all dungeon chunks loaded

# Combat vignette overlay
var _vignette_layer: CanvasLayer = null
var _vignette_rect: ColorRect = null
var _vignette_mat: ShaderMaterial = null

## Ambient light levels for the dungeon environment
const DUNGEON_AMBIENT := 0.05   # dark exploration
const COMBAT_AMBIENT  := 0.35   # readable tactical grid
const DUNGEON_GI_ENERGY := 0.18 # subtle bounce so walls are still readable
const LOW_MED_DUNGEON_AMBIENT := 0.10 # slight fallback lift when SDFGI is disabled
const LOW_MED_FILL_ENERGY := 0.20
const LOW_MED_FILL_RANGE := 14.0
const GRAPHICS_PRESET_HIGH := 2

## Torch light node (OmniLight3D parented to player, only in dungeon)
var _torch_light: OmniLight3D = null
var _fallback_fill_light: OmniLight3D = null

## Dynamic ambient targets (quality-preset aware)
var _explore_ambient: float = DUNGEON_AMBIENT
var _combat_ambient: float = COMBAT_AMBIENT

## Rooms the player has visited this run — keyed by room id (int → true)
var _visited_rooms: Dictionary = {}

## Accumulator for torch fuel burn (fuel is int, burn rate is float)
var _torch_burn_accum: float = 0.0
const TORCH_BURN_RATE := 0.15  # fuel per second; full torch lasts ~11 min

## Companion follower entities (visible outside combat, trail behind player)
var _companion_followers: Array = []
var _player_pos_history: Array = []


func _ready():
	_dungeon_objects = Node3D.new()
	_dungeon_objects.name = "DungeonObjects"
	add_child(_dungeon_objects)

	_floor_num = GameData.current_floor
	GameData.in_dungeon = true

	# Build dungeon after a short delay for terrain loading
	call_deferred("_build_dungeon")


func set_floor(floor_num: int):
	_floor_num = floor_num


func _build_dungeon():
	_dungeon_stamper = DungeonStamperScript.new()
	_dungeon_stamper.setup(_terrain, _dungeon_objects)

	# Add a temporary VoxelViewer at origin to force chunk loading.
	# Without this, no chunks load (real viewer is on the player, who
	# hasn't been spawned yet) and set_voxel() edits silently fail.
	#
	# view_distance is in VOXELS (world units). The dungeon grid is centred
	# at origin, so the farthest point is a grid corner at distance:
	#   sqrt((cols/2)² + (rows/2)²)
	# Floors 1-3: 64×64 → corner ~45 vx   Floors 4-6: 80×80 → ~57 vx
	# Floors 7+:  96×96 → corner ~68 vx
	# We pick the smallest value per tier that covers the corners + margin,
	# to avoid requesting so many chunks that the loader can't finish in time.
	var view_dist: int
	if _floor_num <= 3:
		view_dist = 56   # covers corner 45 + headroom
	elif _floor_num <= 6:
		view_dist = 72   # covers corner 57 + headroom
	else:
		view_dist = 96   # covers corner 68 + headroom

	# Keep this viewer alive for the entire dungeon session.
	# Without a stream/save on VoxelTerrain, freeing the viewer causes
	# chunks to unload and regenerate from the base generator, erasing
	# all stamped walls/floors.
	_chunk_keeper = VoxelViewer.new()
	_chunk_keeper.name = "ChunkKeeper"
	_chunk_keeper.position = Vector3.ZERO
	_chunk_keeper.view_distance = view_dist
	_chunk_keeper.requires_visuals = true
	_chunk_keeper.requires_collisions = true
	_terrain.add_child(_chunk_keeper)

	# Give chunks time to generate around the viewer — larger floors need longer
	var initial_wait := 2.0 if _floor_num <= 3 else (3.0 if _floor_num <= 6 else 4.0)
	await get_tree().create_timer(initial_wait).timeout
	await _wait_for_terrain_editable(view_dist)

	# IMPORTANT: refresh the stamper's voxel tool AFTER terrain is loaded.
	# The tool obtained in setup() may reference a terrain state with no
	# loaded chunks. Getting a fresh one now ensures set_voxel() works.
	_dungeon_stamper.refresh_voxel_tool()
	print("Dungeon: building floor %d (view_dist=%d, grid will be generated next)" % [_floor_num, view_dist])

	# Cache wall material for combat transparency toggling (floor blocks use the other material)
	_terrain_mat = load("res://blocky_game/blocks/terrain_material_wall.tres") as StandardMaterial3D

	# Seed the RNG so the same floor can be reproduced on load.
	# A new floor generates a fresh seed; loading restores the saved one.
	if GameData.dungeon_seed == 0:
		GameData.dungeon_seed = randi() | 1  # |1 avoids seed(0) edge case
	seed(GameData.dungeon_seed)
	GameData.scene_state = "dungeon"

	var data: Dictionary = _dungeon_stamper.build_dungeon(_floor_num)

	# NOTE: _chunk_keeper is intentionally kept alive — see comment above.

	if data.is_empty():
		push_error("Dungeon: failed to generate floor %d" % _floor_num)
		return

	# Restore cleared state for any rooms beaten on a previous visit to this floor.
	# Must happen before _spawn_enemies() so those rooms are skipped.
	var boss_already_cleared: bool = false
	for room in data["rooms"]:
		if GameData.is_room_cleared(_floor_num, room["id"]):
			room["state"] = "cleared"
			if room["room_type"] == "boss":
				boss_already_cleared = true

	# Spawn player at start room
	var start_pos: Vector3 = _dungeon_stamper.get_start_position()
	_spawn_player(start_pos)
	_spawn_companion_followers(start_pos)

	# Spawn enemies in uncleared rooms
	_spawn_enemies(data)

	# Connect portal triggers
	_connect_portals()

	# HUD
	_hud = GameHudScript.new()
	_hud.name = "GameHUD"
	add_child(_hud)
	_hud.set_dungeon_mode(true)

	# Inventory UI (toggle with I or TAB)
	var inv_ui := InventoryUIScript.new()
	inv_ui.name = "InventoryUI"
	add_child(inv_ui)

	# Give player starter gear on first run
	if GameData.equip_weapon.is_empty():
		ItemDB.equip_item(ItemDB.create_item("club"))
	if GameData.equip_chest.is_empty():
		ItemDB.equip_item(ItemDB.create_item("chest_leather"))
	if GameData.backpack.is_empty():
		ItemDB.add_to_backpack(ItemDB.create_item("bread"))
		ItemDB.add_to_backpack(ItemDB.create_item("bread"))
		ItemDB.add_to_backpack(ItemDB.create_item("baked_potato"))
		ItemDB.add_to_backpack(ItemDB.create_item("potion_red"))
		if GameData.gold == 0:
			GameData.add_gold(15)

	# Darken the dungeon: kill the directional sun (it shines into every open-top room)
	# and bring ambient down to near-zero. Corridor sconces + player torch + room lights
	# on entry are the only illumination.
	if _dir_light:
		_dir_light.light_energy = 0.0

	if GraphicsManager and not GraphicsManager.preset_changed.is_connected(_on_graphics_preset_changed):
		GraphicsManager.preset_changed.connect(_on_graphics_preset_changed)
	_apply_quality_fallback_lighting()

	# Start room (id 0) is always pre-revealed — player spawns there
	_visited_rooms[0] = true
	_enable_room_lights(0)

	# If the boss room was already cleared on a previous visit, re-open the portal
	if boss_already_cleared:
		_enable_boss_portal()

	MusicManager.play_dungeon()
	print("Dungeon: floor %d ready — %d rooms" % [_floor_num, data["rooms"].size()])
	dungeon_ready.emit()


func _spawn_player(pos: Vector3):
	_player = PlayerScene.instantiate()
	_player.name = "LocalPlayer"
	_player.position = pos
	_player.terrain = _terrain.get_path()
	_players.add_child(_player)

	_camera = _player.get_node("IsometricCamera") as Camera3D
	if _camera and _camera.has_method("set_follow_target"):
		_camera.set_follow_target(_player)

	if EntityManager:
		EntityManager.set_camera(_camera)

	_camera.global_position = pos + Vector3(12, 16, 12)

	# Torch light — warm OmniLight parented to player, dims as torch_fuel drains
	_torch_light = OmniLight3D.new()
	_torch_light.name = "TorchLight"
	_torch_light.light_color = Color(1.0, 0.75, 0.3)
	_torch_light.omni_attenuation = 1.5
	_torch_light.shadow_enabled = false
	_player.add_child(_torch_light)
	_torch_light.position = Vector3(0.0, 1.5, 0.0)
	_update_torch_light()

	# Low/Medium quality fallback fill light (kept subtle; disabled on High).
	_fallback_fill_light = OmniLight3D.new()
	_fallback_fill_light.name = "QualityFallbackFillLight"
	_fallback_fill_light.light_color = Color(0.82, 0.88, 0.95)
	_fallback_fill_light.light_energy = LOW_MED_FILL_ENERGY
	_fallback_fill_light.omni_range = LOW_MED_FILL_RANGE
	_fallback_fill_light.omni_attenuation = 1.0
	_fallback_fill_light.shadow_enabled = false
	_fallback_fill_light.visible = false
	_player.add_child(_fallback_fill_light)
	_fallback_fill_light.position = Vector3(0.0, 2.0, 0.0)


func _spawn_enemies(data: Dictionary):
	var rooms: Array = data["rooms"]
	var ox: int = data["offset_x"]
	var oz: int = data["offset_z"]

	# Count and store the total number of clearable rooms for this floor
	var clearable_count: int = 0
	for room in rooms:
		if room["room_type"] not in ["start", "bonfire", "fountain", "alchemy", "puzzle", "vault"]:
			clearable_count += 1
	GameData.set_floor_room_count(_floor_num, clearable_count)

	var floor_enemies: Array = EnemyDB.get_enemies_for_floor(_floor_num)
	if floor_enemies.is_empty():
		push_warning("Dungeon: no enemies for floor %d" % _floor_num)
		return

	for room in rooms:
		# Only spawn in uncleared normal/trap/locked rooms
		if room["state"] != "uncleared":
			continue
		if room["room_type"] in ["start", "bonfire", "fountain", "alchemy", "puzzle", "vault"]:
			continue

		# Enemy count: 1–3 for normal, 1 for boss
		var count := 1
		if room["room_type"] == "normal":
			count = randi_range(1, 3)
		elif room["room_type"] == "trap":
			count = randi_range(2, 3)

		# Store enemy blueprints — actual entities are spawned on combat entry.
		# This avoids hitting the EntityManager pool cap on large floors.
		if not room.has("enemy_blueprints"):
			room["enemy_blueprints"] = []

		for i in count:
			var key: String = floor_enemies[randi() % floor_enemies.size()]
			var stats: Dictionary = EnemyDB.get_scaled_enemy(key, _floor_num)
			stats = EnemyDB.apply_variant(stats)

			# Store max HP before any damage
			stats["hp_max"] = stats.get("hp", 20)

			# Random position inside room (clamped to avoid walls)
			var rx_min: int = room["x"] + 1
			var rx_max: int = room["x"] + maxi(2, room["w"] - 2)
			var ry_min: int = room["y"] + 1
			var ry_max: int = room["y"] + maxi(2, room["h"] - 2)
			var ex: float = randi_range(rx_min, rx_max) + ox + 0.5
			var ez: float = randi_range(ry_min, ry_max) + oz + 0.5
			var ey: float = room.get("floor_height", 0) + 1.5

			stats["room_id"] = room["id"]
			stats["entity_key"] = key

			room["enemy_blueprints"].append({
				"key": key,
				"stats": stats,
				"pos": Vector3(ex, ey, ez),
			})


## Spawn actual enemy entities from stored blueprints when entering a room.
## Only the current room's enemies exist as entities, keeping the pool small.
func _materialize_room_enemies(room: Dictionary):
	var blueprints: Array = room.get("enemy_blueprints", [])
	if blueprints.is_empty():
		return
	for bp: Dictionary in blueprints:
		var key: String = bp["key"]
		var stats: Dictionary = bp["stats"]
		var pos: Vector3 = bp["pos"]
		var tex_path: String = EnemyDB.get_ready_texture_path(key)
		var entity: Node3D = EntityManager.spawn_entity(pos, tex_path, stats)
		if entity:
			room["enemies"].append(entity)
		else:
			push_warning("Dungeon: failed to spawn enemy '%s' — entity pool may be full (%d active)" % [key, EntityManager.get_active_count()])
	# Clear blueprints so they aren't spawned again if player re-enters
	room["enemy_blueprints"].clear()


func _connect_portals():
	# Find all Area3D nodes in dungeon objects and connect body_entered
	for child in _dungeon_objects.get_children():
		if child is Area3D:
			child.body_entered.connect(_on_area_body_entered.bind(child))
			# Also detect CharacterBody3D — but our player is Node3D with VoxelBoxMover
			# So we use area overlap with player proximity check instead


func _process(delta: float):
	if _player == null or _dungeon_stamper == null:
		return

	# Burn torch fuel while exploring (not during combat — give player a breather)
	if not _combat_active:
		_torch_burn_accum += delta * TORCH_BURN_RATE
		if _torch_burn_accum >= 1.0:
			var burned: int = int(_torch_burn_accum)
			_torch_burn_accum -= float(burned)
			GameData.torch_fuel = maxi(0, GameData.torch_fuel - burned)
	_update_torch_light()

	# Update dungeon HUD clock from shared world time
	if _hud:
		var hour := GameData.get_world_hour()
		var h := int(hour)
		var m := int((hour - h) * 60)
		_hud.set_time_text("%s  %02d:%02d" % [GameData.get_world_time_name(), h, m])

	# Safety: teleport player back if they fall into the void
	if _player.global_position.y < -15.0:
		var start_pos: Vector3 = _dungeon_stamper.get_start_position()
		_player.global_position = start_pos
		print("Dungeon: player fell into void — teleported to start")

	# Update companion followers trailing behind player
	if not _combat_active:
		_update_companion_followers()

	# Check player proximity to portal areas (since we use VoxelBoxMover, not CharacterBody)
	_check_area_interactions()


func _check_area_interactions():
	var player_pos := _player.global_position
	var near_anything := false
	var e_pressed: bool = Input.is_key_pressed(KEY_E)
	var e_just_pressed: bool = e_pressed and not _e_was_pressed

	for child in _dungeon_objects.get_children():
		if not (child is Area3D):
			continue

		var dist := player_pos.distance_to(child.global_position)
		if dist > 3.0:
			# Puzzle reset areas cover the whole room — use a larger distance
			if child.get_meta("interaction", "") == "puzzle_reset":
				if dist > 15.0:
					continue
			else:
				continue

		var interaction: String = child.get_meta("interaction", "")

		# Puzzle reset areas don't count as "near" unless the puzzle is unsolved
		if interaction == "puzzle_reset":
			var _prid: int = child.get_meta("room_id", -1)
			var _proom: Dictionary = _get_room_by_id(_prid)
			if _proom.is_empty() or _proom.get("state", "") != "uncleared":
				continue

		near_anything = true

		match interaction:
			"return_portal":
				if _hud:
					_hud.show_prompt("[E] Return to Camp")
				if e_just_pressed:
					_do_return_to_camp()
			"bonfire":
				if _hud:
					_hud.show_prompt("[E] Rest at Bonfire")
				if e_just_pressed:
					_do_bonfire_rest()
			"fountain":
				if _hud:
					_hud.show_prompt("[E] Drink from Fountain")
				if e_just_pressed:
					_do_fountain_heal()
			"alchemy":
				if _hud:
					_hud.show_prompt("[E] Brew Random Potion (10g)")
				if e_just_pressed:
					_do_alchemy_brew()
			"vault":
				if not child.get_meta("looted", false):
					if _hud:
						_hud.show_prompt("[E] Open Vault Chest")
					if e_just_pressed:
						_do_vault_loot(child)
			"boss_portal":
				if child.get_meta("enabled", false):
					if _hud:
						_hud.show_prompt("[E] Descend to Next Floor")
					if e_just_pressed:
						_do_advance_floor()
			"puzzle_reset":
				if _hud:
					_hud.show_prompt("[R] Reset Puzzle")
				if Input.is_key_pressed(KEY_R):
					var prid: int = child.get_meta("room_id", -1)
					var proom: Dictionary = _get_room_by_id(prid)
					if not proom.is_empty():
						_reset_puzzle(proom)

	if not near_anything and _hud:
		_hud.hide_prompt()

	_e_was_pressed = e_pressed

	# Check room entry: reveal lights on first visit, trigger combat if uncleared
	if not _combat_active:
		var room: Dictionary = _dungeon_stamper.get_room_at_world(player_pos)
		if not room.is_empty():
			var rid: int = room["id"]

			# Update push/pull mode indicator based on puzzle room presence
			var in_puzzle: bool = room["room_type"] == "puzzle"
			if _player and "_in_puzzle_room" in _player:
				# Changed to a different puzzle state → handle
				if _player._in_puzzle_room != in_puzzle:
					_player._in_puzzle_room = in_puzzle
					if not in_puzzle:
						_player._pull_mode = false  # reset to push when leaving
						if _hud and _hud.has_method("hide_block_mode"):
							_hud.hide_block_mode()
					else:
						if _hud and _hud.has_method("set_block_mode"):
							_hud.set_block_mode("PUSH")

			if not _visited_rooms.has(rid):
				_visited_rooms[rid] = true
				_enable_room_lights(rid)
				# Spawn puzzle blocks on first visit to a puzzle room
				if room["room_type"] == "puzzle" and room.has("puzzle"):
					_spawn_puzzle_blocks(room)
			if room["state"] == "uncleared" and room["room_type"] != "puzzle":
				_trigger_room_combat(room)


func _trigger_room_combat(room: Dictionary):
	# Materialize enemy entities from blueprints (lazy spawn)
	_materialize_room_enemies(room)

	if room["enemies"].is_empty():
		room["state"] = "cleared"
		return

	_combat_active = true
	_combat_floor_height = room.get("floor_height", 0)
	if _player:
		_player.combat_locked = true
	_set_wall_combat_mode(true)

	# Combat-entry vignette pulse
	_show_combat_vignette()

	# Hide follower entities — combat spawns fresh entities placed on the grid
	for f: Node3D in _companion_followers:
		if is_instance_valid(f):
			f.visible = false
	print("Dungeon: combat started in room %d (%s) elev=%d" % [room["id"], room["room_type"], _combat_floor_height])

	# Inject dungeon offsets into room dict for the tactical grid
	room["_offset_x"] = _dungeon_stamper.dungeon_data.get("offset_x", 0)
	room["_offset_z"] = _dungeon_stamper.dungeon_data.get("offset_z", 0)

	# Spawn companion entities for active companions
	var companion_entities: Array = []
	print("Dungeon: combat companion spawn — active_companions = %s" % [GameData.active_companions])
	for ckey: String in GameData.active_companions:
		var cdata: Dictionary = GameData.get_companion(ckey)
		var edata: Dictionary = EnemyDB.get_enemy(ckey)
		if cdata.is_empty() or edata.is_empty():
			print("Dungeon: SKIP combat companion '%s' — cdata.empty=%s edata.empty=%s" % [ckey, cdata.is_empty(), edata.is_empty()])
			continue
		var tex_path: String = EnemyDB.get_ready_texture_path(ckey)
		var ox2: int = room["_offset_x"]
		var oz2: int = room["_offset_z"]
		var ex: float = float(room["cx"] + ox2 - 1 - companion_entities.size()) + 0.5
		var ey: float = float(room.get("floor_height", 0)) + 1.5
		var ez: float = float(room["cy"] + oz2) + 0.5
		var centity: Node3D = EntityManager.spawn_entity(Vector3(ex, ey, ez), tex_path, {
			"entity_key": ckey,
			"name":        cdata.get("name", edata.get("name", ckey)),
			"hp":          cdata["hp"],
			"hp_max":      cdata["hp_max"],
			"attack":      cdata["attack"] + int(cdata.get("equip_weapon", {}).get("attack_bonus", 0)),
			"defense":     cdata["defense"] + int(cdata.get("equip_armor", {}).get("ac_bonus", 0)),
			"speed":       cdata["speed"],
			"move_range":  cdata.get("move_range", 3),
			"attack_range": cdata.get("attack_range", 1),
			"is_companion": true,
		})
		if centity:
			companion_entities.append(centity)

	# Start tactical combat with grid
	_combat_manager = CombatManagerScript.new()
	_combat_manager.name = "CombatManager"
	add_child(_combat_manager)
	_combat_manager.start_combat(room["enemies"], companion_entities, room, _dungeon_objects)
	_combat_manager.combat_ended.connect(_on_combat_ended.bind(room))

	# Move player to room centre, above the elevated floor if applicable
	if _player:
		var ox: int = room["_offset_x"]
		var oz: int = room["_offset_z"]
		_player.global_position = Vector3(room["cx"] + ox + 0.5, _combat_floor_height + 1.5, room["cy"] + oz + 0.5)

	# Show combat UI
	var ui = CombatUIScript.new()
	ui.name = "CombatUI"
	add_child(ui)
	ui.setup(_combat_manager)

	# Connect player movement to tactical grid
	_combat_manager.unit_moved.connect(_on_unit_moved)

	# Lock camera pitch for combat — only yaw rotation (Q/E) allowed
	if _camera and is_instance_valid(_camera):
		_camera.set_combat_mode(true)


func _on_combat_ended(victory: bool, fled: bool, room: Dictionary):
	_combat_active = false
	_set_wall_combat_mode(false)
	_hide_combat_vignette()
	if _player and is_instance_valid(_player):
		_player.combat_locked = false
	if _camera and is_instance_valid(_camera):
		_camera.set_combat_mode(false)

	if _combat_manager and is_instance_valid(_combat_manager):
		_combat_manager.queue_free()
		_combat_manager = null

	# Re-show surviving companion followers; despawn any that died in combat.
	# Snap to player position first so they don't reappear at the old room entrance.
	_player_pos_history.clear()
	var to_remove: Array = []
	for f: Node3D in _companion_followers:
		if not is_instance_valid(f):
			to_remove.append(f)
			continue
		var fkey: String = f.get_meta("entity_key", "")
		if fkey == "" or not (fkey in GameData.active_companions):
			EntityManager.despawn_entity(f)
			to_remove.append(f)
		else:
			if _player and is_instance_valid(_player):
				f.global_position = _player.global_position
			f.visible = true
	for f in to_remove:
		_companion_followers.erase(f)

	if victory:
		var unlocked_jobs: Array = GameData.record_job_victory()
		if not unlocked_jobs.is_empty():
			var names: Array[String] = []
			for jid in unlocked_jobs:
				var nm: String = str(GameData.CLASS_NAMES.get(int(jid), "Unknown"))
				names.append(nm)
				print("Jobs: unlocked %s" % nm)
			if _hud and _hud.has_method("show_toast"):
				var msg := "New job unlocked: %s" % ", ".join(names)
				_hud.show_toast(msg, 4.0)
		room["state"] = "cleared"
		GameData.mark_room_cleared(_floor_num, room["id"])
		print("Dungeon: room %d cleared!" % room["id"])

		# If boss room cleared, enable the floor portal and advance floor
		if room["room_type"] == "boss":
			_enable_boss_portal()
			var cleared_floor: int = _floor_num
			GameData.dungeon_seed = 0
			GameData.advance_floor()
			print("Dungeon: boss defeated — advanced to floor %d" % GameData.current_floor)
			# Rescue NPCs tied to this floor
			var rescued: Array[String] = GameData.rescue_npcs_for_floor(cleared_floor)
			for new_npc: String in rescued:
				if _hud and _hud.has_method("show_toast"):
					var npc_def: Dictionary = NpcDB.get_def(new_npc)
					var npc_name: String = npc_def.get("name", new_npc) as String
					_hud.show_toast("%s has joined the camp!" % npc_name, 5.0)
	else:
		if fled:
			# Player fled — return to camp
			_do_return_to_camp()
		else:
			# Player died — show death screen
			player_defeated.emit()


func _enable_boss_portal():
	for child in _dungeon_objects.get_children():
		if child is Area3D and child.get_meta("interaction", "") == "boss_portal":
			child.set_meta("enabled", true)

			# Add a green light to show it's active
			var light := OmniLight3D.new()
			light.name = "BossPortalActive"
			light.light_color = Color(0.2, 1.0, 0.4)
			light.light_energy = 3.0
			light.omni_range = 8.0
			light.shadow_enabled = false
			_dungeon_objects.add_child(light)
			light.global_position = child.global_position
			break


## When a unit moves on the tactical grid, move the player entity too.
## Companion and enemy entity positions are updated directly inside combat_manager._move_unit().
func _on_unit_moved(unit: Dictionary, _from: Vector2i, to: Vector2i):
	if unit["type"] == "player" and _player and _combat_manager:
		var world_pos: Vector3 = _combat_manager.tactical_grid.grid_to_world(to)
		_player.global_position = world_pos


func _do_return_to_camp():
	GameData.in_dungeon = false
	EntityManager.despawn_all()
	return_to_camp.emit()


func _do_advance_floor():
	EntityManager.despawn_all()
	advance_floor.emit()


func _do_bonfire_rest():
	GameData.heal(GameData.hp_max)
	GameData.heal_companions()
	print("Dungeon: rested at bonfire — HP restored for player and companions")


func _spawn_companion_followers(base_pos: Vector3):
	## Spawn exploration follower entities for each active companion.
	## These trail behind the player outside of combat.
	print("Dungeon: _spawn_companion_followers — active_companions = %s" % [GameData.active_companions])
	for ckey: String in GameData.active_companions:
		var cdata: Dictionary = GameData.get_companion(ckey)
		var edata: Dictionary = EnemyDB.get_enemy(ckey)
		if cdata.is_empty() or edata.is_empty():
			print("Dungeon: SKIP companion '%s' — cdata.empty=%s edata.empty=%s" % [ckey, cdata.is_empty(), edata.is_empty()])
			continue
		var tex_path: String = EnemyDB.get_ready_texture_path(ckey)
		var offset := Vector3(1.2 * (_companion_followers.size() + 1), 0.0, 0.0)
		var entity: Node3D = EntityManager.spawn_entity(base_pos + offset, tex_path, {
			"entity_key": ckey,
			"name": cdata.get("name", edata.get("name", ckey)),
			"is_follower": true,
		})
		if entity:
			# Subtle green tint to indicate allied status
			var sprite: Sprite3D = entity.get_meta("sprite", null) as Sprite3D
			if sprite:
				sprite.modulate = Color(0.75, 1.0, 0.8)
			_companion_followers.append(entity)


func _update_companion_followers():
	## Move companion followers to trail behind the player using a position history.
	if _player == null or _companion_followers.is_empty():
		return

	_player_pos_history.append(_player.global_position)
	if _player_pos_history.size() > 80:
		_player_pos_history.pop_front()

	for i in _companion_followers.size():
		var f: Node3D = _companion_followers[i]
		if not is_instance_valid(f):
			continue
		# Each companion lags 20 extra frames behind the previous one
		var delay: int = (i + 1) * 20
		var target_idx: int = maxi(0, _player_pos_history.size() - 1 - delay)
		var target_pos: Vector3 = _player_pos_history[target_idx]
		f.global_position = f.global_position.lerp(target_pos, 0.12)


func _do_fountain_heal():
	var heal_amount := GameData.hp_max / 3
	GameData.heal(heal_amount)
	print("Dungeon: fountain healed %d HP" % heal_amount)


func _do_alchemy_brew():
	var cost := 10
	if GameData.gold >= cost:
		var potions := ["potion_red", "potion_blue", "potion_green", "potion_yellow", "potion_purple"]
		var key: String = potions[randi() % potions.size()]
		var potion := ItemDB.create_item(key)
		if not potion.is_empty() and ItemDB.add_to_backpack(potion):
			GameData.gold -= cost
			GameData.gold_changed.emit(GameData.gold)
			print("Dungeon: brewed %s for %d gold" % [potion.get("name", "potion"), cost])
		else:
			print("Dungeon: backpack full!")
	else:
		print("Dungeon: not enough gold (need %d, have %d)" % [cost, GameData.gold])


func _do_vault_loot(area: Area3D):
	# Gold reward scales with floor
	var gold_reward := 20 + _floor_num * 10
	GameData.gold += gold_reward
	GameData.gold_changed.emit(GameData.gold)

	# Random bonus item: potion, food, or accessory
	var loot_table := ["potion_red", "potion_blue", "potion_green", "baked_potato", "bread"]
	var loot_key: String = loot_table[randi() % loot_table.size()]
	var item := ItemDB.create_item(loot_key)
	var item_name := ""
	if not item.is_empty() and ItemDB.add_to_backpack(item):
		item_name = item.get("name", loot_key)

	# Mark as looted so it can't be opened again
	area.set_meta("looted", true)

	if item_name != "":
		print("Dungeon: vault — %d gold + %s" % [gold_reward, item_name])
	else:
		print("Dungeon: vault — %d gold (backpack full, item lost)" % gold_reward)


# ── Puzzle room logic ────────────────────────────────────────────────────────

const PushBlockScript = preload("res://dungeon_break/world/push_block.gd")

## Spawn push block entities for a puzzle room (called on first visit).
func _spawn_puzzle_blocks(room: Dictionary):
	var puzzle: Dictionary = room.get("puzzle", {})
	if puzzle.is_empty():
		return

	var floor_y: int = puzzle.get("floor_y", 0)
	var blocks: Array = puzzle["blocks"]
	var targets: Array = puzzle["targets"]

	for pos in blocks:
		var block := Node3D.new()
		block.set_script(PushBlockScript)
		_dungeon_objects.add_child(block)
		block.setup(pos, float(floor_y), room["id"])
		block.moved.connect(_on_puzzle_block_moved.bind(room))

	# Update on_target state for initial positions (in case a block starts on a target)
	_update_puzzle_targets(room)

	if _hud and _hud.has_method("show_toast"):
		_hud.show_toast("Push the blocks onto the glowing plates!", 3.0)
	print("Dungeon: spawned %d puzzle blocks in room %d" % [blocks.size(), room["id"]])


## Called whenever a push block finishes moving.
func _on_puzzle_block_moved(room: Dictionary):
	_update_puzzle_targets(room)
	_check_puzzle_solved(room)


## Update on_target status for all push blocks in a room.
func _update_puzzle_targets(room: Dictionary):
	var puzzle: Dictionary = room.get("puzzle", {})
	var targets: Array = puzzle.get("targets", [])
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if not is_instance_valid(block):
			continue
		if block.room_id != room["id"]:
			continue
		block.set_on_target(block.grid_pos in targets)


## Check if all targets in a puzzle room are covered by blocks.
func _check_puzzle_solved(room: Dictionary):
	var puzzle: Dictionary = room.get("puzzle", {})
	var targets: Array = puzzle.get("targets", [])
	if targets.is_empty():
		return

	# Build set of block positions in this room
	var block_positions: Array[Vector2i] = []
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if not is_instance_valid(block) or block.room_id != room["id"]:
			continue
		block_positions.append(block.grid_pos)

	# Check every target is covered
	for target: Vector2i in targets:
		if target not in block_positions:
			return  # Not solved yet

	# ── Puzzle solved! ───────────────────────────────────────────────────
	room["state"] = "cleared"
	GameData.mark_room_cleared(_floor_num, room["id"])

	# Remove push blocks (they served their purpose)
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if is_instance_valid(block) and block.room_id == room["id"]:
			block.queue_free()

	# Reward: gold + bonus XP
	var gold_reward: int = 15 + _floor_num * 5
	var xp_reward: int = 10 + _floor_num * 3
	GameData.gold += gold_reward
	GameData.gold_changed.emit(GameData.gold)
	GameData.grant_xp(xp_reward)

	# Spawn a chest voxel at room centre as visual feedback
	var puzzle_data: Dictionary = room.get("puzzle", {})
	var floor_y: int = puzzle_data.get("floor_y", 0)
	var ox: int = _dungeon_stamper.dungeon_data.get("offset_x", 0)
	var oz: int = _dungeon_stamper.dungeon_data.get("offset_z", 0)
	var cx: int = room["cx"] + ox
	var cz: int = room["cy"] + oz
	var vt: VoxelTool = _terrain.get_voxel_tool()
	vt.channel = VoxelBuffer.CHANNEL_TYPE
	vt.set_voxel(Vector3i(cx, floor_y + 1, cz), 48)  # CHEST block

	if _hud and _hud.has_method("show_toast"):
		_hud.show_toast("Puzzle solved!  +%dg  +%d XP" % [gold_reward, xp_reward], 3.5)
	print("Dungeon: puzzle room %d solved! +%d gold, +%d XP" % [room["id"], gold_reward, xp_reward])


## Reset all push blocks in a puzzle room to their spawn positions.
func _reset_puzzle(room: Dictionary):
	for block in get_tree().get_nodes_in_group("push_blocks"):
		if is_instance_valid(block) and block.room_id == room["id"]:
			block.reset()
	_update_puzzle_targets(room)
	if _hud and _hud.has_method("show_toast"):
		_hud.show_toast("Puzzle reset.", 1.5)
	print("Dungeon: puzzle room %d reset" % room["id"])


## Look up a room dict by its ID from dungeon_data.
func _get_room_by_id(rid: int) -> Dictionary:
	if _dungeon_stamper == null or _dungeon_stamper.dungeon_data.is_empty():
		return {}
	for room in _dungeon_stamper.dungeon_data["rooms"]:
		if room["id"] == rid:
			return room
	return {}


func _on_area_body_entered(_body: Node3D, _area: Area3D):
	pass  # Handled via proximity in _check_area_interactions


## Enable all lights for a room (called when the player first steps into it).
func _enable_room_lights(room_id: int) -> void:
	var group: String = "room_lights_%d" % room_id
	for node in get_tree().get_nodes_in_group(group):
		if node is OmniLight3D:
			(node as OmniLight3D).visible = true


## Sync torch OmniLight range and energy to current torch_fuel.
func _update_torch_light() -> void:
	if _torch_light == null or not is_instance_valid(_torch_light):
		return
	var t: float = float(GameData.torch_fuel) / float(GameData.get_torch_fuel_max())
	# Deeper floors get a slightly wider torch beam (rooms are bigger)
	var max_range := 10.0 if _floor_num <= 3 else 14.0
	_torch_light.omni_range = lerpf(1.5, max_range, t)
	_torch_light.light_energy = lerpf(0.15, 1.8, t)


## Fade terrain walls in/out during combat.
## Disables vertex_color_use_as_albedo so albedo_color.a controls transparency.
func _set_wall_combat_mode(enabled: bool) -> void:
	if _terrain_mat == null:
		return
	if _wall_tween and _wall_tween.is_valid():
		_wall_tween.kill()
	_wall_tween = create_tween()
	if enabled:
		_terrain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_terrain_mat.vertex_color_use_as_albedo = false
		_wall_tween.tween_property(_terrain_mat, "albedo_color",
			Color(1.0, 1.0, 1.0, 0.08), 0.35)
		# Boost ambient so tactical grid tiles are clearly readable during combat
		if _world_env and _world_env.environment:
			_wall_tween.parallel().tween_property(
				_world_env.environment, "ambient_light_energy", _combat_ambient, 0.35)
	else:
		_wall_tween.tween_property(_terrain_mat, "albedo_color",
			Color(1.0, 1.0, 1.0, 1.0), 0.35)
		# Restore dungeon darkness alongside the wall fade
		if _world_env and _world_env.environment:
			_wall_tween.parallel().tween_property(
				_world_env.environment, "ambient_light_energy", _explore_ambient, 0.35)
		_wall_tween.tween_callback(func() -> void:
			_terrain_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			_terrain_mat.vertex_color_use_as_albedo = true
			# Zoom back out now that walls are fully opaque again
			if _camera and is_instance_valid(_camera):
				_camera.restore_zoom()
		)


func _notification(what: int):
	# Safety: always restore wall material on scene exit, even if mid-combat
	if what == NOTIFICATION_EXIT_TREE and _terrain_mat != null:
		_terrain_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_terrain_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		_terrain_mat.vertex_color_use_as_albedo = true
	if what == NOTIFICATION_EXIT_TREE and GraphicsManager and GraphicsManager.preset_changed.is_connected(_on_graphics_preset_changed):
		GraphicsManager.preset_changed.disconnect(_on_graphics_preset_changed)


func _on_graphics_preset_changed(_preset: int) -> void:
	_apply_quality_fallback_lighting()


func _apply_quality_fallback_lighting() -> void:
	var preset: int = 1
	if GraphicsManager:
		preset = int(GraphicsManager.current_preset)
	var low_or_medium := preset != GRAPHICS_PRESET_HIGH

	_explore_ambient = DUNGEON_AMBIENT
	_combat_ambient = COMBAT_AMBIENT

	# Deeper floors get a small ambient boost so the lighter blocks stay readable
	if _floor_num >= 4:
		_explore_ambient += 0.03

	if low_or_medium:
		_explore_ambient = maxf(_explore_ambient, LOW_MED_DUNGEON_AMBIENT)

	if _fallback_fill_light and is_instance_valid(_fallback_fill_light):
		_fallback_fill_light.visible = low_or_medium

	if _world_env and _world_env.environment:
		var env: Environment = _world_env.environment
		env.sdfgi_energy = DUNGEON_GI_ENERGY
		if _combat_active:
			env.ambient_light_energy = _combat_ambient
		else:
			env.ambient_light_energy = _explore_ambient


## Track the last hovered grid tile for cursor highlight.
var _hover_grid_pos := Vector2i(-9999, -9999)


## Raycast mouse position to floor plane and return grid tile.
func _mouse_to_grid(screen_pos: Vector2) -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector2i(-9999, -9999)

	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)

	# Intersect with floor plane at walkable Y of the current combat room
	var floor_y := float(_combat_floor_height) + 1.0
	if dir.y == 0.0:
		return Vector2i(-9999, -9999)
	var t := (floor_y - from.y) / dir.y
	if t < 0.0:
		return Vector2i(-9999, -9999)

	var hit := from + dir * t
	return Vector2i(int(floor(hit.x)), int(floor(hit.z)))


## Handle mouse input during tactical combat.
func _unhandled_input(event: InputEvent):
	if not _combat_active or _combat_manager == null or _player == null:
		return

	# Only handle during MOVE phase (Phase.MOVE = 1)
	if _combat_manager.phase != 1:
		return

	# Mouse hover → show cursor highlight on tile
	if event is InputEventMouseMotion:
		var grid_pos := _mouse_to_grid(event.position)
		if grid_pos != _hover_grid_pos:
			_hover_grid_pos = grid_pos
			if _combat_manager.tactical_grid:
				_combat_manager.tactical_grid.clear_color(
					_combat_manager.tactical_grid.COLOR_CURSOR)
				# Only highlight if it's in the movement range
				if grid_pos in _combat_manager._move_tiles:
					_combat_manager.tactical_grid.highlight_cursor(grid_pos)

	# Mouse click → select tile to move
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var grid_pos := _mouse_to_grid(event.position)
		_combat_manager.player_select_move(grid_pos)


func _wait_for_terrain_editable(half: int = 50):
	var vt := _terrain.get_voxel_tool()
	# Check the full area we need to stamp into — half on each axis from origin
	var check_aabb := AABB(
		Vector3(-half, -2, -half),
		Vector3(half * 2, 12, half * 2)
	)

	# Poll until editable — up to ~10s at 60fps
	for attempt in 600:
		if vt.is_area_editable(check_aabb):
			print("Dungeon: terrain editable after %d frames (half=%d)" % [attempt, half])
			return
		await get_tree().process_frame

	# If we get here, some chunks didn't load. Print a diagnostic and continue.
	# The dungeon will be partially broken but at least won't hard-lock.
	push_warning("Dungeon: terrain NOT fully editable after 600 frames (half=%d). Some walls may be missing." % half)


# ══════════════════════════════════════════════════════════════════════════════
# COMBAT VIGNETTE — screen-edge darkening on combat entry
# ══════════════════════════════════════════════════════════════════════════════

func _show_combat_vignette() -> void:
	if _vignette_layer == null:
		_vignette_layer = CanvasLayer.new()
		_vignette_layer.name = "VignetteLayer"
		_vignette_layer.layer = 90  # above most UI but below modals
		add_child(_vignette_layer)

		_vignette_rect = ColorRect.new()
		_vignette_rect.name = "Vignette"
		_vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var shader := load("res://dungeon_break/ui/combat_vignette.gdshader") as Shader
		if shader:
			_vignette_mat = ShaderMaterial.new()
			_vignette_mat.shader = shader
			_vignette_mat.set_shader_parameter("strength", 0.0)
			_vignette_mat.set_shader_parameter("color", Color(0.05, 0.0, 0.0, 1.0))
			_vignette_mat.set_shader_parameter("radius", 0.65)
			_vignette_mat.set_shader_parameter("softness", 0.5)
			_vignette_rect.material = _vignette_mat
		_vignette_layer.add_child(_vignette_rect)

	if _vignette_mat:
		# Pulse in, hold briefly, then settle to a light persistent vignette
		var tw := create_tween()
		tw.tween_method(func(v: float): _vignette_mat.set_shader_parameter("strength", v),
			0.0, 0.7, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.3)
		tw.tween_method(func(v: float): _vignette_mat.set_shader_parameter("strength", v),
			0.7, 0.25, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _hide_combat_vignette() -> void:
	if _vignette_mat:
		var tw := create_tween()
		tw.tween_method(func(v: float): _vignette_mat.set_shader_parameter("strength", v),
			0.25, 0.0, 0.4).set_trans(Tween.TRANS_SINE)
