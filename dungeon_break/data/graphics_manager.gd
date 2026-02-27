extends Node
## Graphics settings singleton — controls SDFGI, SSAO, glow, MSAA via quality presets.
## Autoloaded as "GraphicsManager".
##
## Presets:
##   LOW    — MSAA off, SDFGI off, SSAO off, Glow off  (best for old GPUs)
##   MEDIUM — MSAA 2x, SDFGI off, SSAO on,  Glow on   (default)
##   HIGH   — MSAA 4x, SDFGI on,  SSAO on,  Glow on   (modern GPUs)

enum Preset { LOW, MEDIUM, HIGH }

const SAVE_PATH    := "user://graphics_settings.cfg"
const PRESET_NAMES := ["Low", "Medium", "High"]

## Emitted after a preset change so the settings UI can refresh its buttons.
signal preset_changed(preset: int)

var current_preset: int = Preset.MEDIUM


func _ready():
	_load_settings()
	# Apply after one frame so WorldEnvironment nodes are in the tree
	call_deferred("_apply_current")
	# Auto-apply whenever a new WorldEnvironment is added (scene change)
	get_tree().node_added.connect(_on_node_added)


# ── Public API ────────────────────────────────────────────────────────────────

func set_preset(preset: int) -> void:
	current_preset = clampi(preset, Preset.LOW, Preset.HIGH)
	_apply_current()
	_save_settings()
	preset_changed.emit(current_preset)


func get_preset_name() -> String:
	return PRESET_NAMES[current_preset]


# ── Persistence ───────────────────────────────────────────────────────────────

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		current_preset = clampi(
			cfg.get_value("graphics", "preset", Preset.MEDIUM),
			Preset.LOW, Preset.HIGH)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", current_preset)
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
