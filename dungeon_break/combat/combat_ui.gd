extends CanvasLayer
## FFT-style Combat UI — tactical overlay during grid combat.
##
## Shows:
##   - Portrait tracker (left) — unit cards with colored dots, active-unit indent
##   - Action menu (right) — vertical list, FFT-style
##   - Combat log (bottom-left, above enemy panel)
##   - Enemy info panel (bottom-left) — visible during enemy turns
##   - Phase indicator — "YOUR TURN" / "MOVE" / "ACT" / enemy name

var _combat: Node = null  # TacticalCombatManager reference

# ── UI nodes ──────────────────────────────────────────────────────────────────
var _turn_bar: HBoxContainer = null          # null — kept for signal compat
var _phase_label: Label = null
var _action_panel: PanelContainer = null
var _action_list: VBoxContainer = null
var _combat_log: RichTextLabel = null
var _enemy_target_panel: PanelContainer = null
var _enemy_target_list: VBoxContainer = null
var _target_idx: int = -1

# ── Enemy info panel (bottom-left, shown during enemy turns) ──────────────────
var _enemy_info_panel: PanelContainer = null
var _enemy_info_portrait: TextureRect = null
var _enemy_info_name: Label = null
var _enemy_info_hp_fill: ColorRect = null
var _enemy_info_hp_label: Label = null
var _enemy_info_stats: Label = null

# ── Portrait tracker (left side) ──────────────────────────────────────────────
var _portrait_panel: VBoxContainer = null
var _enemy_cards: Dictionary = {}   # unit_idx → card data dict
var _active_unit_idx: int = -1
var _selecting_target: bool = false

# ── Per-unit color palette ────────────────────────────────────────────────────
const UNIT_COLORS: Array = [
	Color(0.9, 0.3, 0.3),    # red
	Color(0.3, 0.65, 0.95),  # blue
	Color(0.95, 0.7, 0.15),  # gold
	Color(0.85, 0.4, 0.85),  # violet
	Color(0.3, 0.9, 0.85),   # cyan
	Color(0.95, 0.55, 0.2),  # orange
	Color(0.55, 0.9, 0.45),  # lime
	Color(0.7, 0.5, 0.9),    # purple
]
const PLAYER_COLOR := Color(0.3, 0.9, 0.4)

var _color_cursor: int = 0


func setup(combat_manager: Node):
	_combat = combat_manager
	_build_ui()
	_connect_signals()
	_build_enemy_cards()
	visible = true


func _build_ui():
	# ── Phase indicator (top-left) ──
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override("font_size", 20)
	_phase_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	_phase_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_phase_label.offset_left = 12
	_phase_label.offset_top = 48
	_phase_label.text = "COMBAT"
	add_child(_phase_label)

	# ── Action menu (right side, vertical) ──
	_action_panel = PanelContainer.new()
	_action_panel.name = "ActionPanel"
	var ap_style := StyleBoxFlat.new()
	ap_style.bg_color = Color(0.05, 0.03, 0.1, 0.9)
	ap_style.border_color = Color(0.6, 0.5, 0.3)
	ap_style.set_border_width_all(2)
	ap_style.set_corner_radius_all(6)
	ap_style.set_content_margin_all(8)
	_action_panel.add_theme_stylebox_override("panel", ap_style)
	_action_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_action_panel.offset_left = -170
	_action_panel.offset_right = -12
	_action_panel.offset_top = -120
	_action_panel.offset_bottom = 120
	_action_panel.visible = false
	add_child(_action_panel)

	_action_list = VBoxContainer.new()
	_action_list.add_theme_constant_override("separation", 4)
	_action_panel.add_child(_action_list)

	# ── Enemy target panel ──
	_enemy_target_panel = PanelContainer.new()
	_enemy_target_panel.name = "TargetPanel"
	var et_style := ap_style.duplicate()
	et_style.border_color = Color(1.0, 0.3, 0.3)
	_enemy_target_panel.add_theme_stylebox_override("panel", et_style)
	_enemy_target_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_enemy_target_panel.offset_left = -400
	_enemy_target_panel.offset_right = -180
	_enemy_target_panel.offset_top = -80
	_enemy_target_panel.offset_bottom = 80
	_enemy_target_panel.visible = false
	add_child(_enemy_target_panel)

	_enemy_target_list = VBoxContainer.new()
	_enemy_target_list.add_theme_constant_override("separation", 4)
	_enemy_target_panel.add_child(_enemy_target_list)

	# ── Combat log (bottom-left, sits above enemy panel) ──
	var log_panel := PanelContainer.new()
	log_panel.name = "LogPanel"
	var lp_style := StyleBoxFlat.new()
	lp_style.bg_color = Color(0.02, 0.02, 0.05, 0.75)
	lp_style.border_color = Color(0.25, 0.25, 0.4)
	lp_style.set_border_width_all(1)
	lp_style.set_corner_radius_all(4)
	lp_style.set_content_margin_all(6)
	log_panel.add_theme_stylebox_override("panel", lp_style)
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.offset_left = 8
	log_panel.offset_right = 380
	log_panel.offset_top = -238
	log_panel.offset_bottom = -100
	add_child(log_panel)

	_combat_log = RichTextLabel.new()
	_combat_log.name = "CombatLog"
	_combat_log.bbcode_enabled = true
	_combat_log.scroll_following = true
	_combat_log.add_theme_font_size_override("normal_font_size", 12)
	_combat_log.add_theme_color_override("default_color", Color(0.7, 0.7, 0.8))
	log_panel.add_child(_combat_log)

	# ── Enemy info panel (bottom-left, shown during enemy turns) ──
	_enemy_info_panel = PanelContainer.new()
	_enemy_info_panel.name = "EnemyInfoPanel"
	var ei_style := StyleBoxFlat.new()
	ei_style.bg_color = Color(0.08, 0.03, 0.03, 0.92)
	ei_style.border_color = Color(0.75, 0.35, 0.2)
	ei_style.set_border_width_all(2)
	ei_style.set_corner_radius_all(6)
	ei_style.set_content_margin_all(8)
	_enemy_info_panel.add_theme_stylebox_override("panel", ei_style)
	_enemy_info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_enemy_info_panel.offset_left = 8
	_enemy_info_panel.offset_right = 320
	_enemy_info_panel.offset_top = -92
	_enemy_info_panel.offset_bottom = -8
	_enemy_info_panel.visible = false
	add_child(_enemy_info_panel)

	var ei_hbox := HBoxContainer.new()
	ei_hbox.add_theme_constant_override("separation", 10)
	_enemy_info_panel.add_child(ei_hbox)

	_enemy_info_portrait = TextureRect.new()
	_enemy_info_portrait.custom_minimum_size = Vector2(64, 64)
	_enemy_info_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_enemy_info_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ei_hbox.add_child(_enemy_info_portrait)

	var ei_vbox := VBoxContainer.new()
	ei_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ei_vbox.add_theme_constant_override("separation", 4)
	ei_hbox.add_child(ei_vbox)

	_enemy_info_name = Label.new()
	_enemy_info_name.add_theme_font_size_override("font_size", 14)
	_enemy_info_name.add_theme_color_override("font_color", Color(1.0, 0.75, 0.6))
	_enemy_info_name.clip_text = true
	ei_vbox.add_child(_enemy_info_name)

	var ei_hp_bg := Control.new()
	ei_hp_bg.custom_minimum_size = Vector2(0, 8)
	ei_hp_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ei_hp_bg_rect := ColorRect.new()
	ei_hp_bg_rect.color = Color(0.08, 0.04, 0.04)
	ei_hp_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	ei_hp_bg.add_child(ei_hp_bg_rect)
	_enemy_info_hp_fill = ColorRect.new()
	_enemy_info_hp_fill.anchor_left = 0.0
	_enemy_info_hp_fill.anchor_top = 0.0
	_enemy_info_hp_fill.anchor_right = 1.0
	_enemy_info_hp_fill.anchor_bottom = 1.0
	_enemy_info_hp_fill.color = Color(0.2, 0.75, 0.25)
	ei_hp_bg.add_child(_enemy_info_hp_fill)
	ei_vbox.add_child(ei_hp_bg)

	_enemy_info_hp_label = Label.new()
	_enemy_info_hp_label.add_theme_font_size_override("font_size", 11)
	_enemy_info_hp_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	ei_vbox.add_child(_enemy_info_hp_label)

	_enemy_info_stats = Label.new()
	_enemy_info_stats.add_theme_font_size_override("font_size", 11)
	_enemy_info_stats.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	ei_vbox.add_child(_enemy_info_stats)

	# ── Portrait tracker (left side, center-anchored) ──
	_portrait_panel = VBoxContainer.new()
	_portrait_panel.name = "PortraitTracker"
	_portrait_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_portrait_panel.offset_left = 8
	_portrait_panel.offset_right = 188
	_portrait_panel.offset_top = -200
	_portrait_panel.offset_bottom = 200
	_portrait_panel.add_theme_constant_override("separation", 4)
	add_child(_portrait_panel)


func _connect_signals():
	if _combat == null:
		return

	_combat.combat_started.connect(_on_combat_started)
	_combat.turn_order_changed.connect(_on_turn_order_changed)
	_combat.unit_turn_started.connect(_on_unit_turn_started)
	_combat.move_phase_started.connect(_on_move_phase_started)
	_combat.act_phase_started.connect(_on_act_phase_started)
	_combat.action_resolved.connect(_on_action_resolved)
	_combat.unit_defeated.connect(_on_unit_defeated)
	_combat.unit_moved.connect(_on_unit_moved)
	_combat.combat_ended.connect(_on_combat_ended)


# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_combat_started():
	_log("[color=yellow]═══ COMBAT ═══[/color]")
	_log("[color=white]Each turn: [color=cyan]MOVE[/color] then [color=gold]ACT[/color][/color]")
	_log("[color=gray]MOVE: Click a [color=dodgerblue]blue tile[/color] or press [S] to skip[/color]")
	_log("[color=gray]ACT:  Pick an action from the menu (1-6 keys)[/color]")
	_log("")


func _on_turn_order_changed(order: Array):
	_update_turn_bar(order)


func _on_unit_turn_started(unit: Dictionary):
	var color := "cyan" if unit["type"] == "player" else "orange"
	var icon := "►" if unit["type"] == "player" else "◆"
	_log("[color=%s]%s %s's turn[/color]" % [color, icon, unit["name"]])

	# Highlight active card in tracker by matching name+type
	if _combat:
		var units: Array = _combat.get_units()
		for i in units.size():
			if units[i]["type"] == unit["type"] and units[i]["name"] == unit["name"]:
				_set_active_card(i)
				break

	if unit["type"] == "player":
		_phase_label.text = "YOUR TURN"
		_phase_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		if _enemy_info_panel:
			_enemy_info_panel.visible = false
	else:
		_phase_label.text = unit["name"]
		_phase_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.2))
		_action_panel.visible = false
		_update_enemy_info_panel(unit)


func _on_move_phase_started(unit: Dictionary, _tiles: Array):
	_phase_label.text = "MOVE"
	_phase_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))

	var tile_count := _tiles.size()
	if tile_count > 0:
		_log("[color=dodgerblue]→ Click a blue tile to move (%d tiles) or [S] skip[/color]" % tile_count)
	else:
		_log("[color=gray]No movement options — press [S] to skip[/color]")

	_show_move_actions()
	_action_panel.visible = true


func _on_act_phase_started(unit: Dictionary):
	_phase_label.text = "ACT"
	_phase_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))

	_selecting_target = false
	_enemy_target_panel.visible = false
	_log("[color=gold]→ Choose an action (1-6 keys or click)[/color]")
	_show_act_actions(unit)
	_action_panel.visible = true


func _on_action_resolved(log_text: String):
	_log(log_text)
	_refresh_enemy_cards()


func _on_unit_defeated(unit: Dictionary):
	_refresh_enemy_cards()


func _on_unit_moved(unit: Dictionary, _from: Vector2i, to: Vector2i):
	if unit["type"] == "player":
		_log("[color=gray]Moved to (%d, %d)[/color]" % [to.x, to.y])


func _on_combat_ended(victory: bool):
	_action_panel.visible = false
	_enemy_target_panel.visible = false
	if _enemy_info_panel:
		_enemy_info_panel.visible = false

	if victory:
		_phase_label.text = "VICTORY!"
		_phase_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		_phase_label.text = "DEFEAT"
		_phase_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	await get_tree().create_timer(2.0).timeout
	queue_free()


# ── Action menus ──────────────────────────────────────────────────────────────

func _show_move_actions():
	_clear_action_list()

	var title := Label.new()
	title.text = "— MOVE —"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_list.add_child(title)

	_add_action_button("Move", "Click a blue tile on the floor", Color(0.3, 0.5, 1.0), func(): pass)
	_add_action_button("Skip [S]", "Stay in place → go to ACT", Color(0.5, 0.5, 0.5), func():
		if _combat:
			_combat.player_skip_move()
	)


func _show_act_actions(unit: Dictionary):
	_clear_action_list()

	var title := Label.new()
	title.text = "— ACT —"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_list.add_child(title)

	var attackable: Array = []
	if _combat:
		var cu: Dictionary = _combat.get_current_unit()
		attackable = _combat.get_attackable_enemies(cu["grid_pos"], cu["attack_range"])

	var has_targets := not attackable.is_empty()

	_add_action_button("Attack [1]", "Strike adjacent foe" if has_targets else "No one in range",
		Color(1.0, 0.3, 0.3) if has_targets else Color(0.4, 0.2, 0.2),
		func(): _start_target_selection() if has_targets else null)

	_add_action_button("Defend [2]", "+4 AC this round", Color(0.3, 0.6, 1.0),
		func(): _do_act("defend"))

	_add_action_button("Counter [3]", "+4 AC + reflect", Color(1.0, 0.8, 0.2),
		func(): _do_act("counter"))

	var guts_text := "Guts %d/%d" % [GameData.guts, GameData.guts_max]
	if GameData.guts >= GameData.guts_max:
		guts_text = "UNLEASH!"
	_add_action_button("Guts [4]", guts_text, Color(1.0, 0.5, 0.1),
		func(): _do_act("guts"))

	_add_action_button("Wait [5]", "End turn", Color(0.5, 0.5, 0.5),
		func(): _do_act("wait"))

	_add_action_button("Flee [6]", "Try to escape", Color(0.4, 0.4, 0.4),
		func(): _do_act("flee"))


func _start_target_selection():
	if not _combat:
		return

	_selecting_target = true
	var cu: Dictionary = _combat.get_current_unit()
	var attackable: Array = _combat.get_attackable_enemies(cu["grid_pos"], cu["attack_range"])

	for child in _enemy_target_list.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "— TARGET —"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_target_list.add_child(title)

	for i in attackable.size():
		var enemy_data: Dictionary = attackable[i]
		var u: Dictionary = enemy_data["unit"]
		var uid: int = enemy_data["unit_idx"]
		_enemy_target_list.add_child(_build_target_card(u, uid))

	if attackable.size() == 1:
		_target_idx = attackable[0]["unit_idx"]

	_enemy_target_panel.visible = true


func _on_target_selected(unit_idx: int):
	_selecting_target = false
	_enemy_target_panel.visible = false
	_do_act("attack", unit_idx)


func _build_target_card(u: Dictionary, uid: int) -> Control:
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.18, 0.04, 0.04, 0.92)
	card_style.border_color = Color(0.85, 0.3, 0.25)
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(4)
	card_style.set_content_margin_all(5)
	card.add_theme_stylebox_override("panel", card_style)
	card.custom_minimum_size = Vector2(210, 68)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_target_selected(uid)
	)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 7)
	card.add_child(hbox)

	var portrait_rect := TextureRect.new()
	portrait_rect.custom_minimum_size = Vector2(56, 56)
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var portrait_path := ""
	if u.has("entity_key") and u["entity_key"] != "":
		portrait_path = EnemyDB.get_portrait_path(u["entity_key"])
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		portrait_rect.texture = load(portrait_path)
	hbox.add_child(portrait_rect)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	var name_lbl := Label.new()
	var variant_str: String = u.get("variant", "normal")
	var name_color := Color(1.0, 0.85, 0.8)
	if variant_str == "elite":
		name_color = Color(1.0, 0.75, 0.2)
		name_lbl.text = u["name"] + " ★"
	elif variant_str == "ghost":
		name_color = Color(0.55, 0.9, 1.0)
		name_lbl.text = u["name"] + " ☽"
	else:
		name_lbl.text = u["name"]
	name_lbl.add_theme_color_override("font_color", name_color)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.clip_text = true
	vbox.add_child(name_lbl)

	var bar_container := Control.new()
	bar_container.custom_minimum_size = Vector2(0, 8)
	bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.15, 0.04, 0.04)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_container.add_child(bar_bg)
	var hp_ratio := clampf(float(u["hp"]) / float(max(u["hp_max"], 1)), 0.0, 1.0)
	var bar_fill := ColorRect.new()
	bar_fill.color = _hp_bar_color(hp_ratio)
	bar_fill.anchor_left = 0.0
	bar_fill.anchor_top = 0.0
	bar_fill.anchor_right = hp_ratio
	bar_fill.anchor_bottom = 1.0
	bar_container.add_child(bar_fill)
	vbox.add_child(bar_container)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP  %d / %d" % [u["hp"], u["hp_max"]]
	hp_lbl.add_theme_font_size_override("font_size", 11)
	hp_lbl.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	vbox.add_child(hp_lbl)

	return card


func _do_act(action: String, target_idx: int = -1):
	_action_panel.visible = false
	_enemy_target_panel.visible = false
	if _combat:
		_combat.player_act(action, target_idx)


func _add_action_button(label_text: String, desc: String, color: Color, callback: Callable):
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(140, 32)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = color.darkened(0.65)
	btn_style.border_color = color
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", btn_style)

	var hover_style := btn_style.duplicate()
	hover_style.bg_color = color.darkened(0.35)
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 13)

	if callback.is_valid():
		btn.pressed.connect(callback)

	_action_list.add_child(btn)

	if desc != "":
		var desc_label := Label.new()
		desc_label.text = "  " + desc
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		_action_list.add_child(desc_label)


func _clear_action_list():
	for child in _action_list.get_children():
		child.queue_free()


# ── Turn bar (compatibility stub — portrait tracker handles visual order) ──────

func _update_turn_bar(_order: Array):
	pass


# ── Enemy info panel ──────────────────────────────────────────────────────────

func _update_enemy_info_panel(u: Dictionary):
	if _enemy_info_panel == null:
		return

	_enemy_info_panel.visible = true

	var portrait_path := ""
	if u.has("entity_key") and u["entity_key"] != "":
		portrait_path = EnemyDB.get_portrait_path(u["entity_key"])
	_enemy_info_portrait.texture = load(portrait_path) if portrait_path != "" and ResourceLoader.exists(portrait_path) else null

	var variant_str: String = u.get("variant", "normal")
	if variant_str == "elite":
		_enemy_info_name.text = u["name"] + "  ★"
		_enemy_info_name.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	elif variant_str == "ghost":
		_enemy_info_name.text = u["name"] + "  ☽"
		_enemy_info_name.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	else:
		_enemy_info_name.text = u["name"]
		_enemy_info_name.add_theme_color_override("font_color", Color(1.0, 0.75, 0.6))

	var hp_ratio := clampf(float(u["hp"]) / float(max(u["hp_max"], 1)), 0.0, 1.0)
	_enemy_info_hp_fill.anchor_right = hp_ratio
	_enemy_info_hp_fill.color = _hp_bar_color(hp_ratio)
	_enemy_info_hp_label.text = "HP  %d / %d" % [u["hp"], u["hp_max"]]
	_enemy_info_stats.text = "AC %d   ATK %d" % [u.get("defense", 0), u.get("attack", 0)]


# ── Portrait tracker — colored dots and active-unit indent ────────────────────

func _set_active_card(unit_idx: int):
	_active_unit_idx = unit_idx
	for i in _enemy_cards:
		var cd: Dictionary = _enemy_cards[i]
		var is_active: bool = (i == unit_idx)

		# Indent the active card right by 8px
		var spacer: Control = cd["spacer"]
		spacer.custom_minimum_size = Vector2(8.0 if is_active else 0.0, 1.0)

		# Border: active = unit color + 2px, inactive = dim + 1px
		var style: StyleBoxFlat = cd["card_style"]
		if is_active:
			style.border_color = cd["color"]
			style.set_border_width_all(2)
		else:
			if cd["is_player"]:
				style.border_color = Color(0.3, 0.75, 0.45)
				style.bg_color = Color(0.02, 0.06, 0.04, 0.92)
			else:
				style.border_color = Color(0.45, 0.35, 0.55)
				style.bg_color = Color(0.04, 0.02, 0.08, 0.88)
			style.set_border_width_all(1)


func _build_enemy_cards():
	for child in _portrait_panel.get_children():
		child.queue_free()
	_enemy_cards.clear()
	_color_cursor = 0

	if _combat == null:
		return

	var units: Array = _combat.get_units()

	# Enemies first (top of tracker)
	for i in units.size():
		var u: Dictionary = units[i]
		if u["type"] == "enemy":
			var color: Color = UNIT_COLORS[_color_cursor % UNIT_COLORS.size()]
			_color_cursor += 1
			_enemy_cards[i] = _create_unit_card(u, false, color)
			_portrait_panel.add_child(_enemy_cards[i]["card_root"])

	# Player last (bottom of tracker)
	for i in units.size():
		var u: Dictionary = units[i]
		if u["type"] == "player":
			_enemy_cards[i] = _create_unit_card(u, true, PLAYER_COLOR)
			_portrait_panel.add_child(_enemy_cards[i]["card_root"])


func _create_unit_card(u: Dictionary, is_player: bool, unit_color: Color) -> Dictionary:
	# ── Wrapper HBox — spacer gives indent when active ──
	var wrapper := HBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 1)
	spacer.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrapper.add_child(spacer)

	# ── Card panel ──
	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	if is_player:
		card_style.bg_color = Color(0.02, 0.06, 0.04, 0.92)
		card_style.border_color = Color(0.3, 0.75, 0.45)
	else:
		card_style.bg_color = Color(0.04, 0.02, 0.08, 0.88)
		card_style.border_color = Color(0.45, 0.35, 0.55)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(4)
	card_style.set_content_margin_all(5)
	card.add_theme_stylebox_override("panel", card_style)
	card.custom_minimum_size = Vector2(170, 58)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(card)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	card.add_child(hbox)

	# ── Portrait container (48×48) with colored dot overlay ──
	var portrait_container := Control.new()
	portrait_container.custom_minimum_size = Vector2(48, 48)
	hbox.add_child(portrait_container)

	var portrait := TextureRect.new()
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE

	var portrait_path := ""
	if is_player:
		portrait_path = GameData.get_portrait_path()
	elif u.has("entity_key") and u["entity_key"] != "":
		portrait_path = EnemyDB.get_portrait_path(u["entity_key"])
	if portrait_path != "" and ResourceLoader.exists(portrait_path):
		portrait.texture = load(portrait_path)
	portrait_container.add_child(portrait)

	# Colored dot — top-right corner of portrait area
	var dot := ColorRect.new()
	dot.color = unit_color
	dot.size = Vector2(10, 10)
	dot.position = Vector2(38, 0)
	portrait_container.add_child(dot)

	# ── Right column ──
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(vbox)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.clip_text = true
	if is_player:
		name_label.text = u["name"]
		name_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.65))
	else:
		var variant_str: String = u.get("variant", "normal")
		var name_color := Color(0.9, 0.85, 0.9)
		if variant_str == "elite":
			name_color = Color(1.0, 0.7, 0.2)
			name_label.text = u["name"] + " ★"
		elif variant_str == "ghost":
			name_color = Color(0.5, 0.85, 1.0)
			name_label.text = u["name"] + " ☽"
		else:
			name_label.text = u["name"]
		name_label.add_theme_color_override("font_color", name_color)
	vbox.add_child(name_label)

	# HP bar
	var hp: int = GameData.hp if is_player else u["hp"]
	var hp_max: int = GameData.hp_max if is_player else u["hp_max"]
	var hp_ratio := clampf(float(hp) / float(max(hp_max, 1)), 0.0, 1.0)

	var bar_bg := Control.new()
	bar_bg.custom_minimum_size = Vector2(0, 8)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_bg_rect := ColorRect.new()
	bar_bg_rect.color = Color(0.08, 0.08, 0.08)
	bar_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(bar_bg_rect)

	var hp_fill := ColorRect.new()
	hp_fill.color = _hp_bar_color(hp_ratio) if not is_player else Color(0.2, 0.8, 0.4)
	hp_fill.anchor_left = 0.0
	hp_fill.anchor_top = 0.0
	hp_fill.anchor_right = hp_ratio
	hp_fill.anchor_bottom = 1.0
	bar_bg.add_child(hp_fill)
	vbox.add_child(bar_bg)

	var hp_label := Label.new()
	hp_label.text = "%d / %d" % [hp, hp_max]
	hp_label.add_theme_font_size_override("font_size", 10)
	hp_label.add_theme_color_override("font_color",
		Color(0.5, 0.9, 0.65) if is_player else Color(0.7, 0.8, 0.7))
	vbox.add_child(hp_label)

	return {
		"card_root": wrapper,
		"card": card,
		"spacer": spacer,
		"hp_fill": hp_fill,
		"hp_label": hp_label,
		"card_style": card_style,
		"is_player": is_player,
		"color": unit_color,
		"dot": dot,
	}


func _refresh_enemy_cards():
	if _combat == null:
		return

	var units: Array = _combat.get_units()
	for i in units.size():
		var u: Dictionary = units[i]
		if not _enemy_cards.has(i):
			continue

		var card_data: Dictionary = _enemy_cards[i]
		var is_player: bool = card_data.get("is_player", false)

		var hp: int = GameData.hp if is_player else u["hp"]
		var hp_max: int = GameData.hp_max if is_player else u["hp_max"]
		var ratio := clampf(float(hp) / float(max(hp_max, 1)), 0.0, 1.0)

		var fill: ColorRect = card_data["hp_fill"]
		fill.anchor_right = ratio
		if not is_player:
			fill.color = _hp_bar_color(ratio)

		var lbl: Label = card_data["hp_label"]
		if not is_player and hp <= 0:
			lbl.text = "DEAD"
			lbl.add_theme_color_override("font_color", Color(0.5, 0.2, 0.2))
			var style: StyleBoxFlat = card_data["card_style"]
			style.bg_color = Color(0.02, 0.01, 0.04, 0.5)
			style.border_color = Color(0.2, 0.15, 0.25, 0.5)
		else:
			lbl.text = "%d / %d" % [hp, hp_max]

	# Keep enemy info panel in sync if it is currently shown
	if _enemy_info_panel and _enemy_info_panel.visible and _active_unit_idx >= 0:
		if _active_unit_idx < units.size():
			var active_u: Dictionary = units[_active_unit_idx]
			if active_u["type"] == "enemy":
				_update_enemy_info_panel(active_u)


func _hp_bar_color(ratio: float) -> Color:
	if ratio > 0.6:
		return Color(0.2, 0.75, 0.25)   # green
	elif ratio > 0.3:
		return Color(0.85, 0.65, 0.1)   # yellow
	else:
		return Color(0.8, 0.15, 0.1)    # red


# ── Combat log ────────────────────────────────────────────────────────────────

func _log(text: String):
	if _combat_log:
		_combat_log.append_text(text + "\n")


# ── Input handling ────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent):
	if _combat == null or not visible:
		return

	if not (event is InputEventKey) or not event.pressed:
		return

	var combat_phase: int = _combat.get_phase()

	if combat_phase == 0:
		pass

	if _combat.phase == 1:  # MOVE
		match event.keycode:
			KEY_S:
				if _combat:
					_combat.player_skip_move()

	elif _combat.phase == 2:  # ACT
		if _selecting_target:
			match event.keycode:
				KEY_ESCAPE:
					_selecting_target = false
					_enemy_target_panel.visible = false
		else:
			match event.keycode:
				KEY_1:
					var cu: Dictionary = _combat.get_current_unit()
					var attackable: Array = _combat.get_attackable_enemies(cu["grid_pos"], cu["attack_range"])
					if not attackable.is_empty():
						if attackable.size() == 1:
							_do_act("attack", attackable[0]["unit_idx"])
						else:
							_start_target_selection()
				KEY_2:
					_do_act("defend")
				KEY_3:
					_do_act("counter")
				KEY_4:
					_do_act("guts")
				KEY_5:
					_do_act("wait")
				KEY_6:
					_do_act("flee")
