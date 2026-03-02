extends CanvasLayer
## JobChangeUI - simple camp modal for switching the hero class at Azure Flame.

signal jobs_closed

var _list_box: VBoxContainer = null
var _feedback_label: Label = null
var _preview_dummy: TextureRect = null
var _preview_name: Label = null
var _preview_info: Label = null
var _preview_unlock: Label = null
var _selected_job: int = -1
var _scaled_tex_cache: Dictionary = {}


func _ready() -> void:
	_build_ui()
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close()


func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.name = "JobChangePanel"
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.04, 0.08, 0.97)
	ps.border_color = Color(0.45, 0.55, 0.9)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -270
	panel.offset_bottom = 270
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "AZURE FLAME - JOBS"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "Close [Esc]"
	close_btn.custom_minimum_size = Vector2(110, 28)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	var sub := Label.new()
	sub.text = "Switching jobs changes base stats and max HP for this run."
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.67, 0.7, 0.8))
	root.add_child(sub)

	root.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(385, 0)
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ls := StyleBoxFlat.new()
	ls.bg_color = Color(0.08, 0.07, 0.12, 0.9)
	ls.border_color = Color(0.3, 0.33, 0.42)
	ls.set_border_width_all(1)
	ls.set_corner_radius_all(4)
	ls.set_content_margin_all(8)
	left_panel.add_theme_stylebox_override("panel", ls)
	body.add_child(left_panel)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	left_panel.add_child(lv)

	var jobs_lbl := Label.new()
	jobs_lbl.text = "JOBS (rank increases on combat wins)"
	jobs_lbl.add_theme_font_size_override("font_size", 12)
	jobs_lbl.add_theme_color_override("font_color", Color(0.66, 0.72, 0.86))
	lv.add_child(jobs_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.07, 0.08, 0.12, 0.9)
	rs.border_color = Color(0.28, 0.4, 0.6)
	rs.set_border_width_all(1)
	rs.set_corner_radius_all(4)
	rs.set_content_margin_all(10)
	right_panel.add_theme_stylebox_override("panel", rs)
	body.add_child(right_panel)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 6)
	right_panel.add_child(rv)

	_preview_name = Label.new()
	_preview_name.add_theme_font_size_override("font_size", 16)
	_preview_name.add_theme_color_override("font_color", Color(0.82, 0.91, 1.0))
	_preview_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_preview_name)

	_preview_dummy = TextureRect.new()
	_preview_dummy.custom_minimum_size = Vector2(0, 320)
	_preview_dummy.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_dummy.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_preview_dummy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rv.add_child(_preview_dummy)

	_preview_info = Label.new()
	_preview_info.add_theme_font_size_override("font_size", 12)
	_preview_info.add_theme_color_override("font_color", Color(0.68, 0.76, 0.88))
	_preview_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_preview_info)

	_preview_unlock = Label.new()
	_preview_unlock.add_theme_font_size_override("font_size", 11)
	_preview_unlock.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	_preview_unlock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_preview_unlock)

	_feedback_label = Label.new()
	_feedback_label.add_theme_font_size_override("font_size", 13)
	_feedback_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_feedback_label)

	_selected_job = int(GameData.player_class)
	_refresh()
	_set_preview(_selected_job)


func _refresh() -> void:
	if _list_box == null:
		return
	for child in _list_box.get_children():
		child.queue_free()

	for job_id in _job_order():
		_list_box.add_child(_make_job_card(int(job_id)))


func _make_job_card(job_id: int) -> Control:
	var row_panel := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.1, 0.08, 0.14, 0.9)
	rs.border_color = Color(0.3, 0.3, 0.38)
	rs.set_border_width_all(1)
	rs.set_corner_radius_all(4)
	rs.set_content_margin_all(8)
	row_panel.add_theme_stylebox_override("panel", rs)

	row_panel.mouse_entered.connect(func() -> void:
		_set_preview(job_id)
	)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)

	var sym := TextureRect.new()
	sym.custom_minimum_size = Vector2(28, 28)
	sym.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	sym.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var sym_path: String = GameData.get_job_symbol_path(job_id)
	var sym_tex: Texture2D = _get_scaled_texture(sym_path, 64)
	if sym_tex:
		sym.texture = sym_tex
	row.add_child(sym)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	row.add_child(left)

	var job_name: String = GameData.CLASS_NAMES.get(job_id, "Unknown")
	var title := Label.new()
	title.text = job_name
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	left.add_child(title)

	var stats: Dictionary = GameData.CLASS_BASE_STATS.get(job_id, {})
	var hp_max: int = 25 + int(stats.get("STR", 1)) * 4
	var stat_lbl := Label.new()
	stat_lbl.text = "STR %d  DEX %d  INT %d  LCK %d  HP %d" % [
		int(stats.get("STR", 0)),
		int(stats.get("DEX", 0)),
		int(stats.get("INT", 0)),
		int(stats.get("LCK", 0)),
		hp_max
	]
	stat_lbl.add_theme_font_size_override("font_size", 11)
	stat_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85))
	left.add_child(stat_lbl)

	var blurb := Label.new()
	var rank: int = GameData.get_job_rank(job_id)
	blurb.text = "R%d  -  %s" % [rank, str(_job_blurbs().get(job_id, ""))]
	blurb.add_theme_font_size_override("font_size", 11)
	blurb.add_theme_color_override("font_color", Color(0.6, 0.66, 0.75))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(blurb)

	var req := Label.new()
	var unlocked: bool = GameData.is_job_unlocked(job_id)
	req.text = "Unlocked" if unlocked else GameData.get_job_unlock_req_text(job_id)
	req.add_theme_font_size_override("font_size", 10)
	req.add_theme_color_override("font_color",
		Color(0.45, 0.95, 0.65) if unlocked else Color(0.82, 0.7, 0.45))
	left.add_child(req)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(106, 30)
	btn.expand_icon = true
	if sym_tex:
		btn.icon = sym_tex
	if job_id == GameData.player_class:
		btn.text = "Current"
		btn.disabled = true
	elif not unlocked:
		btn.text = "Locked"
		btn.disabled = true
		btn.tooltip_text = GameData.get_job_unlock_req_text(job_id)
	else:
		btn.text = "Equip Job"
		var cap_job: int = job_id
		btn.pressed.connect(func():
			var changed: bool = GameData.change_job(cap_job)
			if changed:
				_feedback_label.text = "Class changed to %s." % GameData.CLASS_NAMES.get(cap_job, "Unknown")
				_selected_job = cap_job
				_set_preview(cap_job)
			else:
				_feedback_label.text = "Class already equipped."
			_refresh()
		)
	row.add_child(btn)

	return row_panel


func _set_preview(job_id: int) -> void:
	_selected_job = job_id
	if _preview_name:
		_preview_name.text = str(GameData.CLASS_NAMES.get(job_id, "Unknown"))
	if _preview_info:
		_preview_info.text = "Rank %d" % GameData.get_job_rank(job_id)
	if _preview_unlock:
		if GameData.is_job_unlocked(job_id):
			_preview_unlock.text = "Status: Unlocked"
			_preview_unlock.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
		else:
			_preview_unlock.text = GameData.get_job_unlock_req_text(job_id)
			_preview_unlock.add_theme_color_override("font_color", Color(0.82, 0.7, 0.45))
	if _preview_dummy:
		var dpath: String = GameData.get_job_dummy_path(job_id)
		var max_px: int = 540
		var rect_size: Vector2 = _preview_dummy.size
		if rect_size.x > 8.0 and rect_size.y > 8.0:
			max_px = int(maxf(220.0, minf(rect_size.x, rect_size.y) * 1.9))
		var dtex: Texture2D = _get_scaled_texture(dpath, max_px)
		if dtex:
			_preview_dummy.texture = dtex
		else:
			_preview_dummy.texture = null


func _close() -> void:
	jobs_closed.emit()
	queue_free()


func _job_order() -> Array:
	return [
		0, # Vanguard
		1, # Scoundrel
		2, # Arcanist
		3, # Confessor
		4, # Strider
		5, # Minstrel
		6, # Templar
		7, # Reanimator
		8, # Tinkerer
	]


func _job_blurbs() -> Dictionary:
	return {
		0: "Frontline bruiser. High STR and durability.",
		1: "Fast striker. High DEX and crit potential.",
		2: "Pure caster. High INT for spell pressure.",
		3: "Support caster. Reliable healing toolkit.",
		4: "Mobile hunter. Balanced STR/DEX skirmisher.",
		5: "Trickster support. LCK/INT utility focus.",
		6: "Holy fighter. Durable melee with magic.",
		7: "Dark caster. High INT control profile.",
		8: "Hybrid specialist. DEX/INT gadget style.",
	}


func _get_scaled_texture(path: String, max_px: int) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var safe_max: int = maxi(16, max_px)
	var cache_key: String = "%s#%d" % [path, safe_max]
	if _scaled_tex_cache.has(cache_key):
		return _scaled_tex_cache[cache_key] as Texture2D

	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		var raw: Texture2D = load(path)
		_scaled_tex_cache[cache_key] = raw
		return raw

	var w: int = img.get_width()
	var h: int = img.get_height()
	var max_dim: int = maxi(w, h)
	if max_dim > safe_max:
		var scale: float = float(safe_max) / float(max_dim)
		var nw: int = maxi(1, int(round(float(w) * scale)))
		var nh: int = maxi(1, int(round(float(h) * scale)))
		img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)

	var tex: Texture2D = ImageTexture.create_from_image(img)
	_scaled_tex_cache[cache_key] = tex
	return tex
