extends Node
## Dungeon Break entry point — manages scene transitions (char select → camp ↔ dungeon).

const CharSelectScene = preload("res://dungeon_break/ui/character_select.tscn")
const CampScene       = preload("res://dungeon_break/game.tscn")
const DungeonScene    = preload("res://dungeon_break/dungeon.tscn")

var _current_scene: Node = null


func _ready():
	_show_character_select()


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
	GameData.advance_floor()
	_load_dungeon(GameData.current_floor)
