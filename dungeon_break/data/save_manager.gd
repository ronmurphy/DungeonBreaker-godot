extends Node
## Save Manager — JSON save/load for up to MAX_SLOTS save slots.
##
## Files stored at user://dungeon_break_save_N.json
## Autoloaded as "SaveManager".

const MAX_SLOTS   := 3
const SAVE_VERSION := 1


func _slot_path(slot: int) -> String:
	return "user://dungeon_break_save_%d.json" % slot


## Write current GameData state to slot. Returns true on success.
func save_game(slot: int) -> bool:
	var data: Dictionary = GameData.to_save_dict()
	data["version"]    = SAVE_VERSION
	data["timestamp"]  = int(Time.get_unix_time_from_system())
	data["save_slot"]  = slot

	var file := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot open slot %d for writing" % slot)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("SaveManager: saved slot %d" % slot)
	return true


## Load raw dict from a slot. Returns {} if the slot is empty or corrupt.
func load_game(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if not (parsed is Dictionary):
		push_error("SaveManager: slot %d is corrupt — removing" % slot)
		DirAccess.remove_absolute(path)
		return {}
	var data: Dictionary = parsed as Dictionary
	var version: int = int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_error("SaveManager: slot %d version %d is newer than supported version %d" % [
			slot, version, SAVE_VERSION])
		return {}
	return data


## Returns a lightweight summary dict for the slot UI, or {} if the slot is empty.
func get_slot_info(slot: int) -> Dictionary:
	var data := load_game(slot)
	if data.is_empty():
		return {}
	# active_companions is an Array of String keys (not dicts)
	var active: Array = data.get("active_companions", []) as Array
	var first_comp_key: String = ""
	if active.size() > 0 and active[0] is String:
		first_comp_key = active[0] as String

	return {
		"slot":                slot,
		"player_name":         data.get("player_name",   "Hero"),
		"player_class":        data.get("player_class",   0),
		"player_race":         data.get("player_race",    "human"),
		"player_gender":       data.get("player_gender",  "male"),
		"floor":               data.get("current_floor",  1),
		"hp":                  data.get("hp",             0),
		"hp_max":              data.get("hp_max",         1),
		"scene_state":         data.get("scene_state",    "camp"),
		"timestamp":           data.get("timestamp",      0),
		"gold":                data.get("gold",           0),
		"first_companion_key": first_comp_key,
	}


## Delete a save slot file.
func delete_slot(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		print("SaveManager: deleted slot %d" % slot)
