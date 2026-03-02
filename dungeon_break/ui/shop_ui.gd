extends CanvasLayer
## ShopUI — modal item shop for camp NPCs.
##
## Handles armor_shop (Daniels), weapon_shop (Mahan), potion_shop (Conner),
## and magic_shop (Zara) roles. Michelle's structure_shop uses structure_shop_ui.gd.
## Instantiated by game.gd on NPC interaction.

signal shop_closed

# Magic weapons sold by Zara (WEAPON type with arcane flavor)
const MAGIC_WEAPON_IDS: Array = ["magic_knife", "fire_staff", "ice_bow"]

# Non-armor items Daniels (armor_shop) always stocks — general goods
const DANIELS_EXTRAS: Array = ["boomerang"]

# Food items sold by Conner alongside potions (all tiers combined)
const POTION_SHOP_FOOD: Array = ["bread", "apple", "mushroom", "berry", "honey", "cookie", "energy_bar"]

# ── Shop tiers ─────────────────────────────────────────────────────────────────
# Tier 0 = floors_cleared 0–1  |  Tier 1 = floors_cleared 2–4  |  Tier 2 = 5+
# Each const lists NEW items added at that tier; lower tiers are always included.

const _WEAPON_T0 := ["club", "stone_spear", "sword"]
const _WEAPON_T1 := ["blade", "axe", "crossbow"]
# Tier 2 adds: knights_sword, morningstar

const _ARMOR_T0 := ["chest_leather", "boots_leather"]
const _ARMOR_T1 := ["helm_iron", "chest_chain", "boots_iron"]
# Tier 2 adds: helm_knight

const _POTION_T0 := ["mushroom", "berry", "apple", "bread"]
const _POTION_T1 := ["honey", "cookie", "energy_bar", "potion_red", "potion_blue"]
# Tier 2 adds: remaining potions + buff foods

const _MAGIC_T0 := ["blood_pendant"]
const _MAGIC_T1 := ["magic_knife"]
# Tier 2 adds: ancient_amulet, fire_staff, ice_bow

var _npc_key: String = ""
var _gold_label: Label = null
var _list_box: VBoxContainer = null
var _feedback_label: Label = null
var _feedback_timer: float = 0.0


func _ready() -> void:
	visible = false


## Open shop for the given NPC key. Builds UI and shows it.
func open(npc_key: String) -> void:
	_npc_key = npc_key
	_build_ui()
	visible = true


## Close and free the shop.
func close_shop() -> void:
	shop_closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_shop()


func _process(delta: float) -> void:
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0 and _feedback_label:
			_feedback_label.text = ""


# ── Build ──────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var npc_def: Dictionary  = NpcDB.get_def(_npc_key)
	var npc_name: String     = npc_def.get("name", _npc_key) as String
	var role: String         = npc_def.get("role", "") as String
	var greeting: String     = npc_def.get("greeting", "...") as String
	var sprite_prefix: String = npc_def.get("sprite_prefix", "") as String

	# ── dim overlay ──
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ── main panel ──
	var panel := PanelContainer.new()
	panel.name = "ShopPanel"
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.04, 0.08, 0.97)
	ps.border_color = Color(0.55, 0.45, 0.3)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -320
	panel.offset_right  =  320
	panel.offset_top    = -270
	panel.offset_bottom =  270
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	# ── header: portrait + name + greeting ──
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

	var title_lbl := Label.new()
	title_lbl.text = "%s  —  %s" % [npc_name, NpcDB.get_role_label(role)]
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	title_col.add_child(title_lbl)

	var greet_lbl := Label.new()
	greet_lbl.text = "\"" + greeting + "\""
	greet_lbl.add_theme_font_size_override("font_size", 12)
	greet_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
	greet_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_col.add_child(greet_lbl)

	# ── gold row ──
	var gold_row := HBoxContainer.new()
	root.add_child(gold_row)

	var coin_lbl := Label.new()
	coin_lbl.text = "Your Gold: "
	coin_lbl.add_theme_font_size_override("font_size", 14)
	coin_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	gold_row.add_child(coin_lbl)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 14)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_gold_label.text = str(GameData.gold)
	gold_row.add_child(_gold_label)

	# ── separator ──
	root.add_child(HSeparator.new())

	# ── item list ──
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	_populate_items(role)

	# ── feedback label ──
	_feedback_label = Label.new()
	_feedback_label.add_theme_font_size_override("font_size", 13)
	_feedback_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_feedback_label)

	# ── close button ──
	root.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "Close  [Esc]"
	close_btn.custom_minimum_size = Vector2(130, 30)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.15, 0.1, 0.22, 0.95)
	btn_style.border_color = Color(0.55, 0.45, 0.3)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.set_content_margin_all(6)
	close_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := btn_style.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.25, 0.15, 0.35, 0.95)
	close_btn.add_theme_stylebox_override("hover", btn_hover)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	close_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_btn.pressed.connect(close_shop)
	root.add_child(close_btn)

	# Live gold updates
	GameData.gold_changed.connect(_on_gold_changed)


func _populate_items(role: String) -> void:
	if _list_box == null:
		return

	var items := _get_shop_items(role)
	if items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Nothing in stock right now."
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_list_box.add_child(empty_lbl)
		return

	for item_def: Dictionary in items:
		_add_item_row(item_def)

	# Hint when stock will expand
	var tier := _get_shop_tier()
	if tier < 2:
		var next_floor := 2 if tier == 0 else 5
		var hint := Label.new()
		hint.text = "More stock available after floor %d." % next_floor
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.45, 0.45, 0.52))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list_box.add_child(hint)


func _add_item_row(item_def: Dictionary) -> void:
	var row_panel := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.1, 0.08, 0.14, 0.9)
	row_style.border_color = Color(0.3, 0.25, 0.2)
	row_style.set_border_width_all(1)
	row_style.set_corner_radius_all(4)
	row_style.set_content_margin(SIDE_LEFT, 6)
	row_style.set_content_margin(SIDE_RIGHT, 6)
	row_style.set_content_margin(SIDE_TOP, 4)
	row_style.set_content_margin(SIDE_BOTTOM, 4)
	row_panel.add_theme_stylebox_override("panel", row_style)
	_list_box.add_child(row_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)

	# Icon
	var icon_path: String = item_def.get("icon", "") as String
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = load(icon_path)
		row.add_child(icon)
	else:
		var ph := ColorRect.new()
		ph.custom_minimum_size = Vector2(32, 32)
		ph.color = Color(0.25, 0.25, 0.3)
		row.add_child(ph)

	# Name + description column
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = item_def.get("name", "?") as String
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	text_col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = item_def.get("description", "") as String
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.58, 0.55))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc_lbl)

	# Price + buy column
	var price_col := VBoxContainer.new()
	price_col.add_theme_constant_override("separation", 4)
	row.add_child(price_col)

	var price: int = item_def.get("value", 0) as int
	var price_lbl := Label.new()
	price_lbl.text = "%dg" % price
	price_lbl.add_theme_font_size_override("font_size", 14)
	price_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_col.add_child(price_lbl)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(56, 26)
	var buy_style := StyleBoxFlat.new()
	buy_style.bg_color = Color(0.12, 0.22, 0.12, 0.95)
	buy_style.border_color = Color(0.3, 0.55, 0.3)
	buy_style.set_border_width_all(1)
	buy_style.set_corner_radius_all(4)
	buy_style.set_content_margin_all(4)
	buy_btn.add_theme_stylebox_override("normal", buy_style)
	var buy_hover := buy_style.duplicate() as StyleBoxFlat
	buy_hover.bg_color = Color(0.2, 0.35, 0.2, 0.95)
	buy_btn.add_theme_stylebox_override("hover", buy_hover)
	buy_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5))
	buy_btn.pressed.connect(_on_buy_pressed.bind(item_def))
	price_col.add_child(buy_btn)


## Current tier: 0 = early (floors 0-1), 1 = mid (2-4), 2 = late (5+).
func _get_shop_tier() -> int:
	var fc: int = GameData.floors_cleared
	if fc >= 5:
		return 2
	elif fc >= 2:
		return 1
	return 0


func _get_shop_items(role: String) -> Array:
	var tier := _get_shop_tier()
	var result: Array = []
	for id: String in ItemDB.ITEMS.keys():
		var def: Dictionary = ItemDB.ITEMS[id]
		var t: int = def.get("type", -1) as int
		if _item_allowed(id, t, role, tier):
			result.append(def)
	return result


func _item_allowed(id: String, itype: int, role: String, tier: int) -> bool:
	match role:
		"armor_shop":
			# Daniels also stocks a few general-goods items at all tiers
			if id in DANIELS_EXTRAS:
				return true
			if not (itype == ItemDB.ItemType.HELM or itype == ItemDB.ItemType.CHEST
					or itype == ItemDB.ItemType.LEGS or itype == ItemDB.ItemType.BOOTS):
				return false
			if tier == 0:   return id in _ARMOR_T0
			elif tier == 1: return id in _ARMOR_T0 or id in _ARMOR_T1
			return true  # tier 2: all armor
		"weapon_shop":
			if itype != ItemDB.ItemType.WEAPON or id in MAGIC_WEAPON_IDS:
				return false
			if tier == 0:   return id in _WEAPON_T0
			elif tier == 1: return id in _WEAPON_T0 or id in _WEAPON_T1
			return true  # tier 2: all non-magic weapons
		"potion_shop":
			if tier == 0:   return id in _POTION_T0
			elif tier == 1: return id in _POTION_T0 or id in _POTION_T1
			# tier 2: all potions + potion-shop food
			return itype == ItemDB.ItemType.POTION \
				or (itype == ItemDB.ItemType.FOOD and id in POTION_SHOP_FOOD)
		"magic_shop":
			if itype != ItemDB.ItemType.MISC and id not in MAGIC_WEAPON_IDS:
				return false
			if tier == 0:   return id in _MAGIC_T0
			elif tier == 1: return id in _MAGIC_T0 or id in _MAGIC_T1
			return true  # tier 2: all magic items
	return false


func _on_buy_pressed(item_def: Dictionary) -> void:
	var price: int   = item_def.get("value", 0) as int
	var iname: String = item_def.get("name", "item") as String
	var iid: String   = item_def.get("id", "") as String

	if GameData.gold < price:
		_show_feedback("Not enough gold!", Color(1.0, 0.4, 0.3))
		return

	if not ItemDB.add_to_backpack(ItemDB.create_item(iid)):
		_show_feedback("Backpack is full!", Color(1.0, 0.6, 0.2))
		return

	GameData.add_gold(-price)
	_show_feedback("Bought %s!" % iname, Color(0.4, 1.0, 0.5))


func _show_feedback(msg: String, color: Color = Color(0.4, 1.0, 0.5)) -> void:
	if _feedback_label:
		_feedback_label.text = msg
		_feedback_label.add_theme_color_override("font_color", color)
		_feedback_timer = 2.5


func _on_gold_changed(amount: int) -> void:
	if _gold_label:
		_gold_label.text = str(amount)
