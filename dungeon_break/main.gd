extends Node
## Dungeon Break entry point — manages scene transitions (save slots → char select → camp ↔ dungeon).

const CharSelectScene  = preload("res://dungeon_break/ui/character_select.tscn")
const CampScene        = preload("res://dungeon_break/game.tscn")
const DungeonScene     = preload("res://dungeon_break/dungeon.tscn")
const SaveSlotUIScript = preload("res://dungeon_break/ui/save_slot_ui.gd")

var _current_scene: Node = null

# ── Dungeon load transition overlay ───────────────────────────────────────────
const DungeonLoadShader   = preload("res://dungeon_break/ui/dungeon_load_transition.gdshader")
const DungeonLoadBgShader = preload("res://dungeon_break/ui/dungeon_load_bg.gdshader")
var _load_overlay_layer: CanvasLayer = null
var _load_solid_rect: ColorRect = null    # solid base — stops grey dungeon showing through shader edges
var _load_bg_rect: ColorRect = null       # pixelated warped fractal — animates while dungeon generates
var _load_bg_mat: ShaderMaterial = null
var _load_wipe_rect: ColorRect = null     # fractal noise wipe — plays when dungeon is ready
var _load_wipe_mat: ShaderMaterial = null
var _load_floor_label: Label = null       # "Floor X" text shown during loading

# ── Screenshot overlay ────────────────────────────────────────────────────────
var _screenshot_layer: CanvasLayer = null
var _screenshot_toast_panel: PanelContainer = null
var _screenshot_toast_title: Label = null
var _screenshot_toast_sub: Label = null
var _screenshot_toast_tween: Tween = null
var _screenshot_dir_path: String = ""


func _ready():
	_build_load_overlay()
	_build_screenshot_overlay()
	_show_save_slots()


func _build_load_overlay():
	_load_overlay_layer = CanvasLayer.new()
	_load_overlay_layer.layer = 64  # above game, below screenshot toast
	add_child(_load_overlay_layer)

	# 1 — Solid base (blocks grey dungeon; bg shader has transparent vignette edges)
	_load_solid_rect = ColorRect.new()
	_load_solid_rect.color = Color(0.02, 0.01, 0.06)
	_load_solid_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_solid_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_load_solid_rect.visible = false
	_load_overlay_layer.add_child(_load_solid_rect)

	# 2 — Animated loading background: pixelated warped fractal
	_load_bg_mat = ShaderMaterial.new()
	_load_bg_mat.shader = DungeonLoadBgShader
	_load_bg_mat.set_shader_parameter("speed", 0.08)
	_load_bg_mat.set_shader_parameter("zoom", 2.0)
	_load_bg_mat.set_shader_parameter("pixelation", 6.0)
	_load_bg_mat.set_shader_parameter("color_low",  Color(0.02, 0.04, 0.22, 1.0))
	_load_bg_mat.set_shader_parameter("color_mid",  Color(0.28, 0.02, 0.24, 1.0))
	_load_bg_mat.set_shader_parameter("color_high", Color(0.55, 0.45, 0.85, 1.0))

	_load_bg_rect = ColorRect.new()
	_load_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_bg_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_load_bg_rect.material = _load_bg_mat
	_load_bg_rect.visible = false
	_load_overlay_layer.add_child(_load_bg_rect)

	# 3 — Wipe transition: fractal noise band sweeps diagonally to reveal dungeon
	_load_wipe_mat = ShaderMaterial.new()
	_load_wipe_mat.shader = DungeonLoadShader
	_load_wipe_mat.set_shader_parameter("progress", 0.0)
	_load_wipe_mat.set_shader_parameter("color", Color(0.02, 0.01, 0.06, 1.0))
	_load_wipe_mat.set_shader_parameter("zoom", 2.5)
	_load_wipe_mat.set_shader_parameter("speed", 0.08)

	_load_wipe_rect = ColorRect.new()
	_load_wipe_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_wipe_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_wipe_rect.material = _load_wipe_mat
	_load_wipe_rect.visible = false
	_load_overlay_layer.add_child(_load_wipe_rect)

	# 4 — Floor label: centered text showing current floor number
	_load_floor_label = Label.new()
	_load_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_floor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_load_floor_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_floor_label.add_theme_font_size_override("font_size", 48)
	_load_floor_label.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	_load_floor_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	_load_floor_label.add_theme_constant_override("shadow_offset_x", 2)
	_load_floor_label.add_theme_constant_override("shadow_offset_y", 2)
	_load_floor_label.visible = false
	_load_overlay_layer.add_child(_load_floor_label)


func _show_load_overlay():
	_load_solid_rect.visible = true
	_load_bg_rect.visible = true
	_load_wipe_rect.visible = false
	_load_floor_label.text = "Floor %d" % GameData.current_floor
	_load_floor_label.visible = true


func _hide_load_overlay():
	# The wipe shader sweeps a fractal band diagonally (transparent → full coverage at p=0.5 → transparent).
	# Phase 1 (0→0.5): band enters and covers the loading bg.
	# Phase 2 (0.5→1.0): band exits, revealing the dungeon beneath.
	_load_wipe_mat.set_shader_parameter("progress", 0.0)
	_load_wipe_rect.visible = true

	var tw := create_tween()
	tw.tween_method(
		func(v: float): _load_wipe_mat.set_shader_parameter("progress", v),
		0.0, 0.5, 0.75)
	# Band fully covers screen — safe to hide the loading bg and label
	tw.tween_callback(func():
		_load_bg_rect.visible = false
		_load_solid_rect.visible = false
		_load_floor_label.visible = false)
	tw.tween_method(
		func(v: float): _load_wipe_mat.set_shader_parameter("progress", v),
		0.5, 1.0, 0.75)
	tw.tween_callback(func(): _load_wipe_rect.visible = false)


func _build_screenshot_overlay():
	_screenshot_layer = CanvasLayer.new()
	_screenshot_layer.layer = 128  # above everything
	add_child(_screenshot_layer)

	_screenshot_toast_panel = PanelContainer.new()
	_screenshot_toast_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_screenshot_toast_panel.offset_left = 12
	_screenshot_toast_panel.offset_top = 12
	_screenshot_toast_panel.offset_right = 440
	_screenshot_toast_panel.offset_bottom = 86
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.04, 0.05, 0.09, 0.96)
	ts.border_color = Color(0.35, 0.55, 0.9, 0.96)
	ts.set_border_width_all(2)
	ts.set_corner_radius_all(7)
	ts.set_content_margin(SIDE_LEFT, 10)
	ts.set_content_margin(SIDE_RIGHT, 10)
	ts.set_content_margin(SIDE_TOP, 8)
	ts.set_content_margin(SIDE_BOTTOM, 8)
	_screenshot_toast_panel.add_theme_stylebox_override("panel", ts)
	_screenshot_toast_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_screenshot_toast_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_screenshot_toast_panel.visible = false
	_screenshot_toast_panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _screenshot_dir_path != "":
				_open_folder(_screenshot_dir_path)
	)
	_screenshot_layer.add_child(_screenshot_toast_panel)

	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 2)
	_screenshot_toast_panel.add_child(vv)

	_screenshot_toast_title = Label.new()
	_screenshot_toast_title.add_theme_font_size_override("font_size", 14)
	_screenshot_toast_title.add_theme_color_override("font_color", Color(0.78, 0.92, 1.0))
	vv.add_child(_screenshot_toast_title)

	_screenshot_toast_sub = Label.new()
	_screenshot_toast_sub.add_theme_font_size_override("font_size", 12)
	_screenshot_toast_sub.add_theme_color_override("font_color", Color(0.66, 0.74, 0.86))
	_screenshot_toast_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vv.add_child(_screenshot_toast_sub)


func _input(event: InputEvent):
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: int = event.keycode
	if kc == KEY_S and event.ctrl_pressed:
		get_viewport().set_input_as_handled()
		_take_screenshot()


func _take_screenshot():
	# Ensure screenshots folder exists
	_screenshot_dir_path = OS.get_user_data_dir() + "/screenshots"
	var dir_path: String = _screenshot_dir_path
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# Build filename from current timestamp
	var dt := Time.get_datetime_dict_from_system()
	var filename: String = "shot_%04d%02d%02d_%02d%02d%02d.png" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second]
	var full_path: String = dir_path + "/" + filename

	# Capture and save
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(full_path)

	if err == OK:
		print("Screenshot saved: %s" % full_path)
		_show_screenshot_toast("Screenshot Saved", "%s  (click to open folder)" % filename)
	else:
		print("Screenshot failed (error %d)" % err)
		_show_screenshot_toast("Screenshot Failed", "Could not write PNG file.")


func _open_folder(path: String) -> void:
	var platform := OS.get_name()
	if platform == "Linux" or platform == "FreeBSD":
		var desktop: String = OS.get_environment("XDG_CURRENT_DESKTOP").to_lower()
		var cmd: String = "xdg-open"
		if "kde" in desktop:
			cmd = "dolphin"
		elif "gnome" in desktop or "unity" in desktop:
			cmd = "nautilus"
		elif "xfce" in desktop:
			cmd = "thunar"
		elif "lxde" in desktop or "lxqt" in desktop:
			cmd = "pcmanfm"
		OS.create_process(cmd, [path])
	else:
		OS.shell_open(path)  # Windows / macOS work fine with shell_open


func _show_screenshot_toast(title: String, subtitle: String):
	if _screenshot_toast_panel == null:
		return
	if _screenshot_toast_tween and _screenshot_toast_tween.is_valid():
		_screenshot_toast_tween.kill()

	if _screenshot_toast_title:
		_screenshot_toast_title.text = title
	if _screenshot_toast_sub:
		_screenshot_toast_sub.text = subtitle
	_screenshot_toast_panel.modulate.a = 1.0
	_screenshot_toast_panel.visible = true

	_screenshot_toast_tween = create_tween()
	_screenshot_toast_tween.tween_interval(2.2)
	_screenshot_toast_tween.tween_property(_screenshot_toast_panel, "modulate:a", 0.0, 0.45)
	_screenshot_toast_tween.tween_callback(func():
		if _screenshot_toast_panel:
			_screenshot_toast_panel.visible = false
	)


## Show the save slot selection screen.
func _show_save_slots():
	_clear_current()
	var ui := SaveSlotUIScript.new()
	ui.name = "SaveSlotUI"
	add_child(ui)
	_current_scene = ui
	ui.new_game_requested.connect(_on_new_game_requested)
	ui.load_game_requested.connect(_on_load_game_requested)


func _on_new_game_requested(slot: int):
	GameData.save_slot = slot
	_show_character_select()


func _on_load_game_requested(slot: int):
	var data := SaveManager.load_game(slot)
	if data.is_empty():
		_show_save_slots()
		return
	GameData.from_save_dict(data)
	GameData.save_slot = slot
	print("Main: loaded slot %d — scene=%s floor=%d" % [slot, GameData.scene_state, GameData.current_floor])
	if GameData.scene_state == "dungeon":
		_load_dungeon(GameData.current_floor)
	else:
		_load_camp()


## Show the race/gender/name selection screen.
func _show_character_select():
	_clear_current()
	var sel = CharSelectScene.instantiate()
	sel.name = "CharacterSelect"
	add_child(sel)
	_current_scene = sel
	sel.confirmed.connect(_on_character_select_confirmed)


func _on_character_select_confirmed():
	_load_camp()


## Load the camp scene.
func _load_camp():
	_clear_current()
	EntityManager.despawn_all()

	var camp = CampScene.instantiate()
	camp.name = "Camp"
	add_child(camp)
	_current_scene = camp

	# Connect the portal trigger from camp
	camp.connect("enter_dungeon", _on_enter_dungeon)
	print("Main: camp loaded")


## Load a dungeon floor.
func _load_dungeon(floor_num: int):
	_show_load_overlay()
	_clear_current()
	EntityManager.despawn_all()

	var dungeon = DungeonScene.instantiate()
	dungeon.name = "Dungeon"
	dungeon.set_floor(floor_num)
	add_child(dungeon)
	_current_scene = dungeon

	dungeon.return_to_camp.connect(_on_return_to_camp)
	dungeon.advance_floor.connect(_on_advance_floor)
	dungeon.dungeon_ready.connect(_hide_load_overlay, CONNECT_ONE_SHOT)
	print("Main: dungeon floor %d loaded" % floor_num)


func _clear_current():
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null


## Signal handlers ────────────────────────────────────────────────────────────

func _on_enter_dungeon():
	GameData.in_dungeon = true
	# Skip floors the player has fully cleared (all clearable rooms beaten)
	while GameData.is_floor_cleared(GameData.current_floor):
		GameData.current_floor += 1
		GameData.dungeon_seed = 0
	_load_dungeon(GameData.current_floor)


func _on_return_to_camp():
	GameData.in_dungeon = false
	_load_camp()


func _on_advance_floor():
	var rescued := GameData.rescue_random_npc()
	if rescued != "":
		var npc_def: Dictionary = NpcDB.get_def(rescued)
		print("Main: rescued — %s (%s)" % [npc_def.get("name", rescued), rescued])
	_load_dungeon(GameData.current_floor)
