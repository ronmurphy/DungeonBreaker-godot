extends Node
## Stamps a BSP dungeon layout into VoxelTerrain.
##
## Takes the result dict from BspDungeon.generate() and carves the rooms,
## corridors, decorations, and lighting into the dungeon voxel terrain.
## Similar role to CampBuilder but for dungeon floors.

const BspDungeon = preload("res://dungeon_break/generator/bsp_dungeon.gd")

# ── Block IDs (now using the full range from theLongNights import) ──
const AIR    = 0
const DIRT   = 1    
const GRASS  = 2
const LOG_X  = 3
const LOG_Y  = 4
const LOG_Z  = 5
const STAIRS    = 6   # stairs_nx — climb toward -X
const STAIRS_NZ = 9   # stairs_nz — climb toward -Z
const STAIRS_PX = 10  # stairs_px — climb toward +X
const STAIRS_PZ = 11  # stairs_pz — climb toward +Z
const PLANKS = 7
const TALL_GRASS = 8
const GLASS  = 12
const WATER  = 14
const LEAVES = 25
const DEAD_SHRUB = 26
const STONE  = 29
const GOLD_ORE = 30
const IRON_ORE = 31
const RUIN_STONE = 33
const RUIN_FLOOR = 34
const TELEPORT_STONE = 35
const SAND   = 44
const SAND_STONE = 45
const CRATE  = 42
const CHEST  = 48
const RUST_BLOCK = 49
const RUST_PIPE = 50
const VOID_STONE = 53
const VOID_STONE_ACTIVE = 54
const VOID_FOG = 55
const PIPE_BLOCK = 56
const RUNE_CORE = 61
const STONE_BRICKS = 63
const VOID_STONE_BRICKS = 64

const WALL_HEIGHT    := 3   # walls are 3 blocks tall above floor
const FLOOR_Y        := 0   # base floor level
const MAX_ELEVATION  := 3   # max room floor_height (blocks above FLOOR_Y)

var _terrain: VoxelTerrain = null
var _voxel_tool: VoxelTool = null
var _scene_root: Node3D = null

# Store the generated dungeon data for game logic
var dungeon_data: Dictionary = {}

# Set before calling _decorate_room() so _add_light() can group lights by room.
# -1 means "no room" (corridor lights), which stay permanently visible.
var _current_room_id: int = -1


func setup(terrain: VoxelTerrain, scene_parent: Node3D):
	_terrain = terrain
	_voxel_tool = terrain.get_voxel_tool()
	_scene_root = scene_parent


## Re-acquire the voxel tool after chunks have loaded.
## Must be called between _wait_for_terrain_editable() and build_dungeon().
func refresh_voxel_tool():
	if _terrain:
		_voxel_tool = _terrain.get_voxel_tool()
		print("DungeonStamper: voxel tool refreshed")


## Generate and stamp a full dungeon floor. Returns dungeon data dict.
func build_dungeon(floor_num: int) -> Dictionary:
	if _voxel_tool == null:
		push_error("DungeonStamper: no voxel tool — call setup() first")
		return {}

	# Generate the BSP layout
	var gen := BspDungeon.new()
	dungeon_data = gen.generate(floor_num)

	var grid: Array = dungeon_data["grid"]
	var rooms: Array = dungeon_data["rooms"]
	var cols: int = dungeon_data["cols"]
	var rows: int = dungeon_data["rows"]

	# Offset: centre the dungeon around origin
	var ox: int = -cols / 2
	var oz: int = -rows / 2

	print("DungeonStamper: floor %d — grid %dx%d, offset (%d,%d), %d rooms" % [
		floor_num, cols, rows, ox, oz, rooms.size()])

	# Quick editability spot-check: test a tile near the grid corner
	var corner := Vector3i(ox + 1, 0, oz + 1)
	var corner_editable := _voxel_tool.is_area_editable(AABB(Vector3(corner), Vector3(1, 1, 1)))
	print("DungeonStamper: corner (%d,0,%d) editable=%s" % [corner.x, corner.z, str(corner_editable)])

	# Determine block themes based on floor level
	var wall_block := LOG_Y
	var room_floor := PLANKS
	var corr_floor := DIRT

	if floor_num >= 10:
		# Void dungeon — very dark, endgame only
		wall_block = VOID_STONE_BRICKS
		room_floor = RUIN_FLOOR
		corr_floor = VOID_STONE
	elif floor_num >= 7:
		# Grey stone dungeon — medium brightness, deep floors
		wall_block = STONE_BRICKS
		room_floor = RUIN_STONE
		corr_floor = STONE
	elif floor_num >= 4:
		# Sandstone crypt — warm and readable, mid floors
		wall_block = SAND_STONE
		room_floor = SAND
		corr_floor = STONE

	# Build room_at lookup: grid position → room dict (for elevation queries)
	var room_at := {}
	for room in rooms:
		for r in range(room["y"], room["y"] + room["h"]):
			for c in range(room["x"], room["x"] + room["w"]):
				room_at[Vector2i(c, r)] = room

	# Stamp tiles. Walls are extended to MAX_ELEVATION+WALL_HEIGHT so elevated
	# room walls reach the correct height. Elevated rooms get a solid platform
	# base (Y=1..elev-1) plus floor at Y=elev; corridor tiles stay flat.
	var stamp_count := 0
	var fail_count := 0
	for row in range(rows):
		for col in range(cols):
			var tile: int = grid[row][col]
			var wx: int = col + ox
			var wz: int = row + oz

			if tile == BspDungeon.ROOM:
				var rv: Dictionary = room_at.get(Vector2i(col, row), {})
				var elev: int = rv.get("floor_height", 0)
				var room_type: String = rv.get("room_type", "normal")

				# Per-room-type floor accent
				var floor_block := room_floor
				match room_type:
					"trap":   floor_block = RUST_BLOCK
					"locked": floor_block = IRON_ORE
					"alchemy":
						floor_block = RUNE_CORE if randf() < 0.12 else room_floor

				if elev > 0:
					for y in range(1, elev):
						_voxel_tool.set_voxel(Vector3i(wx, y, wz), wall_block)
						stamp_count += 1
					_voxel_tool.set_voxel(Vector3i(wx, elev, wz), floor_block)
					stamp_count += 1
					for y in range(elev + 1, elev + WALL_HEIGHT + 2):
						_voxel_tool.set_voxel(Vector3i(wx, y, wz), AIR)
						stamp_count += 1
				else:
					_voxel_tool.set_voxel(Vector3i(wx, FLOOR_Y, wz), floor_block)
					stamp_count += 1
					for y in range(FLOOR_Y + 1, FLOOR_Y + WALL_HEIGHT + 2):
						_voxel_tool.set_voxel(Vector3i(wx, y, wz), AIR)
						stamp_count += 1

			elif tile == BspDungeon.CORRIDOR:
				if corr_floor != DIRT:
					_voxel_tool.set_voxel(Vector3i(wx, FLOOR_Y, wz), corr_floor)
					stamp_count += 1
				for y in range(FLOOR_Y + 1, FLOOR_Y + WALL_HEIGHT + 1):
					_voxel_tool.set_voxel(Vector3i(wx, y, wz), AIR)
					stamp_count += 1

			elif tile == BspDungeon.WALL:
				for y in range(FLOOR_Y, FLOOR_Y + MAX_ELEVATION + WALL_HEIGHT + 2):
					_voxel_tool.set_voxel(Vector3i(wx, y, wz), wall_block)
					stamp_count += 1

	# Read-back verification: check a few wall tiles actually stuck
	var verify_ok := 0
	var verify_fail := 0
	for room in rooms:
		var wx_test: int = room["x"] + ox
		var wz_test: int = room["y"] + oz
		# The tile at (room_x-1, room_y) should be a WALL in the grid
		if room["x"] > 0:
			var test_col: int = room["x"] - 1
			var test_row: int = room["y"]
			if test_row >= 0 and test_row < rows and test_col >= 0 and test_col < cols:
				if grid[test_row][test_col] == BspDungeon.WALL:
					var read_back: int = _voxel_tool.get_voxel(Vector3i(test_col + ox, FLOOR_Y, test_row + oz))
					if read_back == wall_block:
						verify_ok += 1
					else:
						verify_fail += 1
	print("DungeonStamper: stamped %d voxels. Verify: %d ok, %d FAILED read-back" % [stamp_count, verify_ok, verify_fail])

	# Build staircases connecting corridors to elevated rooms
	_build_staircases(grid, rooms, cols, rows, ox, oz, wall_block)

	# Place room decorations and lights.
	# Set _current_room_id so _add_light() groups each light under its room —
	# dungeon.gd enables the group when the player first enters that room.
	for room in rooms:
		_current_room_id = room["id"]
		_decorate_room(room, ox, oz, floor_num)
		_current_room_id = -1

	# Place corridor decorations (sconces every ~8 tiles)
	_decorate_corridors(grid, cols, rows, ox, oz, floor_num)

	# Store offset for world→grid coordinate conversion
	dungeon_data["offset_x"] = ox
	dungeon_data["offset_z"] = oz

	var elevated_count := rooms.filter(func(r): return r.get("floor_height", 0) > 0).size()
	print("DungeonStamper: floor %d (%dx%d, %d rooms, %d elevated) theme wall=%d floor=%d" % [
		floor_num, cols, rows, rooms.size(), elevated_count, wall_block, room_floor])

	return dungeon_data


## Place stair blocks in corridor tiles adjacent to elevated rooms.
## For elev=2: 1 step (Y=1) in the adjacent tile.
## For elev=3: 2 steps — Y=2 in adjacent tile, Y=1 in the tile one step further out.
func _build_staircases(grid: Array, rooms: Array, cols: int, rows: int, ox: int, oz: int, wall_block: int) -> void:
	for room in rooms:
		var elev: int = room.get("floor_height", 0)
		if elev <= 0:
			continue

		var rx: int = room["x"]
		var ry: int = room["y"]
		var rw: int = room["w"]
		var rh: int = room["h"]
		var stamped := {}

		# Check each of the 4 room perimeter edges for adjacent corridor tiles.
		# dir = direction away from the room (used to extend multi-tile stairs outward).

		# North (ry - 1) — dir points further north (decreasing z)
		if ry > 0:
			for col in range(rx, rx + rw):
				if grid[ry - 1][col] == BspDungeon.CORRIDOR:
					var k := Vector2i(col, ry - 1)
					if not stamped.has(k):
						stamped[k] = true
						_stamp_stair_approach(col + ox, ry - 1 + oz, elev, Vector2i(0, -1), wall_block)

		# South (ry + rh) — dir points further south (increasing z)
		if ry + rh < grid.size():
			for col in range(rx, rx + rw):
				if grid[ry + rh][col] == BspDungeon.CORRIDOR:
					var k := Vector2i(col, ry + rh)
					if not stamped.has(k):
						stamped[k] = true
						_stamp_stair_approach(col + ox, ry + rh + oz, elev, Vector2i(0, 1), wall_block)

		# West (rx - 1) — dir points further west (decreasing x)
		if rx > 0:
			for row in range(ry, ry + rh):
				if grid[row][rx - 1] == BspDungeon.CORRIDOR:
					var k := Vector2i(rx - 1, row)
					if not stamped.has(k):
						stamped[k] = true
						_stamp_stair_approach(rx - 1 + ox, row + oz, elev, Vector2i(-1, 0), wall_block)

		# East (rx + rw) — dir points further east (increasing x)
		if rx + rw < cols:
			for row in range(ry, ry + rh):
				if grid[row][rx + rw] == BspDungeon.CORRIDOR:
					var k := Vector2i(rx + rw, row)
					if not stamped.has(k):
						stamped[k] = true
						_stamp_stair_approach(rx + rw + ox, row + oz, elev, Vector2i(1, 0), wall_block)


## Stamp stair approach tiles leading up to an elevated room.
##
## Tile layout (elev=3, approaching from north):
##   (tile, ry-2): STAIRS at Y=1  ← player steps here first
##   (tile, ry-1): STAIRS at Y=2  ← second step (adjacent to room)
##   (room floor): Y=3            ← enter room
##
## dir = direction away from the room (so tile at i=0 is adjacent, i=1 is one further out).
## fill_block fills the solid sub-support so stair blocks don't float.
func _stamp_stair_approach(wx: int, wz: int, elev: int, dir: Vector2i, fill_block: int) -> void:
	# dir is the direction away from the room — player climbs in the opposite direction.
	# stair ID encodes which way you climb (the open/low end faces dir).
	const DIR_TO_STAIR: Dictionary = {
		Vector2i( 1,  0): STAIRS,    # extends +X → climb toward -X → stairs_nx
		Vector2i(-1,  0): STAIRS_PX, # extends -X → climb toward +X → stairs_px
		Vector2i( 0,  1): STAIRS_NZ, # extends +Z → climb toward -Z → stairs_nz
		Vector2i( 0, -1): STAIRS_PZ, # extends -Z → climb toward +Z → stairs_pz
	}
	var stair_id: int = DIR_TO_STAIR.get(dir, STAIRS)

	var num_stairs := elev - 1   # 0 for elev≤1, 1 for elev=2, 2 for elev=3
	for i in range(num_stairs):
		var tx := wx + dir.x * i
		var tz := wz + dir.y * i
		var step_y := elev - 1 - i   # adjacent tile gets the highest step
		# Fill solid support below this step so it doesn't float
		for y in range(FLOOR_Y + 1, step_y):
			_voxel_tool.set_voxel(Vector3i(tx, y, tz), fill_block)
		# Place the correctly-oriented stair block
		_voxel_tool.set_voxel(Vector3i(tx, step_y, tz), stair_id)
		# Clear headroom from just above the stair up to wall top
		for y in range(step_y + 1, FLOOR_Y + MAX_ELEVATION + WALL_HEIGHT + 2):
			_voxel_tool.set_voxel(Vector3i(tx, y, tz), AIR)


## Decorate a room based on its type.
func _decorate_room(room: Dictionary, ox: int, oz: int, floor_num: int = 1):
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["w"]
	var rh: int = room["h"]
	var cx: int = room["cx"]
	var cy: int = room["cy"]

	# World coordinates of room centre
	var wcx: float = cx + ox + 0.5
	var wcz: float = cy + oz + 0.5
	
	# Pass floor_num where relevant (e.g. boss/lights)
	match room["room_type"]:
		"start":
			_build_start_room(wcx, wcz, room, ox, oz)
		"boss":
			_build_boss_room(wcx, wcz, room, ox, oz)
		"bonfire":
			_build_bonfire_room(wcx, wcz, room, ox, oz)
		"merchant":
			_build_merchant_room(wcx, wcz, room, ox, oz)
		"fountain":
			_build_fountain_room(wcx, wcz, room, ox, oz)
		"trap":
			_build_trap_room(wcx, wcz, room, ox, oz)
		"alchemy":
			_build_alchemy_room(wcx, wcz, room, ox, oz)
		"locked":
			pass  # Normal looking but needs a key
		"vault":
			_build_vault_room(wcx, wcz, room, ox, oz)
		"puzzle":
			_build_puzzle_room(wcx, wcz, room, ox, oz)
		"normal":
			pass  # Enemy rooms — decorated by enemy spawner

	# All rooms get corner sconces for lighting
	_add_room_sconces(room, ox, oz, floor_num)


## Start room: return portal + clear area.
func _build_start_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	if not _scene_root:
		return

	# Return portal light (blue — return to camp)
	_add_light(Vector3(wcx, 2.5, wcz), "ReturnPortal", Color(0.3, 0.5, 1.0), 2.5, 8.0)

	# Return portal trigger
	var area := Area3D.new()
	area.name = "ReturnPortal"
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 3)
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "return_portal")
	_scene_root.add_child(area)
	area.global_position = Vector3(wcx, 2.0, wcz)

	# Mark glass block under portal
	var gx := int(floor(wcx))
	var gz := int(floor(wcz))
	_voxel_tool.set_voxel(Vector3i(gx, FLOOR_Y, gz), GLASS)


## Boss room: large, dramatic lighting. Handles elevated upper rooms correctly.
func _build_boss_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	if not _scene_root:
		return

	var elev: int = room.get("floor_height", 0)
	var floor_y := FLOOR_Y + elev

	# Red ominous light
	_add_light(Vector3(wcx, float(floor_y) + 3.0, wcz), "BossLight", Color(1.0, 0.2, 0.1), 3.0, 14.0)

	# Floor portal (appears after boss defeat → next floor)
	var area := Area3D.new()
	area.name = "BossPortal"
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 3)
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "boss_portal")
	area.set_meta("enabled", false)  # Enabled after boss dies
	_scene_root.add_child(area)
	area.global_position = Vector3(wcx, float(floor_y) + 2.0, wcz)

	# 4 Rune Pillars around centre — placed relative to elevated floor
	for offset in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
		var px: int = int(floor(wcx)) + offset.x
		var pz: int = int(floor(wcz)) + offset.y
		# Base + Mid (Void Stone)
		_voxel_tool.set_voxel(Vector3i(px, floor_y + 1, pz), VOID_STONE)
		_voxel_tool.set_voxel(Vector3i(px, floor_y + 2, pz), VOID_STONE)
		# Top (Rune Core)
		_voxel_tool.set_voxel(Vector3i(px, floor_y + 3, pz), RUNE_CORE)


## Bonfire room: safe rest area.
func _build_bonfire_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	if not _scene_root:
		return

	# Warm campfire light
	_add_light(Vector3(wcx, 2.0, wcz), "DungeonBonfire", Color(1.0, 0.6, 0.2), 2.5, 10.0)

	# Log ring (3×3 minus centre)
	var gx := int(floor(wcx))
	var gz := int(floor(wcz))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			_voxel_tool.set_voxel(Vector3i(gx + dx, FLOOR_Y + 1, gz + dz), LOG_Y)

	# Bonfire interaction area
	var area := Area3D.new()
	area.name = "DungeonBonfireArea"
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 3, 4)
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "bonfire")
	_scene_root.add_child(area)
	area.global_position = Vector3(wcx, 2.0, wcz)

	room["state"] = "cleared"  # Safe room


## Merchant room: stalls.
func _build_merchant_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	if not _scene_root:
		return

	# Warm shop light
	_add_light(Vector3(wcx, 2.5, wcz), "MerchantLight", Color(1.0, 0.9, 0.6), 2.0, 8.0)

	# Small counter (planks block)
	var gx := int(floor(wcx))
	var gz := int(floor(wcz))
	for dx in range(-1, 2):
		_voxel_tool.set_voxel(Vector3i(gx + dx, FLOOR_Y + 1, gz - 1), PLANKS)

	# Merchant interaction area
	var area := Area3D.new()
	area.name = "MerchantArea"
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 3, 4)
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "merchant")
	_scene_root.add_child(area)
	area.global_position = Vector3(wcx, 2.0, wcz)

	room["state"] = "cleared"  # Safe room


## Fountain room: heal point.
func _build_fountain_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	if not _scene_root:
		return

	# Blue healing light
	_add_light(Vector3(wcx, 2.0, wcz), "FountainLight", Color(0.3, 0.6, 1.0), 2.0, 8.0)

	# Glass block "fountain"
	var gx := int(floor(wcx))
	var gz := int(floor(wcz))
	_voxel_tool.set_voxel(Vector3i(gx, FLOOR_Y + 1, gz), GLASS)

	# Fountain interaction area
	var area := Area3D.new()
	area.name = "FountainArea"
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 3)
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "fountain")
	_scene_root.add_child(area)
	area.global_position = Vector3(wcx, 2.0, wcz)

	room["state"] = "cleared"


## Trap room: hazard tiles.
func _build_trap_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	# Spooky greenish light
	if _scene_root:
		_add_light(Vector3(wcx, 2.0, wcz), "TrapLight", Color(0.3, 1.0, 0.3), 1.5, 6.0)


## Alchemy room: crafting station.
func _build_alchemy_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	if not _scene_root:
		return

	_add_light(Vector3(wcx, 2.0, wcz), "AlchemyLight", Color(0.8, 0.4, 1.0), 2.0, 8.0)

	# Alchemy table
	var gx := int(floor(wcx))
	var gz := int(floor(wcz))
	_voxel_tool.set_voxel(Vector3i(gx, FLOOR_Y + 1, gz), PLANKS)

	var area := Area3D.new()
	area.name = "AlchemyArea"
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 3)
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "alchemy")
	_scene_root.add_child(area)
	area.global_position = Vector3(wcx, 2.0, wcz)

	room["state"] = "cleared"


## Vault room: decoy elevated room that looks valuable but isn't the boss.
## Gives players a chest and gold ore decorations to reward exploration.
func _build_vault_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	if not _scene_root:
		return

	var elev: int = room.get("floor_height", 0)
	var floor_y := FLOOR_Y + elev

	# Warm golden light
	_add_light(Vector3(wcx, float(floor_y) + 2.5, wcz), "VaultLight", Color(1.0, 0.85, 0.1), 2.5, 10.0)

	# Chest at centre
	var gx := int(floor(wcx))
	var gz := int(floor(wcz))
	_voxel_tool.set_voxel(Vector3i(gx, floor_y + 1, gz), CHEST)

	# Gold ore decorations flanking the chest
	for dx in [-1, 1]:
		_voxel_tool.set_voxel(Vector3i(gx + dx, floor_y + 1, gz), GOLD_ORE)
	for dz in [-1, 1]:
		_voxel_tool.set_voxel(Vector3i(gx, floor_y + 1, gz + dz), GOLD_ORE)

	# Vault interaction trigger
	var area := Area3D.new()
	area.name = "VaultArea"
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 3, 4)
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "vault")
	_scene_root.add_child(area)
	area.global_position = Vector3(wcx, float(floor_y) + 2.0, wcz)

	room["state"] = "cleared"


## ── Puzzle room: Sokoban push-block puzzle ──────────────────────────────────
## Places push blocks and target plates from a hand-designed template.
## The room dict gets a "puzzle" key with block/target data used by dungeon.gd.

# Templates: each is { "blocks": [Vector2i, ...], "targets": [Vector2i, ...] }
# Coordinates are *relative to room top-left corner* (rx, ry), 1-tile inset.
# Templates are designed for rooms at least 6×6 inner area.
const _PUZZLE_TEMPLATES := [
	# Template 0 — "Straight Shot" (easy, 2 blocks)
	{
		"blocks":  [Vector2i(2, 3), Vector2i(4, 3)],
		"targets": [Vector2i(2, 5), Vector2i(4, 5)],
	},
	# Template 1 — "L-Push" (easy-medium, 2 blocks)
	{
		"blocks":  [Vector2i(2, 2), Vector2i(4, 4)],
		"targets": [Vector2i(2, 5), Vector2i(4, 2)],
	},
	# Template 2 — "Trio" (medium, 3 blocks)
	{
		"blocks":  [Vector2i(2, 2), Vector2i(4, 2), Vector2i(3, 4)],
		"targets": [Vector2i(5, 5), Vector2i(3, 5), Vector2i(1, 5)],
	},
	# Template 3 — "Diamond" (medium, 3 blocks)
	{
		"blocks":  [Vector2i(3, 1), Vector2i(1, 3), Vector2i(5, 3)],
		"targets": [Vector2i(3, 5), Vector2i(1, 5), Vector2i(5, 5)],
	},
	# Template 4 — "Corner Trap" (medium-hard, 3 blocks)
	{
		"blocks":  [Vector2i(2, 2), Vector2i(4, 2), Vector2i(3, 3)],
		"targets": [Vector2i(1, 5), Vector2i(5, 5), Vector2i(3, 5)],
	},
	# Template 5 — "Cross" (hard, 4 blocks)
	{
		"blocks":  [Vector2i(3, 1), Vector2i(1, 3), Vector2i(5, 3), Vector2i(3, 5)],
		"targets": [Vector2i(3, 6), Vector2i(1, 6), Vector2i(5, 6), Vector2i(3, 1)],
	},
]

## Pressure plate block — using RUNE_CORE gives a glowing look.
const PRESSURE_PLATE_BLOCK := RUNE_CORE

func _build_puzzle_room(wcx: float, wcz: float, room: Dictionary, ox: int, oz: int):
	if not _scene_root:
		return

	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["w"]
	var rh: int = room["h"]
	var elev: int = room.get("floor_height", 0)
	var floor_y := FLOOR_Y + elev

	# Soft blue-purple puzzle light
	_add_light(Vector3(wcx, float(floor_y) + 3.0, wcz), "PuzzleLight", Color(0.4, 0.5, 1.0), 2.5, 12.0)

	# Pick a template that fits this room (need inner area ≥ max coord + 2 for walls)
	var usable: Array = []
	var inner_w: int = rw - 2  # 1-tile inset from each wall
	var inner_h: int = rh - 2
	for i in _PUZZLE_TEMPLATES.size():
		var tmpl: Dictionary = _PUZZLE_TEMPLATES[i]
		var fits := true
		for pos: Vector2i in tmpl["blocks"] + tmpl["targets"]:
			if pos.x >= inner_w or pos.y >= inner_h:
				fits = false
				break
		if fits:
			usable.append(i)

	if usable.is_empty():
		# Room too small — fall back to simplest 2-block template at (1,1) and (1,2)
		usable.append(0)

	var tmpl_idx: int = usable[randi() % usable.size()]
	var tmpl: Dictionary = _PUZZLE_TEMPLATES[tmpl_idx]

	# Possibly mirror the template (flip X) for variety
	var mirror: bool = randf() < 0.5
	var blocks_rel: Array = []
	var targets_rel: Array = []
	for pos: Vector2i in tmpl["blocks"]:
		blocks_rel.append(Vector2i(inner_w - 1 - pos.x, pos.y) if mirror else pos)
	for pos: Vector2i in tmpl["targets"]:
		targets_rel.append(Vector2i(inner_w - 1 - pos.x, pos.y) if mirror else pos)

	# Convert relative positions to world grid coordinates
	# Inset by 1 from room edge so blocks don't sit against walls
	var base_x: int = rx + 1 + ox
	var base_z: int = ry + 1 + oz

	var block_positions: Array = []  # Array[Vector2i] in world grid coords
	var target_positions: Array = []

	for pos: Vector2i in blocks_rel:
		block_positions.append(Vector2i(base_x + pos.x, base_z + pos.y))
	for pos: Vector2i in targets_rel:
		var wp := Vector2i(base_x + pos.x, base_z + pos.y)
		target_positions.append(wp)
		# Stamp pressure plate voxel on the floor
		_voxel_tool.set_voxel(Vector3i(wp.x, floor_y, wp.y), PRESSURE_PLATE_BLOCK)

	# Puzzle reset sign (interaction area at room centre)
	var area := Area3D.new()
	area.name = "PuzzleResetArea_%d" % room["id"]
	var coll := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(rw), 4.0, float(rh))
	coll.shape = shape
	area.add_child(coll)
	area.set_meta("interaction", "puzzle_reset")
	area.set_meta("room_id", room["id"])
	_scene_root.add_child(area)
	area.global_position = Vector3(wcx, float(floor_y) + 2.0, wcz)

	# Store puzzle data in the room dict for dungeon.gd to use
	room["puzzle"] = {
		"blocks": block_positions,
		"targets": target_positions,
		"template": tmpl_idx,
		"floor_y": floor_y,
	}
	# Puzzle rooms start uncleared — cleared when solved
	room["state"] = "uncleared"

	print("DungeonStamper: puzzle room %d — template %d, %d blocks, %d targets" % [
		room["id"], tmpl_idx, block_positions.size(), target_positions.size()])


## Add sconces (lights) in room corners.
func _add_room_sconces(room: Dictionary, ox: int, oz: int, floor_num: int = 1):
	if not _scene_root:
		return

	var rx: int = room["x"] + ox
	var ry: int = room["y"] + oz
	var rw: int = room["w"]
	var rh: int = room["h"]
	var elev: float = float(room.get("floor_height", 0))

	# Place sconces at the 4 corners (1 block in from walls), above the actual floor
	var corners := [
		Vector3(rx + 1.5, FLOOR_Y + elev + 2.5, ry + 1.5),
		Vector3(rx + rw - 0.5, FLOOR_Y + elev + 2.5, ry + 1.5),
		Vector3(rx + 1.5, FLOOR_Y + elev + 2.5, ry + rh - 0.5),
		Vector3(rx + rw - 0.5, FLOOR_Y + elev + 2.5, ry + rh - 0.5),
	]
	
	# Light color based on biome
	var light_col := Color(1.0, 0.7, 0.3)
	if floor_num >= 5:
		light_col = Color(0.6, 0.0, 0.8) # Void purple
	elif floor_num >= 3:
		light_col = Color(0.4, 0.6, 0.7) # Ruin cyan

	var idx := 0
	for corner_pos in corners:
		# Only 15% of potential sconces are placed (performance)
		if randf() < 0.40:
			_add_light(corner_pos, "Sconce_%d_%d" % [room["id"], idx],
				light_col, 0.8, 5.0)
		idx += 1


## Scatter sconce lights along corridors.
func _decorate_corridors(grid: Array, cols: int, rows: int, ox: int, oz: int, floor_num: int = 1):
	if not _scene_root:
		return

	var sconce_count := 0
	var spacing := 8  # one light every ~8 tiles
	
	# Light color based on biome
	var light_col := Color(1.0, 0.5, 0.2)
	if floor_num >= 5:
		light_col = Color(0.6, 0.0, 0.8) # Void purple
	elif floor_num >= 3:
		light_col = Color(0.4, 0.6, 0.7) # Ruin cyan

	for row in range(0, rows, spacing):
		for col in range(0, cols, spacing):
			if row < grid.size() and col < grid[0].size():
				if grid[row][col] == BspDungeon.CORRIDOR:
					var wx: float = col + ox + 0.5
					var wz: float = row + oz + 0.5
					_add_light(
						Vector3(wx, FLOOR_Y + 2.5, wz),
						"CorridorSconce_%d" % sconce_count,
						light_col, 0.6, 4.0)
					sconce_count += 1


## Add an OmniLight3D to the scene.
## If _current_room_id >= 0 the light is hidden by default and added to
## "room_lights_N" so dungeon.gd can reveal it when the player enters.
## Corridor lights (_current_room_id == -1) are always visible.
func _add_light(pos: Vector3, node_name: String, color: Color, energy: float, range_val: float) -> void:
	var light := OmniLight3D.new()
	light.name = node_name
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_val
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	if _current_room_id >= 0:
		light.add_to_group("room_lights_%d" % _current_room_id)
		light.visible = false
	_scene_root.add_child(light)
	light.global_position = pos


## Get the world position of the start room (for player spawn).
func get_start_position() -> Vector3:
	if dungeon_data.is_empty():
		return Vector3.ZERO

	var rooms: Array = dungeon_data["rooms"]
	for room in rooms:
		if room["room_type"] == "start":
			var ox: int = dungeon_data["offset_x"]
			var oz: int = dungeon_data["offset_z"]
			return Vector3(room["cx"] + ox + 0.5, FLOOR_Y + 1.5, room["cy"] + oz + 0.5)

	return Vector3.ZERO


## Get the world position of the boss room.
func get_boss_position() -> Vector3:
	if dungeon_data.is_empty():
		return Vector3.ZERO

	var rooms: Array = dungeon_data["rooms"]
	for room in rooms:
		if room["room_type"] == "boss":
			var ox: int = dungeon_data["offset_x"]
			var oz: int = dungeon_data["offset_z"]
			var elev: int = room.get("floor_height", 0)
			return Vector3(room["cx"] + ox + 0.5, FLOOR_Y + elev + 1.5, room["cy"] + oz + 0.5)

	return Vector3.ZERO


## Convert world position to room dict (or null if not in a room).
func get_room_at_world(world_pos: Vector3) -> Dictionary:
	if dungeon_data.is_empty():
		return {}

	var ox: int = dungeon_data["offset_x"]
	var oz: int = dungeon_data["offset_z"]
	var col: int = int(floor(world_pos.x)) - ox
	var row: int = int(floor(world_pos.z)) - oz

	for room in dungeon_data["rooms"]:
		if col >= room["x"] and col < room["x"] + room["w"]:
			if row >= room["y"] and row < room["y"] + room["h"]:
				return room

	return {}
