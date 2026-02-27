extends Node3D
## Player controller for Dungeon Break (isometric view).
##
## Two movement modes:
##   1. WASD/arrows — relative to the isometric camera angle
##   2. Click-to-move — left-click uses VoxelAStarGrid3D pathfinding
##
## Elevation rules:
##   - Auto-jump up 1–2 blocks when walking into a ledge
##   - Can jump out of holes (1–2 blocks)
##   - Will NOT walk off a cliff (3+ block drop ahead)
##
## Uses VoxelBoxMover for collision against voxel terrain.

@export var speed := 5.0
@export var gravity := 30.0
@export var jump_force := 10.0

## Path to the VoxelTerrain node (set from game scene)
@export var terrain: NodePath

## Click-to-move: how close to a waypoint before advancing to the next one
@export var waypoint_threshold: float = 1.0

## Max step-up height for auto-jump (in blocks). 2 = can hop up 2-block ledges.
@export var max_step_up: float = 2.5

## Max drop the player is allowed to walk into. Drops bigger than this are cliffs.
@export var max_safe_drop: float = 2.5

## Set true by dungeon.gd when tactical combat is active.
## Suppresses all movement input so the tactical grid has full control.
var combat_locked: bool = false

## Pathfinding search radius (voxels from player)
@export var pathfind_radius: int = 50

var _velocity := Vector3()
var _grounded := false
var _box_mover := VoxelBoxMover.new()

# Camera ref — set in _ready, used to read live yaw
var _camera = null

# Billboard sprite
var _sprite: Sprite3D = null
var _last_move_dir := Vector3()

# ── Pathfinding ───────────────────────────────────────────────────────────────
var _pathfinder: VoxelAStarGrid3D = null
var _path_waypoints: Array[Vector3i] = []  # current A* path
var _path_index: int = 0                   # which waypoint we're walking toward
var _has_path: bool = false

# ── Click marker ─────────────────────────────────────────────────────────────
var _click_marker: MeshInstance3D = null

# ── Cached refs ──────────────────────────────────────────────────────────────
var _terrain_node: VoxelTerrain = null
var _voxel_tool: VoxelTool = null


func _ready():
	_box_mover.set_collision_mask(1)
	_box_mover.set_step_climbing_enabled(true)
	_box_mover.set_max_step_height(max_step_up)

	# Grab the isometric camera (child of this node)
	_camera = get_node_or_null("IsometricCamera")

	# Find the Sprite3D child for facing direction
	for child in get_children():
		if child is Sprite3D:
			_sprite = child
			break

	# Create click indicator
	_click_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.5
	torus.rings = 8
	torus.ring_segments = 12
	_click_marker.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.4, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_click_marker.material_override = mat
	_click_marker.visible = false
	_click_marker.top_level = true
	add_child(_click_marker)


func _enter_tree():
	# Defer terrain setup until the node is in the tree so get_node works
	call_deferred("_setup_terrain")


func _setup_terrain():
	if has_node(terrain):
		_terrain_node = get_node(terrain)
		_voxel_tool = _terrain_node.get_voxel_tool()

		# Set up pathfinder
		_pathfinder = VoxelAStarGrid3D.new()
		_pathfinder.set_terrain(_terrain_node)


## Get the Y of the topmost solid block at (x, z), searching downward from start_y.
## Returns the Y of the air block just above the surface (where you'd stand).
func _get_surface_y(xi: int, zi: int, start_y: int = 30) -> int:
	if _voxel_tool == null:
		return 0
	for y in range(start_y, -10, -1):
		var v := _voxel_tool.get_voxel(Vector3i(xi, y, zi))
		if v != 0:  # non-air
			return y + 1  # stand on top
	return 0


## Check if the ground ahead is a cliff (drop > max_safe_drop).
## probe_dir is the XZ movement direction (normalized).
func _is_cliff_ahead(probe_dir: Vector3) -> bool:
	if _voxel_tool == null:
		return false

	# Probe 1 block ahead in movement direction
	var probe_pos := global_position + probe_dir * 1.2
	var px := int(floor(probe_pos.x))
	var pz := int(floor(probe_pos.z))
	var current_foot_y := int(floor(global_position.y))

	var ahead_surface_y := _get_surface_y(px, pz, current_foot_y + 2)

	# If the surface ahead is much lower, it's a cliff
	var drop := current_foot_y - ahead_surface_y
	return drop > max_safe_drop


## Check if there's a 1–2 block ledge ahead we should auto-jump over.
func _should_auto_jump(probe_dir: Vector3) -> bool:
	if not _grounded or _voxel_tool == null:
		return false

	# Probe 1 block ahead
	var probe_pos := global_position + probe_dir * 0.8
	var px := int(floor(probe_pos.x))
	var pz := int(floor(probe_pos.z))
	var current_foot_y := int(floor(global_position.y))

	var ahead_surface_y := _get_surface_y(px, pz, current_foot_y + 4)
	var height_diff := ahead_surface_y - current_foot_y

	# Auto-jump if there's a 1–2 block ledge up
	return height_diff >= 1 and height_diff <= int(max_step_up)


func _unhandled_input(event: InputEvent):
	if combat_locked:
		return
	# Left-click → pathfind-to-move
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_do_click_to_move(event.position)


func _do_click_to_move(mouse_pos: Vector2):
	var camera := get_viewport().get_camera_3d()
	if camera == null or _voxel_tool == null or _pathfinder == null:
		return

	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)

	var hit := _voxel_tool.raycast(ray_origin, ray_dir, 200.0)
	if hit == null:
		return

	# Destination: the air block above the hit surface
	var dst := hit.previous_position

	# Source: the block the player is standing in
	var src := Vector3i(
		int(floor(global_position.x)),
		int(floor(global_position.y)),
		int(floor(global_position.z))
	)

	# Set pathfinder search region around the player
	var region_center := src
	_pathfinder.set_region(AABB(
		Vector3(region_center) - Vector3(pathfind_radius, pathfind_radius, pathfind_radius),
		Vector3(pathfind_radius * 2, pathfind_radius * 2, pathfind_radius * 2)
	))

	# Find path
	var path := _pathfinder.find_path(src, dst)

	if path.size() > 0:
		_path_waypoints = path
		_path_index = 0
		_has_path = true

		# Show marker at destination
		var dest_world := Vector3(dst) + Vector3(0.5, 0.1, 0.5)
		_click_marker.global_position = dest_world
		_click_marker.visible = true
	else:
		# No path found — try direct move as fallback (short distances)
		var target_pos := Vector3(dst) + Vector3(0.5, 0.0, 0.5)
		var dist_xz := Vector2(target_pos.x - global_position.x, target_pos.z - global_position.z).length()
		if dist_xz < 8.0:
			# Short distance, just walk directly
			_path_waypoints = [dst]
			_path_index = 0
			_has_path = true

			_click_marker.global_position = target_pos + Vector3(0, 0.1, 0)
			_click_marker.visible = true


func _physics_process(delta: float):
	if combat_locked:
		return
	# ── WASD input ────────────────────────────────────────────────────────────
	# Read live yaw from camera so rotation stays synced
	var yaw_deg: float = 45.0
	if _camera and _camera.has_method("get_current_yaw"):
		yaw_deg = _camera.get_current_yaw()
	var yaw_rad := deg_to_rad(yaw_deg)
	var cam_forward := Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad)).normalized()
	var cam_right := Vector3(-cam_forward.z, 0.0, cam_forward.x).normalized()

	var input_dir := Vector3()

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir += cam_forward
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir -= cam_forward
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir -= cam_right
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir += cam_right

	# WASD cancels pathfinding
	var has_keyboard_input := input_dir.length_squared() > 0.01
	if has_keyboard_input:
		_has_path = false
		_click_marker.visible = false

	# ── Pathfinding follow ────────────────────────────────────────────────────
	if _has_path and not has_keyboard_input:
		if _path_index < _path_waypoints.size():
			var wp: Vector3i = _path_waypoints[_path_index]
			# Target centre of the waypoint block
			var wp_world := Vector3(wp) + Vector3(0.5, 0.0, 0.5)
			var to_wp := wp_world - global_position
			to_wp.y = 0
			var dist := to_wp.length()

			if dist < waypoint_threshold:
				_path_index += 1
				if _path_index >= _path_waypoints.size():
					_has_path = false
					_click_marker.visible = false
			else:
				input_dir = to_wp.normalized()
		else:
			_has_path = false
			_click_marker.visible = false

	# ── Cliff check + auto-jump ───────────────────────────────────────────────
	if input_dir.length_squared() > 0.01:
		input_dir = input_dir.normalized()
		_last_move_dir = input_dir

		# Cliff prevention: block movement if there's a big drop ahead
		if _grounded and _is_cliff_ahead(input_dir):
			input_dir = Vector3.ZERO

		# Auto-jump up 1–2 block ledges
		elif _should_auto_jump(input_dir):
			_velocity.y = jump_force
			_grounded = false

		# Flip sprite based on movement direction
		if _sprite != null:
			_sprite.flip_h = input_dir.x < -0.1

	var motor := input_dir * speed

	_velocity.x = motor.x
	_velocity.z = motor.z
	_velocity.y -= gravity * delta

	# Manual jump (space)
	if _grounded and Input.is_key_pressed(KEY_SPACE):
		_velocity.y = jump_force
		_grounded = false

	var motion := _velocity * delta

	if _terrain_node != null:
		var aabb := AABB(Vector3(-0.4, -0.9, -0.4), Vector3(0.8, 1.8, 0.8))

		var vt := _terrain_node.get_voxel_tool()
		if vt.is_area_editable(AABB(aabb.position + position, aabb.size)):
			var prev_motion := motion
			motion = _box_mover.get_motion(position, motion, aabb, _terrain_node)
			global_translate(motion)

			if absf(motion.y) < 0.001 and prev_motion.y < -0.001:
				_grounded = true

			if _box_mover.has_stepped_up():
				motion.y = 0
				_grounded = true
			elif absf(motion.y) > 0.001:
				_grounded = false
		else:
			motion = Vector3()

	assert(delta > 0)
	_velocity = motion / delta
