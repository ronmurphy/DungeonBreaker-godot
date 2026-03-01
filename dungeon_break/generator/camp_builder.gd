extends Node
## Builds camp structures by stamping blocks into the VoxelTerrain.
##
## Three landmark buildings (from JS generateCampRooms):
##   - Room 0: Azure Flame — torch refuelling station at island edge
##   - Room 1: Bonfire — rest/heal campfire near centre
##   - Room 2: Spire — dungeon entrance portal
##
## Called once after terrain loads. Uses VoxelTool to place blocks.

const NpcSpriteScript = preload("res://dungeon_break/entities/npc_sprite.gd")

# ── Block IDs matching voxel_library.tres order ──────────────────────────────
const AIR       = 0
const DIRT      = 1
const GRASS     = 2
const LOG_X     = 3
const LOG_Y     = 4
const LOG_Z     = 5
const PLANKS    = 7
const GLASS     = 12
const LEAVES    = 25

const _CHANNEL = VoxelBuffer.CHANNEL_TYPE

# ── Camp room positions (from JS: gx, gy → world X, Z) ──────────────────────
# JS uses grid coords where 1 grid unit ≈ 1 voxel for camp
const AZURE_FLAME_POS := Vector3i(32, 0, 0)    # East edge (pulled in from 42 to be on island)
const BONFIRE_POS     := Vector3i(-9, 0, -9)    # Northwest, near centre
const SPIRE_POS       := Vector3i(9, 0, 9)      # Southeast, near centre

# ── Decoration positions — scatter props around camp ─────────────────────────
const MARKER_POSITIONS := [
	Vector3i(20, 0, -15),   # East marker
	Vector3i(-20, 0, 15),   # West marker
	Vector3i(0, 0, -25),    # North marker
	Vector3i(-15, 0, -20),  # NW marker
	Vector3i(15, 0, 20),    # SE marker
]

var _terrain: VoxelTerrain = null
var _voxel_tool: VoxelTool = null

# ── 3D scene objects (particles, lights, etc.) ───────────────────────────────
var _scene_root: Node3D = null  # Parent node for non-voxel decorations


## Initialise with terrain reference and a parent node for 3D objects.
func setup(terrain: VoxelTerrain, scene_parent: Node3D):
	_terrain = terrain
	_voxel_tool = terrain.get_voxel_tool()
	_scene_root = scene_parent


## Build all camp structures. Call after terrain has generated.
func build_camp():
	if _voxel_tool == null:
		push_error("CampBuilder: no voxel tool — call setup() first")
		return

	_build_bonfire(BONFIRE_POS)
	_build_spire(SPIRE_POS)
	_build_azure_flame(AZURE_FLAME_POS)
	_build_markers()

	print("CampBuilder: camp structures placed")


## Get surface Y at (x, z) — topmost solid block.
func _surface_y(x: int, z: int) -> int:
	for y in range(20, -5, -1):
		var v := _voxel_tool.get_voxel(Vector3i(x, y, z))
		if v != AIR:
			return y
	return 0


## Fill a rectangular box with a block type.
func _fill_box(origin: Vector3i, size: Vector3i, block: int):
	for x in range(size.x):
		for y in range(size.y):
			for z in range(size.z):
				_voxel_tool.set_voxel(origin + Vector3i(x, y, z), block)


## Place a hollow room (walls + floor, no roof) — used for shelters.
func _fill_hollow(origin: Vector3i, size: Vector3i, wall_block: int, floor_block: int):
	for x in range(size.x):
		for z in range(size.z):
			# Floor
			_voxel_tool.set_voxel(origin + Vector3i(x, 0, z), floor_block)

			# Walls (only on edges)
			var is_edge := (x == 0 or x == size.x - 1 or z == 0 or z == size.z - 1)
			if is_edge:
				for y in range(1, size.y):
					_voxel_tool.set_voxel(origin + Vector3i(x, y, z), wall_block)
			else:
				# Interior air
				for y in range(1, size.y):
					_voxel_tool.set_voxel(origin + Vector3i(x, y, z), AIR)


# ══════════════════════════════════════════════════════════════════════════════
# BONFIRE — A 5×5 flat clearing with a log-ring campfire + OmniLight
# ══════════════════════════════════════════════════════════════════════════════
func _build_bonfire(pos: Vector3i):
	var sy := _surface_y(pos.x, pos.z)

	# Flatten a 7×7 area at surface level
	for x in range(pos.x - 3, pos.x + 4):
		for z in range(pos.z - 3, pos.z + 4):
			_voxel_tool.set_voxel(Vector3i(x, sy, z), GRASS)
			# Clear above
			for y in range(sy + 1, sy + 5):
				_voxel_tool.set_voxel(Vector3i(x, y, z), AIR)

	# Log ring (3×3 ring of log blocks at ground+1)
	var ring := [
		Vector3i(-1, 0, -1), Vector3i(0, 0, -1), Vector3i(1, 0, -1),
		Vector3i(-1, 0, 0),                        Vector3i(1, 0, 0),
		Vector3i(-1, 0, 1),  Vector3i(0, 0, 1),   Vector3i(1, 0, 1),
	]
	for offset in ring:
		_voxel_tool.set_voxel(Vector3i(pos.x, sy + 1, pos.z) + offset, LOG_Y)

	# Add fire particle + light as 3D scene objects
	if _scene_root:
		var fire_pos := Vector3(pos.x + 0.5, sy + 2.0, pos.z + 0.5)
		_add_campfire_light(fire_pos, "BonfireLight", Color(1.0, 0.6, 0.2), 2.5, 12.0)

		# Interaction area
		var area := Area3D.new()
		area.name = "Bonfire"
		var coll := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(5, 4, 5)
		coll.shape = shape
		area.add_child(coll)
		area.set_meta("interaction", "bonfire")
		_scene_root.add_child(area)
		area.global_position = Vector3(pos.x + 0.5, sy + 2.0, pos.z + 0.5)


# ══════════════════════════════════════════════════════════════════════════════
# SPIRE — Dungeon entrance: a stone column with a glowing portal marker
# ══════════════════════════════════════════════════════════════════════════════
func _build_spire(pos: Vector3i):
	var sy := _surface_y(pos.x, pos.z)

	# Flatten 5×5 area
	for x in range(pos.x - 2, pos.x + 3):
		for z in range(pos.z - 2, pos.z + 3):
			_voxel_tool.set_voxel(Vector3i(x, sy, z), PLANKS)
			for y in range(sy + 1, sy + 8):
				_voxel_tool.set_voxel(Vector3i(x, y, z), AIR)

	# Central spire column (dirt = stone-ish look)
	for y in range(sy + 1, sy + 6):
		_voxel_tool.set_voxel(Vector3i(pos.x, y, pos.z), DIRT)

	# Cap with glass (glows)
	_voxel_tool.set_voxel(Vector3i(pos.x, sy + 6, pos.z), GLASS)

	# Corner pillars
	for dx in [-2, 2]:
		for dz in [-2, 2]:
			for y in range(sy + 1, sy + 4):
				_voxel_tool.set_voxel(Vector3i(pos.x + dx, y, pos.z + dz), DIRT)

	# Portal light — purple/violet
	if _scene_root:
		var portal_pos := Vector3(pos.x + 0.5, sy + 4.0, pos.z + 0.5)
		_add_campfire_light(portal_pos, "PortalLight", Color(0.6, 0.2, 1.0), 3.0, 10.0)

		# Interaction area marker (for later — trigger zone)
		var area := Area3D.new()
		area.name = "DungeonEntrance"
		var coll := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(5, 4, 5)
		coll.shape = shape
		area.add_child(coll)
		area.set_meta("interaction", "dungeon_entrance")
		_scene_root.add_child(area)
		area.global_position = Vector3(pos.x + 0.5, sy + 2.5, pos.z + 0.5)


# ══════════════════════════════════════════════════════════════════════════════
# AZURE FLAME — Torch refuelling station at island edge
# ══════════════════════════════════════════════════════════════════════════════
func _build_azure_flame(pos: Vector3i):
	var sy := _surface_y(pos.x, pos.z)

	# Flatten 6×6 area
	for x in range(pos.x - 3, pos.x + 3):
		for z in range(pos.z - 3, pos.z + 3):
			# Build up the platform if needed (island edge might be low)
			for y in range(maxi(0, sy - 2), sy + 1):
				_voxel_tool.set_voxel(Vector3i(x, y, z), PLANKS)
			for y in range(sy + 1, sy + 6):
				_voxel_tool.set_voxel(Vector3i(x, y, z), AIR)

	# Central pedestal
	for y in range(sy + 1, sy + 3):
		_voxel_tool.set_voxel(Vector3i(pos.x, y, pos.z), DIRT)

	# Azure light — blue flame
	if _scene_root:
		var flame_pos := Vector3(pos.x + 0.5, sy + 3.5, pos.z + 0.5)
		_add_campfire_light(flame_pos, "AzureFlameLight", Color(0.2, 0.5, 1.0), 2.0, 8.0)

		# Interaction area
		var area := Area3D.new()
		area.name = "AzureFlame"
		var coll := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(4, 3, 4)
		coll.shape = shape
		area.add_child(coll)
		area.set_meta("interaction", "azure_flame")
		_scene_root.add_child(area)
		area.global_position = Vector3(pos.x + 0.5, sy + 2.0, pos.z + 0.5)


# ══════════════════════════════════════════════════════════════════════════════
# MARKERS — Small decorative posts around the camp
# ══════════════════════════════════════════════════════════════════════════════
func _build_markers():
	for mpos in MARKER_POSITIONS:
		var sy := _surface_y(mpos.x, mpos.z)
		# Simple log post with a leaf block on top
		_voxel_tool.set_voxel(Vector3i(mpos.x, sy + 1, mpos.z), LOG_Y)
		_voxel_tool.set_voxel(Vector3i(mpos.x, sy + 2, mpos.z), LOG_Y)
		_voxel_tool.set_voxel(Vector3i(mpos.x, sy + 3, mpos.z), LEAVES)


# ══════════════════════════════════════════════════════════════════════════════
# HELPERS — Lights, particles, etc.
# ══════════════════════════════════════════════════════════════════════════════

func _add_campfire_light(pos: Vector3, node_name: String, color: Color, energy: float, range_val: float):
	var light := OmniLight3D.new()
	light.name = node_name
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_val
	light.omni_attenuation = 1.2
	light.shadow_enabled = false  # Performance: skip shadow for camp lights
	_scene_root.add_child(light)
	light.global_position = pos


# ══════════════════════════════════════════════════════════════════════════════
# NPC SPAWNING — one slot per rescued NPC, spread around camp
# ══════════════════════════════════════════════════════════════════════════════

## Six named slots scattered around the bonfire/spire area.
## "pos" = Vector2i(world_x, world_z), "face" = Vector2(fx, fz) direction NPC faces.
const NPC_SLOTS: Array = [
	{ "pos": Vector2i(-18,  0), "face": Vector2( 1,  0) },  # west,  face east
	{ "pos": Vector2i( -5,-17), "face": Vector2( 0,  1) },  # north, face south
	{ "pos": Vector2i(  5, -3), "face": Vector2(-1,  1) },  # near bonfire NE
	{ "pos": Vector2i( -2,  7), "face": Vector2( 1, -1) },  # near bonfire SW
	{ "pos": Vector2i( 17, -9), "face": Vector2(-1,  1) },  # east area
	{ "pos": Vector2i( 20,  9), "face": Vector2(-1,  0) },  # east, face west
]


## Spawn billboard sprites for every rescued NPC. Returns the NpcSprite nodes
## so game.gd can call update_facing() on them each frame.
func spawn_rescued_npcs() -> Array:
	if _scene_root == null:
		return []

	var sprites: Array = []
	var rescued: Array = GameData.rescued_npcs

	for i in mini(rescued.size(), NPC_SLOTS.size()):
		var npc_key: String = rescued[i]
		var slot:    Dictionary = NPC_SLOTS[i]
		var npc_def: Dictionary = NpcDB.get_def(npc_key)
		if npc_def.is_empty():
			continue

		var pos2: Vector2i  = slot["pos"]
		var face2: Vector2  = slot["face"]
		var sy    := _surface_y(pos2.x, pos2.y)
		var world_pos := Vector3(pos2.x + 0.5, sy + 1.5, pos2.y + 0.5)
		var face_dir  := Vector3(face2.x, 0.0, face2.y).normalized()

		# ── NPC billboard sprite ──
		var npc_sprite := NpcSpriteScript.new() as NpcSprite
		npc_sprite.name = "Npc_" + npc_key
		_scene_root.add_child(npc_sprite)
		npc_sprite.global_position = world_pos
		npc_sprite.setup(npc_def.get("sprite_prefix", "") as String, face_dir)
		sprites.append(npc_sprite)

		# ── Interaction trigger area ──
		var area := Area3D.new()
		area.name = "NpcArea_" + npc_key
		var coll  := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = 2.5
		coll.shape   = shape
		area.add_child(coll)
		area.set_meta("interaction", "npc")
		area.set_meta("npc_key",     npc_key)
		_scene_root.add_child(area)
		area.global_position = Vector3(world_pos.x, sy + 1.0, world_pos.z)

	return sprites


## Get the world position of the dungeon entrance (for player navigation).
func get_dungeon_entrance_pos() -> Vector3:
	var sy := _surface_y(SPIRE_POS.x, SPIRE_POS.z)
	return Vector3(SPIRE_POS.x + 0.5, sy + 1.0, SPIRE_POS.z + 0.5)


## Get the world position of the bonfire (for player spawn/rest).
func get_bonfire_pos() -> Vector3:
	var sy := _surface_y(BONFIRE_POS.x, BONFIRE_POS.z)
	return Vector3(BONFIRE_POS.x + 0.5, sy + 1.0, BONFIRE_POS.z + 0.5)
