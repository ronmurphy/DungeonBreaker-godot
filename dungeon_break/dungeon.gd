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

## Ambient light levels for the dungeon environment
const DUNGEON_AMBIENT := 0.05   # dark exploration
const COMBAT_AMBIENT  := 0.35   # readable tactical grid

## Torch light node (OmniLight3D parented to player, only in dungeon)
var _torch_light: OmniLight3D = null

## Rooms the player has visited this run — keyed by room id (int → true)
var _visited_rooms: Dictionary = {}

## Accumulator for torch fuel burn (fuel is int, burn rate is float)
var _torch_burn_accum: float = 0.0
const TORCH_BURN_RATE := 0.15  # fuel per second; full torch lasts ~11 min


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
	var temp_viewer := VoxelViewer.new()
	temp_viewer.name = "TempViewer"
	temp_viewer.position = Vector3.ZERO
	temp_viewer.view_distance = 16   # ~256 blocks — covers largest dungeon
	temp_viewer.requires_visuals = true
	temp_viewer.requires_collisions = true
	_terrain.add_child(temp_viewer)

	# Give chunks time to generate around the viewer
	await get_tree().create_timer(1.5).timeout
	await _wait_for_terrain_editable()

	# Cache wall material for combat transparency toggling (floor blocks use the other material)
	_terrain_mat = load("res://blocky_game/blocks/terrain_material_wall.tres") as StandardMaterial3D

	var data: Dictionary = _dungeon_stamper.build_dungeon(_floor_num)

	# Clean up temp viewer now that stamping is done
	temp_viewer.queue_free()

	if data.is_empty():
		push_error("Dungeon: failed to generate floor %d" % _floor_num)
		return

	# Spawn player at start room
	var start_pos: Vector3 = _dungeon_stamper.get_start_position()
	_spawn_player(start_pos)

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
	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_energy = DUNGEON_AMBIENT

	# Start room (id 0) is always pre-revealed — player spawns there
	_visited_rooms[0] = true
	_enable_room_lights(0)

	MusicManager.play_dungeon()
	print("Dungeon: floor %d ready — %d rooms" % [_floor_num, data["rooms"].size()])


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


func _spawn_enemies(data: Dictionary):
	var rooms: Array = data["rooms"]
	var ox: int = data["offset_x"]
	var oz: int = data["offset_z"]

	var floor_enemies: Array = EnemyDB.get_enemies_for_floor(_floor_num)
	if floor_enemies.is_empty():
		push_warning("Dungeon: no enemies for floor %d" % _floor_num)
		return

	for room in rooms:
		# Only spawn in uncleared normal/trap/locked rooms
		if room["state"] != "uncleared":
			continue
		if room["room_type"] in ["start", "bonfire", "merchant", "fountain", "alchemy"]:
			continue

		# Enemy count: 1–3 for normal, 1 for boss
		var count := 1
		if room["room_type"] == "normal":
			count = randi_range(1, 3)
		elif room["room_type"] == "trap":
			count = randi_range(2, 3)

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
			var ey: float = room.get("floor_height", 0) + 1.5  # above elevated floor if applicable

			var tex_path: String = EnemyDB.get_ready_texture_path(key)
			stats["room_id"] = room["id"]
			stats["entity_key"] = key

			var entity: Node3D = EntityManager.spawn_entity(Vector3(ex, ey, ez), tex_path, stats)
			if entity:
				room["enemies"].append(entity)


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

	# Check player proximity to portal areas (since we use VoxelBoxMover, not CharacterBody)
	_check_area_interactions()


func _check_area_interactions():
	var player_pos := _player.global_position
	var near_anything := false

	for child in _dungeon_objects.get_children():
		if not (child is Area3D):
			continue

		var dist := player_pos.distance_to(child.global_position)
		if dist > 3.0:
			continue

		var interaction: String = child.get_meta("interaction", "")
		near_anything = true

		match interaction:
			"return_portal":
				if _hud:
					_hud.show_prompt("[E] Return to Camp")
				if Input.is_key_pressed(KEY_E):
					_do_return_to_camp()
			"bonfire":
				if _hud:
					_hud.show_prompt("[E] Rest at Bonfire")
				if Input.is_key_pressed(KEY_E):
					_do_bonfire_rest()
			"fountain":
				if _hud:
					_hud.show_prompt("[E] Drink from Fountain")
				if Input.is_key_pressed(KEY_E):
					_do_fountain_heal()
			"merchant":
				if _hud:
					_hud.show_prompt("[E] Buy Health Potion (15g)")
				if Input.is_key_pressed(KEY_E):
					_do_merchant_buy()
			"alchemy":
				if _hud:
					_hud.show_prompt("[E] Brew Random Potion (10g)")
				if Input.is_key_pressed(KEY_E):
					_do_alchemy_brew()
			"boss_portal":
				if child.get_meta("enabled", false):
					if _hud:
						_hud.show_prompt("[E] Descend to Next Floor")
					if Input.is_key_pressed(KEY_E):
						_do_advance_floor()

	if not near_anything and _hud:
		_hud.hide_prompt()

	# Check room entry: reveal lights on first visit, trigger combat if uncleared
	if not _combat_active:
		var room: Dictionary = _dungeon_stamper.get_room_at_world(player_pos)
		if not room.is_empty():
			var rid: int = room["id"]
			if not _visited_rooms.has(rid):
				_visited_rooms[rid] = true
				_enable_room_lights(rid)
			if room["state"] == "uncleared":
				_trigger_room_combat(room)


func _trigger_room_combat(room: Dictionary):
	if room["enemies"].is_empty():
		room["state"] = "cleared"
		return

	_combat_active = true
	_combat_floor_height = room.get("floor_height", 0)
	if _player:
		_player.combat_locked = true
	_set_wall_combat_mode(true)
	print("Dungeon: combat started in room %d (%s) elev=%d" % [room["id"], room["room_type"], _combat_floor_height])

	# Inject dungeon offsets into room dict for the tactical grid
	room["_offset_x"] = _dungeon_stamper.dungeon_data.get("offset_x", 0)
	room["_offset_z"] = _dungeon_stamper.dungeon_data.get("offset_z", 0)

	# Start tactical combat with grid
	_combat_manager = CombatManagerScript.new()
	_combat_manager.name = "CombatManager"
	add_child(_combat_manager)
	_combat_manager.start_combat(room["enemies"], room, _dungeon_objects)
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


func _on_combat_ended(victory: bool, room: Dictionary):
	_combat_active = false
	_set_wall_combat_mode(false)
	if _player and is_instance_valid(_player):
		_player.combat_locked = false
	if _camera and is_instance_valid(_camera):
		_camera.set_combat_mode(false)

	if _combat_manager and is_instance_valid(_combat_manager):
		_combat_manager.queue_free()
		_combat_manager = null

	if victory:
		room["state"] = "cleared"
		print("Dungeon: room %d cleared!" % room["id"])

		# If boss room cleared, enable the floor portal
		if room["room_type"] == "boss":
			_enable_boss_portal()
	else:
		# Player died — return to camp with penalty
		GameData.hp = GameData.hp_max / 2
		GameData.gold = maxi(0, GameData.gold - 10)
		_do_return_to_camp()


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
			light.global_position = child.global_position
			_dungeon_objects.add_child(light)
			break


## When a unit moves on the tactical grid, move the player entity too.
func _on_unit_moved(unit: Dictionary, _from: Vector2i, to: Vector2i):
	if unit["type"] == "player" and _player and _combat_manager:
		var world_pos: Vector3 = _combat_manager.tactical_grid.grid_to_world(to)
		_player.global_position = world_pos


func _do_return_to_camp():
	GameData.in_dungeon = false
	EntityManager.despawn_all()
	return_to_camp.emit()


func _do_advance_floor():
	GameData.advance_floor()
	EntityManager.despawn_all()
	advance_floor.emit()


func _do_bonfire_rest():
	GameData.heal(GameData.hp_max)
	print("Dungeon: rested at bonfire — HP restored")


func _do_fountain_heal():
	var heal_amount := GameData.hp_max / 3
	GameData.heal(heal_amount)
	print("Dungeon: fountain healed %d HP" % heal_amount)


func _do_merchant_buy():
	var cost := 15
	if GameData.gold >= cost:
		var potion := ItemDB.create_item("potion_red")
		if not potion.is_empty() and ItemDB.add_to_backpack(potion):
			GameData.gold -= cost
			GameData.gold_changed.emit(GameData.gold)
			print("Dungeon: bought Health Potion for %d gold" % cost)
		else:
			print("Dungeon: backpack full!")
	else:
		print("Dungeon: not enough gold (need %d, have %d)" % [cost, GameData.gold])


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


func _on_area_body_entered(_body: Node3D, _area: Area3D):
	pass  # Handled via proximity in _check_area_interactions


## Enable all lights for a room (called when the player first steps into it).
func _enable_room_lights(room_id: int) -> void:
	var group: String = "room_lights_%d" % room_id
	for node in get_tree().get_nodes_in_group(group):
		if node is OmniLight3D:
			(node as OmniLight3D).visible = true


## Sync torch OmniLight range and energy to current torch_fuel (0–100).
func _update_torch_light() -> void:
	if _torch_light == null or not is_instance_valid(_torch_light):
		return
	var t: float = float(GameData.torch_fuel) / 100.0
	_torch_light.omni_range = lerpf(1.5, 10.0, t)
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
				_world_env.environment, "ambient_light_energy", COMBAT_AMBIENT, 0.35)
	else:
		_wall_tween.tween_property(_terrain_mat, "albedo_color",
			Color(1.0, 1.0, 1.0, 1.0), 0.35)
		# Restore dungeon darkness alongside the wall fade
		if _world_env and _world_env.environment:
			_wall_tween.parallel().tween_property(
				_world_env.environment, "ambient_light_energy", DUNGEON_AMBIENT, 0.35)
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


func _wait_for_terrain_editable():
	var vt := _terrain.get_voxel_tool()
	var half := 50  # covers largest dungeon (96/2 = 48) + margin
	var check_aabb := AABB(Vector3(-half, -5, -half), Vector3(half * 2, 15, half * 2))

	for attempt in 200:
		if vt.is_area_editable(check_aabb):
			return
		await get_tree().process_frame

	push_warning("Dungeon: terrain not editable after timeout — building anyway")
