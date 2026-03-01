extends Node
## Game data singleton — player stats, classes, inventory, floor progression.
##
## Ported from JS game-state.js. Autoloaded as "GameData".

# ── Signals ──────────────────────────────────────────────────────────────────
signal hp_changed(current: int, maximum: int)
signal gold_changed(amount: int)
signal floor_changed(floor_num: int)
signal inventory_changed()
signal equipment_changed()
signal player_died()

# ── Player Classes ───────────────────────────────────────────────────────────
enum PlayerClass {
	VANGUARD,    # Tank — high STR, shield abilities
	SCOUNDREL,   # DPS — high DEX, backstab/poison
	ARCANIST,    # Mage — high INT, spell burst
	CONFESSOR,   # Healer — INT/LCK hybrid, holy magic
	STRIDER,     # Ranger — DEX/STR, bow + traps
	MINSTREL,    # Bard — LCK/INT, buffs + debuffs
	TEMPLAR,     # Paladin — STR/INT, holy + melee
	REANIMATOR,  # Necro — INT, summon undead
	TINKERER,    # Engineer — DEX/INT, gadgets + bombs
}

# Class display names
const CLASS_NAMES := {
	PlayerClass.VANGUARD:    "Vanguard",
	PlayerClass.SCOUNDREL:   "Scoundrel",
	PlayerClass.ARCANIST:    "Arcanist",
	PlayerClass.CONFESSOR:   "Confessor",
	PlayerClass.STRIDER:     "Strider",
	PlayerClass.MINSTREL:    "Minstrel",
	PlayerClass.TEMPLAR:     "Templar",
	PlayerClass.REANIMATOR:  "Reanimator",
	PlayerClass.TINKERER:    "Tinkerer",
}

# Base stats per class: { STR, DEX, INT, LCK }
const CLASS_BASE_STATS := {
	PlayerClass.VANGUARD:    { "STR": 5, "DEX": 2, "INT": 1, "LCK": 2 },
	PlayerClass.SCOUNDREL:   { "STR": 2, "DEX": 5, "INT": 1, "LCK": 3 },
	PlayerClass.ARCANIST:    { "STR": 1, "DEX": 2, "INT": 5, "LCK": 2 },
	PlayerClass.CONFESSOR:   { "STR": 1, "DEX": 2, "INT": 4, "LCK": 3 },
	PlayerClass.STRIDER:     { "STR": 3, "DEX": 4, "INT": 1, "LCK": 2 },
	PlayerClass.MINSTREL:    { "STR": 1, "DEX": 3, "INT": 3, "LCK": 4 },
	PlayerClass.TEMPLAR:     { "STR": 4, "DEX": 1, "INT": 3, "LCK": 2 },
	PlayerClass.REANIMATOR:  { "STR": 1, "DEX": 2, "INT": 5, "LCK": 2 },
	PlayerClass.TINKERER:    { "STR": 2, "DEX": 4, "INT": 3, "LCK": 1 },
}

# ── Player State ─────────────────────────────────────────────────────────────
var player_class: PlayerClass = PlayerClass.SCOUNDREL
var player_name: String = "Hero"
var player_race: String = "human"     # human / elf / dwarf / goblin
var player_gender: String = "male"    # male / female
var player_sprite_prefix: String = ""  # set by character select; e.g. "res://assets/art/player_avatars/human_male"

# ── Camp NPCs ─────────────────────────────────────────────────────────────────
## Named NPCs rescued from dungeons (one per floor cleared), in rescue order.
## Daniels and Conner are always present from game start.
var rescued_npcs: Array[String] = ["daniels", "conner"]

# ── Companion Roster ──────────────────────────────────────────────────────────
## Full companion roster (persisted to save). Each entry is a companion dict.
var companions: Array[Dictionary] = []
## Entity keys of companions currently in the dungeon party.
var active_companions: Array[String] = []

## Cleared room IDs per floor — key = floor number as String, value = Array[int].
## Rooms in this dict are skipped for enemy spawning when the floor is re-entered.
var cleared_rooms: Dictionary = {}

## Total clearable room count per floor — key = floor number as String, value = int.
## Set during dungeon generation; used to check if a floor is fully cleared.
var floor_room_counts: Dictionary = {}

## Ordered pool — matches NpcDB.NPC_DEFS keys.
const NPC_RESCUE_POOL: Array = ["daniels", "conner", "zara", "michelle", "mahan", "claude"]

## Rescue a random unrecruited NPC. Returns the key, or "" if all recruited.
func rescue_random_npc() -> String:
	var available: Array[String] = []
	for key: String in NPC_RESCUE_POOL:
		if key not in rescued_npcs:
			available.append(key)
	if available.is_empty():
		return ""
	var chosen: String = available[randi() % available.size()]
	rescued_npcs.append(chosen)
	return chosen

# Core stats (single-digit)
var stat_str: int = 2
var stat_dex: int = 5
var stat_int: int = 1
var stat_lck: int = 3

# Vitals
var hp: int = 33
var hp_max: int = 33
var ac: int = 10  # Armor class (base 10 + equipment)
var gold: int = 0

# Progression
var current_floor: int = 1
var floors_cleared: int = 0
var total_kills: int = 0

# Dungeon state
var in_dungeon: bool = false
var torch_fuel: int = 100  # 0–100, burns while in dungeon

# Save state
var save_slot: int = 0                # which slot this run is using
var scene_state: String = "camp"      # "camp" or "dungeon" — for save/load routing
var dungeon_seed: int = 0             # RNG seed used to build current floor (0 = regenerate)

# ── Inventory ────────────────────────────────────────────────────────────────
const BACKPACK_SIZE := 24
const HOTBAR_SIZE := 6

var backpack: Array = []  # Array of item dicts, max BACKPACK_SIZE
var hotbar: Array = []    # Array of item dicts, max HOTBAR_SIZE

# Equipment slots
var equip_weapon: Dictionary = {}   # { id, name, attack_bonus, ... }
var equip_helm: Dictionary = {}
var equip_chest: Dictionary = {}
var equip_legs: Dictionary = {}
var equip_boots: Dictionary = {}

# ── Guts (delayed-power attack meter) ────────────────────────────────────────
var guts: int = 0
var guts_max: int = 3

# ── World clock (shared between camp and dungeon) ────────────────────────────
var world_time: float = 0.25        # 0..1, starts at dawn
const _WORLD_TIME_SPEED := 1.0 / 600.0  # full day every 10 real minutes

func _process(delta: float):
	world_time += delta * _WORLD_TIME_SPEED
	if world_time >= 1.0:
		world_time -= 1.0

## Return the portrait PNG path for the current race/gender selection.
## e.g. human male → "res://assets/art/player_avatars/mh_port.png"
func get_portrait_path() -> String:
	var g := "m" if player_gender == "male" else "f"
	var r := player_race[0]  # h / e / d / g
	return "res://assets/art/player_avatars/" + g + r + "_port.png"


func get_world_hour() -> float:
	return world_time * 24.0

func get_world_time_name() -> String:
	var h := get_world_hour()
	if h >= 5.0 and h < 12.0:
		return "Morning"
	elif h >= 12.0 and h < 17.0:
		return "Afternoon"
	elif h >= 17.0 and h < 21.0:
		return "Evening"
	return "Night"

# ── Tactical combat temp state ───────────────────────────────────────────────
var stat_spd: int = 3         # Speed stat (for initiative rolls)
var ac_bonus_temp: int = 0    # Temporary AC bonus from Defend/Counter (resets each turn)
var counter_active: bool = false  # Counter stance active this turn

# ── Status Effects ───────────────────────────────────────────────────────────
var status_effects: Array = []  # Array of { id: String, turns_left: int }


func _ready():
	_init_class(player_class)


## Initialise stats from chosen class.
func _init_class(cls: PlayerClass):
	player_class = cls
	var base = CLASS_BASE_STATS[cls]
	stat_str = base["STR"]
	stat_dex = base["DEX"]
	stat_int = base["INT"]
	stat_lck = base["LCK"]

	# HP scales with STR  (25 base + 4 per STR)
	hp_max = 25 + stat_str * 4
	hp = hp_max
	ac = 10
	gold = 0
	current_floor = 1
	guts = 0
	backpack.clear()
	hotbar.clear()
	equip_weapon = {}
	equip_helm = {}
	equip_chest = {}
	equip_legs = {}
	equip_boots = {}
	status_effects.clear()
	rescued_npcs = ["daniels", "conner"]
	companions.clear()
	active_companions.clear()
	cleared_rooms.clear()
	floor_room_counts.clear()
	scene_state  = "camp"
	dungeon_seed = 0


## Change class and reset stats.
func set_class(cls: PlayerClass):
	_init_class(cls)


## Deal damage to the player after AC reduction.
func take_damage(raw: int) -> int:
	var mitigated := maxi(1, raw - ac)
	hp = maxi(0, hp - mitigated)
	hp_changed.emit(hp, hp_max)
	if hp <= 0:
		player_died.emit()
	return mitigated


## Deal exact damage (no AC reduction). Used by tactical combat which
## already handles defense via clash rolls.
func take_raw_damage(amount: int) -> int:
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, hp_max)
	if hp <= 0:
		player_died.emit()
	return amount


## Heal the player.
func heal(amount: int):
	hp = mini(hp + amount, hp_max)
	hp_changed.emit(hp, hp_max)


## Add gold.
func add_gold(amount: int):
	gold += amount
	gold_changed.emit(gold)


## Get total attack power (best of STR/DEX + weapon bonus).
## DEX-based classes (Scoundrel, Ranger) benefit from their primary stat.
func get_attack_power() -> int:
	var weapon_bonus: int = equip_weapon.get("attack_bonus", 0) if equip_weapon else 0
	return maxi(stat_str, stat_dex) + weapon_bonus


## Get total AC (base + all armor + temp bonus from combat stance).
func get_total_ac() -> int:
	var total := 10
	for piece in [equip_helm, equip_chest, equip_legs, equip_boots]:
		if piece:
			total += piece.get("ac_bonus", 0)
	return total + ac_bonus_temp


## Advance to next floor.
func advance_floor():
	current_floor += 1
	floors_cleared += 1
	floor_changed.emit(current_floor)


## Roll a die: returns random int 1..sides.
func roll_die(sides: int) -> int:
	return randi_range(1, sides)


## Clash roll — maps power to the best die (d20/d12/d10/d8/d6/d4) + remainder bonus.
## Returns total roll value.
func clash_roll(power: int) -> int:
	var dice: Array[int] = [20, 12, 10, 8, 6, 4]
	for die_size in dice:
		if power >= die_size:
			var bonus: int = power - die_size
			return roll_die(die_size) + bonus
	# power < 4, just use d4
	return roll_die(4)


## Max companions allowed in active dungeon party based on current floor.
## Floor 1–3: 1, Floor 4–6: 2, Floor 7–9: 3, etc.
func get_companion_slots() -> int:
	return 1 + (current_floor - 1) / 3


## Chance to recruit an enemy, adjusted by player LCK.
## Returns a value in [0.05, 0.85]. Boss cap at 0.25.
func get_recruit_chance(hp: int, hp_max: int, is_boss: bool) -> float:
	var hp_ratio: float = float(hp) / float(maxi(1, hp_max))
	var chance: float = clampf((1.0 - hp_ratio) * 0.90 + 0.05, 0.05, 0.85)
	chance += stat_lck * 0.01
	if is_boss:
		chance = minf(chance, 0.25)
	return clampf(chance, 0.05, 0.85)


## Returns true if a companion with this entity_key is already in the roster.
func has_companion_type(key: String) -> bool:
	for c in companions:
		if c.get("key", "") == key:
			return true
	return false


## Returns the companion dict for the given entity_key, or {} if not found.
func get_companion(key: String) -> Dictionary:
	for c in companions:
		if c.get("key", "") == key:
			return c
	return {}


## Append a companion dict to the roster. Defaults tactic to "balanced".
func add_companion(dict: Dictionary):
	if not dict.has("tactic"):
		dict["tactic"] = "balanced"
	companions.append(dict)


## Set the combat tactic for a companion by entity_key.
func set_companion_tactic(key: String, tactic: String):
	for c in companions:
		if c.get("key", "") == key:
			c["tactic"] = tactic
			return


## Remove companion from roster and active list by entity_key.
func remove_companion(key: String):
	for i in companions.size():
		if companions[i].get("key", "") == key:
			companions.remove_at(i)
			break
	var aidx: int = active_companions.find(key)
	if aidx >= 0:
		active_companions.remove_at(aidx)


## Update a companion's current HP in the roster.
func update_companion_hp(key: String, new_hp: int):
	for c in companions:
		if c.get("key", "") == key:
			c["hp"] = new_hp
			return


## Restore all roster companions to full HP (bonfire rest).
func heal_companions():
	for c in companions:
		c["hp"] = c.get("hp_max", c.get("hp", 1))


## Returns the display name of a companion by entity_key.
func get_companion_name(key: String) -> String:
	var c: Dictionary = get_companion(key)
	if not c.is_empty():
		return c.get("name", key)
	return key


## Record a cleared room for a floor so it won't spawn enemies on re-entry.
func mark_room_cleared(floor: int, room_id: int):
	var fkey: String = str(floor)
	if not cleared_rooms.has(fkey):
		cleared_rooms[fkey] = []
	var arr: Array = cleared_rooms[fkey]
	if room_id not in arr:
		arr.append(room_id)


## Returns true if the room was previously cleared on that floor.
func is_room_cleared(floor: int, room_id: int) -> bool:
	var fkey: String = str(floor)
	if not cleared_rooms.has(fkey):
		return false
	return room_id in (cleared_rooms[fkey] as Array)


## Store the total number of clearable rooms for a floor.
func set_floor_room_count(floor: int, count: int):
	floor_room_counts[str(floor)] = count


## Returns true if every clearable room on the floor has been cleared.
func is_floor_cleared(floor: int) -> bool:
	var fkey: String = str(floor)
	if not floor_room_counts.has(fkey):
		return false
	var total: int = floor_room_counts[fkey] as int
	if not cleared_rooms.has(fkey):
		return false
	return (cleared_rooms[fkey] as Array).size() >= total


## Get deck multiplier for current floor (controls encounter density).
## Floor 1–3: 1x, Floor 4–6: 2x, Floor 7+: 3x.
func get_deck_multiplier() -> int:
	if current_floor >= 7:
		return 3
	elif current_floor >= 4:
		return 2
	return 1


## Save to JSON dict (for persistence).
func to_save_dict() -> Dictionary:
	return {
		"player_class": player_class,
		"player_name": player_name,
		"player_race": player_race,
		"player_gender": player_gender,
		"player_sprite_prefix": player_sprite_prefix,
		"stat_str": stat_str,
		"stat_dex": stat_dex,
		"stat_int": stat_int,
		"stat_lck": stat_lck,
		"hp": hp,
		"hp_max": hp_max,
		"ac": ac,
		"gold": gold,
		"current_floor": current_floor,
		"floors_cleared": floors_cleared,
		"total_kills": total_kills,
		"in_dungeon": in_dungeon,
		"torch_fuel": torch_fuel,
		"backpack": backpack.duplicate(true),
		"hotbar": hotbar.duplicate(true),
		"equip_weapon": equip_weapon.duplicate(true),
		"equip_helm": equip_helm.duplicate(true),
		"equip_chest": equip_chest.duplicate(true),
		"equip_legs": equip_legs.duplicate(true),
		"equip_boots": equip_boots.duplicate(true),
		"guts": guts,
		"scene_state":       scene_state,
		"dungeon_seed":      dungeon_seed,
		"save_slot":         save_slot,
		"rescued_npcs":      rescued_npcs.duplicate(),
		"companions":        companions.duplicate(true),
		"active_companions": active_companions.duplicate(),
		"cleared_rooms":     cleared_rooms.duplicate(true),
		"floor_room_counts": floor_room_counts.duplicate(true),
	}


## Load from JSON dict.
func from_save_dict(data: Dictionary):
	player_class = data.get("player_class", PlayerClass.SCOUNDREL)
	player_name = data.get("player_name", "Hero")
	var race: String = data.get("player_race", "human")
	player_race = race
	var gender: String = data.get("player_gender", "male")
	player_gender = gender
	var prefix: String = data.get("player_sprite_prefix", "")
	player_sprite_prefix = prefix
	stat_str = data.get("stat_str", 2)
	stat_dex = data.get("stat_dex", 5)
	stat_int = data.get("stat_int", 1)
	stat_lck = data.get("stat_lck", 3)
	hp = data.get("hp", 20)
	hp_max = data.get("hp_max", 20)
	ac = data.get("ac", 10)
	gold = data.get("gold", 0)
	current_floor = data.get("current_floor", 1)
	floors_cleared = data.get("floors_cleared", 0)
	total_kills = data.get("total_kills", 0)
	in_dungeon = data.get("in_dungeon", false)
	torch_fuel = data.get("torch_fuel", 100)
	backpack = data.get("backpack", [])
	hotbar = data.get("hotbar", [])
	equip_weapon = data.get("equip_weapon", {})
	equip_helm = data.get("equip_helm", {})
	equip_chest = data.get("equip_chest", {})
	equip_legs = data.get("equip_legs", {})
	equip_boots = data.get("equip_boots", {})
	guts         = data.get("guts",         0)
	scene_state  = data.get("scene_state",  "camp")
	dungeon_seed = data.get("dungeon_seed", 0)
	save_slot    = data.get("save_slot",    0)
	var saved_npcs = data.get("rescued_npcs", ["daniels", "conner"])
	rescued_npcs = []
	for n in saved_npcs:
		rescued_npcs.append(n as String)
	var saved_companions = data.get("companions", [])
	companions = []
	for c in saved_companions:
		companions.append(c as Dictionary)
	var saved_active = data.get("active_companions", [])
	active_companions = []
	for k in saved_active:
		active_companions.append(k as String)
	# JSON returns numbers as floats; convert room IDs back to int so `in` checks work.
	var saved_cr: Dictionary = data.get("cleared_rooms", {})
	cleared_rooms = {}
	for fkey: String in saved_cr:
		var raw_ids: Array = saved_cr[fkey]
		var int_ids: Array = []
		for v in raw_ids:
			int_ids.append(int(v))
		cleared_rooms[fkey] = int_ids
	# Load floor room counts (JSON stores keys as strings, values as floats)
	var saved_frc: Dictionary = data.get("floor_room_counts", {})
	floor_room_counts = {}
	for fkey2: String in saved_frc:
		floor_room_counts[fkey2] = int(saved_frc[fkey2])
