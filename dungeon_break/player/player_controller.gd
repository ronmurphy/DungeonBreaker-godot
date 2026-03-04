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

# ── Push block cooldown (prevents multi-push per step) ──────────────────────
var _push_cooldown: float = 0.0
const PUSH_COOLDOWN_TIME := 0.25

# ── Pull mode toggle (K key) ────────────────────────────────────────────────
var _pull_mode: bool = false
var _in_puzzle_room: bool = false

# ── Footstep dust particles ──────────────────────────────────────────────────
var _dust_particles: GPUParticles3D = null

# ── Block push/pull SFX ──────────────────────────────────────────────────────
var _block_sfx_player: AudioStreamPlayer = null
const _SFX_BLOCK_PUSH := "res://assets/sfx/combat/block_push.ogg"


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

	# Apply the race/gender sprite chosen on the character select screen
	if _sprite != null and _sprite.has_method("setup"):
		var prefix: String = GameData.player_sprite_prefix
		if prefix != "":
			_sprite.setup(prefix)

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

	# ── Block push SFX player ────────────────────────────────────────────────
	_block_sfx_player = AudioStreamPlayer.new()
	_block_sfx_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_block_sfx_player)

	# ── Footstep dust particles ──────────────────────────────────────────────
	_dust_particles = GPUParticles3D.new()
	_dust_particles.name = "FootDust"
	_dust_particles.emitting = false
	_dust_particles.amount = 6
	_dust_particles.lifetime = 0.6
	_dust_particles.one_shot = false
	_dust_particles.explosiveness = 0.3
	_dust_particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))

	var dust_mat := ParticleProcessMaterial.new()
	dust_mat.direction = Vector3(0, 1, 0)
	dust_mat.spread = 45.0
	dust_mat.initial_velocity_min = 0.4
	dust_mat.initial_velocity_max = 1.0
	dust_mat.gravity = Vector3(0, -1.5, 0)
	dust_mat.scale_min = 0.08
	dust_mat.scale_max = 0.18
	dust_mat.damping_min = 2.0
	dust_mat.damping_max = 4.0
	dust_mat.color = Color(0.75, 0.68, 0.55, 0.5)
	# Fade out over lifetime
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.6, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	dust_mat.alpha_curve = alpha_curve
	_dust_particles.process_material = dust_mat

	# Simple quad mesh for each particle
	var quad := QuadMesh.new()
	quad.size = Vector2(0.15, 0.15)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.albedo_color = Color(0.75, 0.68, 0.55, 0.5)
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = quad_mat
	_dust_particles.draw_pass_1 = quad

	add_child(_dust_particles)
	_dust_particles.position = Vector3(0, -0.6, 0)  # near feet

	# Respect graphics preset — disable on LOW
	if GraphicsManager:
		_apply_dust_quality(GraphicsManager.current_preset)
		if not GraphicsManager.preset_changed.is_connected(_on_gfx_preset_changed):
			GraphicsManager.preset_changed.connect(_on_gfx_preset_changed)


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

	# Tick push block cooldown
	if _push_cooldown > 0.0:
		_push_cooldown -= delta

	# ── K key: toggle push / pull mode ───────────────────────────────────
	if Input.is_key_pressed(KEY_K) and _push_cooldown <= 0.0 and _in_puzzle_room:
		_pull_mode = not _pull_mode
		_push_cooldown = PUSH_COOLDOWN_TIME  # reuse cooldown to debounce
		var hud = get_tree().get_first_node_in_group("game_hud")
		if hud and hud.has_method("set_block_mode"):
			hud.set_block_mode("PULL" if _pull_mode else "PUSH")

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

		# ── Push block detection ──────────────────────────────────────────
		if _push_cooldown <= 0.0:
			_try_push_block(input_dir)

		# Update sprite direction (CharacterSprite) or fall back to simple flip
		if _sprite != null:
			if _sprite.has_method("update_direction"):
				_sprite.update_direction(input_dir, cam_forward, cam_right)
			else:
				_sprite.flip_h = input_dir.x < -0.1

	# When no input, tell CharacterSprite to return to idle
	if input_dir.length_squared() < 0.01 and _sprite != null:
		if _sprite.has_method("update_direction"):
			_sprite.update_direction(Vector3.ZERO, cam_forward, cam_right)

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

	# ── Footstep dust: emit only when grounded + moving ──────────────────────
	if _dust_particles and _dust_particles.visible:
		var moving := input_dir.length_squared() > 0.01
		_dust_particles.emitting = moving and _grounded


# ── Graphics preset callback ─────────────────────────────────────────────────

func _on_gfx_preset_changed(preset: int) -> void:
	_apply_dust_quality(preset)


func _apply_dust_quality(preset: int) -> void:
	if _dust_particles == null:
		return
	match preset:
		0:  # LOW — disable completely
			_dust_particles.visible = false
			_dust_particles.emitting = false
		1:  # MEDIUM — reduced
			_dust_particles.visible = true
			_dust_particles.amount = 4
		_:  # HIGH — full
			_dust_particles.visible = true
			_dust_particles.amount = 6


# ── Push block helpers ───────────────────────────────────────────────────────

## Check if the player is walking into a push block tile and push it,
## or — in pull mode — drag a block behind the player into the vacated tile.
func _try_push_block(move_dir: Vector3):
	# Quantise movement to a cardinal direction (strongest axis)
	var dir := Vector2i.ZERO
	if absf(move_dir.x) > absf(move_dir.z):
		dir = Vector2i(1, 0) if move_dir.x > 0 else Vector2i(-1, 0)
	elif absf(move_dir.z) > 0.01:
		dir = Vector2i(0, 1) if move_dir.z > 0 else Vector2i(0, -1)
	else:
		return

	# Player's current tile in world grid
	var player_tile := Vector2i(int(floor(global_position.x)), int(floor(global_position.z)))

	if _pull_mode:
		# Pull mode: look for a block BEHIND the player (opposite of move dir).
		# That block will slide into the tile the player is leaving.
		var behind_tile := player_tile - dir
		for block in get_tree().get_nodes_in_group("push_blocks"):
			if not is_instance_valid(block):
				continue
			if block.grid_pos == behind_tile:
				if _voxel_tool == null and _terrain_node != null:
					_voxel_tool = _terrain_node.get_voxel_tool()
				if _voxel_tool:
					_voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
					if block.try_pull(player_tile, _voxel_tool):
						_push_cooldown = PUSH_COOLDOWN_TIME
						_play_block_sfx()
				break
	else:
		# Push mode: block is ahead, push it further ahead.
		var ahead_tile := player_tile + dir
		for block in get_tree().get_nodes_in_group("push_blocks"):
			if not is_instance_valid(block):
				continue
			if block.grid_pos == ahead_tile:
				if _voxel_tool == null and _terrain_node != null:
					_voxel_tool = _terrain_node.get_voxel_tool()
				if _voxel_tool:
					_voxel_tool.channel = VoxelBuffer.CHANNEL_TYPE
					if block.try_push(dir, _voxel_tool):
						_push_cooldown = PUSH_COOLDOWN_TIME
						_play_block_sfx()
				break


func _play_block_sfx():
	if _block_sfx_player == null:
		return
	var stream := load(_SFX_BLOCK_PUSH) as AudioStream
	if stream == null:
		return
	_block_sfx_player.stream = stream
	_block_sfx_player.pitch_scale = randf_range(0.9, 1.1)
	_block_sfx_player.play()
