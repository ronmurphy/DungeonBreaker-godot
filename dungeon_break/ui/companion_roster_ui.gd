extends CanvasLayer
## Companion Roster UI — manage active party and bench roster from camp.
##
## Shows two columns:
##   Left:  Active party slots (max based on floor)
##   Right: Full roster bench (companions not in active party)
## Opened from the Azure Flame in camp.

signal roster_closed()

var _root_panel: PanelContainer = null
var _active_col: VBoxContainer = null
var _bench_col: VBoxContainer = null


func _ready():
	_build_ui()
	visible = true


func _build_ui():
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	_root_panel = PanelContainer.new()
	_root_panel.name = "RosterPanel"
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.03, 0.07, 0.97)
	ps.border_color = Color(0.6, 0.5, 0.2)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.set_content_margin_all(14)
	_root_panel.add_theme_stylebox_override("panel", ps)
	_root_panel.set_anchors_preset(Control.PRESET_CENTER)
	_root_panel.offset_left   = -300
	_root_panel.offset_right  =  300
	_root_panel.offset_top    = -240
	_root_panel.offset_bottom =  240
	add_child(_root_panel)

	var vroot := VBoxContainer.new()
	vroot.add_theme_constant_override("separation", 8)
	_root_panel.add_child(vroot)

	# ── Header ──
	var header := HBoxContainer.new()
	vroot.add_child(header)

	var title := Label.new()
	title.text = "COMPANIONS"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕ Close"
	close_btn.custom_minimum_size = Vector2(70, 28)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	# ── Slot info ──
	var slot_info := Label.new()
	var slots: int = GameData.get_companion_slots()
	slot_info.text = "Active party slots: %d  (Floor %d)" % [slots, GameData.current_floor]
	slot_info.add_theme_font_size_override("font_size", 12)
	slot_info.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vroot.add_child(slot_info)

	# ── Two-column layout ──
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vroot.add_child(hbox)

	# Left: Active party
	var active_panel := PanelContainer.new()
	active_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ap_s := StyleBoxFlat.new()
	ap_s.bg_color = Color(0.03, 0.06, 0.03, 0.85)
	ap_s.border_color = Color(0.25, 0.6, 0.3)
	ap_s.set_border_width_all(1)
	ap_s.set_corner_radius_all(4)
	ap_s.set_content_margin_all(8)
	active_panel.add_theme_stylebox_override("panel", ap_s)
	hbox.add_child(active_panel)

	var active_vbox := VBoxContainer.new()
	active_vbox.add_theme_constant_override("separation", 6)
	active_panel.add_child(active_vbox)

	var active_title := Label.new()
	active_title.text = "ACTIVE PARTY"
	active_title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	active_title.add_theme_font_size_override("font_size", 13)
	active_vbox.add_child(active_title)

	_active_col = VBoxContainer.new()
	_active_col.add_theme_constant_override("separation", 6)
	active_vbox.add_child(_active_col)

	# Right: Roster bench
	var bench_panel := PanelContainer.new()
	bench_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bench_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bp_s := StyleBoxFlat.new()
	bp_s.bg_color = Color(0.05, 0.04, 0.02, 0.85)
	bp_s.border_color = Color(0.5, 0.4, 0.15)
	bp_s.set_border_width_all(1)
	bp_s.set_corner_radius_all(4)
	bp_s.set_content_margin_all(8)
	bench_panel.add_theme_stylebox_override("panel", bp_s)
	hbox.add_child(bench_panel)

	var bench_vbox := VBoxContainer.new()
	bench_vbox.add_theme_constant_override("separation", 6)
	bench_panel.add_child(bench_vbox)

	var bench_title := Label.new()
	bench_title.text = "ROSTER (BENCH)"
	bench_title.add_theme_color_override("font_color", Color(0.85, 0.65, 0.2))
	bench_title.add_theme_font_size_override("font_size", 13)
	bench_vbox.add_child(bench_title)

	_bench_col = VBoxContainer.new()
	_bench_col.add_theme_constant_override("separation", 6)
	bench_vbox.add_child(_bench_col)

	_refresh()


func _refresh():
	for child in _active_col.get_children():
		child.queue_free()
	for child in _bench_col.get_children():
		child.queue_free()

	var slots: int = GameData.get_companion_slots()
	var active_keys: Array = GameData.active_companions

	# ── Active column ──
	for s in slots:
		if s < active_keys.size():
			var key: String = active_keys[s]
			_active_col.add_child(_build_active_card(key))
		else:
			# Empty slot
			var empty := Label.new()
			empty.text = "— Empty Slot —"
			empty.add_theme_color_override("font_color", Color(0.3, 0.3, 0.35))
			empty.add_theme_font_size_override("font_size", 11)
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_active_col.add_child(empty)

	if GameData.companions.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No companions yet.\nRecruit enemies in combat!"
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		none_lbl.add_theme_font_size_override("font_size", 11)
		none_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_active_col.add_child(none_lbl)

	# ── Bench column ──
	var has_bench: bool = false
	for c in GameData.companions:
		var ckey: String = c.get("key", "")
		if ckey in active_keys:
			continue
		_bench_col.add_child(_build_bench_card(c))
		has_bench = true

	if not has_bench:
		var none_lbl := Label.new()
		none_lbl.text = "No companions on bench."
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		none_lbl.add_theme_font_size_override("font_size", 11)
		_bench_col.add_child(none_lbl)


func _build_active_card(key: String) -> Control:
	var c: Dictionary = GameData.get_companion(key)
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.04, 0.07, 0.04, 0.9)
	cs.border_color = Color(0.3, 0.75, 0.35)
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(4)
	cs.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", cs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	# Portrait + name row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	vb.add_child(top_row)
	top_row.add_child(_make_portrait(key, 44))

	var info_vb := VBoxContainer.new()
	info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vb.add_theme_constant_override("separation", 2)
	top_row.add_child(info_vb)

	var name_lbl := Label.new()
	name_lbl.text = c.get("name", key)
	name_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	name_lbl.add_theme_font_size_override("font_size", 13)
	info_vb.add_child(name_lbl)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP %d / %d  ATK %d  DEF %d" % [c.get("hp", 0), c.get("hp_max", 1), c.get("attack", 0), c.get("defense", 0)]
	hp_lbl.add_theme_font_size_override("font_size", 11)
	hp_lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 0.75))
	info_vb.add_child(hp_lbl)

	# ── Tactic selector ──
	var tactic_hdr := Label.new()
	tactic_hdr.text = "TACTIC"
	tactic_hdr.add_theme_font_size_override("font_size", 10)
	tactic_hdr.add_theme_color_override("font_color", Color(0.55, 0.65, 0.6))
	vb.add_child(tactic_hdr)

	var tactic_row := HBoxContainer.new()
	tactic_row.add_theme_constant_override("separation", 3)
	vb.add_child(tactic_row)

	var current_tactic: String = c.get("tactic", "balanced")
	var tactics: Array = [
		["balanced",  "Balanced"],
		["healer",    "Healer"],
		["berserker", "Berserker"],
		["defender",  "Defender"],
	]
	for tdef in tactics:
		var tid: String  = tdef[0]
		var tlbl: String = tdef[1]
		var tbtn := Button.new()
		tbtn.text = tlbl
		tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tbtn.custom_minimum_size = Vector2(0, 24)
		tbtn.add_theme_font_size_override("font_size", 10)
		var is_sel: bool = (tid == current_tactic)
		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color     = Color(0.12, 0.32, 0.15) if is_sel else Color(0.07, 0.07, 0.09)
		btn_style.border_color = Color(0.35, 0.85, 0.4)  if is_sel else Color(0.28, 0.28, 0.32)
		btn_style.set_border_width_all(1)
		btn_style.set_corner_radius_all(3)
		btn_style.set_content_margin_all(3)
		tbtn.add_theme_stylebox_override("normal", btn_style)
		var cap_key: String = key
		var cap_tid: String = tid
		tbtn.pressed.connect(func():
			GameData.set_companion_tactic(cap_key, cap_tid)
			_refresh()
		)
		tactic_row.add_child(tbtn)

	var send_btn := Button.new()
	send_btn.text = "Send to Camp"
	send_btn.custom_minimum_size = Vector2(0, 26)
	send_btn.pressed.connect(func():
		var aidx: int = GameData.active_companions.find(key)
		if aidx >= 0:
			GameData.active_companions.remove_at(aidx)
		_refresh()
	)
	vb.add_child(send_btn)

	return card


func _build_bench_card(c: Dictionary) -> Control:
	var key: String = c.get("key", "")
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.05, 0.02, 0.9)
	cs.border_color = Color(0.5, 0.38, 0.1)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(4)
	cs.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", cs)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	# Portrait + name row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	vb.add_child(top_row)
	top_row.add_child(_make_portrait(key, 44))

	var info_vb := VBoxContainer.new()
	info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vb.add_theme_constant_override("separation", 2)
	top_row.add_child(info_vb)

	var name_lbl := Label.new()
	name_lbl.text = c.get("name", key)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.65, 0.2))
	name_lbl.add_theme_font_size_override("font_size", 13)
	info_vb.add_child(name_lbl)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP %d / %d  ATK %d  DEF %d" % [c.get("hp", 0), c.get("hp_max", 1), c.get("attack", 0), c.get("defense", 0)]
	hp_lbl.add_theme_font_size_override("font_size", 11)
	hp_lbl.add_theme_color_override("font_color", Color(0.75, 0.65, 0.45))
	info_vb.add_child(hp_lbl)

	var slots: int = GameData.get_companion_slots()
	var can_activate: bool = GameData.active_companions.size() < slots
	var set_btn := Button.new()
	set_btn.text = "Set Active" if can_activate else "Party Full"
	set_btn.disabled = not can_activate
	set_btn.custom_minimum_size = Vector2(0, 26)
	set_btn.pressed.connect(func():
		if GameData.active_companions.size() < GameData.get_companion_slots():
			GameData.active_companions.append(key)
			_refresh()
	)
	vb.add_child(set_btn)

	return card


func _make_portrait(key: String, size: int) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(size, size)
	container.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var path := EnemyDB.get_portrait_path(key)
	if path == "" or not ResourceLoader.exists(path):
		path = EnemyDB.get_ready_texture_path(key)

	if path != "" and ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.texture = load(path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		container.add_child(tex)
	else:
		var placeholder := ColorRect.new()
		placeholder.color = Color(0.08, 0.07, 0.1)
		placeholder.set_anchors_preset(Control.PRESET_FULL_RECT)
		container.add_child(placeholder)

	return container


func _on_close():
	roster_closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()
