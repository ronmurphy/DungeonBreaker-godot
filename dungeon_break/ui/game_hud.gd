extends CanvasLayer
## Game HUD — minimal persistent overlay.
##
## Camp:   time icon + clock + ⚙ button (top-right). Nothing else.
## Dungeon: same top-right + hero panel (bottom-right, always visible).
## Both:   interaction prompt (centre-bottom, shown on demand).

const TIME_ICONS := {
	"Morning"   : "res://assets/art/time/sun.png",
	"Afternoon" : "res://assets/art/time/sun.png",
	"Evening"   : "res://assets/art/time/dusk.png",
	"Night"     : "res://assets/art/time/moon.png",
}

var _prompt_label: Label = null
var _time_label: Label = null
var _time_icon: TextureRect = null
var _settings_modal: Control = null
var _preset_buttons: Array[Button] = []

# Hero panel (bottom-right, dungeon mode only)
var _hero_panel: PanelContainer = null
var _hero_hp_fill: ColorRect = null
var _hero_hp_label: Label = null
var _hero_stats_label: Label = null
var _hero_panel_style: StyleBoxFlat = null


func _ready():
	_build_ui()


func _build_ui():
	# ── Top-right: time icon + time text + settings button ──
	var time_bar := HBoxContainer.new()
	time_bar.name = "TimeBar"
	time_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	time_bar.offset_left   = -220
	time_bar.offset_right  = -8
	time_bar.offset_top    = 6
	time_bar.offset_bottom = 32
	time_bar.alignment = BoxContainer.ALIGNMENT_END
	time_bar.add_theme_constant_override("separation", 6)
	add_child(time_bar)

	_time_icon = TextureRect.new()
	_time_icon.name = "TimeIcon"
	_time_icon.custom_minimum_size = Vector2(22, 22)
	_time_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_time_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	time_bar.add_child(_time_icon)

	_time_label = Label.new()
	_time_label.name = "TimeLabel"
	_time_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
	_time_label.add_theme_font_size_override("font_size", 14)
	_time_label.add_theme_constant_override("shadow_offset_x", 1)
	_time_label.add_theme_constant_override("shadow_offset_y", 1)
	_time_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	time_bar.add_child(_time_label)

	var gear_btn := Button.new()
	gear_btn.name = "GearButton"
	gear_btn.text = "⚙"
	gear_btn.custom_minimum_size = Vector2(26, 26)
	gear_btn.add_theme_font_size_override("font_size", 16)
	var gear_style := StyleBoxFlat.new()
	gear_style.bg_color = Color(0.08, 0.06, 0.12, 0.85)
	gear_style.border_color = Color(0.5, 0.4, 0.6)
	gear_style.set_border_width_all(1)
	gear_style.set_corner_radius_all(4)
	gear_style.set_content_margin_all(2)
	gear_btn.add_theme_stylebox_override("normal", gear_style)
	var gear_hover := gear_style.duplicate()
	gear_hover.bg_color = Color(0.15, 0.1, 0.22, 0.95)
	gear_btn.add_theme_stylebox_override("hover", gear_hover)
	gear_btn.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	gear_btn.pressed.connect(_toggle_settings_modal)
	time_bar.add_child(gear_btn)

	# ── Centre-bottom: interaction prompt ──
	_prompt_label = Label.new()
	_prompt_label.name = "PromptLabel"
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.position = Vector2(-100, -60)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.add_theme_constant_override("shadow_offset_x", 2)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 2)
	_prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.visible = false
	add_child(_prompt_label)

	# ── Hero panel (bottom-right, hidden until set_dungeon_mode(true)) ──
	_build_hero_panel()

	# ── Settings modal ──
	_build_settings_modal()


func _build_hero_panel():
	_hero_panel = PanelContainer.new()
	_hero_panel.name = "HeroPanel"
	_hero_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hero_panel.offset_left   = -248
	_hero_panel.offset_right  = -8
	_hero_panel.offset_top    = -88
	_hero_panel.offset_bottom = -8
	_hero_panel.visible = false

	_hero_panel_style = StyleBoxFlat.new()
	_hero_panel_style.bg_color = Color(0.02, 0.07, 0.04, 0.92)
	_hero_panel_style.border_color = Color(0.25, 0.65, 0.38)
	_hero_panel_style.set_border_width_all(2)
	_hero_panel_style.set_corner_radius_all(5)
	_hero_panel_style.set_content_margin_all(8)
	_hero_panel.add_theme_stylebox_override("panel", _hero_panel_style)
	add_child(_hero_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	_hero_panel.add_child(hbox)

	# Portrait
	var portrait := TextureRect.new()
	portrait.name = "HeroPortrait"
	portrait.custom_minimum_size = Vector2(56, 56)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	const PORTRAIT_PATH := "res://assets/art/entities/human_male.png"
	if ResourceLoader.exists(PORTRAIT_PATH):
		portrait.texture = load(PORTRAIT_PATH)
	hbox.add_child(portrait)

	# Stats column
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	# Name + class
	_hero_stats_label = Label.new()
	_hero_stats_label.add_theme_font_size_override("font_size", 12)
	_hero_stats_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.68))
	vbox.add_child(_hero_stats_label)

	# HP bar
	var bar_bg := Control.new()
	bar_bg.custom_minimum_size = Vector2(0, 8)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_bg_rect := ColorRect.new()
	bar_bg_rect.color = Color(0.06, 0.06, 0.06)
	bar_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(bar_bg_rect)
	_hero_hp_fill = ColorRect.new()
	_hero_hp_fill.color = Color(0.2, 0.8, 0.4)
	_hero_hp_fill.anchor_left   = 0.0
	_hero_hp_fill.anchor_top    = 0.0
	_hero_hp_fill.anchor_right  = 1.0
	_hero_hp_fill.anchor_bottom = 1.0
	bar_bg.add_child(_hero_hp_fill)
	vbox.add_child(bar_bg)

	# HP / AC / ATK line
	_hero_hp_label = Label.new()
	_hero_hp_label.add_theme_font_size_override("font_size", 11)
	_hero_hp_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.65))
	vbox.add_child(_hero_hp_label)


## Call once after the HUD is added — shows/hides the hero stats panel.
func set_dungeon_mode(on: bool) -> void:
	if _hero_panel:
		_hero_panel.visible = on


func _build_settings_modal():
	var overlay := ColorRect.new()
	overlay.name = "SettingsOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)

	var modal := PanelContainer.new()
	modal.name = "SettingsModal"
	var modal_style := StyleBoxFlat.new()
	modal_style.bg_color = Color(0.06, 0.04, 0.1, 0.97)
	modal_style.border_color = Color(0.55, 0.45, 0.7)
	modal_style.set_border_width_all(2)
	modal_style.set_corner_radius_all(8)
	modal_style.set_content_margin_all(20)
	modal.add_theme_stylebox_override("panel", modal_style)
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.offset_left   = -160
	modal.offset_right  = 160
	modal.offset_top    = -110
	modal.offset_bottom = 110
	overlay.add_child(modal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	modal.add_child(vbox)

	var title := Label.new()
	title.text = "⚙  GRAPHICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 1.0))
	vbox.add_child(title)

	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.4, 0.3, 0.55)
	sep_style.set_content_margin_all(1)
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	var desc := Label.new()
	desc.name = "PresetDesc"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 11)
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(hbox)

	var preset_labels := ["Low", "Medium", "High"]
	var preset_descs := [
		"No SDFGI · No SSAO · No Glow",
		"No SDFGI · SSAO on · Glow on",
		"SDFGI on · SSAO on · Glow on",
	]
	_preset_buttons.clear()

	for i in 3:
		var btn := Button.new()
		btn.text = preset_labels[i]
		btn.custom_minimum_size = Vector2(80, 36)
		btn.add_theme_font_size_override("font_size", 14)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.1, 0.07, 0.18)
		normal.border_color = Color(0.4, 0.3, 0.55)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(5)
		normal.set_content_margin_all(6)
		btn.add_theme_stylebox_override("normal", normal)
		var hover := normal.duplicate()
		hover.bg_color = Color(0.18, 0.12, 0.3)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))

		var idx := i
		btn.pressed.connect(func():
			GraphicsManager.set_preset(idx)
			_refresh_preset_buttons()
			desc.text = preset_descs[GraphicsManager.current_preset]
		)
		_preset_buttons.append(btn)
		hbox.add_child(btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(80, 30)
	close_btn.add_theme_font_size_override("font_size", 13)
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.08, 0.05, 0.12)
	close_style.border_color = Color(0.35, 0.25, 0.45)
	close_style.set_border_width_all(1)
	close_style.set_corner_radius_all(4)
	close_style.set_content_margin_all(5)
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.add_theme_color_override("font_color", Color(0.65, 0.6, 0.75))
	close_btn.pressed.connect(_toggle_settings_modal)
	var close_hbox := HBoxContainer.new()
	close_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	close_hbox.add_child(close_btn)
	vbox.add_child(close_hbox)

	_settings_modal = overlay
	_refresh_preset_buttons()
	if desc:
		desc.text = preset_descs[GraphicsManager.current_preset]


func _toggle_settings_modal():
	if _settings_modal:
		_settings_modal.visible = not _settings_modal.visible
		if _settings_modal.visible:
			_refresh_preset_buttons()


func _refresh_preset_buttons():
	for i in _preset_buttons.size():
		var btn: Button = _preset_buttons[i]
		var is_active := (i == GraphicsManager.current_preset)
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(5)
		style.set_content_margin_all(6)
		if is_active:
			style.bg_color = Color(0.25, 0.15, 0.45)
			style.border_color = Color(0.75, 0.6, 1.0)
			style.set_border_width_all(2)
		else:
			style.bg_color = Color(0.1, 0.07, 0.18)
			style.border_color = Color(0.4, 0.3, 0.55)
			style.set_border_width_all(1)
		btn.add_theme_stylebox_override("normal", style)


func _process(_delta: float):
	_update_hero_panel()


func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _settings_modal and _settings_modal.visible:
			_settings_modal.visible = false
			get_viewport().set_input_as_handled()


func _update_hero_panel():
	if _hero_panel == null or not _hero_panel.visible:
		return

	var hp_ratio := clampf(float(GameData.hp) / float(max(GameData.hp_max, 1)), 0.0, 1.0)
	_hero_hp_fill.anchor_right = hp_ratio

	if hp_ratio > 0.6:
		_hero_hp_fill.color = Color(0.2, 0.8, 0.4)
		_hero_panel_style.border_color = Color(0.25, 0.65, 0.38)
	elif hp_ratio > 0.3:
		_hero_hp_fill.color = Color(0.85, 0.65, 0.1)
		_hero_panel_style.border_color = Color(0.75, 0.55, 0.18)
	else:
		_hero_hp_fill.color = Color(0.8, 0.15, 0.1)
		_hero_panel_style.border_color = Color(0.75, 0.2, 0.18)
	_hero_panel.add_theme_stylebox_override("panel", _hero_panel_style)

	var weapon_name: String = GameData.equip_weapon.get("name", "Unarmed") if GameData.equip_weapon else "Unarmed"
	var class_str: String = GameData.CLASS_NAMES.get(GameData.player_class, "Hero")
	_hero_stats_label.text = "%s  ·  %s  ·  Floor %d" % [GameData.player_name, class_str, GameData.current_floor]
	_hero_hp_label.text = "HP %d/%d   AC %d   ATK %d   %s" % [
		GameData.hp, GameData.hp_max,
		GameData.get_total_ac(),
		GameData.get_attack_power(),
		weapon_name]


## Update the time-of-day display (called by game.gd / dungeon.gd _process).
func set_time_text(text: String):
	if _time_label:
		_time_label.text = text
	if _time_icon:
		for period in TIME_ICONS:
			if text.begins_with(period):
				var path: String = TIME_ICONS[period]
				if ResourceLoader.exists(path):
					_time_icon.texture = load(path)
				break


## Show an interaction prompt.
func show_prompt(text: String):
	if _prompt_label:
		_prompt_label.text = text
		_prompt_label.visible = true


## Hide the interaction prompt.
func hide_prompt():
	if _prompt_label:
		_prompt_label.visible = false
