extends Node
## Dungeon Break entry point — manages scene transitions (save slots → char select → camp ↔ dungeon).

const CharSelectScene  = preload("res://dungeon_break/ui/character_select.tscn")
const CampScene        = preload("res://dungeon_break/game.tscn")
const DungeonScene     = preload("res://dungeon_break/dungeon.tscn")
const SaveSlotUIScript = preload("res://dungeon_break/ui/save_slot_ui.gd")

var _current_scene: Node = null


func _ready():
	_show_save_slots()


## Show the save slot selection screen.
func _show_save_slots():
	_clear_current()
	var ui := SaveSlotUIScript.new()
	ui.name = "SaveSlotUI"
	add_child(ui)
	_current_scene = ui
	ui.new_game_requested.connect(_on_new_game_requested)
	ui.load_game_requested.connect(_on_load_game_requested)


func _on_new_game_requested(slot: int):
	GameData.save_slot = slot
	_show_character_select()


func _on_load_game_requested(slot: int):
	var data := SaveManager.load_game(slot)
	if data.is_empty():
		_show_save_slots()
		return
	GameData.from_save_dict(data)
	GameData.save_slot = slot
	print("Main: loaded slot %d — scene=%s floor=%d" % [slot, GameData.scene_state, GameData.current_floor])
	if GameData.scene_state == "dungeon":
		_load_dungeon(GameData.current_floor)
	else:
		_load_camp()


## Show the race/gender/name selection screen.
func _show_character_select():
	_clear_current()
	var sel = CharSelectScene.instantiate()
	sel.name = "CharacterSelect"
	add_child(sel)
	_current_scene = sel
	sel.confirmed.connect(_on_character_select_confirmed)


func _on_character_select_confirmed():
	_load_camp()


## Load the camp scene.
func _load_camp():
	_clear_current()
	EntityManager.despawn_all()

	var camp = CampScene.instantiate()
	camp.name = "Camp"
	add_child(camp)
	_current_scene = camp

	# Connect the portal trigger from camp
	camp.connect("enter_dungeon", _on_enter_dungeon)
	print("Main: camp loaded")


## Load a dungeon floor.
func _load_dungeon(floor_num: int):
	_clear_current()
	EntityManager.despawn_all()

	var dungeon = DungeonScene.instantiate()
	dungeon.name = "Dungeon"
	dungeon.set_floor(floor_num)
	add_child(dungeon)
	_current_scene = dungeon

	dungeon.return_to_camp.connect(_on_return_to_camp)
	dungeon.advance_floor.connect(_on_advance_floor)
	print("Main: dungeon floor %d loaded" % floor_num)


func _clear_current():
	if _current_scene:
		_current_scene.queue_free()
		_current_scene = null


## Signal handlers ────────────────────────────────────────────────────────────

func _on_enter_dungeon():
	GameData.in_dungeon = true
	_load_dungeon(GameData.current_floor)


func _on_return_to_camp():
	GameData.in_dungeon = false
	_load_camp()


func _on_advance_floor():
	var rescued := GameData.rescue_random_npc()
	if rescued != "":
		var npc_def: Dictionary = NpcDB.get_def(rescued)
		print("Main: rescued — %s (%s)" % [npc_def.get("name", rescued), rescued])
	GameData.dungeon_seed = 0  # generate a fresh seed for the new floor
	GameData.advance_floor()
	_load_dungeon(GameData.current_floor)
