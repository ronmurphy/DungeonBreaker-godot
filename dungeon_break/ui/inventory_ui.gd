extends CanvasLayer
## Inventory UI — paper doll, backpack grid, character stats.
##
## Three columns:
##   Left:   Paper doll — equipment slots arranged around character portrait
##   Centre: Backpack grid (6×4) + selected item detail panel below
##   Right:  Character stats — name, class, floor, STR/DEX/INT/LCK, HP bar, AC/ATK

const ItemDB_Script = preload("res://dungeon_break/data/item_db.gd")

# ── References ────────────────────────────────────────────────────────────────
var _backpack_grid: GridContainer = null
var _detail_name: Label = null
var _detail_desc: Label = null
var _detail_stats: Label = null
var _action_row: HBoxContainer = null
var _gold_label: Label = null
var _toast_label: Label = null
var _toast_timer: float = 0.0

# Stats column
var _stat_hp_fill: ColorRect = null
var _stat_hp_label: Label = null
var _stat_name_label: Label = null
var _stat_class_label: Label = null
var _stat_floor_label: Label = null
var _stat_str_label: Label = null
var _stat_dex_label: Label = null
var _stat_int_label: Label = null
var _stat_lck_label: Label = null
var _stat_combat_label: Label = null

# Equipment slots: slot_idx (-100…-104) → { btn, icon_rect, style, slot_label, base_border }
var _equip_slots: Dictionary = {}

var _selected_index: int = -1
var _is_open: bool = false


func _ready():
	_build_ui()
	visible = false


func toggle():
	_is_open = not _is_open
	visible = _is_open
	if _is_open:
		_refresh()


# ── Build ─────────────────────────────────────────────────────────────────────

func _build_ui():
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var panel := PanelContainer.new()
	panel.name = "InventoryPanel"
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.04, 0.08, 0.97)
	ps.border_color = Color(0.55, 0.45, 0.3)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -425
	panel.offset_right  =  425
	panel.offset_top    = -275
	panel.offset_bottom =  275
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	# ── Header ──
	var header := HBoxContainer.new()
	root.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "INVENTORY"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕  Close  [ESC]"
	close_btn.add_theme_font_size_override("font_size", 12)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.06, 0.06, 0.9)
	cs.border_color = Color(0.55, 0.25, 0.25)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(4)
	cs.set_content_margin_all(4)
	close_btn.add_theme_stylebox_override("normal", cs)
	close_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
	close_btn.pressed.connect(func(): _is_open = false; visible = false)
	header.add_child(close_btn)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.45, 0.38, 0.25, 0.6))
	root.add_child(sep)

	# ── Body ──
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_build_paper_doll_col(body)

	var vd1 := VSeparator.new()
	vd1.add_theme_color_override("color", Color(0.4, 0.35, 0.25, 0.5))
	body.add_child(vd1)

	_build_backpack_col(body)

	var vd2 := VSeparator.new()
	vd2.add_theme_color_override("color", Color(0.4, 0.35, 0.25, 0.5))
	body.add_child(vd2)

	_build_stats_col(body)

	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 15)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast_label.offset_top = -40
	_toast_label.offset_bottom = -10
	_toast_label.visible = false
	add_child(_toast_label)


func _build_paper_doll_col(parent: HBoxContainer):
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 195
	col.add_theme_constant_override("separation", 5)
	parent.add_child(col)

	var col_title := Label.new()
	col_title.text = "EQUIPMENT"
	col_title.add_theme_font_size_override("font_size", 13)
	col_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	col_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(col_title)

	# Head slot (centered)
	var head_row := HBoxContainer.new()
	head_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(head_row)
	head_row.add_child(_make_equip_slot("Helm", -101, Color(0.3, 0.4, 0.65, 0.7)))

	# Weapon | Portrait | Chest
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 5)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(mid)

	mid.add_child(_make_equip_slot("Weapon", -100, Color(0.65, 0.25, 0.25, 0.7)))

	var pf := PanelContainer.new()
	var pfs := StyleBoxFlat.new()
	pfs.bg_color = Color(0.08, 0.06, 0.12)
	pfs.border_color = Color(0.4, 0.35, 0.55)
	pfs.set_border_width_all(1)
	pfs.set_corner_radius_all(4)
	pfs.set_content_margin_all(2)
	pf.add_theme_stylebox_override("panel", pfs)
	mid.add_child(pf)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(72, 72)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if ResourceLoader.exists("res://assets/art/entities/human_male.png"):
		portrait.texture = load("res://assets/art/entities/human_male.png")
	pf.add_child(portrait)

	mid.add_child(_make_equip_slot("Chest", -102, Color(0.3, 0.4, 0.65, 0.7)))

	# Legs slot
	var legs_row := HBoxContainer.new()
	legs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(legs_row)
	legs_row.add_child(_make_equip_slot("Legs", -103, Color(0.3, 0.4, 0.65, 0.7)))

	# Boots slot
	var boots_row := HBoxContainer.new()
	boots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(boots_row)
	boots_row.add_child(_make_equip_slot("Boots", -104, Color(0.3, 0.4, 0.65, 0.7)))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 14)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_gold_label)


func _make_equip_slot(slot_label: String, slot_idx: int, border_color: Color) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	wrap.custom_minimum_size.x = 60

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(58, 58)
	btn.clip_contents = true

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.1, 0.9)
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(2)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.15, 0.12, 0.2)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_font_size_override("font_size", 9)
	btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	btn.text = slot_label

	# Pre-created icon rect (shown when item equipped)
	var icon_rect := TextureRect.new()
	icon_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.visible = false
	btn.add_child(icon_rect)

	btn.pressed.connect(_on_slot_clicked.bind(slot_idx))
	wrap.add_child(btn)

	var lbl := Label.new()
	lbl.text = slot_label
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.5))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(lbl)

	_equip_slots[slot_idx] = {
		"btn": btn, "style": style,
		"icon_rect": icon_rect,
		"slot_label": slot_label,
		"base_border": border_color,
	}
	return wrap


func _build_backpack_col(parent: HBoxContainer):
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	var col_title := Label.new()
	col_title.text = "BACKPACK"
	col_title.add_theme_font_size_override("font_size", 13)
	col_title.add_theme_color_override("font_color", Color(0.65, 0.75, 1.0))
	col_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(col_title)

	_backpack_grid = GridContainer.new()
	_backpack_grid.columns = 6
	_backpack_grid.add_theme_constant_override("h_separation", 4)
	_backpack_grid.add_theme_constant_override("v_separation", 4)
	col.add_child(_backpack_grid)

	# Detail panel (below grid, expands to fill)
	var det_bg := PanelContainer.new()
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.06, 0.05, 0.09, 0.88)
	ds.border_color = Color(0.35, 0.3, 0.45)
	ds.set_border_width_all(1)
	ds.set_corner_radius_all(5)
	ds.set_content_margin_all(10)
	det_bg.add_theme_stylebox_override("panel", ds)
	det_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(det_bg)

	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 5)
	det_bg.add_child(dv)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 14)
	_detail_name.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_detail_name.clip_text = true
	dv.add_child(_detail_name)

	_detail_desc = Label.new()
	_detail_desc.add_theme_font_size_override("font_size", 11)
	_detail_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	dv.add_child(_detail_desc)

	_detail_stats = Label.new()
	_detail_stats.add_theme_font_size_override("font_size", 12)
	_detail_stats.add_theme_color_override("font_color", Color(0.5, 0.85, 0.55))
	dv.add_child(_detail_stats)

	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 6)
	dv.add_child(_action_row)


func _build_stats_col(parent: HBoxContainer):
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 175
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	var col_title := Label.new()
	col_title.text = "CHARACTER"
	col_title.add_theme_font_size_override("font_size", 13)
	col_title.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	col_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(col_title)

	_stat_name_label = Label.new()
	_stat_name_label.add_theme_font_size_override("font_size", 15)
	_stat_name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	_stat_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stat_name_label.clip_text = true
	col.add_child(_stat_name_label)

	_stat_class_label = Label.new()
	_stat_class_label.add_theme_font_size_override("font_size", 12)
	_stat_class_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.65))
	_stat_class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_stat_class_label)

	_stat_floor_label = Label.new()
	_stat_floor_label.add_theme_font_size_override("font_size", 11)
	_stat_floor_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	_stat_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_stat_floor_label)

	var sep1 := HSeparator.new()
	sep1.add_theme_color_override("color", Color(0.35, 0.3, 0.4, 0.5))
	col.add_child(sep1)

	# 2×2 stat grid
	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 8)
	sg.add_theme_constant_override("v_separation", 5)
	col.add_child(sg)

	_stat_str_label = _make_stat_row_label("STR", Color(1.0, 0.65, 0.35))
	_stat_dex_label = _make_stat_row_label("DEX", Color(0.4, 0.9, 0.5))
	_stat_int_label = _make_stat_row_label("INT", Color(0.5, 0.7, 1.0))
	_stat_lck_label = _make_stat_row_label("LCK", Color(0.85, 0.5, 0.9))
	sg.add_child(_stat_str_label)
	sg.add_child(_stat_dex_label)
	sg.add_child(_stat_int_label)
	sg.add_child(_stat_lck_label)

	var sep2 := HSeparator.new()
	sep2.add_theme_color_override("color", Color(0.35, 0.3, 0.4, 0.5))
	col.add_child(sep2)

	# HP bar
	var hp_bg := Control.new()
	hp_bg.custom_minimum_size = Vector2(0, 10)
	hp_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hp_bg_r := ColorRect.new()
	hp_bg_r.color = Color(0.07, 0.03, 0.03)
	hp_bg_r.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_bg.add_child(hp_bg_r)
	_stat_hp_fill = ColorRect.new()
	_stat_hp_fill.color = Color(0.2, 0.75, 0.3)
	_stat_hp_fill.anchor_left = 0.0
	_stat_hp_fill.anchor_top = 0.0
	_stat_hp_fill.anchor_right = 1.0
	_stat_hp_fill.anchor_bottom = 1.0
	hp_bg.add_child(_stat_hp_fill)
	col.add_child(hp_bg)

	_stat_hp_label = Label.new()
	_stat_hp_label.add_theme_font_size_override("font_size", 12)
	_stat_hp_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	_stat_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_stat_hp_label)

	_stat_combat_label = Label.new()
	_stat_combat_label.add_theme_font_size_override("font_size", 12)
	_stat_combat_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_stat_combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_stat_combat_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)


func _make_stat_row_label(prefix: String, color: Color) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	lbl.text = prefix + "  —"
	return lbl


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh():
	_refresh_equipment()
	_refresh_backpack()
	_refresh_detail()
	_refresh_stats()


func _refresh_equipment():
	var slot_data: Dictionary = {
		-100: GameData.equip_weapon,
		-101: GameData.equip_helm,
		-102: GameData.equip_chest,
		-103: GameData.equip_legs,
		-104: GameData.equip_boots,
	}

	_gold_label.text = "◆  %d  gold" % GameData.gold

	for slot_idx in _equip_slots:
		var sd: Dictionary = _equip_slots[slot_idx]
		var btn: Button = sd["btn"]
		var style: StyleBoxFlat = sd["style"]
		var icon_rect: TextureRect = sd["icon_rect"]
		var item: Dictionary = slot_data.get(slot_idx, {})
		var has_item: bool = not item.is_empty()

		if has_item:
			var icon_path: String = item.get("icon", "")
			if icon_path != "" and ResourceLoader.exists(icon_path):
				icon_rect.texture = load(icon_path)
				icon_rect.visible = true
				btn.text = ""
			else:
				icon_rect.visible = false
				btn.text = item.get("name", sd["slot_label"]).substr(0, 6)
			style.border_color = (sd["base_border"] as Color).lightened(0.4)
			style.set_border_width_all(2)
		else:
			icon_rect.visible = false
			btn.text = sd["slot_label"]
			style.border_color = sd["base_border"]
			style.set_border_width_all(1)

		if _selected_index == slot_idx:
			style.border_color = Color(1.0, 1.0, 0.4)
			style.set_border_width_all(2)


func _refresh_backpack():
	for child in _backpack_grid.get_children():
		child.queue_free()

	for i in GameData.BACKPACK_SIZE:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(46, 46)
		btn.clip_contents = true

		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(3)
		s.set_content_margin_all(2)

		if i < GameData.backpack.size():
			var item: Dictionary = GameData.backpack[i]
			var icon_path: String = item.get("icon", "")

			if icon_path != "" and ResourceLoader.exists(icon_path):
				var tex: Texture2D = load(icon_path)
				if tex:
					var tr := TextureRect.new()
					tr.texture = tex
					tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
					tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					tr.custom_minimum_size = Vector2(40, 40)
					tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
					btn.add_child(tr)
			else:
				btn.text = item.get("name", "?").substr(0, 3)
				btn.add_theme_font_size_override("font_size", 9)

			match item.get("type", -1):
				0:          s.bg_color = Color(0.2, 0.1, 0.1, 0.9);  s.border_color = Color(0.8, 0.3, 0.3)
				1, 2, 3, 4: s.bg_color = Color(0.1, 0.1, 0.2, 0.9);  s.border_color = Color(0.3, 0.5, 0.85)
				5:          s.bg_color = Color(0.1, 0.14, 0.07, 0.9); s.border_color = Color(0.5, 0.75, 0.3)
				6:          s.bg_color = Color(0.14, 0.07, 0.14, 0.9);s.border_color = Color(0.75, 0.3, 0.75)
				_:          s.bg_color = Color(0.1, 0.1, 0.1, 0.9);  s.border_color = Color(0.3, 0.3, 0.35)

			if i == _selected_index:
				s.border_color = Color(1.0, 1.0, 0.4)
				s.set_border_width_all(2)
			else:
				s.set_border_width_all(1)

			btn.pressed.connect(_on_item_clicked.bind(i))
		else:
			s.bg_color = Color(0.06, 0.06, 0.08, 0.6)
			s.border_color = Color(0.14, 0.14, 0.18)
			s.set_border_width_all(1)

		btn.add_theme_stylebox_override("normal", s)
		var sh := s.duplicate()
		sh.bg_color = s.bg_color.lightened(0.12)
		btn.add_theme_stylebox_override("hover", sh)
		_backpack_grid.add_child(btn)


func _refresh_detail():
	_detail_name.text = ""
	_detail_desc.text = ""
	_detail_stats.text = ""
	for c in _action_row.get_children():
		c.queue_free()

	var item: Dictionary = _get_selected_item()
	if item.is_empty():
		_detail_name.text = "Select an item"
		_detail_desc.text = "Click a backpack slot or equipment slot to view details."
		return

	_detail_name.text = item.get("name", "Unknown")
	_detail_desc.text = item.get("description", "")

	var stats_text := ""
	var atk: int = item.get("attack_bonus", 0)
	var aac: int = item.get("ac_bonus", 0)
	var heal: int = item.get("heal_amount", 0)
	var val: int = item.get("value", 0)
	if atk != 0:  stats_text += "ATK %+d  " % atk
	if aac != 0:  stats_text += "AC %+d  " % aac
	if heal > 0:  stats_text += "HEAL +%d  " % heal
	if val > 0:   stats_text += "  ◆ %d g" % val
	_detail_stats.text = stats_text.strip_edges()

	var item_type: int = item.get("type", -1)

	if _selected_index <= -100:
		_add_action_btn("Unequip", Color(0.7, 0.55, 0.3), func():
			var slot_type: int = -(_selected_index + 100)
			var old: Dictionary = ItemDB.unequip_slot(slot_type)
			if old and not old.is_empty():
				ItemDB.add_to_backpack(old)
				_show_toast("Unequipped  %s" % old.get("name", ""))
			_selected_index = -1
			_refresh()
		)
	else:
		if item_type in [ItemDB_Script.ItemType.WEAPON, ItemDB_Script.ItemType.HELM,
				ItemDB_Script.ItemType.CHEST, ItemDB_Script.ItemType.LEGS,
				ItemDB_Script.ItemType.BOOTS]:
			_add_action_btn("Equip", Color(0.3, 0.6, 1.0), func():
				var removed: Dictionary = ItemDB.remove_from_backpack(_selected_index)
				if not removed.is_empty():
					var old: Dictionary = ItemDB.equip_item(removed)
					if old and not old.is_empty():
						ItemDB.add_to_backpack(old)
					_show_toast("Equipped  %s" % removed.get("name", ""))
				_selected_index = -1
				_refresh()
			)

		if item_type == ItemDB_Script.ItemType.FOOD or item_type == ItemDB_Script.ItemType.POTION:
			_add_action_btn("Use", Color(0.3, 0.85, 0.35), func():
				var removed: Dictionary = ItemDB.remove_from_backpack(_selected_index)
				if not removed.is_empty():
					var msg: String = ItemDB.use_item(removed)
					_show_toast(msg if msg != "" else "Used  %s" % removed.get("name", ""))
				_selected_index = -1
				_refresh()
			)

		_add_action_btn("Drop", Color(0.6, 0.3, 0.3), func():
			var removed: Dictionary = ItemDB.remove_from_backpack(_selected_index)
			if not removed.is_empty():
				_show_toast("Dropped  %s" % removed.get("name", ""))
			_selected_index = -1
			_refresh()
		)


func _refresh_stats():
	var hp_ratio := clampf(float(GameData.hp) / float(max(GameData.hp_max, 1)), 0.0, 1.0)
	_stat_hp_fill.anchor_right = hp_ratio
	if hp_ratio > 0.6:
		_stat_hp_fill.color = Color(0.2, 0.75, 0.3)
	elif hp_ratio > 0.3:
		_stat_hp_fill.color = Color(0.85, 0.65, 0.1)
	else:
		_stat_hp_fill.color = Color(0.8, 0.15, 0.1)

	_stat_hp_label.text = "HP  %d / %d" % [GameData.hp, GameData.hp_max]
	_stat_combat_label.text = "AC %d   ATK %d" % [GameData.get_total_ac(), GameData.get_attack_power()]

	var class_str: String = GameData.CLASS_NAMES.get(GameData.player_class, "Hero")
	_stat_name_label.text = GameData.player_name
	_stat_class_label.text = class_str
	_stat_floor_label.text = "Floor %d   ◆ %d gold" % [GameData.current_floor, GameData.gold]

	_stat_str_label.text = "STR  %d" % GameData.stat_str
	_stat_dex_label.text = "DEX  %d" % GameData.stat_dex
	_stat_int_label.text = "INT  %d" % GameData.stat_int
	_stat_lck_label.text = "LCK  %d" % GameData.stat_lck


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_selected_item() -> Dictionary:
	if _selected_index >= 0 and _selected_index < GameData.backpack.size():
		return GameData.backpack[_selected_index]
	match _selected_index:
		-100: return GameData.equip_weapon
		-101: return GameData.equip_helm
		-102: return GameData.equip_chest
		-103: return GameData.equip_legs
		-104: return GameData.equip_boots
	return {}


func _on_item_clicked(index: int):
	_selected_index = index
	_refresh()


func _on_slot_clicked(slot_idx: int):
	_selected_index = slot_idx
	_refresh()


func _add_action_btn(text: String, color: Color, callback: Callable):
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(80, 28)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", Color.WHITE)
	var s := StyleBoxFlat.new()
	s.bg_color = color.darkened(0.55)
	s.border_color = color
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(4)
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate()
	h.bg_color = color.darkened(0.3)
	btn.add_theme_stylebox_override("hover", h)
	btn.pressed.connect(callback)
	_action_row.add_child(btn)


func _show_toast(text: String):
	_toast_label.text = text
	_toast_label.visible = true
	_toast_timer = 2.5


func _process(delta: float):
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_label.visible = false


func _unhandled_input(event: InputEvent):
	if not (event is InputEventKey) or not event.pressed:
		return

	if event.keycode == KEY_I or event.keycode == KEY_TAB:
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.keycode == KEY_ESCAPE:
		_is_open = false
		visible = false
		get_viewport().set_input_as_handled()
	elif not _is_open and event.keycode == KEY_F:
		_quick_use_consumable()
		get_viewport().set_input_as_handled()
	elif not _is_open:
		var kc: int = event.keycode
		if kc >= KEY_1 and kc <= KEY_6:
			var idx: int = kc - KEY_1
			if idx < GameData.backpack.size():
				_quick_use_at_index(idx)
			get_viewport().set_input_as_handled()


func _quick_use_consumable():
	for i in GameData.backpack.size():
		var item: Dictionary = GameData.backpack[i]
		var t: int = item.get("type", -1)
		if t == ItemDB.ItemType.FOOD or t == ItemDB.ItemType.POTION:
			_quick_use_at_index(i)
			return
	_show_toast("No food or potions!")


func _quick_use_at_index(idx: int):
	if idx < 0 or idx >= GameData.backpack.size():
		return
	var item: Dictionary = GameData.backpack[idx]
	var t: int = item.get("type", -1)
	if t == ItemDB.ItemType.FOOD or t == ItemDB.ItemType.POTION:
		var msg: String = ItemDB.use_item(item)
		ItemDB.remove_from_backpack(idx)
		_show_toast("%s: %s" % [item.get("name", "Item"), msg])
		if _is_open:
			_refresh()
	elif t in [ItemDB.ItemType.WEAPON, ItemDB.ItemType.HELM, ItemDB.ItemType.CHEST,
			ItemDB.ItemType.LEGS, ItemDB.ItemType.BOOTS]:
		var old: Dictionary = ItemDB.equip_item(item)
		ItemDB.remove_from_backpack(idx)
		if old and not old.is_empty():
			ItemDB.add_to_backpack(old)
		_show_toast("Equipped  %s" % item.get("name", "item"))
		if _is_open:
			_refresh()
