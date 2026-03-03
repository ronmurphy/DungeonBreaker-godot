extends CanvasLayer
## Death screen — shown when the player is defeated in combat.
## Fades in "YOU DIED" with run stats, then offers New Run / Return to Menu.

signal new_run_requested()
signal menu_requested()

const _CINZEL_PATH := "res://assets/fonts/Cinzel-VariableFont_wght.ttf"

func _ready():
	layer = 10

	# Load variable font and create two weight variants
	var base_font: FontFile = load(_CINZEL_PATH)
	var font_bold := FontVariation.new()
	font_bold.base_font = base_font
	font_bold.variation_opentype = { "wght": 700 }

	var font_reg := FontVariation.new()
	font_reg.base_font = base_font
	font_reg.variation_opentype = { "wght": 400 }

	var vp_size := get_viewport().get_visible_rect().size

	# ── Root control (full-rect anchor base) ──────────────────────────────────
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	# ── 1. Background ─────────────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.modulate.a = 0.0
	root.add_child(bg)

	# ── 2. "YOU DIED" title ───────────────────────────────────────────────────
	var title := Label.new()
	title.text = "YOU DIED"
	title.add_theme_font_override("font", font_bold)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.85, 0.45, 0.05))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = vp_size.y * 0.28
	title.offset_bottom = vp_size.y * 0.28 + 120.0
	title.modulate.a = 0.0
	root.add_child(title)

	# ── 3. Subtitle "on floor N" ──────────────────────────────────────────────
	var sub := Label.new()
	sub.text = "on floor %d" % GameData.current_floor
	sub.add_theme_font_override("font", font_reg)
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.offset_top = vp_size.y * 0.28 + 128.0
	sub.offset_bottom = vp_size.y * 0.28 + 164.0
	sub.modulate.a = 0.0
	root.add_child(sub)

	# ── 4. Stats VBoxContainer ────────────────────────────────────────────────
	var stats_box := VBoxContainer.new()
	stats_box.anchor_left = 0.5
	stats_box.anchor_right = 0.5
	stats_box.anchor_top = 0.0
	stats_box.anchor_bottom = 0.0
	stats_box.offset_top = vp_size.y * 0.52
	stats_box.offset_bottom = vp_size.y * 0.52 + 220.0
	stats_box.offset_left = -200.0
	stats_box.offset_right = 200.0
	stats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_box.modulate.a = 0.0
	root.add_child(stats_box)

	var stat_lines: Array = [
		["Level", str(GameData.player_level)],
		["Floor Reached", str(GameData.current_floor)],
		["Enemies Slain", str(GameData.total_kills)],
		["Gold Earned", "%dg" % GameData.run_gold_earned],
		["Damage Dealt", str(GameData.run_damage_dealt)],
		["Damage Taken", str(GameData.run_damage_taken)],
		["Companions", str(GameData.run_companions_recruited)],
	]

	for row in stat_lines:
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		stats_box.add_child(hb)

		var key_lbl := Label.new()
		key_lbl.text = row[0] + ":"
		key_lbl.add_theme_font_override("font", font_reg)
		key_lbl.add_theme_font_size_override("font_size", 18)
		key_lbl.add_theme_color_override("font_color", Color(0.75, 0.70, 0.65))
		key_lbl.custom_minimum_size = Vector2(200.0, 0.0)
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(key_lbl)

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(12.0, 0.0)
		hb.add_child(spacer)

		var val_lbl := Label.new()
		val_lbl.text = row[1]
		val_lbl.add_theme_font_override("font", font_bold)
		val_lbl.add_theme_font_size_override("font_size", 18)
		val_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
		val_lbl.custom_minimum_size = Vector2(140.0, 0.0)
		hb.add_child(val_lbl)

	# Cause of death
	var cod := Label.new()
	var cod_text: String = GameData.cause_of_death if GameData.cause_of_death != "" else "Fallen in battle"
	cod.text = cod_text
	cod.add_theme_font_override("font", font_reg)
	cod.add_theme_font_size_override("font_size", 16)
	cod.add_theme_color_override("font_color", Color(0.8, 0.3, 0.2))
	cod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cod.set_anchors_preset(Control.PRESET_TOP_WIDE)
	cod.offset_top = vp_size.y * 0.52 + 232.0
	cod.offset_bottom = vp_size.y * 0.52 + 258.0
	cod.modulate.a = 0.0
	root.add_child(cod)

	# ── 5. Button row ─────────────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.anchor_left = 0.5
	btn_row.anchor_right = 0.5
	btn_row.anchor_top = 0.0
	btn_row.anchor_bottom = 0.0
	btn_row.offset_top = vp_size.y * 0.83
	btn_row.offset_bottom = vp_size.y * 0.83 + 52.0
	btn_row.offset_left = -220.0
	btn_row.offset_right = 220.0
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 32)
	btn_row.modulate.a = 0.0
	root.add_child(btn_row)

	var btn_new := Button.new()
	btn_new.text = "New Run"
	btn_new.add_theme_font_override("font", font_reg)
	btn_new.add_theme_font_size_override("font_size", 20)
	btn_new.custom_minimum_size = Vector2(180.0, 48.0)
	btn_new.pressed.connect(func(): new_run_requested.emit())
	btn_row.add_child(btn_new)

	var btn_menu := Button.new()
	btn_menu.text = "Return to Menu"
	btn_menu.add_theme_font_override("font", font_reg)
	btn_menu.add_theme_font_size_override("font_size", 20)
	btn_menu.custom_minimum_size = Vector2(180.0, 48.0)
	btn_menu.pressed.connect(func(): menu_requested.emit())
	btn_row.add_child(btn_menu)

	# ── Tween animation sequence (parallel tweens with staggered delays) ────────
	var tw := create_tween()
	tw.set_parallel(true)

	tw.tween_property(bg,        "modulate:a", 0.88, 1.2).set_ease(Tween.EASE_IN).set_delay(0.0)
	tw.tween_property(title,     "modulate:a", 1.0,  1.8).set_ease(Tween.EASE_OUT).set_delay(1.0)
	tw.tween_property(sub,       "modulate:a", 1.0,  0.6).set_ease(Tween.EASE_OUT).set_delay(2.2)
	tw.tween_property(stats_box, "modulate:a", 1.0,  0.7).set_ease(Tween.EASE_OUT).set_delay(2.8)
	tw.tween_property(cod,       "modulate:a", 1.0,  0.7).set_ease(Tween.EASE_OUT).set_delay(2.8)
	tw.tween_property(btn_row,   "modulate:a", 1.0,  0.5).set_ease(Tween.EASE_OUT).set_delay(3.5)
