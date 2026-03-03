extends Node
## Entity manager — spawns and pools billboard Sprite3D entities.
##
## Handles enemy, NPC, and wanderer billboard sprites with LOD.
## Object-pooled for performance. Autoloaded as "EntityManager".

# ── Signals ──────────────────────────────────────────────────────────────────
signal entity_spawned(entity: Node3D)
signal entity_despawned(entity: Node3D)

# ── Pool settings ────────────────────────────────────────────────────────────
const POOL_INITIAL_SIZE := 16
const POOL_GROW_SIZE := 8
const MAX_ENTITIES := 64

# ── Scene parent for active entities (visible in world) ──────────────────────
var _active_parent: Node3D = null

# ── LOD distances ────────────────────────────────────────────────────────────
const LOD_FULL_DIST := 30.0      # Full sprite below this distance
const LOD_SIMPLE_DIST := 60.0    # Simplified sprite below this
const LOD_CULL_DIST := 100.0     # Invisible beyond this

# ── Enemy sprite sizing ───────────────────────────────────────────────────────
# Enemy portraits are 1024×1024px. At 0.003 that's ~3 units tall (≈ 3 voxel blocks).
# Adjust here if sprites need to be bigger or smaller overall.
const ENTITY_PIXEL_SIZE_FULL   := 0.003
const ENTITY_PIXEL_SIZE_SIMPLE := 0.0015

# ── Texture cache ────────────────────────────────────────────────────────────
var _texture_cache: Dictionary = {}  # path → Texture2D

# ── Entity pool ──────────────────────────────────────────────────────────────
var _pool: Array[Node3D] = []       # Inactive pooled entities
var _active: Array[Node3D] = []     # Currently in use
var _pool_parent: Node3D = null     # Hidden node for pooled entities

# ── Camera ref for LOD ───────────────────────────────────────────────────────
var _camera: Camera3D = null


func _ready():
	_pool_parent = Node3D.new()
	_pool_parent.name = "EntityPool"
	_pool_parent.visible = false
	add_child(_pool_parent)

	_active_parent = Node3D.new()
	_active_parent.name = "ActiveEntities"
	add_child(_active_parent)

	# Pre-fill the pool
	for i in POOL_INITIAL_SIZE:
		_pool.append(_create_entity_node())


## Set the camera reference for LOD calculations.
func set_camera(cam: Camera3D):
	_camera = cam


func _process(_delta: float):
	if _camera == null:
		return

	var cam_pos := _camera.global_position

	# LOD update for all active entities
	for entity in _active:
		if not is_instance_valid(entity):
			continue
		var dist := cam_pos.distance_to(entity.global_position)

		var sprite: Sprite3D = entity.get_meta("sprite", null)
		if sprite == null:
			continue

		if dist > LOD_CULL_DIST:
			sprite.visible = false
		elif dist > LOD_SIMPLE_DIST:
			# Simple LOD: smaller/faded
			sprite.visible = true
			sprite.pixel_size = ENTITY_PIXEL_SIZE_SIMPLE
			sprite.modulate.a = 0.6
		else:
			# Full detail
			sprite.visible = true
			sprite.pixel_size = ENTITY_PIXEL_SIZE_FULL
			sprite.modulate.a = 1.0


## Spawn an entity at a world position with the given texture key.
## Returns the entity Node3D. `data` is stored as metadata for game logic.
func spawn_entity(world_pos: Vector3, texture_path: String, data: Dictionary = {}) -> Node3D:
	if _active.size() >= MAX_ENTITIES:
		push_warning("EntityManager: MAX_ENTITIES reached (%d)" % MAX_ENTITIES)
		return null

	var entity := _acquire()
	var sprite: Sprite3D = entity.get_meta("sprite")

	# Load texture (cached)
	var tex := _get_texture(texture_path)
	if tex:
		sprite.texture = tex
	sprite.visible = true

	# Apply variant tints
	var variant: String = data.get("variant", "normal")
	match variant:
		"ghost":
			sprite.modulate = Color(0.6, 0.8, 1.0, 0.5)
		"elite":
			sprite.modulate = Color(1.0, 0.3, 0.3, 1.0)
		_:
			sprite.modulate = Color.WHITE

	# Store game data as metadata
	for key in data:
		entity.set_meta(key, data[key])

	entity.global_position = world_pos
	entity_spawned.emit(entity)
	return entity


## Briefly swap an entity's world sprite to its attack pose, then restore.
## attack_tex_path should come from EnemyDB.get_attack_texture_path(key).
func play_attack_flash(entity: Node3D, attack_tex_path: String) -> void:
	if not is_instance_valid(entity):
		return
	var sprite: Sprite3D = entity.get_meta("sprite", null)
	if sprite == null:
		return
	# Try cache first, then load() directly (bypass ResourceLoader.exists which can fail for some paths)
	var attack_tex: Texture2D = null
	if _texture_cache.has(attack_tex_path):
		attack_tex = _texture_cache[attack_tex_path]
	else:
		attack_tex = load(attack_tex_path) as Texture2D
		if attack_tex != null:
			_texture_cache[attack_tex_path] = attack_tex
	if attack_tex == null:
		push_warning("EntityManager: attack texture not found — %s" % attack_tex_path)
		return
	var base_tex: Texture2D = sprite.texture
	sprite.texture = attack_tex
	# Capture entity (not sprite) to avoid "lambda capture freed" errors when the
	# entity is despawned/pooled before the timer fires.
	get_tree().create_timer(0.75).timeout.connect(func() -> void:
		if is_instance_valid(entity):
			var s: Sprite3D = entity.get_meta("sprite", null)
			if s != null:
				s.texture = base_tex
	)


## Despawn an entity back into the pool.
func despawn_entity(entity: Node3D):
	if not is_instance_valid(entity):
		return
	if entity not in _active:
		return

	entity_despawned.emit(entity)
	_release(entity)


## Despawn all active entities.
func despawn_all():
	# Work on a copy since _release modifies _active
	var to_release := _active.duplicate()
	for entity in to_release:
		if is_instance_valid(entity):
			_release(entity)


## Get all currently active entities.
func get_active_entities() -> Array[Node3D]:
	return _active


## Get active entity count.
func get_active_count() -> int:
	return _active.size()


# ── Internal pool management ─────────────────────────────────────────────────

func _create_entity_node() -> Node3D:
	var root := Node3D.new()
	root.name = "PooledEntity"

	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = ENTITY_PIXEL_SIZE_FULL
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.transform.origin.y = 1.5   # Centre above ground (scales with pixel size)
	sprite.shaded = false
	sprite.render_priority = 2  # Draw on top of grid tiles (priority 1)
	root.add_child(sprite)

	# Drop shadow — flat dark ellipse at feet
	var shadow := _create_drop_shadow()
	root.add_child(shadow)
	root.set_meta("shadow", shadow)

	root.set_meta("sprite", sprite)

	_pool_parent.add_child(root)
	return root


## Create a small dark ellipse mesh used as a drop shadow.
static func _create_drop_shadow() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Shadow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 0.6)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.position = Vector3(0, 0.02, 0)  # Just above ground to avoid z-fight
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Only show on MEDIUM+ (managed per-frame by LOD or on spawn)
	if GraphicsManager and GraphicsManager.current_preset == 0:
		mi.visible = false
	return mi


func _acquire() -> Node3D:
	var entity: Node3D

	if _pool.size() > 0:
		entity = _pool.pop_back()
	else:
		# Pool empty — grow it
		for i in POOL_GROW_SIZE - 1:
			_pool.append(_create_entity_node())
		entity = _create_entity_node()

	# Move from pool to visible scene
	_pool_parent.remove_child(entity)
	_active_parent.add_child(entity)
	_active.append(entity)
	return entity


func _release(entity: Node3D):
	_active.erase(entity)

	# Clear entity metadata (except sprite ref)
	var sprite = entity.get_meta("sprite", null)
	var meta_keys := entity.get_meta_list()
	for key in meta_keys:
		if key != "sprite":
			entity.remove_meta(key)

	# Reset visual state
	if sprite:
		sprite.modulate = Color.WHITE
		sprite.texture = null
		sprite.visible = false

	# Reparent to pool
	if entity.get_parent():
		entity.get_parent().remove_child(entity)
	_pool_parent.add_child(entity)
	_pool.append(entity)


func _get_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]

	if not ResourceLoader.exists(path):
		push_warning("EntityManager: texture not found — %s" % path)
		return null

	var tex: Texture2D = load(path)
	_texture_cache[path] = tex
	return tex
