extends Sprite3D
class_name CharacterSprite
## Direction-aware FFT-style sprite for player characters.
##
## Uses a 2-row 9-pose sprite sheet (see assets/REFS/spatial.json for layout).
## Selects the correct frame based on movement direction relative to the camera.
## Set sheet_path in the inspector or call setup() from code.
##
## Frame rects start at hardcoded defaults.  Place assets/REFS/ssheet.json
## (exported from ssheet_tool.html) to override them without recompiling.

@export var sheet_path: String = ""

# ── Frame bounding boxes ──────────────────────────────────────────────────────
# Declared as static var so ssheet.json can override them once at startup.
# Row 0  (y = 0 … 771)
static var FRAME_PORTRAIT: Rect2 = Rect2(   0, 0, 746, 771)  # UI portrait — not a world frame
static var FRAME_IDLE_SW:  Rect2 = Rect2( 739, 0, 509, 771)  # front idle  — toward viewer
static var FRAME_IDLE_NE:  Rect2 = Rect2(1241, 0, 509, 771)  # back idle   — away from viewer
static var FRAME_IDLE_NW:  Rect2 = Rect2(1743, 0, 509, 771)  # side left
static var FRAME_IDLE_SE:  Rect2 = Rect2(2245, 0, 507, 771)  # side right

# Row 1  (y = 764 … 1536)
static var FRAME_WALK_SW1: Rect2 = Rect2(   0, 764, 691, 772)  # walk front frame 1
static var FRAME_WALK_SW2: Rect2 = Rect2( 684, 764, 695, 772)  # walk front frame 2
static var FRAME_WALK_NE:  Rect2 = Rect2(1372, 764, 695, 772)  # walk back
static var FRAME_DEAD:     Rect2 = Rect2(2060, 764, 692, 772)  # prone / dead

const SHEET_PIXEL_SIZE := 0.002
const SSHEET_JSON_PATH := "res://assets/REFS/ssheet.json"

# ── ssheet.json load-once guard ──────────────────────────────────────────────
static var _ssheet_loaded: bool = false

# ── Per-instance state ────────────────────────────────────────────────────────
var _is_dead:    bool  = false
var _is_walking: bool  = false
var _walk_frame: int   = 0      # 0 = WALK_SW1, 1 = WALK_SW2
var _walk_timer: float = 0.0
const WALK_FRAME_TIME := 0.22   # seconds per SW walk frame


func _ready() -> void:
	_load_ssheet_once()
	billboard       = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter  = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	region_enabled  = true
	pixel_size      = SHEET_PIXEL_SIZE
	render_priority = 2  # Draw on top of grid tiles (priority 1)
	if sheet_path != "":
		setup(sheet_path)


## Load the sprite sheet and display the default idle (SW) pose.
## Can be called at any time to swap races/characters.
func setup(path: String) -> void:
	sheet_path = path
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("CharacterSprite: sheet not found — %s" % path)
		return
	texture = tex
	region_rect = FRAME_IDLE_SW
	flip_h = false


## Call every frame from the controller with the entity's flat movement vector
## and the camera's forward/right world-space vectors.
## Pass Vector3.ZERO for move_dir when the entity is standing still.
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
		if fwd_dot > 0.0:
			_show_walk_ne()
		else:
			_show_walk_sw()
	else:
		if rgt_dot > 0.0:
			_show_idle_se()
		else:
			_show_idle_nw()


## Freeze the sprite on the prone/dead frame.
func set_dead() -> void:
	_is_dead    = true
	_is_walking = false
	region_rect = FRAME_DEAD
	flip_h      = false


func _process(delta: float) -> void:
	if not _is_walking or _is_dead:
		return
	# SW: 2-frame cycle between WALK_SW1 and WALK_SW2
	if region_rect == FRAME_WALK_SW1 or region_rect == FRAME_WALK_SW2:
		_walk_timer += delta
		if _walk_timer >= WALK_FRAME_TIME:
			_walk_timer = 0.0
			_walk_frame = 1 - _walk_frame
			region_rect = FRAME_WALK_SW1 if _walk_frame == 0 else FRAME_WALK_SW2
	# NE (walk-up): 2-frame cycle using flip_h — frame 0 normal, frame 1 mirrored
	elif region_rect == FRAME_WALK_NE:
		_walk_timer += delta
		if _walk_timer >= WALK_FRAME_TIME:
			_walk_timer = 0.0
			_walk_frame = 1 - _walk_frame
			flip_h = (_walk_frame == 1)


# ── ssheet.json loader (runs once for all instances) ─────────────────────────

static func _load_ssheet_once() -> void:
	if _ssheet_loaded:
		return
	_ssheet_loaded = true

	if not FileAccess.file_exists(SSHEET_JSON_PATH):
		return  # no override file — use hardcoded defaults

	var file := FileAccess.open(SSHEET_JSON_PATH, FileAccess.READ)
	if file == null:
		push_warning("CharacterSprite: could not open %s" % SSHEET_JSON_PATH)
		return

	var text: String = file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("CharacterSprite: ssheet.json parse failed")
		return

	var root: Dictionary = parsed
	if not (root.has("frames") and root["frames"] is Dictionary):
		push_warning("CharacterSprite: ssheet.json missing 'frames' key")
		return

	var fd: Dictionary = root["frames"]

	FRAME_PORTRAIT = _rect_from(fd, "PORTRAIT",  FRAME_PORTRAIT)
	FRAME_IDLE_SW  = _rect_from(fd, "IDLE_SW",   FRAME_IDLE_SW)
	FRAME_IDLE_NE  = _rect_from(fd, "IDLE_NE",   FRAME_IDLE_NE)
	FRAME_IDLE_NW  = _rect_from(fd, "IDLE_NW",   FRAME_IDLE_NW)
	FRAME_IDLE_SE  = _rect_from(fd, "IDLE_SE",   FRAME_IDLE_SE)
	FRAME_WALK_SW1 = _rect_from(fd, "WALK_SW1",  FRAME_WALK_SW1)
	FRAME_WALK_SW2 = _rect_from(fd, "WALK_SW2",  FRAME_WALK_SW2)
	FRAME_WALK_NE  = _rect_from(fd, "WALK_NE",   FRAME_WALK_NE)
	FRAME_DEAD     = _rect_from(fd, "DEAD",       FRAME_DEAD)

	print("CharacterSprite: loaded frame overrides from ssheet.json")


## Build a Rect2 from a frames-dict entry, falling back to `default` for missing keys.
static func _rect_from(frames_dict: Dictionary, name: String, default_rect: Rect2) -> Rect2:
	if not frames_dict.has(name):
		return default_rect
	var entry = frames_dict[name]
	if not entry is Dictionary:
		return default_rect
	var d: Dictionary = entry
	return Rect2(
		float(d.get("x", default_rect.position.x)),
		float(d.get("y", default_rect.position.y)),
		float(d.get("w", default_rect.size.x)),
		float(d.get("h", default_rect.size.y)),
	)


# ── Internal show helpers ─────────────────────────────────────────────────────

func _show_walk_sw() -> void:
	flip_h      = false
	region_rect = FRAME_WALK_SW1 if _walk_frame == 0 else FRAME_WALK_SW2

func _show_walk_ne() -> void:
	# WALK_NE is the single up-walk frame; frame 2 is a flip_h mirror.
	region_rect = FRAME_WALK_NE
	flip_h      = (_walk_frame == 1)

func _show_idle_nw() -> void:
	# FACE_LEFT — the one side-facing pose on the sheet.
	flip_h      = false
	region_rect = FRAME_IDLE_NW

func _show_idle_se() -> void:
	# FACE_RIGHT — reuse IDLE_NW mirrored; IDLE_SE on the sheet is a duplicate
	# left-facing pose so we derive right-facing from flip_h instead.
	flip_h      = true
	region_rect = FRAME_IDLE_NW

func _to_idle() -> void:
	if region_rect == FRAME_WALK_SW1 or region_rect == FRAME_WALK_SW2:
		region_rect = FRAME_IDLE_SW
		flip_h      = false
	elif region_rect == FRAME_WALK_NE:
		region_rect = FRAME_IDLE_NE
		flip_h      = false  # reset the per-frame flip from the walk cycle
	# IDLE_NW (face-left) and IDLE_NW+flip_h (face-right) are already idle — leave them
