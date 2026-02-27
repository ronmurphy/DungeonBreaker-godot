extends Camera3D
## Isometric follow camera for Dungeon Break.
##
## Follows a target node from an isometric angle.
## Q/E rotates the camera 90° around the player.
## Scroll wheel controls zoom distance.

## The node we follow (set by player scene)
@export var target_path: NodePath

## Starting yaw in degrees. Q/E rotate in 90° steps.
@export var yaw_degrees: float = 45.0

## Camera pitch (degrees from horizontal). ~35.26° = true isometric; 40 feels good for gameplay.
## Use R/F keys to tilt up/down in 5° steps.
@export var pitch_degrees: float = 40.0
@export var min_pitch: float = 15.0
@export var max_pitch: float = 75.0
@export var pitch_step: float = 5.0

## Distance from target
@export var distance: float = 25.0
@export var min_distance: float = 10.0
@export var max_distance: float = 60.0
@export var zoom_speed: float = 2.0

## How quickly the camera catches up to the player (0–1, lower = smoother)
@export var follow_smoothing: float = 0.08

## How quickly the yaw animates to the target (0–1 per frame)
@export var rotation_smoothing: float = 0.12

## Vertical offset so camera looks slightly above the player's feet
@export var target_offset := Vector3(0.0, 1.5, 0.0)

var _target: Node3D = null

## The actual rendered yaw (smoothly lerps toward _target_yaw)
var _current_yaw: float = 45.0

## Where Q/E drives us to (snaps in 90° increments)
var _target_yaw: float = 45.0

## Signal emitted when yaw changes so player controller can stay aligned
signal yaw_changed(new_yaw: float)

## Combat mode: locks R/T pitch controls and resets pitch to default
var _combat_locked := false
var _pre_combat_pitch := 0.0
var _pre_combat_distance := 0.0
var _zoom_tween: Tween = null

## Distance to snap to when combat begins (close enough to see the tactical grid clearly)
const COMBAT_DISTANCE := 18.0


func _ready():
	top_level = true
	_current_yaw = yaw_degrees
	_target_yaw = yaw_degrees

	if target_path != NodePath(""):
		_target = get_node_or_null(target_path)


func set_follow_target(node: Node3D):
	_target = node


## Returns the current rendered camera yaw in degrees.
func get_current_yaw() -> float:
	return _current_yaw


## Enable or disable combat mode.
## On enable: saves pitch + zoom, snaps pitch to default, animates zoom in.
## On disable: restores pitch. Zoom-out is deferred — call restore_zoom() after
##             walls have faded back to opaque, so the reveal feels intentional.
func set_combat_mode(enabled: bool) -> void:
	_combat_locked = enabled
	if enabled:
		_pre_combat_pitch = pitch_degrees
		_pre_combat_distance = distance
		pitch_degrees = 40.0
		_zoom_tween_to(COMBAT_DISTANCE, 0.45)
	else:
		pitch_degrees = _pre_combat_pitch
		# Zoom-out happens in restore_zoom(), called by dungeon.gd after wall fade


## Animate zoom back to the distance the player had before combat.
## Call this after the wall-opacity restore tween has finished.
func restore_zoom() -> void:
	_zoom_tween_to(_pre_combat_distance, 0.6)


func _zoom_tween_to(target_dist: float, duration: float) -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(self, "distance", target_dist, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and not _combat_locked:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				distance = max(distance - zoom_speed - distance * 0.05, min_distance)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				distance = min(distance + zoom_speed + distance * 0.05, max_distance)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_target_yaw -= 90.0
			_current_yaw = _target_yaw  # Snap immediately so frustum culling is correct
			yaw_changed.emit(_target_yaw)
		elif event.keycode == KEY_E:
			_target_yaw += 90.0
			_current_yaw = _target_yaw  # Snap immediately so frustum culling is correct
			yaw_changed.emit(_target_yaw)
		elif event.keycode == KEY_R and not _combat_locked:
			pitch_degrees = clampf(pitch_degrees + pitch_step, min_pitch, max_pitch)
		elif event.keycode == KEY_T and not _combat_locked:
			pitch_degrees = clampf(pitch_degrees - pitch_step, min_pitch, max_pitch)


func _process(delta: float):
	# Smoothly animate yaw toward the target
	_current_yaw = lerp(_current_yaw, _target_yaw, rotation_smoothing)
	# Snap when very close to avoid perpetual drift
	if absf(_current_yaw - _target_yaw) < 0.05:
		_current_yaw = _target_yaw

	if _target == null:
		return

	var target_pos: Vector3 = _target.global_position + target_offset

	# Compute camera offset from angles
	var yaw_rad := deg_to_rad(_current_yaw)
	var pitch_rad := deg_to_rad(pitch_degrees)

	var offset := Vector3()
	offset.x = cos(pitch_rad) * sin(yaw_rad) * distance
	offset.z = cos(pitch_rad) * cos(yaw_rad) * distance
	offset.y = sin(pitch_rad) * distance

	var desired_pos := target_pos + offset

	# Smooth follow
	global_position = global_position.lerp(desired_pos, follow_smoothing)

	# Always look at the target
	look_at(target_pos, Vector3.UP)
