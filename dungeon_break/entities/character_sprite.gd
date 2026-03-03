extends Sprite3D
class_name CharacterSprite
## Direction-aware billboard sprite for player characters.
##
## Uses individual PNG files from assets/art/player_avatars/.
## Set sprite_prefix (e.g. "res://assets/art/player_avatars/human_male")
## and the script loads all available pose variants automatically.
##
## Walk animation: alternates flip_h every WALK_FRAME_TIME seconds.
##   SW (toward camera): _run → _run mirrored → _run → …
##   NE (away):          _run_back → _run_back mirrored → _run_back → …
##   Sideways w/ side sprites: _side_1 → _side_2 → _side_1 → …  (flip_h when going LEFT)
##   Sideways w/o side sprites: static _run  (flip_h when going LEFT; fallback)
##
## Poses loaded by suffix:
##   ""              → idle / base (facing camera)
##   "_back"         → idle facing away
##   "_run"          → walking toward camera (SW)
##   "_run_back"     → walking away from camera (NE)
##   "_side_1"       → sideways walk frame 1 (facing right; flip_h for left)
##   "_side_2"       → sideways walk frame 2 (facing right; flip_h for left)
##   "_attack"       → attack swing
##   "_ready"        → combat-ready stance
##   "_jumping"      → mid-jump toward camera
##   "_jumping_back" → mid-jump away
##   "_sad"          → dead / defeated fallback
##   "_worried"      → alternate dead fallback
##   "_happy"  "_angry"  "_thumbs_up"  → emotion poses (dialogue)

@export var sprite_prefix: String = ""

# ── Pixel size ────────────────────────────────────────────────────────────────
# Avatar PNGs are ~433×688px. 0.0045 px/unit → ~3.1 units tall (≈ 3 voxels).
const SPRITE_PIXEL_SIZE := 0.0045

# ── Walk animation ────────────────────────────────────────────────────────────
const WALK_FRAME_TIME := 0.25   # seconds between mirror flips

# ── All known pose suffixes (missing files are silently skipped) ──────────────
const ALL_POSES: Array = [
	"", "_back", "_run", "_run_back",
	"_side_1", "_side_2",
	"_attack", "_ready",
	"_jumping", "_jumping_back",
	"_sad", "_worried", "_happy", "_angry", "_thumbs_up",
]

# ── Per-instance texture cache ────────────────────────────────────────────────
var _tex: Dictionary = {}   # suffix (String) → Texture2D

# ── State ─────────────────────────────────────────────────────────────────────
var _is_dead:      bool   = false
var _is_walking:   bool   = false
var _is_sideways:  bool   = false   # true when moving left/right
var _has_side:     bool   = false   # true when _side_1 + _side_2 textures exist
var _current_pose: String = ""      # active suffix
var _last_face:    String = "sw"    # "sw", "ne", "side_r", "side_l"
var _walk_timer:   float  = 0.0
var _walk_flip:    bool   = false   # current frame / mirror state


func _ready() -> void:
	billboard       = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter  = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pixel_size      = SPRITE_PIXEL_SIZE
	render_priority = 2   # draw on top of grid tiles (priority 1)

	# Drop shadow at feet
	_add_drop_shadow()

	if sprite_prefix != "":
		setup(sprite_prefix)


## Load all pose textures from `prefix` and show the idle pose.
## Safe to call at any time to swap race / gender.
func setup(prefix: String) -> void:
	sprite_prefix = prefix
	_tex.clear()
	for suffix in ALL_POSES:
		var path: String = prefix + suffix + ".png"
		if ResourceLoader.exists(path):
			_tex[suffix] = load(path) as Texture2D
	_has_side    = _tex.has("_side_1") and _tex.has("_side_2")
	_is_dead     = false
	_is_walking  = false
	_is_sideways = false
	_walk_timer  = 0.0
	_walk_flip   = false
	_last_face   = "sw"
	flip_h       = false
	_apply_pose("")


## Called every physics frame by the controller.
## move_dir is the entity's flat (XZ) movement vector; pass Vector3.ZERO when still.
## cam_forward / cam_right are the camera's world-space axes (flat, normalised).
func update_direction(move_dir: Vector3, cam_forward: Vector3, cam_right: Vector3) -> void:
	if _is_dead:
		return

	var flat := Vector3(move_dir.x, 0.0, move_dir.z)
	_is_walking = flat.length_squared() > 0.01

	if not _is_walking:
		_to_idle()
		return

	flat = flat.normalized()
	var fwd_dot: float = flat.dot(cam_forward)
	var rgt_dot: float = flat.dot(cam_right)

	if absf(fwd_dot) >= absf(rgt_dot):
		_is_sideways = false
		if fwd_dot > 0.0:
			# Moving away from camera — NE
			if _last_face != "ne":
				_walk_flip  = false
				_walk_timer = 0.0
			_last_face = "ne"
			flip_h     = _walk_flip
			_apply_pose("_run_back")
		else:
			# Moving toward camera — SW
			if _last_face != "sw":
				_walk_flip  = false
				_walk_timer = 0.0
			_last_face = "sw"
			flip_h     = _walk_flip
			_apply_pose("_run")
	else:
		# Sideways: flip_h encodes direction; 2-frame cycle if side sprites exist
		_is_sideways = true
		var going_right: bool  = rgt_dot > 0.0
		var new_face:    String = "side_r" if going_right else "side_l"
		if _last_face != new_face:
			_walk_flip  = false
			_walk_timer = 0.0
		_last_face = new_face
		flip_h     = not going_right   # sprites face right; flip for leftward movement
		if _has_side:
			_apply_pose("_side_1" if not _walk_flip else "_side_2")
		else:
			_apply_pose("_run")


func _process(delta: float) -> void:
	if not _is_walking or _is_dead:
		return
	if _is_sideways and not _has_side:
		return   # no side sprites — static _run fallback, nothing to animate
	_walk_timer += delta
	if _walk_timer >= WALK_FRAME_TIME:
		_walk_timer = 0.0
		_walk_flip  = not _walk_flip
		if _is_sideways:
			_apply_pose("_side_1" if not _walk_flip else "_side_2")
		else:
			flip_h = _walk_flip


## Freeze on dead/defeated pose.
func set_dead() -> void:
	_is_dead    = true
	_is_walking = false
	flip_h      = false
	if _tex.has("_sad"):
		_apply_pose("_sad")
	elif _tex.has("_worried"):
		_apply_pose("_worried")
	else:
		_apply_pose("")


## Switch to the combat-ready idle.
func set_ready() -> void:
	if _is_dead:
		return
	_is_walking = false
	flip_h      = false
	_apply_pose("_ready")


## Briefly flash the attack pose then restore the previous pose.
func play_attack_flash() -> void:
	if _is_dead or not _tex.has("_attack"):
		return
	var prev_pose: String = _current_pose
	var prev_flip: bool   = flip_h
	flip_h      = false
	_is_walking = false
	_apply_pose("_attack")
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_instance_valid(self) and not _is_dead:
			flip_h = prev_flip
			_apply_pose(prev_pose)
	)


## Set any pose by suffix — useful for dialogue ("_happy", "_thumbs_up", etc.).
func set_pose(suffix: String) -> void:
	if _is_dead:
		return
	_is_walking = false
	_apply_pose(suffix)


# ── Internals ─────────────────────────────────────────────────────────────────

func _apply_pose(suffix: String) -> void:
	_current_pose = suffix
	if _tex.has(suffix):
		texture = _tex[suffix]
	elif _tex.has(""):
		texture = _tex[""]   # fallback to base idle


func _to_idle() -> void:
	_is_walking  = false
	_walk_flip   = false
	_walk_timer  = 0.0
	flip_h       = false
	if _last_face == "ne" and _tex.has("_back"):
		_apply_pose("_back")
	else:
		_apply_pose("")


## Add a flat dark ellipse below the sprite as a drop shadow.
func _add_drop_shadow() -> void:
	if GraphicsManager and GraphicsManager.current_preset == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Shadow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.9, 0.55)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	# Sprite origin is at transform.origin.y (1.1 in player.tscn), shadow at ground
	mi.position = Vector3(0, -1.05, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
