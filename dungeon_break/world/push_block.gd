extends Node3D
## PushBlock — grid-snapped sokoban puzzle block for dungeon puzzle rooms.
##
## Walks exactly 1 tile when the player pushes into it.
## Checks if destination is walkable (air above floor). If not, push is blocked.
## Emits `moved` after each push so the puzzle room can check solve state.

signal moved()

## Grid position of this block (2D, floor plane — X/Z in world terms).
var grid_pos := Vector2i.ZERO

## World-space Y of the floor this block sits on.
var floor_y: float = 1.0

## Room ID this block belongs to (for grouping / reset).
var room_id: int = -1

## Original spawn position for puzzle reset.
var spawn_grid_pos := Vector2i.ZERO

## Whether this block is currently on a target tile.
var on_target := false

# ── Internals ────────────────────────────────────────────────────────────────
var _mesh: MeshInstance3D = null
var _tween: Tween = null
const SLIDE_TIME := 0.15  # seconds to tween 1 tile


func _ready():
	add_to_group("push_blocks")
	_create_visual()


## Initialise after adding to the scene tree.
func setup(gpos: Vector2i, fy: float, rid: int):
	grid_pos = gpos
	spawn_grid_pos = gpos
	floor_y = fy
	room_id = rid
	global_position = _world_pos(gpos)


## Try to pull this block to `dest` grid position (the tile the player just vacated).
## Caller must ensure dest is valid floor. Returns true if pull succeeded.
func try_pull(dest: Vector2i, voxel_tool: VoxelTool) -> bool:
	# Destination must have a floor and air above it, same checks as push
	var dest_world := Vector3i(dest.x, int(floor_y), dest.y)
	var block_level := Vector3i(dest.x, int(floor_y) + 1, dest.y)

	var floor_voxel: int = voxel_tool.get_voxel(dest_world)
	var block_voxel: int = voxel_tool.get_voxel(block_level)

	if floor_voxel == 0:
		return false  # no floor at destination
	if block_voxel != 0:
		return false  # something solid blocking

	# Check no other push block at dest
	for other in get_tree().get_nodes_in_group("push_blocks"):
		if other == self:
			continue
		if other.grid_pos == dest:
			return false

	grid_pos = dest
	_animate_to(dest)
	return true


## Try to push this block one tile in `dir` (unit vector on XZ plane).
## Returns true if the push succeeded.
func try_push(dir: Vector2i, voxel_tool: VoxelTool) -> bool:
	var dest := grid_pos + dir

	# Check destination: must be air at floor+1 (block level) AND have a floor below
	var dest_world := Vector3i(dest.x, int(floor_y), dest.y)
	var above := Vector3i(dest.x, int(floor_y) + 1, dest.y)

	# Floor must exist (non-air at floor_y), space above must be air
	var floor_voxel: int = voxel_tool.get_voxel(dest_world)
	# For elevated rooms floor_y already accounts for elevation, so floor_y-1
	# is base; floor_y is the walkable surface. Block occupies floor_y (surface level).
	# Actually, voxel at floor_y IS the floor surface. Block sits visually at floor_y+1.
	# So check that floor_y exists (non-air) and floor_y+1 is air.
	var block_level := Vector3i(dest.x, int(floor_y) + 1, dest.y)
	var block_voxel: int = voxel_tool.get_voxel(block_level)

	if floor_voxel == 0:
		return false  # no floor at destination
	if block_voxel != 0:
		return false  # something solid blocking

	# Also check no other push block is at dest
	for other in get_tree().get_nodes_in_group("push_blocks"):
		if other == self:
			continue
		if other.grid_pos == dest:
			return false  # another block in the way

	# Push!
	grid_pos = dest
	_animate_to(dest)
	return true


## Reset this block to its original spawn position (puzzle retry).
func reset():
	grid_pos = spawn_grid_pos
	on_target = false
	global_position = _world_pos(spawn_grid_pos)
	_update_target_visual()
	if _tween and _tween.is_valid():
		_tween.kill()


## Mark whether this block is sitting on a target tile.
func set_on_target(val: bool):
	on_target = val
	_update_target_visual()


# ── Private ──────────────────────────────────────────────────────────────────

func _world_pos(gpos: Vector2i) -> Vector3:
	# floor_y is the voxel Y coordinate of the floor surface; the walkable
	# surface is the TOP of that voxel, i.e. floor_y + 1.0.  Centre the
	# 0.9-unit box half a unit above that.
	return Vector3(float(gpos.x) + 0.5, floor_y + 1.0 + 0.45, float(gpos.y) + 0.5)


func _animate_to(dest: Vector2i):
	var target := _world_pos(dest)
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "global_position", target, SLIDE_TIME)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_callback(func(): moved.emit())


func _create_visual():
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.9, 0.9)
	_mesh.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.45, 0.25)  # warm brown crate colour
	mat.roughness = 0.85
	_mesh.material_override = mat
	add_child(_mesh)

	# Drop shadow beneath
	var shadow_mesh := MeshInstance3D.new()
	var shadow_quad := QuadMesh.new()
	shadow_quad.size = Vector2(0.85, 0.85)
	shadow_mesh.mesh = shadow_quad
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0, 0, 0, 0.35)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mesh.material_override = smat
	shadow_mesh.rotation_degrees.x = -90
	shadow_mesh.position.y = -0.44  # just above floor surface
	add_child(shadow_mesh)


func _update_target_visual():
	if _mesh and _mesh.material_override:
		if on_target:
			_mesh.material_override.albedo_color = Color(0.25, 0.75, 0.3)  # green when on target
		else:
			_mesh.material_override.albedo_color = Color(0.6, 0.45, 0.25)  # default brown
