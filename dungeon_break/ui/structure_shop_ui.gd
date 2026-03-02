extends CanvasLayer
## StructureShopUI — Michelle's Workshop.
##
## Two sections: permanent camp upgrades and dungeon supply consumables.
## Instantiated by game.gd on NPC interaction with Michelle.

signal shop_closed

const ACVoiceBoxScript = preload("res://dungeon_break/ui/ac_voicebox.gd")

# ── Camp upgrades ────────────────────────────────────────────────────────────
const CAMP_UPGRADES: Array = [
	{
		"id":          "reinforced_gate",
		"name":        "Reinforced Gate",
		"icon":        "res://assets/art/tools/shield.png",
		"description": "Reinforces the dungeon entrance. Increases max torch fuel by 25.",
		"cost":        50,
	},
	{
		"id":          "storage_expansion",
		"name":        "Storage Expansion",
		"icon":        "res://assets/art/tools/backpack.png",
		"description": "Michelle builds extra storage crates in camp. +8 backpack slots.",
		"cost":        60,
	},
	{
		"id":          "supply_depot",
		"name":        "Supply Depot",
		"icon":        "res://assets/art/food/bread.png",
		"description": "A stocked food cache near the bonfire. Resting gives 2 free bread.",
		"cost":        80,
	},
]

# ── Dungeon supply items stocked in Michelle's shop ──────────────────────────
const SUPPLY_ITEM_IDS: Array[String] = [
	"torch", "crystal_light_orb",
	"grapple", "net_trap", "blast_charge",
	"bread", "mushroom_soup", "super_stew",
]

var _gold_label: Label = null
var _feedback_label: Label = null
var _feedback_timer: float = 0.0
var _voicebox: ACVoiceBox = null
var _greet_lbl: Label = null
var _greeting_played: bool = false


func _ready() -> void:
	visible = false


func open() -> void:
	_build_ui()
	visible = true


func close_shop() -> void:
	if _voicebox:
		_voicebox.stop_speaking()
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


# ── Build ─────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var npc_def: Dictionary = NpcDB.get_def("michelle")
	var greeting: String = npc_def.get("greeting", "You want it built, I'll price it out.") as String

	# ── dim overlay ──
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ── main panel ──
	var panel := PanelContainer.new()
	panel.name = "StructureShopPanel"
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.04, 0.08, 0.97)
	ps.border_color = Color(0.55, 0.45, 0.3)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -340
	panel.offset_right  =  340
	panel.offset_top    = -310
	panel.offset_bottom =  310
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	# ── header ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var portrait_path := "res://assets/art/npc_sprites/michelle.png"
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
	title_lbl.text = "Michelle  —  Workshop"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	title_col.add_child(title_lbl)

	var greet_lbl := Label.new()
	greet_lbl.text = "\"" + greeting + "\""
	greet_lbl.visible_characters = 1  # show opening quote
	greet_lbl.add_theme_font_size_override("font_size", 12)
	greet_lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6))
	title_col.add_child(greet_lbl)
	_greet_lbl = greet_lbl

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

	root.add_child(HSeparator.new())

	# ── scrollable body ──
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)

	_add_section_header(list, "CAMP UPGRADES")
	for upgrade in CAMP_UPGRADES:
		_add_upgrade_row(list, upgrade)

	list.add_child(HSeparator.new())
	_add_section_header(list, "DUNGEON SUPPLIES")
	for id: String in SUPPLY_ITEM_IDS:
		var def: Dictionary = ItemDB.get_item_def(id)
		if not def.is_empty():
			_add_supply_row(list, def)

	# ── feedback ──
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

	GameData.gold_changed.connect(_on_gold_changed)

	# Start animalese speech for greeting (skip on UI rebuild)
	if _greeting_played:
		_greet_lbl.visible_characters = -1
	else:
		_greeting_played = true
		if _voicebox:
			_voicebox.stop_speaking()
			_voicebox.queue_free()
		_voicebox = ACVoiceBoxScript.new()
		_voicebox.base_pitch = npc_def.get("voice_pitch", 2.5) as float
		_voicebox.play_speed = npc_def.get("voice_speed", 0.90) as float
		add_child(_voicebox)
		_voicebox.characters_sounded.connect(_on_voice_chars)
		_voicebox.finished_phrase.connect(_on_voice_finished)
		_voicebox.play_string(greeting)


func _add_section_header(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	parent.add_child(lbl)


func _add_upgrade_row(parent: VBoxContainer, upgrade: Dictionary) -> void:
	var owned: bool = GameData.has_upgrade(upgrade["id"] as String)

	var row_panel := PanelContainer.new()
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.08, 0.10, 0.09, 0.9) if owned else Color(0.1, 0.08, 0.14, 0.9)
	row_style.border_color = Color(0.25, 0.45, 0.25) if owned else Color(0.3, 0.25, 0.2)
	row_style.set_border_width_all(1)
	row_style.set_corner_radius_all(4)
	row_style.set_content_margin(SIDE_LEFT, 6)
	row_style.set_content_margin(SIDE_RIGHT, 6)
	row_style.set_content_margin(SIDE_TOP, 4)
	row_style.set_content_margin(SIDE_BOTTOM, 4)
	row_panel.add_theme_stylebox_override("panel", row_style)
	parent.add_child(row_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)

	# Icon
	var icon_path: String = upgrade.get("icon", "") as String
	if icon_path != "" and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture = load(icon_path)
		icon.modulate = Color(0.6, 0.9, 0.6) if owned else Color.WHITE
		row.add_child(icon)
	else:
		var ph := ColorRect.new()
		ph.custom_minimum_size = Vector2(32, 32)
		ph.color = Color(0.25, 0.25, 0.3)
		row.add_child(ph)

	# Name + description
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 2)
	row.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = ("✓  " if owned else "") + (upgrade.get("name", "?") as String)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if owned else Color(0.95, 0.9, 0.8))
	text_col.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = upgrade.get("description", "") as String
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.5) if owned else Color(0.6, 0.58, 0.55))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_col.add_child(desc_lbl)

	# Price / owned button
	var price_col := VBoxContainer.new()
	price_col.add_theme_constant_override("separation", 4)
	row.add_child(price_col)

	var cost: int = upgrade.get("cost", 0) as int
	var price_lbl := Label.new()
	price_lbl.text = "Owned" if owned else "%dg" % cost
	price_lbl.add_theme_font_size_override("font_size", 14)
	price_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5) if owned else Color(1.0, 0.85, 0.2))
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_col.add_child(price_lbl)

	if not owned:
		var buy_btn := Button.new()
		buy_btn.text = "Build"
		buy_btn.custom_minimum_size = Vector2(60, 26)
		var buy_style := StyleBoxFlat.new()
		buy_style.bg_color = Color(0.1, 0.18, 0.12, 0.95)
		buy_style.border_color = Color(0.3, 0.55, 0.35)
		buy_style.set_border_width_all(1)
		buy_style.set_corner_radius_all(4)
		buy_style.set_content_margin_all(4)
		buy_btn.add_theme_stylebox_override("normal", buy_style)
		var buy_hover := buy_style.duplicate() as StyleBoxFlat
		buy_hover.bg_color = Color(0.18, 0.32, 0.2, 0.95)
		buy_btn.add_theme_stylebox_override("hover", buy_hover)
		buy_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.5))
		buy_btn.pressed.connect(_on_upgrade_pressed.bind(upgrade))
		price_col.add_child(buy_btn)


func _add_supply_row(parent: VBoxContainer, item_def: Dictionary) -> void:
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
	parent.add_child(row_panel)

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

	# Name + description
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

	# Price + buy
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
	buy_btn.pressed.connect(_on_supply_buy_pressed.bind(item_def))
	price_col.add_child(buy_btn)


# ── Purchase handlers ─────────────────────────────────────────────────────────

func _on_upgrade_pressed(upgrade: Dictionary) -> void:
	var id: String   = upgrade.get("id", "") as String
	var cost: int    = upgrade.get("cost", 0) as int
	var uname: String = upgrade.get("name", "upgrade") as String

	if GameData.has_upgrade(id):
		_show_feedback("Already built!", Color(0.7, 0.7, 0.5))
		return
	if not GameData.purchase_upgrade(id, cost):
		_show_feedback("Not enough gold!", Color(1.0, 0.4, 0.3))
		return

	_show_feedback("%s built!" % uname, Color(0.4, 1.0, 0.5))
	# Rebuild the UI to show the checkmark
	for child in get_children():
		child.queue_free()
	_gold_label = null
	_feedback_label = null
	_feedback_timer = 0.0
	_build_ui()
	# Re-show the success message after rebuild
	_show_feedback("%s built!" % uname, Color(0.4, 1.0, 0.5))


func _on_supply_buy_pressed(item_def: Dictionary) -> void:
	var price: int    = item_def.get("value", 0) as int
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


func _on_voice_chars(chars: String) -> void:
	if _greet_lbl:
		_greet_lbl.visible_characters += chars.length()


func _on_voice_finished() -> void:
	if _greet_lbl:
		_greet_lbl.visible_characters = -1
