extends Node3D
## Tactical Grid — visual tile overlay for FFT-style combat.
##
## Creates coloured flat markers on the room floor to show:
##   - Blue:   movement range
##   - Red:    attack range (beyond move range)
##   - Green:  selected tile / player position
##   - Orange: enemy positions
##   - White:  cursor / hovered tile
##
## Uses a pool of MeshInstance3D thin boxes placed at floor level.

const TILE_SIZE := 1.0
const TILE_Y    := 0.12   # just above floor surface
const TILE_THICK := 0.06  # thin slab

const COLOR_MOVE         := Color(0.2, 0.4, 1.0, 0.45)
const COLOR_ATTACK       := Color(1.0, 0.2, 0.2, 0.35)
const COLOR_PLAYER       := Color(0.2, 1.0, 0.3, 0.55)
const COLOR_ENEMY        := Color(1.0, 0.5, 0.1, 0.45)
const COLOR_CURSOR       := Color(1.0, 1.0, 1.0, 0.50)
const COLOR_PATH         := Color(0.5, 0.8, 1.0, 0.50)
const COLOR_ALLY         := Color(0.3, 0.9, 0.5, 0.40)
## Ranged attack zone (replaces red for ranged weapons — teal diamond)
const COLOR_RANGED_ZONE  := Color(0.0, 0.85, 0.85, 0.35)
## Active flight path tiles (bright cyan, shown while projectile is in flight)
const COLOR_RANGED_PATH  := Color(0.1, 1.0, 0.85, 0.70)

# ── Grid state ───────────────────────────────────────────────────────────────
var grid_origin := Vector2i.ZERO   # world offset (room top-left corner)
var grid_w := 0
var grid_h := 0
var floor_y := 0                   # Y level of the floor tiles

# Which tiles are walkable (true = walkable floor)
var _walkable: Array = []          # [row][col] bool

# Active highlight markers {Vector2i → MeshInstance3D}
var _markers: Dictionary = {}

# Shared material for markers (one per colour)
var _materials: Dictionary = {}    # Color → StandardMaterial3D

# Pool of mesh instances
var _pool: Array[MeshInstance3D] = []
var _pool_cursor := 0

# Dedicated cursor overlay — never touches _markers so blue tiles are preserved
var _cursor_mesh: MeshInstance3D = null

# ── Mesh template ────────────────────────────────────────────────────────────
var _tile_mesh: BoxMesh = null


func _ready():
	_tile_mesh = BoxMesh.new()
	_tile_mesh.size = Vector3(TILE_SIZE * 0.92, TILE_THICK, TILE_SIZE * 0.92)

	# Pre-create materials
	for col in [COLOR_MOVE, COLOR_ATTACK, COLOR_PLAYER, COLOR_ENEMY, COLOR_CURSOR,
			COLOR_PATH, COLOR_ALLY, COLOR_RANGED_ZONE, COLOR_RANGED_PATH]:
		_get_material(col)

	# Cursor mesh sits slightly above normal tiles (TILE_Y + 0.01) so it renders on top
	_cursor_mesh = MeshInstance3D.new()
	_cursor_mesh.mesh = _tile_mesh
	_cursor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor_mesh.visible = false
	var cursor_mat := StandardMaterial3D.new()
	cursor_mat.albedo_color = COLOR_CURSOR
	cursor_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cursor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cursor_mat.render_priority = 2
	_cursor_mesh.set_surface_override_material(0, cursor_mat)
	add_child(_cursor_mesh)

	# Pre-populate pool
	_grow_pool(64)


## Initialise grid from a BSP room dict + dungeon offset.
func setup_room(room: Dictionary, offset_x: int, offset_z: int, room_floor_y: int = 0):
	grid_w = room["w"]
	grid_h = room["h"]
	grid_origin = Vector2i(room["x"] + offset_x, room["y"] + offset_z)
	floor_y = room_floor_y

	# All room tiles are walkable
	_walkable.clear()
	for row in grid_h:
		var r: Array = []
		r.resize(grid_w)
		r.fill(true)
		_walkable.append(r)


## Mark a tile as blocked (e.g. occupied by an obstacle or unit).
func set_blocked(grid_pos: Vector2i, blocked: bool = true):
	var lx: int = grid_pos.x - grid_origin.x
	var lz: int = grid_pos.y - grid_origin.y
	if lx >= 0 and lx < grid_w and lz >= 0 and lz < grid_h:
		_walkable[lz][lx] = not blocked


## Check if a grid position is walkable.
func is_walkable(grid_pos: Vector2i) -> bool:
	var lx: int = grid_pos.x - grid_origin.x
	var lz: int = grid_pos.y - grid_origin.y
	if lx < 0 or lx >= grid_w or lz < 0 or lz >= grid_h:
		return false
	return _walkable[lz][lx]


## Convert a world position to a grid Vector2i (tile coordinates).
func world_to_grid(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(world_pos.x)), int(floor(world_pos.z)))


## Convert a grid position to world centre position.
func grid_to_world(grid_pos: Vector2i, y_offset: float = 0.0) -> Vector3:
	return Vector3(grid_pos.x + 0.5, floor_y + 1.0 + y_offset, grid_pos.y + 0.5)


## BFS: compute all tiles reachable within `max_steps` moves from `origin`.
## Returns Array[Vector2i] of reachable tiles (excludes origin if desired).
func get_movement_range(origin: Vector2i, max_steps: int, exclude_occupied: Array[Vector2i] = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited: Dictionary = {}  # Vector2i → int (steps)
	var queue: Array = [[origin, 0]]
	visited[origin] = 0

	while not queue.is_empty():
		var item: Array = queue.pop_front()
		var pos: Vector2i = item[0]
		var steps: int = item[1]

		if steps > 0 and pos not in exclude_occupied:
			result.append(pos)

		if steps >= max_steps:
			continue

		# 4 cardinal directions
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = pos + dir
			if next in visited:
				continue
			if not is_walkable(next):
				continue
			if next in exclude_occupied:
				visited[next] = steps + 1
				continue
			visited[next] = steps + 1
			queue.append([next, steps + 1])

	return result


## Get attack range tiles from `origin` with `attack_range` (Chebyshev distance).
## Returns tiles that are within range but NOT in the movement set.
func get_attack_range(origin: Vector2i, attack_range: int, move_tiles: Array[Vector2i] = []) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var move_set: Dictionary = {}
	for t in move_tiles:
		move_set[t] = true
	move_set[origin] = true

	for dx in range(-attack_range, attack_range + 1):
		for dz in range(-attack_range, attack_range + 1):
			if absi(dx) + absi(dz) > attack_range:
				continue  # diamond shape (Manhattan)
			var pos := origin + Vector2i(dx, dz)
			if pos in move_set:
				continue
			if _is_in_room(pos):
				result.append(pos)

	return result


## Find shortest path between two grid positions (BFS). Returns Array[Vector2i].
func find_path(from: Vector2i, to: Vector2i, max_steps: int = 100) -> Array[Vector2i]:
	if from == to:
		return []

	var visited: Dictionary = {}
	var parents: Dictionary = {}
	var queue: Array = [from]
	visited[from] = true

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to:
			# Reconstruct path
			var path: Array[Vector2i] = []
			var p := current
			while p != from:
				path.push_front(p)
				p = parents[p]
			return path

		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + dir
			if next in visited:
				continue
			if not is_walkable(next):
				continue
			visited[next] = true
			parents[next] = current
			queue.append(next)

	return []  # no path


# ══════════════════════════════════════════════════════════════════════════════
# VISUAL HIGHLIGHTS
# ══════════════════════════════════════════════════════════════════════════════

## Show movement range tiles.
func highlight_move(tiles: Array[Vector2i]):
	for pos in tiles:
		_place_marker(pos, COLOR_MOVE)


## Show attack range tiles.
func highlight_attack(tiles: Array[Vector2i]):
	for pos in tiles:
		_place_marker(pos, COLOR_ATTACK)


## Show unit positions.
func highlight_player(pos: Vector2i):
	_place_marker(pos, COLOR_PLAYER)


func highlight_enemy(pos: Vector2i):
	_place_marker(pos, COLOR_ENEMY)


func highlight_companion(pos: Vector2i):
	_place_marker(pos, COLOR_ALLY)


func highlight_cursor(pos: Vector2i):
	if _cursor_mesh == null:
		return
	_cursor_mesh.position = Vector3(
		pos.x + 0.5,
		floor_y + 1.0 + TILE_Y + 0.01,  # just above regular tiles
		pos.y + 0.5
	)
	_cursor_mesh.visible = true


func highlight_path(tiles: Array[Vector2i]):
	for pos in tiles:
		_place_marker(pos, COLOR_PATH)


## Show ranged weapon attack zone (teal diamond — replaces red for ranged).
func highlight_ranged_zone(tiles: Array[Vector2i]):
	for pos in tiles:
		_place_marker(pos, COLOR_RANGED_ZONE)


## Show projectile flight path tiles (bright cyan, drawn over zone tiles).
func highlight_ranged_path(tiles: Array[Vector2i]):
	for pos in tiles:
		_place_marker(pos, COLOR_RANGED_PATH)


## Clear only the flight path tiles (called when projectile lands).
func clear_ranged_path():
	clear_color(COLOR_RANGED_PATH)


## Clear ALL markers.
func clear_all():
	for marker in _markers.values():
		marker.visible = false
	_markers.clear()
	_pool_cursor = 0
	if _cursor_mesh:
		_cursor_mesh.visible = false


## Clear only markers of a specific colour.
func clear_color(color: Color):
	# Cursor has its own dedicated mesh — just hide it
	if color.is_equal_approx(COLOR_CURSOR):
		if _cursor_mesh:
			_cursor_mesh.visible = false
		return
	var to_remove: Array = []
	for pos in _markers:
		var m: MeshInstance3D = _markers[pos]
		var mat: StandardMaterial3D = m.get_surface_override_material(0)
		if mat and mat.albedo_color.is_equal_approx(color):
			m.visible = false
			to_remove.append(pos)
	for pos in to_remove:
		_markers.erase(pos)


# ══════════════════════════════════════════════════════════════════════════════
# INTERNAL
# ══════════════════════════════════════════════════════════════════════════════

func _is_in_room(pos: Vector2i) -> bool:
	var lx: int = pos.x - grid_origin.x
	var lz: int = pos.y - grid_origin.y
	return lx >= 0 and lx < grid_w and lz >= 0 and lz < grid_h


func _place_marker(grid_pos: Vector2i, color: Color):
	if grid_pos in _markers:
		# Update colour
		var m: MeshInstance3D = _markers[grid_pos]
		m.set_surface_override_material(0, _get_material(color))
		m.visible = true
		return

	var m := _get_from_pool()
	m.set_surface_override_material(0, _get_material(color))
	m.position = Vector3(
		grid_pos.x + 0.5,
		floor_y + 1.0 + TILE_Y,
		grid_pos.y + 0.5
	)
	m.visible = true
	_markers[grid_pos] = m


func _get_material(color: Color) -> StandardMaterial3D:
	if color in _materials:
		return _materials[color]

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.render_priority = 1
	_materials[color] = mat
	return mat


func _get_from_pool() -> MeshInstance3D:
	if _pool_cursor >= _pool.size():
		_grow_pool(16)

	var m := _pool[_pool_cursor]
	_pool_cursor += 1
	return m


func _grow_pool(count: int):
	for _i in count:
		var m := MeshInstance3D.new()
		m.mesh = _tile_mesh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_pool.append(m)
