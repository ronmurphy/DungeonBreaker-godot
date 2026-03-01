extends CanvasLayer
## Save Slot UI — shown at startup. Player picks a slot to load or start fresh.
##
## Three slot cards side-by-side; occupied slots show character info + Load/New buttons.
## Empty slots show a single "New Game" button.

signal new_game_requested(slot: int)
signal load_game_requested(slot: int)

const CLASS_NAMES := [
	"Vanguard", "Scoundrel", "Arcanist", "Confessor",
	"Strider",  "Minstrel",  "Templar",  "Reanimator", "Tinkerer",
]

var _confirm_slot: int = -1   # slot awaiting overwrite confirmation


func _ready() -> void:
	_build_ui()
	visible = true


func _build_ui() -> void:
	# ── full-screen dark background ──
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_CENTER)
	root.offset_left   = -460
	root.offset_right  =  460
	root.offset_top    = -280
	root.offset_bottom =  280
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	# ── title ──
	var title := Label.new()
	title.text = "DUNGEON BREAK"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var sub := Label.new()
	sub.text = "Choose a save slot"
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.55, 0.52, 0.5))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(sub)

	# ── three slot cards ──
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 14)
	root.add_child(slots_row)

	for slot in SaveManager.MAX_SLOTS:
		var info: Dictionary = SaveManager.get_slot_info(slot)
		slots_row.add_child(_build_slot_card(slot, info))

	# ── quit row ──
	var quit_row := HBoxContainer.new()
	quit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(quit_row)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(100, 30)
	var qs := StyleBoxFlat.new()
	qs.bg_color = Color(0.1, 0.06, 0.06)
	qs.border_color = Color(0.4, 0.25, 0.2)
	qs.set_border_width_all(1)
	qs.set_corner_radius_all(4)
	qs.set_content_margin_all(6)
	quit_btn.add_theme_stylebox_override("normal", qs)
	quit_btn.add_theme_color_override("font_color", Color(0.7, 0.5, 0.5))
	quit_btn.pressed.connect(func(): get_tree().quit())
	quit_row.add_child(quit_btn)


func _build_slot_card(slot: int, info: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 220)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.07, 0.05, 0.11, 0.97)
	cs.border_color = Color(0.45, 0.38, 0.28)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(8)
	cs.set_content_margin_all(14)
	card.add_theme_stylebox_override("panel", cs)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	# Slot number label
	var slot_lbl := Label.new()
	slot_lbl.text = "SLOT  %d" % (slot + 1)
	slot_lbl.add_theme_font_size_override("font_size", 12)
	slot_lbl.add_theme_color_override("font_color", Color(0.45, 0.42, 0.55))
	slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(slot_lbl)

	col.add_child(HSeparator.new())

	if info.is_empty():
		_build_empty_slot(col, slot)
	else:
		_build_occupied_slot(col, slot, info)

	return card


func _build_empty_slot(col: VBoxContainer, slot: int) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var empty_lbl := Label.new()
	empty_lbl.text = "— EMPTY —"
	empty_lbl.add_theme_font_size_override("font_size", 16)
	empty_lbl.add_theme_color_override("font_color", Color(0.35, 0.33, 0.4))
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(empty_lbl)

	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer2)

	var new_btn := Button.new()
	new_btn.text = "New Game"
	new_btn.custom_minimum_size = Vector2(0, 36)
	_style_btn(new_btn, Color(0.3, 0.6, 0.35))
	new_btn.pressed.connect(func(): new_game_requested.emit(slot))
	col.add_child(new_btn)


func _build_occupied_slot(col: VBoxContainer, slot: int, info: Dictionary) -> void:
	# ── Portrait row: [hero portrait] [name/class/loc] [companion portrait] ──
	var portrait_row := HBoxContainer.new()
	portrait_row.add_theme_constant_override("separation", 6)
	col.add_child(portrait_row)

	# Hero portrait (left)
	var race: String = info.get("player_race", "human") as String
	var gender: String = info.get("player_gender", "male") as String
	var g := "f" if gender == "female" else "m"
	var r := race[0] if race.length() > 0 else "h"
	var hero_port_path := "res://assets/art/player_avatars/%s%s_port.png" % [g, r]
	portrait_row.add_child(_make_portrait(hero_port_path, 52))

	# Centre: name / class / location
	var centre := VBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.add_theme_constant_override("separation", 2)
	portrait_row.add_child(centre)

	var name_lbl := Label.new()
	var pname: String = info.get("player_name", "Hero") as String
	name_lbl.text = pname
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	centre.add_child(name_lbl)

	var cls_idx: int = info.get("player_class", 0) as int
	var cls_lbl := Label.new()
	cls_lbl.text = CLASS_NAMES[cls_idx] if cls_idx < CLASS_NAMES.size() else "?"
	cls_lbl.add_theme_font_size_override("font_size", 13)
	cls_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85))
	cls_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(cls_lbl)

	var scene: String = info.get("scene_state", "camp") as String
	var floor_num: int = info.get("floor", 1) as int
	var loc_text := "Camp  -  Floor %d" % floor_num if scene == "camp" else "Dungeon  -  Floor %d" % floor_num
	var loc_lbl := Label.new()
	loc_lbl.text = loc_text
	loc_lbl.add_theme_font_size_override("font_size", 12)
	loc_lbl.add_theme_color_override("font_color",
		Color(0.5, 0.9, 0.6) if scene == "camp" else Color(0.9, 0.6, 0.3))
	loc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre.add_child(loc_lbl)

	# Companion portrait (right) — portrait if it exists, else ready-pose fallback
	var comp_key: String = info.get("first_companion_key", "") as String
	var comp_port_path := ""
	if comp_key != "":
		var port := EnemyDB.get_portrait_path(comp_key)
		if port != "" and ResourceLoader.exists(port):
			comp_port_path = port
		else:
			comp_port_path = EnemyDB.get_ready_texture_path(comp_key)
	portrait_row.add_child(_make_portrait(comp_port_path, 52))

	# HP bar
	var hp: int     = info.get("hp",     0) as int
	var hp_max: int = info.get("hp_max", 1) as int
	var hp_ratio := clampf(float(hp) / float(maxi(hp_max, 1)), 0.0, 1.0)

	var bar_bg := Control.new()
	bar_bg.custom_minimum_size = Vector2(0, 8)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_bg_rect := ColorRect.new()
	bar_bg_rect.color = Color(0.1, 0.06, 0.06)
	bar_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(bar_bg_rect)
	var bar_fill := ColorRect.new()
	bar_fill.color = _hp_color(hp_ratio)
	bar_fill.anchor_left   = 0.0
	bar_fill.anchor_top    = 0.0
	bar_fill.anchor_right  = hp_ratio
	bar_fill.anchor_bottom = 1.0
	bar_bg.add_child(bar_fill)
	col.add_child(bar_bg)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP  %d / %d      Gold  %d" % [hp, hp_max, info.get("gold", 0) as int]
	hp_lbl.add_theme_font_size_override("font_size", 11)
	hp_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.65))
	hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hp_lbl)

	# Timestamp
	var ts: int = info.get("timestamp", 0) as int
	var ts_lbl := Label.new()
	ts_lbl.text = _format_timestamp(ts)
	ts_lbl.add_theme_font_size_override("font_size", 10)
	ts_lbl.add_theme_color_override("font_color", Color(0.38, 0.36, 0.42))
	ts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(ts_lbl)

	col.add_child(HSeparator.new())

	# ── Button row: Load + New ──
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	col.add_child(btn_row)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.custom_minimum_size = Vector2(0, 32)
	_style_btn(load_btn, Color(0.3, 0.55, 0.8))
	load_btn.pressed.connect(func(): load_game_requested.emit(slot))
	btn_row.add_child(load_btn)

	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_btn.custom_minimum_size = Vector2(0, 32)
	_style_btn(new_btn, Color(0.55, 0.38, 0.22))
	new_btn.pressed.connect(func(): _confirm_new(slot, col, btn_row))
	btn_row.add_child(new_btn)


## Replace the button row with a "Overwrite? Yes / No" confirmation.
func _confirm_new(slot: int, col: VBoxContainer, btn_row: HBoxContainer) -> void:
	for c in btn_row.get_children():
		c.queue_free()

	var confirm_lbl := Label.new()
	confirm_lbl.text = "Overwrite save?"
	confirm_lbl.add_theme_font_size_override("font_size", 12)
	confirm_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	confirm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(confirm_lbl)

	var yes_btn := Button.new()
	yes_btn.text = "Yes — New Game"
	yes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_btn.custom_minimum_size = Vector2(0, 30)
	_style_btn(yes_btn, Color(0.7, 0.3, 0.2))
	yes_btn.pressed.connect(func():
		SaveManager.delete_slot(slot)
		new_game_requested.emit(slot)
	)
	btn_row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_btn.custom_minimum_size = Vector2(0, 30)
	_style_btn(no_btn, Color(0.3, 0.3, 0.35))
	no_btn.pressed.connect(func(): get_tree().reload_current_scene())
	btn_row.add_child(no_btn)


# ── Helpers ────────────────────────────────────────────────────────────────────

func _make_portrait(path: String, size: int) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(size, size)
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	if path != "" and ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		container.add_child(tex)
	else:
		# Dim placeholder box when no portrait available
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.1, 0.09, 0.14)
		placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
		container.add_child(placeholder)

	return container


func _style_btn(btn: Button, accent: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = accent.darkened(0.6)
	s.border_color = accent
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate() as StyleBoxFlat
	h.bg_color = accent.darkened(0.35)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 13)


func _hp_color(ratio: float) -> Color:
	if ratio > 0.6: return Color(0.2, 0.75, 0.25)
	elif ratio > 0.3: return Color(0.85, 0.65, 0.1)
	return Color(0.8, 0.15, 0.1)


func _format_timestamp(ts: int) -> String:
	if ts == 0:
		return ""
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(ts)
	return "%04d-%02d-%02d  %02d:%02d" % [
		dt.get("year", 0), dt.get("month", 0), dt.get("day", 0),
		dt.get("hour", 0), dt.get("minute", 0),
	]
