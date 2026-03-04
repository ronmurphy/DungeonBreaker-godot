extends CanvasLayer
## ForgeUI — modal forge interface for Steven (weapons) and Mahan (armor).
##
## Shows available skyshards, lets the player forge class weapons/armor,
## manage forge skill slots, and reforge merged items.
## Instantiated by game.gd on NPC interaction with enhanced_weapons_shop
## or enhanced_armor_shop roles.

signal forge_closed

var _npc_key: String = ""
var _forge_type: String = ""  # "weapon" or "armor"
var _gold_label: Label = null
var _list_box: VBoxContainer = null
var _feedback_label: Label = null
var _feedback_timer: float = 0.0
var _skill_section: VBoxContainer = null


func _ready() -> void:
	visible = false


## Open forge for the given NPC key. forge_type is "weapon" or "armor".
func open(npc_key: String) -> void:
	_npc_key = npc_key
	var npc_def: Dictionary = NpcDB.get_def(npc_key)
	var role: String = npc_def.get("role", "") as String
	_forge_type = "weapon" if role == "enhanced_weapons_shop" else "armor"
	_build_ui()
	visible = true


## Close and free the forge UI.
func close_forge() -> void:
	forge_closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_forge()


func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0 and _feedback_label:
			_feedback_label.text = ""


# ══════════════════════════════════════════════════════════════════════════════
# BUILD UI
# ══════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var npc_def: Dictionary = NpcDB.get_def(_npc_key)
	var npc_name: String = npc_def.get("name", _npc_key) as String
	var sprite_prefix: String = npc_def.get("sprite_prefix", "") as String

	# ── dim overlay ──
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ── main panel ──
	var panel := PanelContainer.new()
	panel.name = "ForgePanel"
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.04, 0.02, 0.97)
	ps.border_color = Color(0.8, 0.5, 0.15)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -340
	panel.offset_right  =  340
	panel.offset_top    = -300
	panel.offset_bottom =  300
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	# ── header ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	if sprite_prefix != "":
		var portrait_path := sprite_prefix + ".png"
		if ResourceLoader.exists(portrait_path):
			var portrait := TextureRect.new()
			portrait.custom_minimum_size = Vector2(48, 64)
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.texture = load(portrait_path)
			header.add_child(portrait)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_col)

	var forge_label: String = "Weapon Forge" if _forge_type == "weapon" else "Armor Forge"
	var title_lbl := Label.new()
	title_lbl.text = "%s  —  %s" % [npc_name, forge_label]
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_col.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "Bring a Class Skyshard + %dg to forge powerful gear." % ForgeSystem.FORGE_COST
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	title_col.add_child(desc_lbl)

	# ── gold display ──
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 14)
	_update_gold_label()
	root.add_child(_gold_label)

	# ── separator ──
	root.add_child(HSeparator.new())

	# ── forge list ──
	var forge_header := Label.new()
	forge_header.text = "— Available Forges —"
	forge_header.add_theme_font_size_override("font_size", 14)
	forge_header.add_theme_color_override("font_color", Color(0.85, 0.7, 0.3))
	forge_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(forge_header)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	root.add_child(_list_box)

	_populate_forge_list()

	# ── separator ──
	root.add_child(HSeparator.new())

	# ── reforge section ──
	var reforge_header := Label.new()
	reforge_header.text = "— Reforge (Merge Two Forged Items) —"
	reforge_header.add_theme_font_size_override("font_size", 14)
	reforge_header.add_theme_color_override("font_color", Color(0.85, 0.5, 0.3))
	reforge_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(reforge_header)

	var reforge_desc := Label.new()
	reforge_desc.text = "Merge two forged %ss to combine their skills (%dg, -1 random stat)." % [_forge_type, ForgeSystem.REFORGE_COST]
	reforge_desc.add_theme_font_size_override("font_size", 11)
	reforge_desc.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	reforge_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(reforge_desc)

	_build_reforge_list(root)

	# ── separator ──
	root.add_child(HSeparator.new())

	# ── skill management section ──
	var skill_header := Label.new()
	skill_header.text = "— Forge Skill Slots (%d / %d) —" % [ForgeSystem.forge_skill_slots.size(), ForgeSystem.MAX_FORGE_SKILLS]
	skill_header.add_theme_font_size_override("font_size", 14)
	skill_header.add_theme_color_override("font_color", Color(0.3, 0.7, 0.85))
	skill_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(skill_header)

	_skill_section = VBoxContainer.new()
	_skill_section.add_theme_constant_override("separation", 4)
	root.add_child(_skill_section)

	_build_skill_management()

	# ── feedback label ──
	_feedback_label = Label.new()
	_feedback_label.add_theme_font_size_override("font_size", 13)
	_feedback_label.add_theme_color_override("font_color", Color(0.3, 1, 0.3))
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_feedback_label)

	# ── close button ──
	var close_btn := Button.new()
	close_btn.text = "Close  [Esc]"
	close_btn.pressed.connect(close_forge)
	root.add_child(close_btn)


# ══════════════════════════════════════════════════════════════════════════════
# FORGE LIST — shows available skyshards and what they can forge
# ══════════════════════════════════════════════════════════════════════════════

func _populate_forge_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()

	var available: Array[int] = ForgeSystem.get_available_forges()
	if available.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No Skyshards available. Clear a full floor as one class to earn one."
		none_lbl.add_theme_font_size_override("font_size", 12)
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		none_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list_box.add_child(none_lbl)
		return

	for cls_id in available:
		var item_map: Dictionary = ForgeSystem.CLASS_FORGE_WEAPON_MAP if _forge_type == "weapon" else ForgeSystem.CLASS_FORGE_ARMOR_MAP
		var item_id: String = item_map.get(cls_id, "")
		if item_id == "":
			continue
		var item_def: Dictionary = ItemDB.get_item_def(item_id)
		if item_def.is_empty():
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		# Class color indicator
		var color_rect := ColorRect.new()
		color_rect.color = ForgeSystem.get_class_color(cls_id)
		color_rect.custom_minimum_size = Vector2(6, 0)
		row.add_child(color_rect)

		# Item icon
		var icon_path: String = item_def.get("icon", "")
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(32, 32)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.texture = load(icon_path)
			row.add_child(icon)

		# Item info
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		name_lbl.text = "%s" % item_def.get("name", item_id)
		name_lbl.add_theme_font_size_override("font_size", 13)
		info.add_child(name_lbl)

		var desc_lbl2 := Label.new()
		desc_lbl2.text = item_def.get("description", "")
		desc_lbl2.add_theme_font_size_override("font_size", 11)
		desc_lbl2.add_theme_color_override("font_color", Color(0.65, 0.6, 0.55))
		desc_lbl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc_lbl2)

		# Stat bonuses
		var stat_parts: Array[String] = []
		for sk in ["stat_str", "stat_dex", "stat_int", "stat_lck"]:
			var v: int = int(item_def.get(sk, 0))
			if v > 0:
				stat_parts.append("+%d %s" % [v, sk.replace("stat_", "").to_upper()])
		var atk: int = int(item_def.get("attack_bonus", 0))
		var ac: int = int(item_def.get("ac_bonus", 0))
		if atk > 0:
			stat_parts.append("+%d ATK" % atk)
		if ac > 0:
			stat_parts.append("+%d AC" % ac)
		if not stat_parts.is_empty():
			var stat_lbl := Label.new()
			stat_lbl.text = ", ".join(stat_parts)
			stat_lbl.add_theme_font_size_override("font_size", 11)
			stat_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
			info.add_child(stat_lbl)

		row.add_child(info)

		# Forge button
		var btn := Button.new()
		btn.text = "Forge (%dg)" % ForgeSystem.FORGE_COST
		btn.disabled = GameData.gold < ForgeSystem.FORGE_COST
		btn.pressed.connect(_on_forge_pressed.bind(cls_id))
		row.add_child(btn)

		_list_box.add_child(row)


func _on_forge_pressed(cls_id: int) -> void:
	var result: Dictionary
	if _forge_type == "weapon":
		result = ForgeSystem.forge_weapon(cls_id)
	else:
		result = ForgeSystem.forge_armor(cls_id)

	if result.is_empty():
		_show_feedback("Cannot forge — check gold and skyshards.", Color(1, 0.3, 0.3))
		return

	var item_name: String = result.get("name", "item")
	_show_feedback("Forged %s!" % item_name, Color(0.3, 1, 0.3))

	# Auto-slot the skill if there's room
	var skill_action: String = result.get("grants_skill", "")
	if skill_action != "" and ForgeSystem.forge_skill_slots.size() < ForgeSystem.MAX_FORGE_SKILLS:
		ForgeSystem.slot_forge_skill(skill_action)

	_refresh_ui()


# ══════════════════════════════════════════════════════════════════════════════
# REFORGE LIST — shows forged items that can be merged
# ══════════════════════════════════════════════════════════════════════════════

var _reforge_box: VBoxContainer = null
var _reforge_sel_a: int = -1
var _reforge_sel_b: int = -1

func _build_reforge_list(parent: VBoxContainer) -> void:
	_reforge_box = VBoxContainer.new()
	_reforge_box.add_theme_constant_override("separation", 4)
	parent.add_child(_reforge_box)
	_populate_reforge_list()


func _populate_reforge_list() -> void:
	for child in _reforge_box.get_children():
		child.queue_free()
	_reforge_sel_a = -1
	_reforge_sel_b = -1

	# Find forged items of the correct type in backpack
	var target_type: int = ItemDB.ItemType.WEAPON if _forge_type == "weapon" else ItemDB.ItemType.CHEST
	var forged_indices: Array[int] = []
	for i in GameData.backpack.size():
		var item: Dictionary = GameData.backpack[i]
		if item.has("forged_from") and ItemDB.resolve_item_type(item) == target_type:
			forged_indices.append(i)

	if forged_indices.size() < 2:
		var none_lbl := Label.new()
		none_lbl.text = "Need 2+ forged %ss to reforge." % _forge_type
		none_lbl.add_theme_font_size_override("font_size", 12)
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_reforge_box.add_child(none_lbl)
		return

	for bp_idx in forged_indices:
		var item: Dictionary = GameData.backpack[bp_idx]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var check := CheckBox.new()
		check.text = "%s" % item.get("name", "?")
		check.add_theme_font_size_override("font_size", 12)
		check.toggled.connect(_on_reforge_check.bind(bp_idx))
		row.add_child(check)

		# Show skills
		var origins: Array = item.get("forged_from", [])
		var skill_text := "Skills: %d/%d" % [origins.size(), ForgeSystem.MAX_FORGE_SKILLS]
		var sk_lbl := Label.new()
		sk_lbl.text = skill_text
		sk_lbl.add_theme_font_size_override("font_size", 11)
		sk_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.8))
		row.add_child(sk_lbl)

		_reforge_box.add_child(row)

	# Reforge button
	var btn := Button.new()
	btn.name = "ReforgeBtn"
	btn.text = "Reforge Selected (%dg)" % ForgeSystem.REFORGE_COST
	btn.disabled = true
	btn.pressed.connect(_on_reforge_confirmed)
	_reforge_box.add_child(btn)


func _on_reforge_check(toggled_on: bool, bp_idx: int) -> void:
	if toggled_on:
		if _reforge_sel_a < 0:
			_reforge_sel_a = bp_idx
		elif _reforge_sel_b < 0:
			_reforge_sel_b = bp_idx
		else:
			# Already have 2 selected — ignore
			return
	else:
		if bp_idx == _reforge_sel_a:
			_reforge_sel_a = _reforge_sel_b
			_reforge_sel_b = -1
		elif bp_idx == _reforge_sel_b:
			_reforge_sel_b = -1

	# Enable/disable reforge button
	var btn := _reforge_box.find_child("ReforgeBtn", true, false) as Button
	if btn:
		var can_reforge: bool = _reforge_sel_a >= 0 and _reforge_sel_b >= 0 and GameData.gold >= ForgeSystem.REFORGE_COST
		# Also validate the preview
		if can_reforge:
			var preview: Dictionary = ForgeSystem.preview_reforge(_reforge_sel_a, _reforge_sel_b)
			can_reforge = not preview.is_empty()
		btn.disabled = not can_reforge


func _on_reforge_confirmed() -> void:
	if _reforge_sel_a < 0 or _reforge_sel_b < 0:
		return
	var result: Dictionary = ForgeSystem.reforge(_reforge_sel_a, _reforge_sel_b)
	if result.is_empty():
		_show_feedback("Reforge failed — check requirements.", Color(1, 0.3, 0.3))
		return

	var item_name: String = result.get("name", "merged item")
	_show_feedback("Reforged into %s!" % item_name, Color(0.6, 0.3, 1))
	_refresh_ui()


# ══════════════════════════════════════════════════════════════════════════════
# SKILL MANAGEMENT — show and manage forge skill slots
# ══════════════════════════════════════════════════════════════════════════════

func _build_skill_management() -> void:
	for child in _skill_section.get_children():
		child.queue_free()

	var slots: Array[String] = ForgeSystem.get_active_forge_skills()
	if slots.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No forge skills slotted. Forge an item to gain a skill."
		none_lbl.add_theme_font_size_override("font_size", 12)
		none_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_skill_section.add_child(none_lbl)
	else:
		for i in slots.size():
			var action: String = slots[i]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)

			var slot_lbl := Label.new()
			slot_lbl.text = "Slot %d:" % (i + 1)
			slot_lbl.add_theme_font_size_override("font_size", 12)
			slot_lbl.custom_minimum_size.x = 50
			row.add_child(slot_lbl)

			var name_lbl := Label.new()
			name_lbl.text = ForgeSystem._skill_action_to_name(action)
			name_lbl.add_theme_font_size_override("font_size", 13)
			name_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1))
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)

			var remove_btn := Button.new()
			remove_btn.text = "Remove"
			remove_btn.add_theme_font_size_override("font_size", 11)
			remove_btn.pressed.connect(_on_unslot_skill.bind(action))
			row.add_child(remove_btn)

			_skill_section.add_child(row)

	# Show available skills not yet slotted
	var all_available: Array[String] = ForgeSystem.get_all_available_forge_skills()
	var unslotted: Array[String] = []
	for sk in all_available:
		if sk not in slots:
			unslotted.append(sk)

	if not unslotted.is_empty() and slots.size() < ForgeSystem.MAX_FORGE_SKILLS:
		_skill_section.add_child(HSeparator.new())
		var avail_lbl := Label.new()
		avail_lbl.text = "Available to slot:"
		avail_lbl.add_theme_font_size_override("font_size", 12)
		avail_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.55))
		_skill_section.add_child(avail_lbl)

		for sk2 in unslotted:
			var row2 := HBoxContainer.new()
			row2.add_theme_constant_override("separation", 6)
			var sk_name := Label.new()
			sk_name.text = ForgeSystem._skill_action_to_name(sk2)
			sk_name.add_theme_font_size_override("font_size", 12)
			sk_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(sk_name)

			var add_btn := Button.new()
			add_btn.text = "Slot"
			add_btn.add_theme_font_size_override("font_size", 11)
			add_btn.pressed.connect(_on_slot_skill.bind(sk2))
			row2.add_child(add_btn)

			_skill_section.add_child(row2)


func _on_slot_skill(action: String) -> void:
	if ForgeSystem.slot_forge_skill(action):
		_show_feedback("Skill slotted: %s" % ForgeSystem._skill_action_to_name(action), Color(0.3, 0.85, 1))
		_refresh_ui()


func _on_unslot_skill(action: String) -> void:
	if ForgeSystem.unslot_forge_skill(action):
		_show_feedback("Skill removed.", Color(0.7, 0.7, 0.5))
		_refresh_ui()


# ══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _update_gold_label() -> void:
	if _gold_label:
		_gold_label.text = "Gold: %d" % GameData.gold


func _show_feedback(msg: String, color: Color = Color.WHITE) -> void:
	if _feedback_label:
		_feedback_label.text = msg
		_feedback_label.add_theme_color_override("font_color", color)
		_feedback_timer = 3.0


func _refresh_ui() -> void:
	# Rebuild the entire UI to reflect new state
	for child in get_children():
		child.queue_free()
	_build_ui()
	visible = true
