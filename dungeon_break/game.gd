extends Node
## Main game script for Dungeon Break — camp world.
##
## Spawns the player, builds camp structures (bonfire, spire, azure flame),
## spawns wanderer NPCs, and manages the camp lifecycle.

const PlayerScene = preload("res://dungeon_break/player/player.tscn")
const IsometricCamera = preload("res://dungeon_break/player/isometric_camera.gd")
const CampBuilderScript = preload("res://dungeon_break/generator/camp_builder.gd")
const CampAnimalsScript = preload("res://dungeon_break/world/camp_animals.gd")
const WandererScript = preload("res://dungeon_break/entities/wanderer_controller.gd")
const DayNightCycleScript = preload("res://dungeon_break/world/day_night_cycle.gd")
const CloudShadowCasterShader = preload("res://dungeon_break/world/cloud_shadow_caster.gdshader")
const LowlandGrassShader = preload("res://dungeon_break/world/lowland_billboard_grass.gdshader")
const TallGrassMesh = preload("res://blocky_game/blocks/tall_grass/tall_grass.obj")
const TallGrassAtlas = preload("res://blocky_game/blocks/tall_grass/tall_grass_sprite.png")
const GameHudScript = preload("res://dungeon_break/ui/game_hud.gd")
const InventoryUIScript = preload("res://dungeon_break/ui/inventory_ui.gd")
const ShopUIScript = preload("res://dungeon_break/ui/shop_ui.gd")
const StructureShopUIScript = preload("res://dungeon_break/ui/structure_shop_ui.gd")
const SageUIScript = preload("res://dungeon_break/ui/sage_ui.gd")
const CompanionRosterUIScript = preload("res://dungeon_break/ui/companion_roster_ui.gd")
const JobChangeUIScript = preload("res://dungeon_break/ui/job_change_ui.gd")

signal enter_dungeon()

@onready var _terrain: VoxelTerrain = $VoxelTerrain
@onready var _players: Node = $Players
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $DirectionalLight3D

var _player: Node3D = null
var _camp_builder = null
var _wanderer_ctrl = null
var _day_night: Node = null
var _hud: CanvasLayer = null
var _cloud_shadow_caster: MeshInstance3D = null
var _camp_animals = null
var _lowland_grass: MultiMeshInstance3D = null
var _lowland_grass_mat: ShaderMaterial = null

const GRAPHICS_PRESET_LOW := 0
const GRAPHICS_PRESET_MEDIUM := 1
const GRAPHICS_PRESET_HIGH := 2
const AIR := 0
const GRASS := 2
const LOWLAND_MIN_Y := -22
const LOWLAND_RING_MIN_RADIUS := 50.0
const LOWLAND_RING_MAX_RADIUS := 76.0

# Rescued NPC billboard sprites — updated for camera-facing each frame
var _npc_sprites: Array = []

# ── Camp structure parent node ───────────────────────────────────────────────
var _camp_objects: Node3D = null

# Tracks whether a shop/sage UI is currently open (prevents multi-open)
var _npc_ui_open: bool = false

# Prevents bonfire rest from firing every frame while E is held
var _bonfire_rest_pending: bool = false
var _e_was_pressed: bool = false
var _r_was_pressed: bool = false
var _c_was_pressed: bool = false


func _ready():
	# Create container for camp 3D objects (lights, areas, etc.)
	_camp_objects = Node3D.new()
	_camp_objects.name = "CampObjects"
	add_child(_camp_objects)

	# Spawn the player above the island centre — gravity will land them
	_spawn_player(Vector3(0, 20, 0))

	# Build camp structures after a short delay so terrain has generated
	call_deferred("_build_camp")


func _spawn_player(pos: Vector3):
	_player = PlayerScene.instantiate()
	_player.name = "LocalPlayer"
	_player.position = pos
	_player.terrain = _terrain.get_path()
	_players.add_child(_player)

	# Point the isometric camera at the player
	var cam: Camera3D = _player.get_node("IsometricCamera")
	if cam and cam.has_method("set_follow_target"):
		cam.set_follow_target(_player)

	# Give EntityManager the camera for LOD
	if EntityManager:
		EntityManager.set_camera(cam)

	# Ensure the camera starts at the correct position (no lerp jump on first frame)
	cam.global_position = pos + Vector3(12, 16, 12)


func _build_camp():
	# Set up builders (they'll be called once terrain is loaded)
	_camp_builder = CampBuilderScript.new()
	_camp_builder.setup(_terrain, _camp_objects)

	_wanderer_ctrl = WandererScript.new()
	_wanderer_ctrl.setup(_terrain)
	add_child(_wanderer_ctrl)

	# Wait for terrain chunks around camp to be loaded before editing
	await _wait_for_terrain_editable()

	_camp_builder.build_camp()
	_npc_sprites = _camp_builder.spawn_rescued_npcs()
	_camp_animals = CampAnimalsScript.new()
	_camp_animals.name = "CampAnimals"
	add_child(_camp_animals)
	_camp_animals.setup(_camp_builder)
	_wanderer_ctrl.spawn_camp_wanderers()
	_build_cloud_shadow_caster()
	_build_lowland_billboard_grass()
	if GraphicsManager and not GraphicsManager.preset_changed.is_connected(_on_graphics_preset_changed):
		GraphicsManager.preset_changed.connect(_on_graphics_preset_changed)
	_apply_lowland_grass_quality()

	# Start day/night cycle
	_day_night = DayNightCycleScript.new()
	_day_night.name = "DayNightCycle"
	add_child(_day_night)
	_day_night.setup(_sun, _world_env)

	# HUD
	_hud = GameHudScript.new()
	_hud.name = "GameHUD"
	add_child(_hud)

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

	GameData.scene_state = "camp"
	MusicManager.play_camp()
	print("Game: camp fully initialised")


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and GraphicsManager and GraphicsManager.preset_changed.is_connected(_on_graphics_preset_changed):
		GraphicsManager.preset_changed.disconnect(_on_graphics_preset_changed)


func _on_graphics_preset_changed(_preset: int) -> void:
	_apply_lowland_grass_quality()


func _build_cloud_shadow_caster() -> void:
	# One large, shadow-only plane above camp/lowlands gives cheap moving cloud shadows.
	var plane := PlaneMesh.new()
	plane.size = Vector2(420.0, 420.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1

	var mat := ShaderMaterial.new()
	mat.shader = CloudShadowCasterShader
	mat.set_shader_parameter("uv_scale", Vector2(4.6, 3.2))
	mat.set_shader_parameter("wind_dir", Vector2(0.012, 0.007))
	mat.set_shader_parameter("cutoff", 0.58)
	mat.set_shader_parameter("softness", 0.09)
	mat.set_shader_parameter("cloud_noise", _make_cloud_noise_texture())

	_cloud_shadow_caster = MeshInstance3D.new()
	_cloud_shadow_caster.name = "CloudShadowCaster"
	_cloud_shadow_caster.mesh = plane
	_cloud_shadow_caster.material_override = mat
	_cloud_shadow_caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_cloud_shadow_caster.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_cloud_shadow_caster.position = Vector3(0.0, 95.0, 36.0)
	_cloud_shadow_caster.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	_cloud_shadow_caster.extra_cull_margin = 512.0
	_camp_objects.add_child(_cloud_shadow_caster)


func _make_cloud_noise_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 7331
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.frequency = 0.02

	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.normalize = true
	tex.noise = noise
	return tex


func _build_lowland_billboard_grass() -> void:
	# iGPU-safe approach:
	# - one MultiMesh draw call
	# - alpha scissor (no alpha blending overdraw chain)
	# - no shadow casting on grass
	var positions := _collect_lowland_grass_positions(720)
	if positions.is_empty():
		return

	_lowland_grass_mat = ShaderMaterial.new()
	_lowland_grass_mat.shader = LowlandGrassShader
	_lowland_grass_mat.set_shader_parameter("albedo_texture", TallGrassAtlas)
	_lowland_grass_mat.set_shader_parameter("sway_strength", 0.22)
	_lowland_grass_mat.set_shader_parameter("sway_speed", 1.2)
	_lowland_grass_mat.set_shader_parameter("alpha_cutoff", 0.30)
	_lowland_grass_mat.set_shader_parameter("tint", Color(0.86, 1.0, 0.86))

	var mm := MultiMesh.new()
	mm.mesh = TallGrassMesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	mm.instance_count = positions.size()
	mm.visible_instance_count = positions.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = 5201
	for i in positions.size():
		var p: Vector3 = positions[i]
		var yaw := rng.randf() * TAU
		var sx := rng.randf_range(1.15, 1.65)
		var sy := rng.randf_range(1.30, 1.95)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sx, sy, sx))
		mm.set_instance_transform(i, Transform3D(basis, p))

	_lowland_grass = MultiMeshInstance3D.new()
	_lowland_grass.name = "LowlandBillboardGrass"
	_lowland_grass.multimesh = mm
	_lowland_grass.material_override = _lowland_grass_mat
	_lowland_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lowland_grass.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_lowland_grass.extra_cull_margin = 64.0
	_camp_objects.add_child(_lowland_grass)


func _collect_lowland_grass_positions(target_count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _terrain == null:
		return out
	var vt := _terrain.get_voxel_tool()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4103

	var attempts := 0
	var max_attempts := target_count * 50
	while out.size() < target_count and attempts < max_attempts:
		attempts += 1
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(LOWLAND_RING_MIN_RADIUS, LOWLAND_RING_MAX_RADIUS)
		var x: int = roundi(cos(angle) * dist)
		var z: int = roundi(sin(angle) * dist)
		var y := _surface_y(vt, x, z)
		if y < LOWLAND_MIN_Y:
			continue
		if vt.get_voxel(Vector3i(x, y, z)) != GRASS:
			continue
		if vt.get_voxel(Vector3i(x, y + 1, z)) != AIR:
			continue
		# Keep a clear ring around the bottom arch.
		if Vector2(float(x), float(z)).distance_to(Vector2(0.0, 48.0)) < 8.0:
			continue
		out.append(Vector3(x + 0.5, y + 0.08, z + 0.5))
	return out


func _surface_y(vt: VoxelTool, x: int, z: int) -> int:
	for y in range(20, -25, -1):
		if vt.get_voxel(Vector3i(x, y, z)) != AIR:
			return y
	return 0


func _apply_lowland_grass_quality() -> void:
	if _lowland_grass == null or not is_instance_valid(_lowland_grass):
		return
	if _lowland_grass.multimesh == null:
		return

	var preset := GRAPHICS_PRESET_MEDIUM
	if GraphicsManager:
		preset = int(GraphicsManager.current_preset)

	var max_visible: int = _lowland_grass.multimesh.instance_count
	var sway: float = 0.22
	var vis_end: float = 95.0
	match preset:
		GRAPHICS_PRESET_LOW:
			max_visible = mini(max_visible, 180)
			sway = 0.16
			vis_end = 70.0
		GRAPHICS_PRESET_MEDIUM:
			max_visible = mini(max_visible, 340)
			sway = 0.22
			vis_end = 95.0
		GRAPHICS_PRESET_HIGH:
			max_visible = mini(max_visible, 560)
			sway = 0.30
			vis_end = 120.0

	_lowland_grass.multimesh.visible_instance_count = max_visible
	_lowland_grass.visibility_range_end = vis_end
	if _lowland_grass_mat:
		_lowland_grass_mat.set_shader_parameter("sway_strength", sway)


func _wait_for_terrain_editable():
	## Poll until the VoxelTool says the camp area is editable.
	## Checks a small AABB around origin (covers bonfire/spire area).
	var vt := _terrain.get_voxel_tool()
	var check_aabb := AABB(Vector3(-65, -25, -65), Vector3(130, 50, 145))

	for attempt in 200:  # up to ~3+ seconds
		if vt.is_area_editable(check_aabb):
			return
		await get_tree().process_frame

	push_warning("Game: terrain still not editable after timeout — building anyway")


func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F3:
			# Toggle debug info visibility (if we add one later)
			pass


func _process(_delta: float):
	_update_npc_facing()
	_check_portal_interactions()
	_check_void_fall()

	# Update time display in HUD
	if _hud and _day_night:
		var hour: float = _day_night.get_hour()
		var h: int = int(hour)
		var m := int((hour - h) * 60)
		_hud.set_time_text("%s  %02d:%02d" % [_day_night.get_time_name(), h, m])


## Update each rescued NPC's front/back texture based on camera position.
func _update_npc_facing() -> void:
	if _player == null or _npc_sprites.is_empty():
		return
	var cam: Camera3D = _player.get_node_or_null("IsometricCamera")
	if cam == null:
		return
	var cam_pos := cam.global_position
	for sprite in _npc_sprites:
		if is_instance_valid(sprite):
			sprite.update_facing(cam_pos)


## Teleport the player to the cave catch shelf if they fall into the void.
func _check_void_fall() -> void:
	if _player == null:
		return
	if _player.global_position.y < -30.0:
		var shelf_pos := Vector3(0.5, -1.0, 46.5)
		if _camp_builder and _camp_builder.has_method("get_bottom_arch_pos"):
			shelf_pos = _camp_builder.get_bottom_arch_pos()
		_player.global_position = shelf_pos
		if _hud and _hud.has_method("show_toast"):
			_hud.show_toast("You fell... but found a way back up!", 3.0)


## Check if the player is near a camp interaction area and pressing E.
func _check_portal_interactions():
	if _player == null or _camp_objects == null:
		return

	var player_pos := _player.global_position
	var near_anything := false
	var e_pressed: bool = Input.is_key_pressed(KEY_E)
	var r_pressed: bool = Input.is_key_pressed(KEY_R)
	var c_pressed: bool = Input.is_key_pressed(KEY_C)
	var e_just_pressed: bool = e_pressed and not _e_was_pressed
	var r_just_pressed: bool = r_pressed and not _r_was_pressed
	var c_just_pressed: bool = c_pressed and not _c_was_pressed

	for child in _camp_objects.get_children():
		if not (child is Area3D):
			continue

		var dist := player_pos.distance_to(child.global_position)
		if dist > 3.5:
			continue

		var interaction: String = child.get_meta("interaction", "")

		if interaction == "dungeon_entrance":
			near_anything = true
			if _hud:
				_hud.show_prompt("[E] Enter Dungeon")
			if e_just_pressed:
				print("Game: entering dungeon portal!")
				enter_dungeon.emit()
				return
		elif interaction == "bonfire":
			near_anything = true
			if _hud:
				_hud.show_prompt("[E] Rest  (restores HP, advances 8 hrs)")
			if e_just_pressed:
				if not _bonfire_rest_pending:
					_bonfire_rest_pending = true
					GameData.heal(GameData.hp_max)
					GameData.heal_companions()
					var _old_time := GameData.world_time
					GameData.world_time = fmod(GameData.world_time + 8.0 / 24.0, 1.0)
					if GameData.world_time < _old_time:
						GameData.game_day += 1
					if GameData.has_upgrade("supply_depot"):
						ItemDB.add_to_backpack(ItemDB.create_item("bread"))
						ItemDB.add_to_backpack(ItemDB.create_item("bread"))
					print("Game: Bonfire — rested, healed, time advanced 8 hrs")
			else:
				_bonfire_rest_pending = false

		elif interaction == "azure_flame":
			near_anything = true
			var flame_prompt: String = "[E] Rest & Refuel  [C] Jobs"
			if not GameData.companions.is_empty():
				flame_prompt = "[E] Rest & Refuel  [R] Companions  [C] Jobs"
			if _hud:
				_hud.show_prompt(flame_prompt)
			if e_just_pressed:
				GameData.torch_fuel = GameData.get_torch_fuel_max()
				GameData.heal(GameData.hp_max)
				GameData.heal_companions()
				if GameData.has_upgrade("supply_depot"):
					ItemDB.add_to_backpack(ItemDB.create_item("bread"))
					ItemDB.add_to_backpack(ItemDB.create_item("bread"))
				print("Game: Azure Flame — rested, healed, torch refuelled!")
			elif r_just_pressed and not _npc_ui_open:
				_open_companion_roster()
			elif c_just_pressed and not _npc_ui_open:
				_open_job_change_ui()

		elif interaction == "magic_arch":
			near_anything = true
			if _hud:
				_hud.show_prompt("[E] Teleport")
			if e_just_pressed:
				var dest: Vector3 = child.get_meta("teleport_to", Vector3.ZERO)
				_player.global_position = dest

		elif interaction == "npc":
			var npc_key: String  = child.get_meta("npc_key", "")
			var npc_def: Dictionary = NpcDB.get_def(npc_key)
			var npc_name: String = npc_def.get("name", npc_key) as String
			var role: String     = npc_def.get("role", "") as String
			near_anything = true
			if _hud:
				_hud.show_prompt("[E] %s — %s" % [npc_name, NpcDB.get_role_label(role)])
			if e_just_pressed and not _npc_ui_open:
				_open_npc_ui(npc_key, role)

		elif interaction == "searchable":
			# Auto-forage: triggers by proximity, no button press needed
			if dist <= 1.5:
				var search_key: String = child.get_meta("search_key", "")
				if not GameData.is_camp_searched(search_key):
					var search_type: String = child.get_meta("search_type", "tree")
					_do_search(search_key, search_type)

	if not near_anything and _hud:
		_hud.hide_prompt()

	_e_was_pressed = e_pressed
	_r_was_pressed = r_pressed
	_c_was_pressed = c_pressed


## Open the appropriate shop or sage UI for the given NPC.
func _open_npc_ui(npc_key: String, role: String) -> void:
	_npc_ui_open = true
	if _hud:
		_hud.hide_prompt()

	if role == "sage":
		var sage_ui := SageUIScript.new()
		sage_ui.name = "SageUI"
		add_child(sage_ui)
		sage_ui.open()
		sage_ui.sage_closed.connect(_on_npc_ui_closed)
	elif role == "structure_shop":
		var struct_ui := StructureShopUIScript.new()
		struct_ui.name = "StructureShopUI"
		add_child(struct_ui)
		struct_ui.open()
		struct_ui.shop_closed.connect(_on_npc_ui_closed)
	else:
		var shop_ui := ShopUIScript.new()
		shop_ui.name = "ShopUI"
		add_child(shop_ui)
		shop_ui.open(npc_key)
		shop_ui.shop_closed.connect(_on_npc_ui_closed)


func _open_companion_roster() -> void:
	_npc_ui_open = true
	if _hud:
		_hud.hide_prompt()
	var roster_ui := CompanionRosterUIScript.new()
	roster_ui.name = "CompanionRosterUI"
	add_child(roster_ui)
	roster_ui.roster_closed.connect(_on_npc_ui_closed)


func _open_job_change_ui() -> void:
	_npc_ui_open = true
	if _hud:
		_hud.hide_prompt()
	var jobs_ui := JobChangeUIScript.new()
	jobs_ui.name = "JobChangeUI"
	add_child(jobs_ui)
	jobs_ui.jobs_closed.connect(_on_npc_ui_closed)


func _on_npc_ui_closed() -> void:
	_npc_ui_open = false


## Search a tree or bush for random loot.
func _do_search(key: String, search_type: String) -> void:
	GameData.mark_camp_searched(key)

	# Loot tables: [weight, item_id or "gold_N" or "nothing"]
	var tree_loot := [
		[25, "nothing"],
		[18, "mushroom"], [15, "berry"], [12, "apple"],
		[8, "honey"], [5, "bread"],
		[4, "club"], [3, "stone_spear"],
		[3, "chest_leather"], [2, "boots_leather"],
		[3, "gold_5"], [2, "gold_10"],
	]
	var bush_loot := [
		[35, "nothing"],
		[25, "berry"], [20, "mushroom"],
		[10, "apple"], [5, "honey"],
		[3, "gold_3"], [2, "gold_5"],
	]

	var table: Array = tree_loot if search_type == "tree" else bush_loot
	var total_weight := 0
	for entry in table:
		total_weight += entry[0]

	var roll := randi_range(1, total_weight)
	var cumulative := 0
	var result: String = "nothing"
	for entry in table:
		cumulative += entry[0]
		if roll <= cumulative:
			result = entry[1]
			break

	if result == "nothing":
		if _hud:
			_hud.show_toast("Nothing useful here.", 2.0)
		return

	if result.begins_with("gold_"):
		var amount := int(result.split("_")[1])
		GameData.add_gold(amount)
		if _hud:
			_hud.show_toast("You found %d gold!" % amount, 2.5)
		return

	var item: Dictionary = ItemDB.create_item(result)
	if item.is_empty():
		return
	if ItemDB.add_to_backpack(item):
		if _hud:
			_hud.show_toast("You found %s!\nIt was added to your inventory" % item.get("name", "something"), 3.0)
	else:
		if _hud:
			_hud.show_toast("You found %s!\nBut your backpack is full!" % item.get("name", "something"), 3.0)
