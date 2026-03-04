extends Control
## Minimap overlay — shows dungeon room layout in the top-left corner.
##
## Rooms are drawn as coloured rectangles. Corridors are thin lines
## connecting adjacent rooms. A pulsing dot tracks the player.
##
## Colour key:
##   Dark gray   — undiscovered
##   Yellow      — visited but not cleared
##   Green       — cleared
##   Cyan border — current room
##   Red tint    — boss room
##   Blue tint   — puzzle room
##   White tint  — start room

const MAP_SIZE := Vector2(200, 200)   # pixel size of the minimap box
const PADDING  := 8.0                 # inner padding in pixels
const ROOM_BORDER := 1.0              # border thickness around each room rect

# Colours
const COL_BG          := Color(0.02, 0.02, 0.06, 0.72)
const COL_BORDER      := Color(0.35, 0.35, 0.5, 0.6)
const COL_UNDISCOVERED := Color(0.18, 0.18, 0.22, 0.55)
const COL_VISITED     := Color(0.75, 0.65, 0.15)
const COL_CLEARED     := Color(0.2, 0.72, 0.35)
const COL_CURRENT     := Color(0.3, 0.9, 1.0)
const COL_BOSS        := Color(0.85, 0.15, 0.15)
const COL_PUZZLE      := Color(0.3, 0.45, 0.95)
const COL_START       := Color(0.9, 0.9, 0.95)
const COL_CORRIDOR    := Color(0.28, 0.28, 0.38, 0.5)
const COL_PLAYER_DOT  := Color(1.0, 1.0, 1.0)

# Data fed from dungeon.gd
var _rooms: Array = []
var _grid: Array = []
var _grid_cols: int = 0
var _grid_rows: int = 0
var _offset_x: int = 0
var _offset_z: int = 0
var _visited: Dictionary = {}       # room_id → true
var _floor_num: int = 1

# Tracking
var _current_room_id: int = -1
var _player_grid_pos: Vector2 = Vector2.ZERO   # col, row in BSP grid space
var _pulse: float = 0.0                         # animation counter

# Toggle
var _map_visible: bool = true

# Pre-computed draw data (rebuilt when dungeon data changes)
var _scale: Vector2 = Vector2.ONE
var _origin: Vector2 = Vector2.ZERO


func _ready():
	# Position: top-left corner with a small margin
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left   = 8
	offset_top    = 40
	offset_right  = 8 + MAP_SIZE.x
	offset_bottom = 40 + MAP_SIZE.y
	custom_minimum_size = MAP_SIZE
	size = MAP_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = _map_visible

	# Floor label
	var lbl := Label.new()
	lbl.name = "FloorLabel"
	lbl.text = "F%d" % _floor_num
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
	lbl.position = Vector2(4, 2)
	add_child(lbl)

	# Legend hint
	var hint := Label.new()
	hint.name = "HintLabel"
	hint.text = "[M] Map"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.6))
	hint.position = Vector2(MAP_SIZE.x - 52, MAP_SIZE.y - 16)
	add_child(hint)


## Called by dungeon.gd after stamping.
func set_dungeon_data(data: Dictionary, floor_num: int) -> void:
	_rooms = data.get("rooms", [])
	_grid = data.get("grid", [])
	_grid_cols = data.get("cols", 0)
	_grid_rows = data.get("rows", 0)
	_offset_x = data.get("offset_x", 0)
	_offset_z = data.get("offset_z", 0)
	_floor_num = floor_num
	_visited.clear()
	_current_room_id = -1

	# Update floor label
	var lbl := get_node_or_null("FloorLabel")
	if lbl:
		lbl.text = "F%d" % _floor_num

	_compute_scale()
	queue_redraw()


## Called every frame (or on room change) with player world position.
func update_player_pos(world_pos: Vector3) -> void:
	var col: float = world_pos.x - _offset_x
	var row: float = world_pos.z - _offset_z
	_player_grid_pos = Vector2(col, row)
	queue_redraw()


## Called when player enters a room for the first time.
func mark_visited(room_id: int) -> void:
	_visited[room_id] = true
	queue_redraw()


## Called when a room is cleared.
func mark_cleared(room_id: int) -> void:
	# Room state is already updated in-place in dungeon_data;
	# we just need to trigger a redraw.
	queue_redraw()


## Called when the player changes rooms.
func set_current_room(room_id: int) -> void:
	if room_id != _current_room_id:
		_current_room_id = room_id
		queue_redraw()


func _compute_scale() -> void:
	if _grid_cols == 0 or _grid_rows == 0:
		return
	var draw_w: float = MAP_SIZE.x - PADDING * 2
	var draw_h: float = MAP_SIZE.y - PADDING * 2
	var sx: float = draw_w / float(_grid_cols)
	var sy: float = draw_h / float(_grid_rows)
	var s: float = minf(sx, sy)           # uniform scale, keep aspect ratio
	_scale = Vector2(s, s)
	# Centre the map in the available space
	_origin = Vector2(
		PADDING + (draw_w - _grid_cols * s) * 0.5,
		PADDING + (draw_h - _grid_rows * s) * 0.5
	)


func _grid_to_pixel(col: float, row: float) -> Vector2:
	return _origin + Vector2(col, row) * _scale


func _process(delta: float) -> void:
	_pulse += delta * 3.0
	if _pulse > TAU:
		_pulse -= TAU
	# Continuous redraw for player dot pulse
	if _map_visible and visible:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			_map_visible = not _map_visible
			visible = _map_visible
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if _rooms.is_empty():
		return

	# Background
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), COL_BG)
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), COL_BORDER, false, 1.0)

	# ── Corridors ──
	# Walk the BSP grid and draw corridor tiles as small dots / lines
	_draw_corridors()

	# ── Rooms ──
	for room in _rooms:
		var rid: int = room["id"]
		var rx: float = float(room["x"])
		var ry: float = float(room["y"])
		var rw: float = float(room["w"])
		var rh: float = float(room["h"])

		var top_left: Vector2 = _grid_to_pixel(rx, ry)
		var size_px: Vector2 = Vector2(rw, rh) * _scale
		var rect := Rect2(top_left, size_px)

		# Pick fill colour based on state
		var fill_col: Color
		var is_visited: bool = _visited.has(rid)
		var is_cleared: bool = room.get("state", "uncleared") == "cleared"

		if not is_visited:
			fill_col = COL_UNDISCOVERED
		elif is_cleared:
			fill_col = COL_CLEARED
		else:
			fill_col = COL_VISITED

		# Tint special room types (blend toward type colour)
		var room_type: String = room.get("room_type", "")
		if room_type == "boss":
			fill_col = fill_col.lerp(COL_BOSS, 0.45)
		elif room_type == "puzzle":
			fill_col = fill_col.lerp(COL_PUZZLE, 0.35)
		elif room_type == "start":
			fill_col = fill_col.lerp(COL_START, 0.25)

		draw_rect(rect, fill_col)

		# Current room highlight (pulsing border)
		if rid == _current_room_id:
			var alpha: float = 0.55 + 0.45 * sin(_pulse)
			var border_col := Color(COL_CURRENT.r, COL_CURRENT.g, COL_CURRENT.b, alpha)
			draw_rect(rect, border_col, false, 2.0)

	# ── Player dot ──
	if _player_grid_pos != Vector2.ZERO or _current_room_id >= 0:
		var dot_pos: Vector2 = _grid_to_pixel(_player_grid_pos.x, _player_grid_pos.y)
		# Clamp inside map bounds
		dot_pos = dot_pos.clamp(
			Vector2(PADDING, PADDING),
			Vector2(MAP_SIZE.x - PADDING, MAP_SIZE.y - PADDING)
		)
		var dot_alpha: float = 0.65 + 0.35 * sin(_pulse * 1.5)
		var dot_col := Color(COL_PLAYER_DOT.r, COL_PLAYER_DOT.g, COL_PLAYER_DOT.b, dot_alpha)
		draw_circle(dot_pos, 3.5, dot_col)
		# Outer ring
		draw_arc(dot_pos, 5.5, 0, TAU, 24, Color(COL_CURRENT.r, COL_CURRENT.g, COL_CURRENT.b, dot_alpha * 0.5), 1.0)


func _draw_corridors() -> void:
	if _grid.is_empty():
		return
	# Draw corridor tiles as small filled squares
	# To avoid iterating the entire grid every frame, we only draw near visited rooms.
	# But for simplicity and because the grid isn't huge, iterate all.
	var half_px: Vector2 = _scale * 0.4
	for row_idx in _grid_rows:
		var row_arr: Array = _grid[row_idx]
		for col_idx in _grid_cols:
			if row_arr[col_idx] == 2:  # BspDungeon.CORRIDOR
				# Only show corridors adjacent to visited rooms
				if _is_corridor_near_visited(col_idx, row_idx):
					var center: Vector2 = _grid_to_pixel(float(col_idx) + 0.5, float(row_idx) + 0.5)
					draw_rect(Rect2(center - half_px, half_px * 2), COL_CORRIDOR)


func _is_corridor_near_visited(col: int, row: int) -> bool:
	# Check if this corridor tile is within 2 tiles of any visited room
	for room in _rooms:
		if not _visited.has(room["id"]):
			continue
		var rx: int = room["x"]
		var ry: int = room["y"]
		var rw: int = room["w"]
		var rh: int = room["h"]
		# Expand room bounds by 2 tiles
		if col >= rx - 2 and col < rx + rw + 2 and row >= ry - 2 and row < ry + rh + 2:
			return true
	return false
