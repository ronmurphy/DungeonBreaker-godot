extends Node
## Main game script for Dungeon Break — camp world.
##
## Spawns the player, builds camp structures (bonfire, spire, azure flame),
## spawns wanderer NPCs, and manages the camp lifecycle.

const PlayerScene = preload("res://dungeon_break/player/player.tscn")
const IsometricCamera = preload("res://dungeon_break/player/isometric_camera.gd")
const CampBuilderScript = preload("res://dungeon_break/generator/camp_builder.gd")
const WandererScript = preload("res://dungeon_break/entities/wanderer_controller.gd")
const DayNightCycleScript = preload("res://dungeon_break/world/day_night_cycle.gd")
const GameHudScript = preload("res://dungeon_break/ui/game_hud.gd")
const InventoryUIScript = preload("res://dungeon_break/ui/inventory_ui.gd")
const ShopUIScript = preload("res://dungeon_break/ui/shop_ui.gd")
const SageUIScript = preload("res://dungeon_break/ui/sage_ui.gd")

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

# Rescued NPC billboard sprites — updated for camera-facing each frame
var _npc_sprites: Array = []

# ── Camp structure parent node ───────────────────────────────────────────────
var _camp_objects: Node3D = null

# Tracks whether a shop/sage UI is currently open (prevents multi-open)
var _npc_ui_open: bool = false


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
	_wanderer_ctrl.spawn_camp_wanderers()

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


func _wait_for_terrain_editable():
	## Poll until the VoxelTool says the camp area is editable.
	## Checks a small AABB around origin (covers bonfire/spire area).
	var vt := _terrain.get_voxel_tool()
	var check_aabb := AABB(Vector3(-40, -5, -40), Vector3(80, 30, 80))

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


## Check if the player is near a camp interaction area and pressing E.
func _check_portal_interactions():
	if _player == null or _camp_objects == null:
		return

	var player_pos := _player.global_position
	var near_anything := false

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
			if Input.is_key_pressed(KEY_E):
				print("Game: entering dungeon portal!")
				enter_dungeon.emit()
				return
		elif interaction == "azure_flame":
			near_anything = true
			if _hud:
				_hud.show_prompt("[E] Refuel Torch")
			if Input.is_key_pressed(KEY_E):
				GameData.torch_fuel = 100
				print("Game: torch refuelled!")

		elif interaction == "npc":
			var npc_key: String  = child.get_meta("npc_key", "")
			var npc_def: Dictionary = NpcDB.get_def(npc_key)
			var npc_name: String = npc_def.get("name", npc_key) as String
			var role: String     = npc_def.get("role", "") as String
			near_anything = true
			if _hud:
				_hud.show_prompt("[E] %s — %s" % [npc_name, NpcDB.get_role_label(role)])
			if Input.is_key_pressed(KEY_E) and not _npc_ui_open:
				_open_npc_ui(npc_key, role)

	if not near_anything and _hud:
		_hud.hide_prompt()


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
	else:
		var shop_ui := ShopUIScript.new()
		shop_ui.name = "ShopUI"
		add_child(shop_ui)
		shop_ui.open(npc_key)
		shop_ui.shop_closed.connect(_on_npc_ui_closed)


func _on_npc_ui_closed() -> void:
	_npc_ui_open = false
