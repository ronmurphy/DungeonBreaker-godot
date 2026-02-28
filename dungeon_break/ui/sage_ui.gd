extends CanvasLayer
## SageUI — Claude the Sage's hint display.
##
## Cycled hints about dungeon mechanics, combat, and camp features.
## Instantiated by game.gd when player talks to Claude.

signal sage_closed

const HINTS: Array = [
	"\"Combat is turn-based and tactical. Your initiative order matters — faster heroes act first.\"",
	"\"Your torch fuel drains slowly in the dungeon. Return to the Azure Flame in camp to refuel.\"",
	"\"The Guts meter fills when you take hits. A full Guts charge powers your strongest strikes.\"",
	"\"When you Defend in combat, your AC rises temporarily. Pair it with Counter to punish enemies.\"",
	"\"Higher floors bring harder enemies — but the loot is far better. Risk and reward.\"",
	"\"Every floor you clear, a survivor finds their way to camp. Speak to them — they have skills.\"",
	"\"Gold doesn't spend itself in the grave. Invest in armor before you go deeper.\"",
	"\"Different classes favour different stats. Scoundrels rely on DEX; Vanguards on STR.\"",
	"\"Food buffs last several combats. Eat before a fight you expect to be tough.\"",
	"\"Keys unlock sealed rooms. The rewards inside are always worth the detour.\"",
	"\"If the dungeon feels overwhelming, returning to camp resets nothing — come back prepared.\"",
	"\"I have seen many heroes descend. The ones who survived always knew when to run.\"",
]

var _hint_index: int = 0
var _text_label: Label = null


func _ready() -> void:
	visible = false


## Open the sage dialogue. Picks a random starting hint.
func open() -> void:
	_hint_index = randi() % HINTS.size()
	_build_ui()
	visible = true


## Close and free.
func close_sage() -> void:
	sage_closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_sage()


func _build_ui() -> void:
	# ── dim overlay ──
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# ── panel ──
	var panel := PanelContainer.new()
	panel.name = "SagePanel"
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.04, 0.10, 0.97)
	ps.border_color = Color(0.3, 0.4, 0.7)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -300
	panel.offset_right  =  300
	panel.offset_top    = -170
	panel.offset_bottom =  170
	add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	# ── header ──
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	root.add_child(header)

	var portrait_path := "res://assets/art/npc_sprites/claude.png"
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

	var name_lbl := Label.new()
	name_lbl.text = "Claude  —  Sage"
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	title_col.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "\"Ask me anything. I have seen much in my years.\""
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_col.add_child(sub_lbl)

	# ── separator ──
	root.add_child(HSeparator.new())

	# ── hint text ──
	_text_label = Label.new()
	_text_label.text = HINTS[_hint_index]
	_text_label.add_theme_font_size_override("font_size", 14)
	_text_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_text_label)

	# ── buttons ──
	root.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	root.add_child(btn_row)

	var next_btn := Button.new()
	next_btn.text = "Another Hint"
	var next_style := StyleBoxFlat.new()
	next_style.bg_color = Color(0.08, 0.10, 0.22, 0.95)
	next_style.border_color = Color(0.3, 0.4, 0.7)
	next_style.set_border_width_all(1)
	next_style.set_corner_radius_all(4)
	next_style.set_content_margin_all(8)
	next_btn.add_theme_stylebox_override("normal", next_style)
	var next_hover := next_style.duplicate() as StyleBoxFlat
	next_hover.bg_color = Color(0.12, 0.16, 0.34, 0.95)
	next_btn.add_theme_stylebox_override("hover", next_hover)
	next_btn.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	next_btn.pressed.connect(_on_next_hint)
	btn_row.add_child(next_btn)

	var close_btn := Button.new()
	close_btn.text = "Farewell  [Esc]"
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.15, 0.10, 0.22, 0.95)
	close_style.border_color = Color(0.55, 0.45, 0.3)
	close_style.set_border_width_all(1)
	close_style.set_corner_radius_all(4)
	close_style.set_content_margin_all(8)
	close_btn.add_theme_stylebox_override("normal", close_style)
	var close_hover := close_style.duplicate() as StyleBoxFlat
	close_hover.bg_color = Color(0.25, 0.15, 0.35, 0.95)
	close_btn.add_theme_stylebox_override("hover", close_hover)
	close_btn.add_theme_color_override("font_color", Color(0.85, 0.8, 1.0))
	close_btn.pressed.connect(close_sage)
	btn_row.add_child(close_btn)


func _on_next_hint() -> void:
	_hint_index = (_hint_index + 1) % HINTS.size()
	if _text_label:
		_text_label.text = HINTS[_hint_index]
