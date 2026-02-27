extends Control
## Character select screen shown once at game start.
##
## Player picks race (Human / Elf / Dwarf / Goblin), gender (Male / Female),
## and a name, then clicks "Begin Adventure" to proceed to camp.

signal confirmed()

# Front-idle frame shared by every spritesheet (from character_sprite.gd coords)
const IDLE_SW := Rect2(739, 0, 509, 771)

const RACES: Array = [
	{ "key": "human",  "label": "Human"  },
	{ "key": "elf",    "label": "Elf"    },
	{ "key": "dwarf",  "label": "Dwarf"  },
	{ "key": "goblin", "label": "Goblin" },
]

# Note: elf_male filename has an extra 'd' — matches actual file on disk
const SHEET_PATHS: Dictionary = {
	"human_male":    "res://assets/REFS/human_male_spritesheet_transparent.png",
	"human_female":  "res://assets/REFS/human_female_spritesheet_transparent.png",
	"elf_male":      "res://assets/REFS/elf_male_spritesheetd_transparent.png",
	"elf_female":    "res://assets/REFS/elf_female_spritesheet_transparent.png",
	"dwarf_male":    "res://assets/REFS/dwarf_male_spritesheet_transparent.png",
	"dwarf_female":  "res://assets/REFS/dwarf_female_spritesheet_transparent.png",
	"goblin_male":   "res://assets/REFS/goblin_male_spritesheet_transparent.png",
	"goblin_female": "res://assets/REFS/goblin_female_spritesheet_transparent.png",
}

var _selected_race:   String = "human"
var _selected_gender: String = "male"

# race_key → { "card": PanelContainer, "preview": TextureRect }
var _race_data: Dictionary = {}
# "male"/"female" → Button
var _gender_btns: Dictionary = {}

var _name_input: LineEdit = null

# Preloaded textures: sheet_key → Texture2D
var _tex_cache: Dictionary = {}


func _ready() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0
	_preload_textures()
	_build_ui()
	_refresh()


func _preload_textures() -> void:
	for key: String in SHEET_PATHS:
		var path: String = SHEET_PATHS[key] as String
		if ResourceLoader.exists(path):
			_tex_cache[key] = load(path) as Texture2D
		else:
			push_warning("CharacterSelect: sheet not found — %s" % path)


# ── UI construction ──────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.03, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Centered column
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	center.add_child(vbox)

	_add_title(vbox)
	_add_race_row(vbox)
	_add_gender_row(vbox)
	_add_name_row(vbox)
	_add_begin_button(vbox)


func _add_title(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "DUNGEON BREAK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	parent.add_child(title)

	var sub := Label.new()
	sub.text = "Choose Your Hero"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.75))
	parent.add_child(sub)


func _add_race_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)

	for item in RACES:
		var key:   String = item["key"]   as String
		var label: String = item["label"] as String
		row.add_child(_make_race_card(key, label))


func _make_race_card(race_key: String, race_label: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(130, 190)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 6)
	card.add_child(inner)

	# Sprite preview
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(90, 118)
	preview.stretch_mode       = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.expand_mode        = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	inner.add_child(preview)

	# Race name
	var lbl := Label.new()
	lbl.text = race_label
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	inner.add_child(lbl)

	# Select button
	var btn := Button.new()
	btn.text = "Select"
	btn.custom_minimum_size = Vector2(90, 28)
	btn.pressed.connect(_on_race_selected.bind(race_key))
	inner.add_child(btn)

	_race_data[race_key] = { "card": card, "preview": preview }
	return card


func _add_gender_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = "Gender:"
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	row.add_child(lbl)

	for g: String in ["male", "female"]:
		var btn := Button.new()
		btn.text = g.capitalize()
		btn.custom_minimum_size = Vector2(90, 36)
		btn.pressed.connect(_on_gender_selected.bind(g))
		row.add_child(btn)
		_gender_btns[g] = btn


func _add_name_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = "Name:"
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	row.add_child(lbl)

	_name_input = LineEdit.new()
	_name_input.text = "Hero"
	_name_input.custom_minimum_size = Vector2(190, 36)
	_name_input.max_length = 20
	row.add_child(_name_input)


func _add_begin_button(parent: VBoxContainer) -> void:
	var btn := Button.new()
	btn.text = "Begin Adventure"
	btn.custom_minimum_size = Vector2(210, 50)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	btn.pressed.connect(_on_begin_pressed)
	parent.add_child(btn)


# ── Interaction ──────────────────────────────────────────────────────────────

func _on_race_selected(race_key: String) -> void:
	_selected_race = race_key
	_refresh()


func _on_gender_selected(gender: String) -> void:
	_selected_gender = gender
	_refresh()


func _refresh() -> void:
	# Update every race card's preview and highlight
	for race_key: String in _race_data:
		var data: Dictionary = _race_data[race_key]
		var card: PanelContainer    = data["card"]    as PanelContainer
		var preview: TextureRect    = data["preview"] as TextureRect

		# Show the current-gender variant of this race
		var sheet_key: String = race_key + "_" + _selected_gender
		if _tex_cache.has(sheet_key):
			var base_tex: Texture2D = _tex_cache[sheet_key] as Texture2D
			var atlas := AtlasTexture.new()
			atlas.atlas  = base_tex
			atlas.region = IDLE_SW
			preview.texture = atlas
		else:
			preview.texture = null

		# Highlight the selected card
		card.modulate = Color(1.3, 1.2, 0.55) if race_key == _selected_race else Color.WHITE

	# Highlight the selected gender button
	for g: String in _gender_btns:
		var btn: Button = _gender_btns[g] as Button
		btn.modulate = Color(1.0, 0.85, 0.25) if g == _selected_gender else Color.WHITE


func _on_begin_pressed() -> void:
	var sheet_key: String = _selected_race + "_" + _selected_gender
	var fallback: String  = "res://assets/REFS/human_male_spritesheet_transparent.png"
	var path: String      = SHEET_PATHS.get(sheet_key, fallback) as String

	GameData.player_race        = _selected_race
	GameData.player_gender      = _selected_gender
	GameData.player_sheet_path  = path

	var entered_name: String = _name_input.text.strip_edges()
	if entered_name.length() > 0:
		GameData.player_name = entered_name

	confirmed.emit()
