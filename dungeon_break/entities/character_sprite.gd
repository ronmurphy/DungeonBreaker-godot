extends Sprite3D
class_name CharacterSprite
## Direction-aware FFT-style sprite for player characters.
##
## Uses a 2-row 9-pose sprite sheet (see assets/REFS/spatial.json for layout).
## Selects the correct frame based on movement direction relative to the camera.
## Set sheet_path in the inspector or call setup() from code.

@export var sheet_path: String = ""

# ── Frame bounding boxes (from assets/REFS/spatial.json) ──────────────────────
# Row 0  (y = 0 … 771)
const FRAME_PORTRAIT := Rect2(   0, 0, 746, 771)  # UI only — not a game-world frame
const FRAME_IDLE_SW  := Rect2( 739, 0, 509, 771)  # front_idle  — SW (toward viewer)
const FRAME_IDLE_NE  := Rect2(1241, 0, 509, 771)  # back        — NE (away from viewer)
const FRAME_IDLE_NW  := Rect2(1743, 0, 509, 771)  # side_left   — NW
const FRAME_IDLE_SE  := Rect2(2245, 0, 507, 771)  # side_right  — SE

# Row 1  (y = 764 … 1536)
const FRAME_WALK_SW1 := Rect2(   0, 764, 691, 772)  # walk_front   — SW frame 1
const FRAME_WALK_SW2 := Rect2( 684, 764, 695, 772)  # walk_front_2 — SW frame 2
const FRAME_WALK_NE  := Rect2(1372, 764, 695, 772)  # walk_back    — NE
const FRAME_DEAD     := Rect2(2060, 764, 692, 772)  # prone_dead

const SHEET_PIXEL_SIZE := 0.002

# ── Internal state ─────────────────────────────────────────────────────────────
var _is_dead:    bool  = false
var _is_walking: bool  = false
var _walk_frame: int   = 0      # 0 = WALK_SW1, 1 = WALK_SW2
var _walk_timer: float = 0.0
const WALK_FRAME_TIME := 0.22   # seconds per SW walk frame


func _ready() -> void:
	billboard      = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	region_enabled = true
	pixel_size     = SHEET_PIXEL_SIZE
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
		# Standing still — convert the current walk frame to its idle counterpart
		_to_idle()
		return

	flat = flat.normalized()

	# Project onto camera axes to get screen-relative direction.
	# fwd_dot > 0 → moving away from camera (NE)
	# fwd_dot < 0 → moving toward camera   (SW)
	# rgt_dot > 0 → moving screen-right    (SE)
	# rgt_dot < 0 → moving screen-left     (NW)
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
	# Only SW has a 2-frame walk cycle; NE/NW/SE use static frames
	if region_rect == FRAME_WALK_SW1 or region_rect == FRAME_WALK_SW2:
		_walk_timer += delta
		if _walk_timer >= WALK_FRAME_TIME:
			_walk_timer  = 0.0
			_walk_frame  = 1 - _walk_frame
			region_rect  = FRAME_WALK_SW1 if _walk_frame == 0 else FRAME_WALK_SW2


# ── Internal helpers ───────────────────────────────────────────────────────────

func _show_walk_sw() -> void:
	flip_h      = false
	region_rect = FRAME_WALK_SW1 if _walk_frame == 0 else FRAME_WALK_SW2

func _show_walk_ne() -> void:
	flip_h      = false
	region_rect = FRAME_WALK_NE

func _show_idle_nw() -> void:
	flip_h      = false
	region_rect = FRAME_IDLE_NW

func _show_idle_se() -> void:
	flip_h      = false
	region_rect = FRAME_IDLE_SE

func _to_idle() -> void:
	# Map the current walk/lateral frame to its idle equivalent
	if region_rect == FRAME_WALK_SW1 or region_rect == FRAME_WALK_SW2:
		region_rect = FRAME_IDLE_SW
	elif region_rect == FRAME_WALK_NE:
		region_rect = FRAME_IDLE_NE
	# NW and SE are already idle frames — leave them as-is
