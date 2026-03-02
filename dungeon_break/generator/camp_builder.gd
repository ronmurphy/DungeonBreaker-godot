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
const AIR         = 0
const DIRT        = 1
const GRASS       = 2
const LOG_X       = 3
const LOG_Y       = 4
const LOG_Z       = 5
const PLANKS      = 7
const TALL_GRASS  = 8
const GLASS       = 12
const LEAVES      = 25
const DEAD_SHRUB  = 26
const STONE_BRICKS = 63

const _CHANNEL = VoxelBuffer.CHANNEL_TYPE

# ── Camp room positions (from JS: gx, gy → world X, Z) ──────────────────────
# JS uses grid coords where 1 grid unit ≈ 1 voxel for camp
const AZURE_FLAME_POS := Vector3i(32, 0, 0)    # East edge (pulled in from 42 to be on island)
const BONFIRE_POS     := Vector3i(-9, 0, -9)    # Northwest, near centre
const SPIRE_POS       := Vector3i(9, 0, 9)      # Southeast, near centre

# ── Tree positions — 10 hand-placed, natural-feeling clusters ────────────────
const TREE_POSITIONS := [
	Vector2i(-20,  -8),   # NW cluster
	Vector2i(-15, -18),   # NW cluster
	Vector2i( -5, -22),   # North
	Vector2i( 16, -22),   # NE cluster
	Vector2i( 22, -14),   # NE cluster
	Vector2i(-10,  22),   # South cluster
	Vector2i(  8,  25),   # South cluster
	Vector2i(-22,  18),   # SW cluster
	Vector2i(-28,   8),   # West
	Vector2i( 28, -15),   # East
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
	_build_trees()
	_build_paths()         # before foliage so paths block foliage placement
	_build_central_plaza() # includes well
	_build_dock()
	_build_magic_arches()  # teleporter pair: camp surface ↔ below plateau
	_scatter_foliage()

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
# TREES — 10 proper multi-block trees replacing the old stick markers
# ══════════════════════════════════════════════════════════════════════════════
func _build_trees():
	for tp in TREE_POSITIONS:
		var tx: int = tp.x
		var tz: int = tp.y
		var sy := _surface_y(tx, tz)

		# 4-block trunk
		for y in range(sy + 1, sy + 5):
			_voxel_tool.set_voxel(Vector3i(tx, y, tz), LOG_Y)

		# Canopy ring 1 — 3×3 LEAVES at trunk top (sy+4)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				_voxel_tool.set_voxel(Vector3i(tx + dx, sy + 4, tz + dz), LEAVES)

		# Canopy ring 2 — 3×3 LEAVES one above (sy+5)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				_voxel_tool.set_voxel(Vector3i(tx + dx, sy + 5, tz + dz), LEAVES)

		# Cap — single block (sy+6)
		_voxel_tool.set_voxel(Vector3i(tx, sy + 6, tz), LEAVES)


# ══════════════════════════════════════════════════════════════════════════════
# PATHS — Stone brick paths connecting the three landmarks via a central plaza
# ══════════════════════════════════════════════════════════════════════════════
func _build_paths():
	_stamp_path(-9, -9,  -2, -2)   # Bonfire → Plaza
	_stamp_path( 2,  2,   9,  9)   # Plaza → Spire
	_stamp_path( 2,  0,  31,  0)   # Plaza → Azure Flame (east)


func _stamp_path(ax: int, az: int, bx: int, bz: int):
	var steps := maxi(abs(bx - ax), abs(bz - az))
	if steps == 0:
		return
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var px := roundi(lerp(float(ax), float(bx), t))
		var pz := roundi(lerp(float(az), float(bz), t))
		var sy := _surface_y(px, pz)
		_voxel_tool.set_voxel(Vector3i(px, sy, pz), STONE_BRICKS)


# ══════════════════════════════════════════════════════════════════════════════
# CENTRAL PLAZA — 5×5 stone hub at (0,0) with a well at the centre
# ══════════════════════════════════════════════════════════════════════════════
func _build_central_plaza():
	# 5×5 stone plaza following terrain per-block
	for x in range(-2, 3):
		for z in range(-2, 3):
			var sy := _surface_y(x, z)
			_voxel_tool.set_voxel(Vector3i(x, sy, z), STONE_BRICKS)
			for y in range(sy + 1, sy + 4):
				_voxel_tool.set_voxel(Vector3i(x, y, z), AIR)

	# Well is 3 blocks north of plaza centre (keeps it clear of player spawn)
	_build_well(0, -3, _surface_y(0, -3))


func _build_well(cx: int, cz: int, sy: int):
	# 3×3 stone base (filled)
	for x in range(cx - 1, cx + 2):
		for z in range(cz - 1, cz + 2):
			_voxel_tool.set_voxel(Vector3i(x, sy + 1, z), STONE_BRICKS)

	# Ring at sy+2 — perimeter stone, centre = AIR (the shaft opening)
	for x in range(cx - 1, cx + 2):
		for z in range(cz - 1, cz + 2):
			if x == cx and z == cz:
				_voxel_tool.set_voxel(Vector3i(x, sy + 2, z), AIR)
			else:
				_voxel_tool.set_voxel(Vector3i(x, sy + 2, z), STONE_BRICKS)

	# Two LOG_Y posts east and west of shaft
	_voxel_tool.set_voxel(Vector3i(cx - 1, sy + 3, cz), LOG_Y)
	_voxel_tool.set_voxel(Vector3i(cx + 1, sy + 3, cz), LOG_Y)

	# Plank beam across the top
	for x in range(cx - 1, cx + 2):
		_voxel_tool.set_voxel(Vector3i(x, sy + 4, cz), PLANKS)

	# Soft moonlit glow
	if _scene_root:
		_add_campfire_light(
			Vector3(cx + 0.5, sy + 4.5, cz + 0.5),
			"WellLight", Color(0.85, 0.9, 1.0), 0.8, 6.0)


# ══════════════════════════════════════════════════════════════════════════════
# DOCK — Wooden pier extending east from the island shore near Azure Flame
# ══════════════════════════════════════════════════════════════════════════════
func _build_dock():
	var dock_x_start := 35
	var dock_x_end   := 46
	var dock_y := maxi(_surface_y(dock_x_start, 0) + 1, 3)

	# Deck planks — 3 blocks wide (z = -1..1)
	for x in range(dock_x_start, dock_x_end + 1):
		for z in range(-1, 2):
			_voxel_tool.set_voxel(Vector3i(x, dock_y, z), PLANKS)
			for y in range(dock_y + 1, dock_y + 4):
				_voxel_tool.set_voxel(Vector3i(x, y, z), AIR)

	# Support pillars every 4 blocks (x = 35, 39, 43)
	for px in [dock_x_start, dock_x_start + 4, dock_x_start + 8]:
		for z in range(-1, 2):
			for y in range(0, dock_y):
				_voxel_tool.set_voxel(Vector3i(px, y, z), LOG_Y)

	# Amber lantern light at the end of the pier
	if _scene_root:
		_add_campfire_light(
			Vector3(dock_x_end + 0.5, dock_y + 1.5, 0.5),
			"DockLight", Color(1.0, 0.7, 0.3), 1.5, 8.0)


# ══════════════════════════════════════════════════════════════════════════════
# FOLIAGE — Scatter tall grass and dead shrubs across open island ground
# ══════════════════════════════════════════════════════════════════════════════
func _scatter_foliage():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42  # fixed seed — same scatter every build

	# Zones to avoid (cx, cz, radius)
	var avoid_cx: Array[int] = [BONFIRE_POS.x, SPIRE_POS.x, AZURE_FLAME_POS.x, 0, 35, ARCH_TOP_X]
	var avoid_cz: Array[int] = [BONFIRE_POS.z, SPIRE_POS.z, AZURE_FLAME_POS.z, 0,  0, ARCH_TOP_Z]
	var avoid_r:  Array[int] = [             8,           8,                 8, 5, 10,          6]

	var foliage_blocks: Array[int] = [TALL_GRASS, DEAD_SHRUB]
	var foliage_counts: Array[int] = [        30,         15]
	var foliage_min_r:  Array[int] = [         0,         20]
	var foliage_max_r:  Array[int] = [        38,         38]

	for fi in range(foliage_blocks.size()):
		var block: int   = foliage_blocks[fi]
		var count: int   = foliage_counts[fi]
		var min_r: float = float(foliage_min_r[fi])
		var max_r: int   = foliage_max_r[fi]

		var placed   := 0
		var attempts := 0
		while placed < count and attempts < count * 25:
			attempts += 1
			var fx: int = rng.randi_range(-max_r, max_r)
			var fz: int = rng.randi_range(-max_r, max_r)

			# Must be within island ring
			var dist := sqrt(float(fx * fx + fz * fz))
			if dist < min_r or dist > float(max_r):
				continue

			# Skip structure zones
			var too_close := false
			for ai in range(avoid_cx.size()):
				var dx: int = fx - avoid_cx[ai]
				var dz: int = fz - avoid_cz[ai]
				if sqrt(float(dx * dx + dz * dz)) < float(avoid_r[ai]):
					too_close = true
					break
			if too_close:
				continue

			# Only place on plain GRASS (not path stone, plaza, dock planks)
			var sy := _surface_y(fx, fz)
			if _voxel_tool.get_voxel(Vector3i(fx, sy, fz)) != GRASS:
				continue
			if _voxel_tool.get_voxel(Vector3i(fx, sy + 1, fz)) != AIR:
				continue

			_voxel_tool.set_voxel(Vector3i(fx, sy + 1, fz), block)
			placed += 1


# ══════════════════════════════════════════════════════════════════════════════
# HELPERS — Lights, particles, etc.
# ══════════════════════════════════════════════════════════════════════════════

# ══════════════════════════════════════════════════════════════════════════════
# MAGIC ARCHES — Teleporter pair: one on camp plateau, one below
# ══════════════════════════════════════════════════════════════════════════════

const ARCH_TOP_X := 0
const ARCH_TOP_Z := 32      # south edge of camp plateau
const ARCH_BOTTOM_X := 0
const ARCH_BOTTOM_Z := 48   # south, past island edge

var _bottom_arch_pos := Vector3.ZERO  # cached for void teleport


func _build_magic_arches():
	var bonfire_sy := _surface_y(BONFIRE_POS.x, BONFIRE_POS.z)

	# ── Top arch: on camp plateau, lowered 1 block ──
	var top_sy := _surface_y(ARCH_TOP_X, ARCH_TOP_Z) - 1
	var top_stand := Vector3(ARCH_TOP_X + 0.5, top_sy + 1.0, ARCH_TOP_Z + 0.5)
	_build_arch_structure(ARCH_TOP_X, top_sy, ARCH_TOP_Z)

	# ── Bottom arch: off the plateau, 17 blocks below bonfire level ──
	var bottom_sy := bonfire_sy - 17
	var bottom_stand := Vector3(ARCH_BOTTOM_X + 0.5, bottom_sy + 1.0, ARCH_BOTTOM_Z + 0.5)
	_bottom_arch_pos = bottom_stand

	# Build a 7×7 stone platform for the bottom arch (no natural ground there)
	for x in range(ARCH_BOTTOM_X - 3, ARCH_BOTTOM_X + 4):
		for z in range(ARCH_BOTTOM_Z - 3, ARCH_BOTTOM_Z + 4):
			_voxel_tool.set_voxel(Vector3i(x, bottom_sy, z), STONE_BRICKS)
			_voxel_tool.set_voxel(Vector3i(x, bottom_sy - 1, z), DIRT)
			# Perimeter rim
			var is_edge: bool = (x == ARCH_BOTTOM_X - 3 or x == ARCH_BOTTOM_X + 3
				or z == ARCH_BOTTOM_Z - 3 or z == ARCH_BOTTOM_Z + 3)
			if is_edge:
				_voxel_tool.set_voxel(Vector3i(x, bottom_sy + 1, z), STONE_BRICKS)
			else:
				for y in range(bottom_sy + 1, bottom_sy + 6):
					_voxel_tool.set_voxel(Vector3i(x, y, z), AIR)

	_build_arch_structure(ARCH_BOTTOM_X, bottom_sy, ARCH_BOTTOM_Z)

	# ── Interaction areas ──
	if _scene_root:
		_add_arch_area("TopArch", ARCH_TOP_X, top_sy, ARCH_TOP_Z, bottom_stand)
		_add_arch_area("BottomArch", ARCH_BOTTOM_X, bottom_sy, ARCH_BOTTOM_Z, top_stand)


func _build_arch_structure(cx: int, sy: int, cz: int):
	# Flatten a 5×5 area at surface level
	for x in range(cx - 2, cx + 3):
		for z in range(cz - 2, cz + 3):
			_voxel_tool.set_voxel(Vector3i(x, sy, z), STONE_BRICKS)
			for y in range(sy + 1, sy + 7):
				_voxel_tool.set_voxel(Vector3i(x, y, z), AIR)

	# Two pillars (3 blocks tall)
	for y in range(sy + 1, sy + 4):
		_voxel_tool.set_voxel(Vector3i(cx - 1, y, cz), STONE_BRICKS)
		_voxel_tool.set_voxel(Vector3i(cx + 1, y, cz), STONE_BRICKS)

	# Lintel across the top
	for x in range(cx - 1, cx + 2):
		_voxel_tool.set_voxel(Vector3i(x, sy + 4, cz), STONE_BRICKS)

	# Glass cap (glowing)
	_voxel_tool.set_voxel(Vector3i(cx, sy + 5, cz), GLASS)

	# Purple/blue magic light
	if _scene_root:
		_add_campfire_light(
			Vector3(cx + 0.5, sy + 4.5, cz + 0.5),
			"ArchLight_%d_%d" % [cx, cz], Color(0.5, 0.2, 1.0), 2.5, 10.0)


func _add_arch_area(area_name: String, cx: int, sy: int, cz: int, dest: Vector3):
	var area := Area3D.new()
	area.name = area_name
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 4, 4)
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "magic_arch")
	area.set_meta("teleport_to", dest)
	_scene_root.add_child(area)
	area.global_position = Vector3(cx + 0.5, sy + 2.0, cz + 0.5)


## World position of the bottom magic arch (for void teleport).
func get_bottom_arch_pos() -> Vector3:
	return _bottom_arch_pos


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
