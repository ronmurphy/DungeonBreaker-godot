extends Node
## Graphics settings singleton — controls SDFGI, SSAO, glow, MSAA via quality presets.
## Autoloaded as "GraphicsManager".
##
## Presets:
##   LOW    — MSAA off, SDFGI off, SSAO off, Glow off  (best for old GPUs)
##   MEDIUM — MSAA 2x, SDFGI off, SSAO on,  Glow on   (default)
##   HIGH   — MSAA 4x, SDFGI on,  SSAO on,  Glow on   (modern GPUs)

enum Preset { LOW, MEDIUM, HIGH }
enum TiltShift { OFF, SUBTLE, FULL }

const SAVE_PATH    := "user://graphics_settings.cfg"
const PRESET_NAMES := ["Low", "Medium", "High"]
const TILT_SHIFT_NAMES := ["Off", "Subtle", "Full"]

## Blur strength values per tilt-shift mode (uniform: blur_strength).
const TILT_SHIFT_STRENGTH := {
	TiltShift.OFF:    0.0,
	TiltShift.SUBTLE: 1.2,
	TiltShift.FULL:   2.4,
}

## Emitted after a preset change so the settings UI can refresh its buttons.
signal preset_changed(preset: int)
## Emitted when the tilt-shift mode changes.
signal tilt_shift_changed(mode: int)

var current_preset: int = Preset.MEDIUM
var tilt_shift_mode: int = TiltShift.OFF


func _ready():
	_load_settings()
	# Apply after one frame so WorldEnvironment nodes are in the tree
	call_deferred("_apply_current")
	# Auto-apply whenever a new WorldEnvironment is added (scene change)
	get_tree().node_added.connect(_on_node_added)


# ── Public API ────────────────────────────────────────────────────────────────

func set_preset(preset: int) -> void:
	current_preset = clampi(preset, Preset.LOW, Preset.HIGH)
	# Auto-set tilt-shift default for the preset (user can override)
	match current_preset:
		Preset.LOW:    set_tilt_shift(TiltShift.OFF)
		Preset.MEDIUM: set_tilt_shift(TiltShift.SUBTLE)
		Preset.HIGH:   set_tilt_shift(TiltShift.FULL)
	_apply_current()
	_save_settings()
	preset_changed.emit(current_preset)


func set_tilt_shift(mode: int) -> void:
	tilt_shift_mode = clampi(mode, TiltShift.OFF, TiltShift.FULL)
	_save_settings()
	tilt_shift_changed.emit(tilt_shift_mode)


func get_tilt_shift_strength() -> float:
	return TILT_SHIFT_STRENGTH.get(tilt_shift_mode, 0.0)


## Returns reduced tilt-shift strength for combat readability.
func get_tilt_shift_combat_strength() -> float:
	# ~40% of normal so the effect is present but doesn't impair grid reading
	return get_tilt_shift_strength() * 0.4


func get_preset_name() -> String:
	return PRESET_NAMES[current_preset]


func get_tilt_shift_name() -> String:
	return TILT_SHIFT_NAMES[tilt_shift_mode]


# ── Persistence ───────────────────────────────────────────────────────────────

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		current_preset = clampi(
			cfg.get_value("graphics", "preset", Preset.MEDIUM),
			Preset.LOW, Preset.HIGH)
		tilt_shift_mode = clampi(
			cfg.get_value("graphics", "tilt_shift", TiltShift.OFF),
			TiltShift.OFF, TiltShift.FULL)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", current_preset)
	cfg.set_value("graphics", "tilt_shift", tilt_shift_mode)
	cfg.save(SAVE_PATH)


# ── Application ───────────────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment and node.environment != null:
		_configure_env(node.environment)


func _apply_current() -> void:
	# Viewport-level settings
	var vp := get_viewport()
	if vp:
		match current_preset:
			Preset.LOW:    vp.msaa_3d = Viewport.MSAA_DISABLED
			Preset.MEDIUM: vp.msaa_3d = Viewport.MSAA_2X
			Preset.HIGH:   vp.msaa_3d = Viewport.MSAA_4X

	# Walk the scene tree for all WorldEnvironments
	_walk_tree(get_tree().root)


func _walk_tree(node: Node) -> void:
	if node is WorldEnvironment and node.environment != null:
		_configure_env(node.environment)
	for child in node.get_children():
		_walk_tree(child)


func _configure_env(env: Environment) -> void:
	match current_preset:
		Preset.LOW:
			env.sdfgi_enabled  = false
			env.ssao_enabled   = false
			env.glow_enabled   = false
		Preset.MEDIUM:
			env.sdfgi_enabled  = false
			env.ssao_enabled   = true
			env.glow_enabled   = true
		Preset.HIGH:
			env.sdfgi_enabled  = true
			env.ssao_enabled   = true
			env.glow_enabled   = true
