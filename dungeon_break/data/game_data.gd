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
signal level_up(new_level: int)

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

# Job special skill names — each class gets a unique ability in place of "Defend"
const JOB_SPECIAL_SKILL := {
	PlayerClass.VANGUARD:    { "name": "Shield Wall",  "desc": "Taunt all enemies + AC buff",     "action": "skill_shield_wall" },
	PlayerClass.SCOUNDREL:   { "name": "Shadowstep",   "desc": "Teleport + free bonus attack",    "action": "skill_shadowstep" },
	PlayerClass.ARCANIST:    { "name": "Arcane Blast",  "desc": "AoE d10 to all enemies in range", "action": "skill_arcane_blast" },
	PlayerClass.CONFESSOR:   { "name": "Bless",         "desc": "Heal self +4, allies +2 HP",      "action": "skill_bless" },
	PlayerClass.STRIDER:     { "name": "Steady Shot",   "desc": "+4 dmg on next ranged attack",    "action": "skill_steady_shot" },
	PlayerClass.MINSTREL:    { "name": "War Song",      "desc": "+2 ATK to party this round",      "action": "skill_war_song" },
	PlayerClass.TEMPLAR:     { "name": "Holy Smite",    "desc": "INT-based hit, guaranteed strike", "action": "skill_holy_smite" },
	PlayerClass.REANIMATOR:  { "name": "Soul Drain",    "desc": "Steal HP from nearest enemy",     "action": "skill_soul_drain" },
	PlayerClass.TINKERER:    { "name": "Shock Mine",    "desc": "d6 dmg + stun nearest enemy",     "action": "skill_shock_mine" },
}

# Stat growth per level-up per class: which stat gets +1 at each level
# Pattern repeats: primary, secondary, primary, tertiary, …
const CLASS_LEVEL_GROWTH := {
	PlayerClass.VANGUARD:    ["STR", "DEX", "STR", "LCK"],
	PlayerClass.SCOUNDREL:   ["DEX", "LCK", "DEX", "STR"],
	PlayerClass.ARCANIST:    ["INT", "DEX", "INT", "LCK"],
	PlayerClass.CONFESSOR:   ["INT", "LCK", "INT", "DEX"],
	PlayerClass.STRIDER:     ["DEX", "STR", "DEX", "LCK"],
	PlayerClass.MINSTREL:    ["LCK", "INT", "LCK", "DEX"],
	PlayerClass.TEMPLAR:     ["STR", "INT", "STR", "LCK"],
	PlayerClass.REANIMATOR:  ["INT", "DEX", "INT", "STR"],
	PlayerClass.TINKERER:    ["DEX", "INT", "DEX", "STR"],
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

const STARTING_JOBS: Array[int] = [
	PlayerClass.VANGUARD,
	PlayerClass.SCOUNDREL,
	PlayerClass.ARCANIST,
	PlayerClass.CONFESSOR,
]

const JOB_SLUGS := {
	PlayerClass.VANGUARD: "vanguard",
	PlayerClass.SCOUNDREL: "scoundrel",
	PlayerClass.ARCANIST: "arcanist",
	PlayerClass.CONFESSOR: "confessor",
	PlayerClass.STRIDER: "strider",
	PlayerClass.MINSTREL: "minstrel",
	PlayerClass.TEMPLAR: "templar",
	PlayerClass.REANIMATOR: "reanimator",
	PlayerClass.TINKERER: "tinkerer",
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

## Searched camp objects (trees/bushes) — key = "tree_X_Z" or "bush_X_Z", value = true.
## Auto-resets at the start of each new game day.
var searched_camp_objects: Dictionary = {}
var game_day: int = 0           # increments each time world_time wraps past midnight
var _searched_day: int = -1     # the game_day the current search set belongs to

## NPCs unlocked when each floor is cleared (1-based floor → NPC keys).
## Daniels + Conner are always present from game start.
const NPC_UNLOCK_MAP: Dictionary = {
	1: ["michelle"],
	2: ["mahan", "steven"],
	3: ["claude"],
	4: ["zara"],
}

## Rescue NPCs tied to the given floor number (1-based).
## Returns an array of newly rescued NPC keys (may be empty).
func rescue_npcs_for_floor(floor_num: int) -> Array[String]:
	var result: Array[String] = []
	var keys: Array = NPC_UNLOCK_MAP.get(floor_num, [])
	for key: String in keys:
		if key not in rescued_npcs:
			rescued_npcs.append(key)
			result.append(key)
	return result

## Catch-up: ensure every NPC that should have been unlocked by now is present.
## Called on save load to handle old saves missing the new NPC data.
func _apply_npc_catchup() -> void:
	# Old saves may have floors_cleared=0 even if current_floor>1; use whichever is higher.
	var effective_cleared: int = maxi(floors_cleared, current_floor - 1)
	for floor_num: int in NPC_UNLOCK_MAP.keys():
		if effective_cleared >= floor_num:
			for key: String in NPC_UNLOCK_MAP[floor_num]:
				if key not in rescued_npcs:
					rescued_npcs.append(key)

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
var player_level: int = 1
var player_xp: int = 0
var current_floor: int = 1
var floors_cleared: int = 0
var total_kills: int = 0

# Run stats (reset each new game)
var run_gold_earned: int = 0
var run_damage_dealt: int = 0
var run_damage_taken: int = 0
var run_companions_recruited: int = 0
var cause_of_death: String = ""

# Job progression (FFT-style simplified)
var unlocked_jobs: Dictionary = {}   # int job_id -> bool
var job_rank: Dictionary = {}        # int job_id -> int rank

# Dungeon state
var in_dungeon: bool = false
var in_combat: bool = false
var torch_fuel: int = 100  # 0–100+bonus, burns while in dungeon

# ── Camp upgrades (Michelle's shop — one-time purchases) ─────────────────────
## Keys match CAMP_UPGRADES ids in structure_shop_ui.gd.
var camp_upgrades: Dictionary = {}
var torch_fuel_bonus: int = 0   # +max torch fuel from Reinforced Gate
var backpack_bonus_slots: int = 0  # extra backpack capacity from Storage Expansion

# Save state
var save_slot: int = 0                # which slot this run is using
var scene_state: String = "camp"      # "camp" or "dungeon" — for save/load routing
var dungeon_seed: int = 0             # RNG seed used to build current floor (0 = regenerate)

# ── Inventory ────────────────────────────────────────────────────────────────
const BACKPACK_SIZE := 32
const HOTBAR_SIZE := 6

var backpack: Array = []  # Array of item dicts, max BACKPACK_SIZE
var hotbar: Array = []    # Array of item dicts, max HOTBAR_SIZE

# Equipment slots
var equip_weapon: Dictionary = {}   # { id, name, attack_bonus, ... }
var equip_helm: Dictionary = {}
var equip_chest: Dictionary = {}
var equip_legs: Dictionary = {}
var equip_boots: Dictionary = {}
var equip_accessory: Dictionary = {} # Accessory slot (ring / pendant / crystal)
var phoenix_used: bool = false       # Phoenix Crystal one-time revive consumed this run

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
		game_day += 1

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
var taunt_active: bool = false    # Shield Wall taunt — enemies forced to target player
var steady_shot_bonus: int = 0    # Strider's Steady Shot: bonus damage on next ranged attack
var skill_cooldown: int = 0       # Turns remaining before job special skill can be used again
# Temporary buffs from consumables; cleared at end of combat.
var combat_buff_str: int = 0
var combat_buff_dex: int = 0
var combat_buff_int: int = 0
var combat_buff_lck: int = 0
var combat_buff_spd: int = 0
var combat_buff_atk: int = 0
var combat_buff_ac: int = 0

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

	player_level = 1
	player_xp = 0
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
	equip_accessory = {}
	phoenix_used = false
	status_effects.clear()
	rescued_npcs = ["daniels", "conner"]
	companions.clear()
	active_companions.clear()
	cleared_rooms.clear()
	floor_room_counts.clear()
	camp_upgrades.clear()
	torch_fuel_bonus = 0
	backpack_bonus_slots = 0
	scene_state  = "camp"
	dungeon_seed = 0
	in_combat = false
	run_gold_earned = 0
	run_damage_dealt = 0
	run_damage_taken = 0
	run_companions_recruited = 0
	cause_of_death = ""
	_reset_job_progress()
	clear_combat_buffs()
	ForgeSystem.reset_all()


## Change class and reset stats.
func set_class(cls: PlayerClass):
	_init_class(cls)


## Change class mid-run without resetting progression/inventory.
## Returns true if the class changed.
func change_job(cls: PlayerClass) -> bool:
	var safe_cls: int = clampi(int(cls), PlayerClass.VANGUARD, PlayerClass.TINKERER)
	if not is_job_unlocked(safe_cls):
		return false
	if safe_cls == player_class:
		return false

	var hp_ratio: float = clampf(float(hp) / float(maxi(1, hp_max)), 0.0, 1.0)
	player_class = safe_cls
	unlocked_jobs[player_class] = true
	var base = CLASS_BASE_STATS[safe_cls]
	stat_str = base["STR"]
	stat_dex = base["DEX"]
	stat_int = base["INT"]
	stat_lck = base["LCK"]

	# Recompute max HP from class STR + level while preserving current HP percentage.
	hp_max = 25 + stat_str * 4 + (player_level - 1) * 2
	hp = clampi(int(round(hp_ratio * float(hp_max))), 1, hp_max)
	hp_changed.emit(hp, hp_max)
	clear_combat_buffs()
	return true


func _reset_job_progress() -> void:
	unlocked_jobs.clear()
	job_rank.clear()
	for jid in CLASS_NAMES.keys():
		var job_id: int = int(jid)
		unlocked_jobs[job_id] = false
		job_rank[job_id] = 0
	for starter in STARTING_JOBS:
		unlocked_jobs[int(starter)] = true
	unlocked_jobs[int(player_class)] = true
	_recompute_job_unlocks()


func get_job_rank(job_id: int = -1) -> int:
	var jid: int = int(player_class) if job_id < 0 else job_id
	return int(job_rank.get(jid, 0))


func is_job_unlocked(job_id: int) -> bool:
	return bool(unlocked_jobs.get(job_id, false))


func record_job_victory() -> Array:
	var jid: int = int(player_class)
	job_rank[jid] = int(job_rank.get(jid, 0)) + 1
	return _recompute_job_unlocks()


func _rank_at_least(job_id: int, req_rank: int) -> bool:
	return int(job_rank.get(job_id, 0)) >= req_rank


func _try_unlock(job_id: int, cond: bool, newly_unlocked: Array) -> void:
	if cond and not is_job_unlocked(job_id):
		unlocked_jobs[job_id] = true
		newly_unlocked.append(job_id)


func _recompute_job_unlocks() -> Array:
	var newly_unlocked: Array = []
	for starter in STARTING_JOBS:
		unlocked_jobs[int(starter)] = true
	# Simple FFT-like dependencies using per-job ranks.
	_try_unlock(PlayerClass.STRIDER,
		_rank_at_least(PlayerClass.VANGUARD, 2) or _rank_at_least(PlayerClass.SCOUNDREL, 2),
		newly_unlocked)
	_try_unlock(PlayerClass.MINSTREL,
		_rank_at_least(PlayerClass.CONFESSOR, 2) or _rank_at_least(PlayerClass.ARCANIST, 2),
		newly_unlocked)
	_try_unlock(PlayerClass.TEMPLAR,
		_rank_at_least(PlayerClass.VANGUARD, 3) and _rank_at_least(PlayerClass.CONFESSOR, 2),
		newly_unlocked)
	_try_unlock(PlayerClass.REANIMATOR,
		_rank_at_least(PlayerClass.ARCANIST, 3) and _rank_at_least(PlayerClass.SCOUNDREL, 2),
		newly_unlocked)
	_try_unlock(PlayerClass.TINKERER,
		_rank_at_least(PlayerClass.SCOUNDREL, 2) and _rank_at_least(PlayerClass.ARCANIST, 2),
		newly_unlocked)
	unlocked_jobs[int(player_class)] = true
	return newly_unlocked


func get_job_unlock_req_text(job_id: int) -> String:
	match job_id:
		PlayerClass.STRIDER:
			return "Unlock: Vanguard R2 or Scoundrel R2"
		PlayerClass.MINSTREL:
			return "Unlock: Confessor R2 or Arcanist R2"
		PlayerClass.TEMPLAR:
			return "Unlock: Vanguard R3 + Confessor R2"
		PlayerClass.REANIMATOR:
			return "Unlock: Arcanist R3 + Scoundrel R2"
		PlayerClass.TINKERER:
			return "Unlock: Scoundrel R2 + Arcanist R2"
		_:
			return "Starting Job"


func get_job_symbol_path(job_id: int = -1) -> String:
	var jid: int = int(player_class) if job_id < 0 else job_id
	var slug: String = str(JOB_SLUGS.get(jid, ""))
	if slug == "":
		return ""
	return "res://assets/art/jobs/symbol_%s.png" % slug


func get_job_dummy_path(job_id: int = -1) -> String:
	var jid: int = int(player_class) if job_id < 0 else job_id
	var slug: String = str(JOB_SLUGS.get(jid, ""))
	if slug == "":
		return ""
	return "res://assets/art/jobs/job_%s.png" % slug


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
	run_damage_taken += amount
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, hp_max)
	if hp <= 0:
		player_died.emit()
	return amount


## Heal the player.
func heal(amount: int):
	hp = mini(hp + amount, hp_max)
	hp_changed.emit(hp, hp_max)


## Ensure the player has basic starter equipment on first run.
## Safe to call multiple times — only grants missing items.
func ensure_starter_gear():
	if equip_weapon.is_empty():
		ItemDB.equip_item(ItemDB.create_item("club"))
	if equip_chest.is_empty():
		ItemDB.equip_item(ItemDB.create_item("chest_leather"))
	if backpack.is_empty():
		ItemDB.add_to_backpack(ItemDB.create_item("bread"))
		ItemDB.add_to_backpack(ItemDB.create_item("bread"))
		ItemDB.add_to_backpack(ItemDB.create_item("baked_potato"))
		ItemDB.add_to_backpack(ItemDB.create_item("potion_red"))
		if gold == 0:
			add_gold(15)


## Add gold.
func add_gold(amount: int):
	if amount > 0:
		run_gold_earned += amount
	gold += amount
	gold_changed.emit(gold)


## Get total attack power (best of STR/DEX + weapon bonus).
## DEX-based classes (Scoundrel, Ranger) benefit from their primary stat.
func get_attack_power() -> int:
	var weapon_bonus: int = equip_weapon.get("attack_bonus", 0) if equip_weapon else 0
	var eff_str: int = stat_str + combat_buff_str
	var eff_dex: int = stat_dex + combat_buff_dex
	return maxi(eff_str, eff_dex) + weapon_bonus + combat_buff_atk


## Get total AC (base + all armor + temp bonus from combat stance).
func get_total_ac() -> int:
	var total := 10
	for piece in [equip_helm, equip_chest, equip_legs, equip_boots]:
		if piece:
			total += piece.get("ac_bonus", 0)
	return total + ac_bonus_temp + combat_buff_ac


## Check if the equipped accessory has the given passive id.
func has_accessory_passive(passive_id: String) -> bool:
	return equip_accessory.get("passive", "") == passive_id


## Get the passive value of the equipped accessory (0 if none / wrong passive).
func get_accessory_value(passive_id: String) -> int:
	if equip_accessory.get("passive", "") == passive_id:
		return int(equip_accessory.get("passive_value", 0))
	return 0


func get_combat_speed() -> int:
	return stat_spd + combat_buff_spd


func clear_combat_buffs() -> void:
	combat_buff_str = 0
	combat_buff_dex = 0
	combat_buff_int = 0
	combat_buff_lck = 0
	combat_buff_spd = 0
	combat_buff_atk = 0
	combat_buff_ac = 0


# ── XP / Level System ────────────────────────────────────────────────────────

## XP needed to go from current level to the next (50 × current level).
func xp_to_next_level() -> int:
	return 50 * player_level


## Grant XP to the player. Automatically levels up (possibly multiple times).
## Returns the number of level-ups that occurred.
func grant_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	player_xp += amount
	var levels_gained: int = 0
	while player_xp >= xp_to_next_level():
		player_xp -= xp_to_next_level()
		player_level += 1
		levels_gained += 1
		_apply_level_up_stats()
		level_up.emit(player_level)
	# Sync companion levels
	_sync_companion_levels()
	return levels_gained


## Apply stat growth for the current level-up based on class growth pattern.
func _apply_level_up_stats():
	var growth: Array = CLASS_LEVEL_GROWTH.get(player_class, ["STR", "DEX", "INT", "LCK"])
	var idx: int = (player_level - 2) % growth.size()  # -2 because we already incremented
	var stat_key: String = growth[idx]
	match stat_key:
		"STR": stat_str += 1
		"DEX": stat_dex += 1
		"INT": stat_int += 1
		"LCK": stat_lck += 1
	# Recompute HP max — gain 4 HP per STR, always gain at least 2 HP per level
	var old_hp_max := hp_max
	hp_max = 25 + stat_str * 4 + (player_level - 1) * 2
	var hp_gain := hp_max - old_hp_max
	hp = mini(hp + hp_gain, hp_max)  # Heal by the amount gained
	hp_changed.emit(hp, hp_max)


## Get companion's level: 1 level below player, minimum 1.
func get_companion_level() -> int:
	return maxi(1, player_level - 1)


## Sync companion levels — recalculates companion stats based on player level.
func _sync_companion_levels():
	var clvl: int = get_companion_level()
	for c in companions:
		var old_level: int = c.get("level", 1)
		if clvl > old_level:
			c["level"] = clvl
			# Scale companion HP with level
			var base_hp: int = c.get("base_hp_max", c.get("hp_max", 10))
			var new_hp_max: int = base_hp + (clvl - 1) * 3
			var hp_diff: int = new_hp_max - c.get("hp_max", base_hp)
			c["hp_max"] = new_hp_max
			c["hp"] = mini(c.get("hp", base_hp) + hp_diff, new_hp_max)
			# Scale attack/defense slightly
			c["attack"] = c.get("base_attack", c.get("attack", 5)) + (clvl - 1)
			c["defense"] = c.get("base_defense", c.get("defense", 8)) + (clvl - 1)


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
	# Store base stats for level scaling
	if not dict.has("base_hp_max"):
		dict["base_hp_max"] = dict.get("hp_max", 10)
	if not dict.has("base_attack"):
		dict["base_attack"] = dict.get("attack", 5)
	if not dict.has("base_defense"):
		dict["base_defense"] = dict.get("defense", 8)
	dict["level"] = get_companion_level()
	# Apply level scaling immediately
	var clvl: int = dict["level"]
	if clvl > 1:
		dict["hp_max"] = dict["base_hp_max"] + (clvl - 1) * 3
		dict["hp"] = dict["hp_max"]
		dict["attack"] = dict["base_attack"] + (clvl - 1)
		dict["defense"] = dict["base_defense"] + (clvl - 1)
	companions.append(dict)
	run_companions_recruited += 1


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


## Max torch fuel (base 100 + Reinforced Gate bonus).
func get_torch_fuel_max() -> int:
	return 100 + torch_fuel_bonus


## Returns true if the camp upgrade with the given key has been purchased.
func has_upgrade(key: String) -> bool:
	return camp_upgrades.get(key, false) as bool


## Purchase a camp upgrade. Deducts gold, applies bonus, returns true on success.
func purchase_upgrade(key: String, cost: int) -> bool:
	if has_upgrade(key):
		return false
	if gold < cost:
		return false
	add_gold(-cost)
	camp_upgrades[key] = true
	match key:
		"reinforced_gate":
			torch_fuel_bonus += 25
		"storage_expansion":
			backpack_bonus_slots += 8
	return true


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


## Mark a camp tree/bush as searched.
func mark_camp_searched(key: String) -> void:
	if game_day != _searched_day:
		searched_camp_objects.clear()
		_searched_day = game_day
	searched_camp_objects[key] = true


## Check if a camp tree/bush has been searched today.
func is_camp_searched(key: String) -> bool:
	if game_day != _searched_day:
		return false
	return searched_camp_objects.get(key, false)


## Reset all camp search markers (called on new game day automatically).
func reset_camp_searches() -> void:
	searched_camp_objects.clear()
	_searched_day = -1


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
		"player_level": player_level,
		"player_xp": player_xp,
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
		"equip_accessory": equip_accessory.duplicate(true),
		"phoenix_used": phoenix_used,
		"guts": guts,
		"scene_state":       scene_state,
		"dungeon_seed":      dungeon_seed,
		"save_slot":         save_slot,
		"rescued_npcs":      rescued_npcs.duplicate(),
		"camp_upgrades":     camp_upgrades.duplicate(),
		"companions":        companions.duplicate(true),
		"active_companions": active_companions.duplicate(),
		"cleared_rooms":     cleared_rooms.duplicate(true),
		"floor_room_counts": floor_room_counts.duplicate(true),
		"unlocked_jobs":     unlocked_jobs.duplicate(true),
		"job_rank":          job_rank.duplicate(true),
		"searched_camp_objects": searched_camp_objects.duplicate(true),
		"game_day": game_day,
		"searched_day": _searched_day,
		"forge": ForgeSystem.to_save_dict(),
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
	player_level = data.get("player_level", 1)
	player_xp = data.get("player_xp", 0)
	current_floor = data.get("current_floor", 1)
	floors_cleared = data.get("floors_cleared", 0)
	total_kills = data.get("total_kills", 0)
	in_dungeon = data.get("in_dungeon", false)
	torch_fuel = data.get("torch_fuel", 100)
	backpack = ItemDB.stack_item_array(ItemDB.normalize_item_array(data.get("backpack", [])))
	hotbar   = ItemDB.stack_item_array(ItemDB.normalize_item_array(data.get("hotbar", [])))
	equip_weapon = ItemDB.normalize_item(data.get("equip_weapon", {}))
	equip_helm = ItemDB.normalize_item(data.get("equip_helm", {}))
	equip_chest = ItemDB.normalize_item(data.get("equip_chest", {}))
	equip_legs = ItemDB.normalize_item(data.get("equip_legs", {}))
	equip_boots = ItemDB.normalize_item(data.get("equip_boots", {}))
	equip_accessory = ItemDB.normalize_item(data.get("equip_accessory", {}))
	phoenix_used = bool(data.get("phoenix_used", false))
	guts         = data.get("guts",         0)
	scene_state  = data.get("scene_state",  "camp")
	dungeon_seed = data.get("dungeon_seed", 0)
	save_slot    = data.get("save_slot",    0)
	var saved_npcs = data.get("rescued_npcs", ["daniels", "conner"])
	rescued_npcs = []
	for n in saved_npcs:
		rescued_npcs.append(n as String)
	# Restore camp upgrades and reapply bonuses
	var saved_upgrades: Dictionary = data.get("camp_upgrades", {})
	camp_upgrades = {}
	torch_fuel_bonus = 0
	backpack_bonus_slots = 0
	for k in saved_upgrades:
		camp_upgrades[k as String] = bool(saved_upgrades[k])
	if has_upgrade("reinforced_gate"):
		torch_fuel_bonus = 25
	if has_upgrade("storage_expansion"):
		backpack_bonus_slots = 8
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
	searched_camp_objects = data.get("searched_camp_objects", {})
	game_day = int(data.get("game_day", 0))
	_searched_day = int(data.get("searched_day", -1))
	var saved_unlocked: Dictionary = data.get("unlocked_jobs", {})
	unlocked_jobs = {}
	if saved_unlocked.is_empty():
		for starter in STARTING_JOBS:
			unlocked_jobs[int(starter)] = true
	else:
		for k2 in saved_unlocked:
			unlocked_jobs[int(k2)] = bool(saved_unlocked[k2])
	var saved_ranks: Dictionary = data.get("job_rank", {})
	job_rank = {}
	for k3 in saved_ranks:
		job_rank[int(k3)] = int(saved_ranks[k3])
	for jid in CLASS_NAMES.keys():
		var j2: int = int(jid)
		if not job_rank.has(j2):
			job_rank[j2] = 0
	unlocked_jobs[int(player_class)] = true
	_recompute_job_unlocks()
	# Backfill any NPCs that should be in camp based on floors_cleared
	# (handles old saves that pre-date the NPC unlock system)
	_apply_npc_catchup()
	# Restore forge system state
	var forge_data: Dictionary = data.get("forge", {})
	ForgeSystem.from_save_dict(forge_data)
	in_combat = false
	clear_combat_buffs()
