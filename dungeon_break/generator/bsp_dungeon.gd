extends RefCounted
## BSP Dungeon Generator — procedural dungeon floors for Dungeon Break.
##
## Ported from JS bsp-dungeon.js. Builds a BSP tree, places rooms in leaves,
## connects them with L-shaped corridors, assigns room types, returns a
## dict with grid data + room list that can be stamped into VoxelTerrain.
##
## Usage:
##   var gen = BspDungeon.new()
##   var result = gen.generate(floor_num)
##   # result.grid: 2D array [row][col] of tile IDs
##   # result.rooms: Array of room dicts
##   # result.corridors: Array of corridor segment dicts
##   # result.cols, result.rows: grid dimensions

# ── Tile IDs ─────────────────────────────────────────────────────────────────
const EMPTY    = 0
const ROOM     = 1
const CORRIDOR = 2
const WALL     = 3

# ── BSP parameters per floor range ──────────────────────────────────────────
const MIN_CHUNK := 10

# ── Room assignment helpers ──────────────────────────────────────────────────
const WALL_HEIGHT := 3          # voxel blocks high
const CORRIDOR_W  := 1          # corridor width in tiles


## Generate a full dungeon floor. Returns a Dictionary:
##   grid, rooms, corridors, cols, rows, floor_num
func generate(floor_num: int) -> Dictionary:
	var cols: int
	var rows: int
	var iterations: int

	if floor_num <= 3:
		cols = 64; rows = 64; iterations = 6
	elif floor_num <= 6:
		cols = 80; rows = 80; iterations = 7
	else:
		cols = 96; rows = 96; iterations = 8

	# Create empty grid
	var grid: Array = []
	for r in rows:
		var row: Array = []
		row.resize(cols)
		row.fill(EMPTY)
		grid.append(row)

	# Build BSP tree
	var root := {
		"x": 1, "y": 1,
		"w": cols - 2, "h": rows - 2,
		"left": null, "right": null, "room": null,
	}
	_split(root, iterations)

	# Place rooms in leaf nodes
	var rooms: Array = []
	_place_rooms(root, rooms, floor_num)

	# Carve rooms into grid
	for room in rooms:
		_carve_room(grid, room)

	# Connect sibling rooms with corridors
	var corridors: Array = []
	_connect(root, grid, corridors)

	# Build walls around rooms and corridors
	_build_walls(grid, cols, rows)

	# Select rooms near outer edges as elevated upper rooms (boss + vault decoys)
	_select_upper_rooms(rooms, cols, rows)

	# Assign room types (start, boss, bonfire, trap, etc.)
	_assign_room_types(rooms, floor_num)

	# Build connection graph
	_build_connections(rooms, corridors)

	return {
		"grid": grid,
		"rooms": rooms,
		"corridors": corridors,
		"cols": cols,
		"rows": rows,
		"floor_num": floor_num,
	}


# ══════════════════════════════════════════════════════════════════════════════
# BSP TREE
# ══════════════════════════════════════════════════════════════════════════════

func _split(node: Dictionary, depth: int):
	if depth <= 0:
		return

	var w: int = node["w"]
	var h: int = node["h"]

	# Choose split direction — forced by aspect ratio
	var split_vertical: bool
	var ratio := float(w) / float(h)
	if ratio <= 0.5:
		split_vertical = false  # too tall → split horizontal
	elif ratio >= 2.0:
		split_vertical = true   # too wide → split vertical
	else:
		split_vertical = randf() > 0.5

	if split_vertical:
		var mid := w / 2 + randi_range(-w / 4, w / 4)
		mid = clampi(mid, MIN_CHUNK, w - MIN_CHUNK)
		if mid < MIN_CHUNK or (w - mid) < MIN_CHUNK:
			return  # can't split further

		node["left"] = {
			"x": node["x"], "y": node["y"],
			"w": mid, "h": h,
			"left": null, "right": null, "room": null,
		}
		node["right"] = {
			"x": node["x"] + mid, "y": node["y"],
			"w": w - mid, "h": h,
			"left": null, "right": null, "room": null,
		}
	else:
		var mid := h / 2 + randi_range(-h / 4, h / 4)
		mid = clampi(mid, MIN_CHUNK, h - MIN_CHUNK)
		if mid < MIN_CHUNK or (h - mid) < MIN_CHUNK:
			return

		node["left"] = {
			"x": node["x"], "y": node["y"],
			"w": w, "h": mid,
			"left": null, "right": null, "room": null,
		}
		node["right"] = {
			"x": node["x"], "y": node["y"] + mid,
			"w": w, "h": h - mid,
			"left": null, "right": null, "room": null,
		}

	_split(node["left"], depth - 1)
	_split(node["right"], depth - 1)


# ══════════════════════════════════════════════════════════════════════════════
# ROOM PLACEMENT
# ══════════════════════════════════════════════════════════════════════════════

func _place_rooms(node: Dictionary, rooms: Array, floor_num: int):
	if node["left"] == null and node["right"] == null:
		# Leaf node — place a room inside
		var nx: int = node["x"]
		var ny: int = node["y"]
		var nw: int = node["w"]
		var nh: int = node["h"]

		# Inset: 10–15% from edges, size: 72–82%
		var ox := randi_range(nw / 10, nw / 7)
		var oy := randi_range(nh / 10, nh / 7)
		var rw := maxi(4, randi_range(int(nw * 0.72), int(nw * 0.82)))
		var rh := maxi(4, randi_range(int(nh * 0.72), int(nh * 0.82)))

		# Clamp to chunk
		rw = mini(rw, nw - ox - 1)
		rh = mini(rh, nh - oy - 1)

		# Floor height variation: 30% chance of a raised platform
		var floor_height := 0
		if randf() < 0.30:
			floor_height = randi_range(1, 2)

		var room := {
			"id": rooms.size(),
			"x": nx + ox, "y": ny + oy,
			"w": rw, "h": rh,
			"cx": nx + ox + rw / 2,  # centre
			"cy": ny + oy + rh / 2,
			"floor_height": floor_height,
			"state": "uncleared",
			"room_type": "normal",  # assigned later
			"connections": [],
			"enemies": [],
		}
		rooms.append(room)
		node["room"] = room
		return

	if node["left"] != null:
		_place_rooms(node["left"], rooms, floor_num)
	if node["right"] != null:
		_place_rooms(node["right"], rooms, floor_num)


func _carve_room(grid: Array, room: Dictionary):
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["w"]
	var rh: int = room["h"]

	for row in range(ry, ry + rh):
		for col in range(rx, rx + rw):
			if row >= 0 and row < grid.size() and col >= 0 and col < grid[0].size():
				grid[row][col] = ROOM


# ══════════════════════════════════════════════════════════════════════════════
# CORRIDOR CONNECTION
# ══════════════════════════════════════════════════════════════════════════════

func _get_leaf_room(node: Dictionary) -> Dictionary:
	## Get any leaf room from a subtree (picks leftmost).
	if node["room"] != null:
		return node["room"]
	if node["left"] != null:
		var r := _get_leaf_room(node["left"])
		if not r.is_empty():
			return r
	if node["right"] != null:
		return _get_leaf_room(node["right"])
	return {}


func _connect(node: Dictionary, grid: Array, corridors: Array):
	if node["left"] == null or node["right"] == null:
		return

	# Recurse
	_connect(node["left"], grid, corridors)
	_connect(node["right"], grid, corridors)

	# Get one room from each subtree
	var room_a := _get_leaf_room(node["left"])
	var room_b := _get_leaf_room(node["right"])
	if room_a.is_empty() or room_b.is_empty():
		return

	# L-shaped corridor between centres
	var ax: int = room_a["cx"]
	var ay: int = room_a["cy"]
	var bx: int = room_b["cx"]
	var by: int = room_b["cy"]

	# Carve horizontal arm: ax→bx at row ay
	_carve_corridor_h(grid, ay, mini(ax, bx), maxi(ax, bx), corridors)
	# Carve vertical arm: ay→by at col bx
	_carve_corridor_v(grid, bx, mini(ay, by), maxi(ay, by), corridors)


func _carve_corridor_h(grid: Array, row: int, col_start: int, col_end: int, corridors: Array):
	var max_row: int = grid.size() - 1
	var max_col: int = grid[0].size() - 1

	for col in range(col_start, col_end + 1):
		for w in CORRIDOR_W:
			var r := clampi(row + w, 0, max_row)
			var c := clampi(col, 0, max_col)
			if grid[r][c] == EMPTY:
				grid[r][c] = CORRIDOR

	corridors.append({
		"type": "h",
		"row": row, "col_start": col_start, "col_end": col_end,
	})


func _carve_corridor_v(grid: Array, col: int, row_start: int, row_end: int, corridors: Array):
	var max_row: int = grid.size() - 1
	var max_col: int = grid[0].size() - 1

	for row in range(row_start, row_end + 1):
		for w in CORRIDOR_W:
			var c := clampi(col + w, 0, max_col)
			var r := clampi(row, 0, max_row)
			if grid[r][c] == EMPTY:
				grid[r][c] = CORRIDOR

	corridors.append({
		"type": "v",
		"col": col, "row_start": row_start, "row_end": row_end,
	})


# ══════════════════════════════════════════════════════════════════════════════
# WALLS
# ══════════════════════════════════════════════════════════════════════════════

func _build_walls(grid: Array, cols: int, rows: int):
	# Two passes: first mark adjacent-to-floor cells, then mark cells adjacent
	# to those walls too (creates 2-tile-thick walls for better visibility).
	for _pass in 2:
		var new_walls: Array = []
		for row in rows:
			for col in cols:
				if grid[row][col] != EMPTY:
					continue
				# Check 8 neighbours for floor OR existing wall (2nd pass)
				var adjacent := false
				for dr in range(-1, 2):
					for dc in range(-1, 2):
						if dr == 0 and dc == 0:
							continue
						var nr := row + dr
						var nc := col + dc
						if nr >= 0 and nr < rows and nc >= 0 and nc < cols:
							var t: int = grid[nr][nc]
							if t == ROOM or t == CORRIDOR or (_pass == 1 and t == WALL):
								adjacent = true
								break
					if adjacent:
						break
				if adjacent:
					new_walls.append(Vector2i(col, row))
		for pos in new_walls:
			grid[pos.y][pos.x] = WALL


# ══════════════════════════════════════════════════════════════════════════════
# ROOM TYPE ASSIGNMENT
# ══════════════════════════════════════════════════════════════════════════════

func _assign_room_types(rooms: Array, _floor_num: int):
	if rooms.size() < 2:
		return

	# Room 0 = start (shrine), always cleared, flat floor
	rooms[0]["room_type"] = "start"
	rooms[0]["state"] = "cleared"
	rooms[0]["floor_height"] = 0

	var start_cx: int = rooms[0]["cx"]
	var start_cy: int = rooms[0]["cy"]

	# Boss room: prefer upper rooms (far-edge elevated rooms); fall back to furthest from start
	var best_dist := 0.0
	var boss_idx := 1

	var upper_indices: Array = []
	for i in range(1, rooms.size()):
		if rooms[i].get("is_upper", false):
			upper_indices.append(i)

	if not upper_indices.is_empty():
		# Pick the upper room furthest from start
		for i in upper_indices:
			var dx: float = float(rooms[i]["cx"] - start_cx)
			var dy: float = float(rooms[i]["cy"] - start_cy)
			var dist := sqrt(dx * dx + dy * dy)
			if dist > best_dist:
				best_dist = dist
				boss_idx = i
	else:
		# Fallback: any room furthest from start
		for i in range(1, rooms.size()):
			var dx: float = float(rooms[i]["cx"] - start_cx)
			var dy: float = float(rooms[i]["cy"] - start_cy)
			var dist := sqrt(dx * dx + dy * dy)
			if dist > best_dist:
				best_dist = dist
				boss_idx = i

	rooms[boss_idx]["room_type"] = "boss"
	rooms[boss_idx]["state"] = "uncleared"

	# Available indices for special rooms (not start or boss)
	var available: Array[int] = []
	for i in range(1, rooms.size()):
		if i != boss_idx:
			available.append(i)

	available.shuffle()

	# Assign special rooms from the shuffled pool
	var assign_idx := 0

	# Puzzle (1) — sokoban push-block room, floors 3+  (assigned early to guarantee a slot)
	# Prefer a room large enough for the smallest template (inner 5×6 → room 7×8).
	if _floor_num >= 3 and assign_idx < available.size():
		var puzzle_idx := -1
		# First pass: find a room ≥ 7×8 from the unassigned pool
		for j in range(assign_idx, available.size()):
			var rm: Dictionary = rooms[available[j]]
			if rm["w"] >= 7 and rm["h"] >= 7:
				puzzle_idx = j
				break
		if puzzle_idx == -1:
			puzzle_idx = assign_idx  # fallback — stamper will generate a tiny template
		# Swap chosen room to the front of the available list
		if puzzle_idx != assign_idx:
			var tmp: int = available[assign_idx]
			available[assign_idx] = available[puzzle_idx]
			available[puzzle_idx] = tmp
		rooms[available[assign_idx]]["room_type"] = "puzzle"
		rooms[available[assign_idx]]["floor_height"] = 0  # must be flat
		assign_idx += 1

	# Bonfire (1)
	if assign_idx < available.size():
		rooms[available[assign_idx]]["room_type"] = "bonfire"
		assign_idx += 1

	# Trap (1–2)
	if assign_idx < available.size():
		rooms[available[assign_idx]]["room_type"] = "trap"
		assign_idx += 1
	if assign_idx < available.size() and randf() < 0.5:
		rooms[available[assign_idx]]["room_type"] = "trap"
		assign_idx += 1

	# Alchemy (1)
	if assign_idx < available.size():
		rooms[available[assign_idx]]["room_type"] = "alchemy"
		assign_idx += 1

	# Fountain (1–2)
	if assign_idx < available.size():
		rooms[available[assign_idx]]["room_type"] = "fountain"
		assign_idx += 1
	if assign_idx < available.size() and randf() < 0.4:
		rooms[available[assign_idx]]["room_type"] = "fountain"
		assign_idx += 1

	# Locked (1–2)
	if assign_idx < available.size():
		rooms[available[assign_idx]]["room_type"] = "locked"
		assign_idx += 1
	if assign_idx < available.size() and randf() < 0.5:
		rooms[available[assign_idx]]["room_type"] = "locked"
		assign_idx += 1

	# Rest stay "normal" — these get enemies

	# Upper rooms not assigned boss become vault (decoy elevated rooms)
	for room in rooms:
		if room.get("is_upper", false) and room["room_type"] == "normal":
			room["room_type"] = "vault"

	# Ensure interactive/safe rooms are always flat (elevation breaks their interactions)
	# Boss rooms keep their elevation if they're upper rooms
	const FLAT_TYPES := ["start", "bonfire", "fountain", "puzzle"]
	for room in rooms:
		if room["room_type"] in FLAT_TYPES:
			room["floor_height"] = 0
		elif room["room_type"] == "boss" and not room.get("is_upper", false):
			room["floor_height"] = 0


func _select_upper_rooms(rooms: Array, cols: int, rows: int) -> void:
	## Post-placement pass: mark 2–3 far-edge rooms as upper rooms (floor_height = WALL_HEIGHT = 3).
	## _assign_room_types uses them for boss and vault decoy assignment.
	if rooms.size() < 4:
		return

	# "Edge zone" = outer 25% of the smaller dimension
	var edge_margin := mini(cols, rows) / 4

	# Score each non-start room: higher = closer to any grid edge
	var candidates: Array = []
	for i in range(1, rooms.size()):
		var room: Dictionary = rooms[i]
		var near_edge: bool = (
			room["cx"] < edge_margin or room["cx"] > cols - edge_margin
			or room["cy"] < edge_margin or room["cy"] > rows - edge_margin
		)
		# Normalised distance to closest edge (0 = on edge, 0.5 = centre)
		var ex: float = float(mini(room["cx"], cols - room["cx"])) / float(cols)
		var ey: float = float(mini(room["cy"], rows - room["cy"])) / float(rows)
		var edge_score: float = 1.0 - (ex + ey) * 0.5
		candidates.append({"idx": i, "near_edge": near_edge, "edge_score": edge_score})

	# Sort: near-edge rooms first, then by edge_score descending
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["near_edge"]) != bool(b["near_edge"]):
			return bool(a["near_edge"])
		return float(a["edge_score"]) > float(b["edge_score"])
	)

	# Pick 2 upper rooms on smaller floors, 3 on larger
	var upper_count := 2 if rooms.size() < 12 else 3
	upper_count = mini(upper_count, candidates.size())

	for i in range(upper_count):
		var idx: int = int(candidates[i]["idx"])
		rooms[idx]["floor_height"] = WALL_HEIGHT  # = 3
		rooms[idx]["is_upper"] = true


func _build_connections(rooms: Array, corridors: Array):
	## For each corridor, figure out which two rooms it connects.
	## Simple heuristic: the corridor endpoints are closest to room centres.
	for corr in corridors:
		var best_a := -1
		var best_b := -1
		var best_dist_a := 99999.0
		var best_dist_b := 99999.0

		var cx: float
		var cy: float
		var ex: float
		var ey: float

		if corr["type"] == "h":
			cx = float(corr["col_start"])
			cy = float(corr["row"])
			ex = float(corr["col_end"])
			ey = float(corr["row"])
		else:
			cx = float(corr["col"])
			cy = float(corr["row_start"])
			ex = float(corr["col"])
			ey = float(corr["row_end"])

		for i in rooms.size():
			var rcx := float(rooms[i]["cx"])
			var rcy := float(rooms[i]["cy"])
			# Distance to start of corridor
			var da := sqrt((rcx - cx) ** 2 + (rcy - cy) ** 2)
			# Distance to end of corridor
			var db := sqrt((rcx - ex) ** 2 + (rcy - ey) ** 2)

			var d := minf(da, db)
			if d < best_dist_a:
				best_dist_b = best_dist_a
				best_b = best_a
				best_dist_a = d
				best_a = i
			elif d < best_dist_b:
				best_dist_b = d
				best_b = i

		if best_a >= 0 and best_b >= 0 and best_a != best_b:
			if best_b not in rooms[best_a]["connections"]:
				rooms[best_a]["connections"].append(best_b)
			if best_a not in rooms[best_b]["connections"]:
				rooms[best_b]["connections"].append(best_a)
