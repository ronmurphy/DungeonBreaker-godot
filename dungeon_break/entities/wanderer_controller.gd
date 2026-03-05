extends Node
## Wanderer NPC controller — patrols camp, interactable billboard sprites.
##
## Spawns 4 wanderers on camp with random race/gender avatars.
## Each wanders randomly across walkable terrain.
## Uses EntityManager pooling for the billboard sprites.

const AVATAR_PATH := "res://assets/art/player_avatars/"

# Available avatar prefixes (each has _ready.png)
const AVATAR_KEYS := [
	"human_male", "human_female",
	"elf_male", "elf_female",
	"dwarf_male", "dwarf_female",
	"goblin_male", "goblin_female",
]

const CAMP_WANDERER_COUNT := 4

# Patrol settings
const PATROL_SPEED := 2.0
const PATROL_MIN_WAIT := 2.0   # seconds idle at destination
const PATROL_MAX_WAIT := 6.0
const PATROL_RADIUS := 25.0    # max distance from camp centre to pick targets
const PATROL_MIN_RADIUS := 5.0 # min distance so they don't cluster at origin

# Interaction distance
const INTERACT_DIST := 3.0

# ── Internal state per wanderer ──────────────────────────────────────────────
class WandererState:
	var entity: Node3D = null       # EntityManager pooled node
	var avatar_key: String = ""
	var target_pos: Vector3 = Vector3.ZERO
	var is_moving: bool = false
	var wait_timer: float = 0.0
	var world_pos: Vector3 = Vector3.ZERO  # current position
	var name_tag: String = ""

var _wanderers: Array[WandererState] = []
var _terrain: VoxelTerrain = null
var _voxel_tool: VoxelTool = null

# NPC names (pool to pick from)
const NPC_NAMES := [
	"Mira", "Gorth", "Elara", "Brik", "Thessa", "Durn",
	"Sylva", "Krugg", "Fenna", "Ozrik", "Lysse", "Vosk",
]


func setup(terrain: VoxelTerrain):
	_terrain = terrain
	_voxel_tool = terrain.get_voxel_tool()


## Spawn wanderers at random positions around camp.
func spawn_camp_wanderers():
	if _terrain == null:
		push_error("WandererController: call setup() first")
		return

	var used_names: Array[String] = []
	var used_avatars: Array[String] = []

	for i in CAMP_WANDERER_COUNT:
		var ws := WandererState.new()

		# Pick unique avatar
		var avatar_key: String
		if used_avatars.size() < AVATAR_KEYS.size():
			avatar_key = AVATAR_KEYS[i % AVATAR_KEYS.size()]
			while avatar_key in used_avatars and used_avatars.size() < AVATAR_KEYS.size():
				avatar_key = AVATAR_KEYS[randi() % AVATAR_KEYS.size()]
		else:
			avatar_key = AVATAR_KEYS[randi() % AVATAR_KEYS.size()]
		used_avatars.append(avatar_key)
		ws.avatar_key = avatar_key

		# Pick unique name
		var npc_name: String = NPC_NAMES[randi() % NPC_NAMES.size()]
		while npc_name in used_names and used_names.size() < NPC_NAMES.size():
			npc_name = NPC_NAMES[randi() % NPC_NAMES.size()]
		used_names.append(npc_name)
		ws.name_tag = npc_name

		# Pick random spawn position on walkable terrain
		var spawn_pos := _pick_random_walkable()
		ws.world_pos = spawn_pos
		ws.target_pos = spawn_pos
		ws.wait_timer = randf_range(0.0, PATROL_MAX_WAIT)

		# Spawn via EntityManager
		var tex_path := AVATAR_PATH + avatar_key + "_ready.png"
		var data := {
			"type": "wanderer",
			"name": ws.name_tag,
			"avatar": avatar_key,
			"variant": "normal",
		}

		if EntityManager:
			ws.entity = EntityManager.spawn_entity(spawn_pos, tex_path, data)

		_wanderers.append(ws)


func _process(delta: float):
	for ws in _wanderers:
		if ws.entity == null or not is_instance_valid(ws.entity):
			continue

		if ws.is_moving:
			_move_toward_target(ws, delta)
		else:
			ws.wait_timer -= delta
			if ws.wait_timer <= 0:
				# Pick new patrol target
				ws.target_pos = _pick_random_walkable()
				ws.is_moving = true


func _move_toward_target(ws: WandererState, delta: float):
	var to_target := ws.target_pos - ws.world_pos
	to_target.y = 0  # XZ movement only
	var dist := to_target.length()

	if dist < 0.5:
		# Arrived
		ws.is_moving = false
		ws.wait_timer = randf_range(PATROL_MIN_WAIT, PATROL_MAX_WAIT)
		return

	var dir := to_target.normalized()
	var move := dir * PATROL_SPEED * delta
	ws.world_pos += move

	# Snap Y to terrain surface
	var sx := int(floor(ws.world_pos.x))
	var sz := int(floor(ws.world_pos.z))
	var sy := _surface_y(sx, sz)
	ws.world_pos.y = float(sy) + 0.1

	# Update entity position
	ws.entity.global_position = ws.world_pos

	# Flip sprite based on direction
	var sprite: Sprite3D = ws.entity.get_meta("sprite", null)
	if sprite:
		sprite.flip_h = dir.x < -0.1


func _pick_random_walkable() -> Vector3:
	# Pick random point within patrol radius on the island
	for _attempt in 30:
		var angle := randf() * TAU
		var radius := randf_range(PATROL_MIN_RADIUS, PATROL_RADIUS)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		var xi := int(floor(x))
		var zi := int(floor(z))

		# Check if it's on the island (has a surface)
		var sy := _surface_y(xi, zi)
		if sy > -1:
			return Vector3(x, float(sy) + 0.1, z)

	# Fallback: camp centre
	return Vector3(0, 1, 0)


func _surface_y(x: int, z: int) -> int:
	if _voxel_tool == null:
		return 0
	for y in range(20, -5, -1):
		var v := _voxel_tool.get_voxel(Vector3i(x, y, z))
		if v != 0:
			return y + 1
	return -1


## Despawn all wanderers.
func despawn_all():
	for ws in _wanderers:
		if ws.entity and is_instance_valid(ws.entity) and EntityManager:
			EntityManager.despawn_entity(ws.entity)
	_wanderers.clear()


## Check if the player is near a wanderer. Returns the WandererState or null.
func get_nearby_wanderer(player_pos: Vector3) -> WandererState:
	var closest_dist := INTERACT_DIST
	var closest: WandererState = null

	for ws in _wanderers:
		if ws.entity == null or not is_instance_valid(ws.entity):
			continue
		var dist := player_pos.distance_to(ws.world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = ws

	return closest
