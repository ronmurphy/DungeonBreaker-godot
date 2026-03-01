extends Node
## Tactical Combat Manager — FFT-style grid combat for Dungeon Break.
##
## When combat triggers in a room:
##   1. All combatants (player + enemies) are placed on the room grid.
##   2. Initiative order is rolled (SPD + d6).
##   3. Each unit's turn: MOVE phase → ACT phase → end turn.
##   4. Player selects tiles to move to, then chooses an action.
##   5. Enemies use simple AI to approach and attack.
##   6. Combat ends when all enemies are dead or player is defeated.
##
## Uses the existing clash-roll damage system from GameData.

const TacticalGridScript = preload("res://dungeon_break/combat/tactical_grid.gd")

# ── Combat FX — texture pools & SFX paths ────────────────────────────────────
const _FX_SLASH: Array = [
	"res://assets/art/textures/slash_01.png",
	"res://assets/art/textures/slash_02.png",
	"res://assets/art/textures/slash_04.png",
	"res://assets/art/textures/slash_05.png",
]
const _FX_SPARK: Array = [
	"res://assets/art/textures/spark_01.png",
	"res://assets/art/textures/spark_03.png",
	"res://assets/art/textures/spark_06.png",
]
const _FX_STAR: Array = [
	"res://assets/art/textures/star_01.png",
	"res://assets/art/textures/star_05.png",
	"res://assets/art/textures/star_07.png",
]
const _FX_MAGIC: Array = [
	"res://assets/art/textures/magic_01.png",
	"res://assets/art/textures/circle_01.png",
]
const _SFX_HIT  := "res://assets/sfx/Craft.ogg"
const _SFX_MISS := "res://assets/sfx/Select.ogg"
const _SFX_GUTS := "res://assets/sfx/Fire.ogg"

signal combat_ended(victory: bool)
signal combat_started()
signal turn_order_changed(order: Array)
signal unit_turn_started(unit: Dictionary)
signal move_phase_started(unit: Dictionary, tiles: Array)
signal act_phase_started(unit: Dictionary)
signal action_resolved(log_text: String)
signal unit_defeated(unit: Dictionary)
signal unit_moved(unit: Dictionary, from: Vector2i, to: Vector2i)
signal companion_swap_needed(incoming_unit_idx: int)
signal companion_replace_needed(incoming_unit_idx: int, entity_key: String)
signal recruit_decision_made


# ── Constants ────────────────────────────────────────────────────────────────
const PLAYER_MOVE_RANGE := 4    # tiles per turn
const PLAYER_ATTACK_RANGE := 1  # melee = 1 tile (Manhattan)
const ENEMY_MOVE_RANGE := 3
const ENEMY_ATTACK_RANGE := 1

const _DISMISSAL_MSGS: Array = [
	"%s heads back to camp for some well-earned rest!",
	"%s waves goodbye and wanders toward safety.",
	"%s mumbles something about soup and heads campward.",
	"%s tips a friendly nod and retreats to camp.",
	"%s claps you on the shoulder and disappears toward camp.",
]

# ── Combat phases ────────────────────────────────────────────────────────────
enum Phase { IDLE, MOVE, ACT, RESOLVING, ENEMY_THINKING, ENDED }

var phase: int = Phase.IDLE

# ── Grid ─────────────────────────────────────────────────────────────────────
var tactical_grid: TacticalGridScript = null   # TacticalGrid instance

# ── Units ────────────────────────────────────────────────────────────────────
# Each unit dict: { "type": "player"/"enemy", "entity": Node3D, "grid_pos": Vector2i,
#   "name": str, "hp": int, "hp_max": int, "attack": int, "defense": int,
#   "speed": int, "move_range": int, "attack_range": int, "alive": bool,
#   "has_moved": bool, "has_acted": bool }
var _units: Array = []
var _turn_order: Array = []   # indices into _units, sorted by initiative
var _current_unit_idx: int = -1  # index in _turn_order

var _room: Dictionary = {}
var _round: int = 0

# True while waiting for the player to resolve a recruit swap/replace modal.
# player_act() awaits recruit_decision_made before advancing the turn.
var _waiting_for_recruit_decision: bool = false

# Currently highlighted move tiles (player)
var _move_tiles: Array[Vector2i] = []
var _attack_tiles: Array[Vector2i] = []

# Scene parent for adding the tactical grid Node3D
var _scene_root: Node3D = null

var _sfx_player: AudioStreamPlayer = null
var _slash_shader: Shader = null


## Start tactical combat in a room.
func start_combat(enemies: Array, companions: Array, room: Dictionary, scene_root: Node3D):
	_room = room
	_scene_root = scene_root
	_units.clear()
	_turn_order.clear()
	_round = 0
	phase = Phase.IDLE
	_init_fx()

	# Create tactical grid
	tactical_grid = TacticalGridScript.new()
	tactical_grid.name = "TacticalGrid"
	scene_root.add_child(tactical_grid)

	# Get dungeon offset from room meta if available
	var ox: int = room.get("_offset_x", 0)
	var oz: int = room.get("_offset_z", 0)

	tactical_grid.setup_room(room, ox, oz, room.get("floor_height", 0))

	# ── Place player unit ──
	var player_pos := Vector2i(
		room["cx"] + ox,
		room["cy"] + oz
	)

	_units.append({
		"type": "player",
		"entity": null,  # player entity is controlled separately
		"grid_pos": player_pos,
		"name": GameData.player_name,
		"hp": GameData.hp,
		"hp_max": GameData.hp_max,
		"attack": GameData.get_attack_power(),
		"defense": GameData.get_total_ac(),
		"speed": GameData.stat_spd + randi_range(1, 6),
		"move_range": PLAYER_MOVE_RANGE + (GameData.stat_spd / 4),
		"attack_range": PLAYER_ATTACK_RANGE + GameData.equip_weapon.get("range_bonus", 0),
		"alive": true,
		"has_moved": false,
		"has_acted": false,
	})

	# ── Place companion units (after player, before enemies) ──
	for ci in companions.size():
		var centity: Node3D = companions[ci]
		if not is_instance_valid(centity):
			continue
		var ckey: String = centity.get_meta("entity_key", "")
		var cpos: Vector2i = player_pos + Vector2i(-1 - ci, 0)
		centity.global_position = tactical_grid.grid_to_world(cpos)
		var cspd: int = centity.get_meta("speed", 4) + randi_range(1, 6)
		_units.append({
			"type": "companion",
			"entity": centity,
			"grid_pos": cpos,
			"name": centity.get_meta("name", "Companion"),
			"entity_key": ckey,
			"hp": centity.get_meta("hp", 10),
			"hp_max": centity.get_meta("hp_max", 10),
			"attack": centity.get_meta("attack", 5),
			"defense": centity.get_meta("defense", 8),
			"speed": cspd,
			"move_range": centity.get_meta("move_range", 3),
			"attack_range": centity.get_meta("attack_range", 1),
			"alive": true,
			"has_moved": false,
			"has_acted": false,
		})
		tactical_grid.set_blocked(cpos, true)

	# ── Place enemy units ──
	var spawn_positions: Array[Vector2i] = _get_enemy_spawn_positions(room, ox, oz, enemies.size())
	for i in enemies.size():
		var entity: Node3D = enemies[i]
		if not is_instance_valid(entity):
			continue

		var epos: Vector2i = spawn_positions[i] if i < spawn_positions.size() else player_pos + Vector2i(3, 0)
		# Snap enemy entity to grid position
		entity.global_position = tactical_grid.grid_to_world(epos)

		var espd: int = entity.get_meta("speed", 4) + randi_range(1, 6)

		_units.append({
			"type": "enemy",
			"entity": entity,
			"grid_pos": epos,
			"name": entity.get_meta("name", "Enemy"),
			"entity_key": entity.get_meta("entity_key", ""),
			"variant": entity.get_meta("variant", "normal"),
			"hp": entity.get_meta("hp", 20),
			"hp_max": entity.get_meta("hp_max", 20),
			"attack": entity.get_meta("attack", 5),
			"defense": entity.get_meta("defense", 10),
			"speed": espd,
			"move_range": ENEMY_MOVE_RANGE,
			"attack_range": ENEMY_ATTACK_RANGE,
			"alive": true,
			"has_moved": false,
			"has_acted": false,
		})

		# Block the tile
		tactical_grid.set_blocked(epos, true)

	tactical_grid.set_blocked(player_pos, true)

	print("TacticalCombat: started with %d enemies, %d companions in room %d" % [enemies.size(), companions.size(), room["id"]])
	combat_started.emit()

	# Defer first round so dungeon.gd can call ui.setup() and connect signals first
	call_deferred("_start_round")


## Player selects a tile to move to (called by UI).
func player_select_move(target_pos: Vector2i):
	if phase != Phase.MOVE:
		return
	if _current_unit_idx < 0 or _current_unit_idx >= _turn_order.size():
		return

	var unit_idx: int = _turn_order[_current_unit_idx]
	var unit: Dictionary = _units[unit_idx]
	if unit["type"] != "player":
		return

	# Validate target is in move range
	if target_pos not in _move_tiles and target_pos != unit["grid_pos"]:
		return

	# Move player
	_move_unit(unit_idx, target_pos)
	unit["has_moved"] = true

	# Transition to ACT phase
	phase = Phase.ACT
	tactical_grid.clear_all()
	_show_unit_positions()
	_compute_attack_targets(unit_idx)
	act_phase_started.emit(unit)


## Player selects "Wait" — skip move, go to act phase.
func player_skip_move():
	if phase != Phase.MOVE:
		return
	var unit_idx: int = _turn_order[_current_unit_idx]
	var unit: Dictionary = _units[unit_idx]
	unit["has_moved"] = true
	phase = Phase.ACT
	tactical_grid.clear_all()
	_show_unit_positions()
	_compute_attack_targets(unit_idx)
	act_phase_started.emit(unit)


## Player chooses an action (called by UI).
func player_act(action: String, target_unit_idx: int = -1):
	if phase != Phase.ACT:
		return

	var unit_idx: int = _turn_order[_current_unit_idx]
	var unit: Dictionary = _units[unit_idx]
	if unit["type"] != "player":
		return

	phase = Phase.RESOLVING

	match action:
		"attack":
			_do_attack(unit_idx, target_unit_idx)
		"defend":
			_do_defend(unit_idx)
		"counter":
			_do_counter(unit_idx)
		"guts":
			_do_guts(unit_idx)
		"recruit":
			_do_recruit(unit_idx, target_unit_idx)
		"wait":
			action_resolved.emit("%s waits." % unit["name"])
		"flee":
			_do_flee()

	unit["has_acted"] = true

	# If recruit opened a swap/replace modal, pause here until player decides.
	if _waiting_for_recruit_decision:
		await recruit_decision_made
		_waiting_for_recruit_decision = false

	# End this unit's turn
	await get_tree().create_timer(0.5).timeout
	_advance_turn()


## Get the current phase.
func get_phase() -> int:
	return phase


## Get all units.
func get_units() -> Array:
	return _units


## Get the current active unit dict (or empty).
func get_current_unit() -> Dictionary:
	if _current_unit_idx >= 0 and _current_unit_idx < _turn_order.size():
		return _units[_turn_order[_current_unit_idx]]
	return {}


## Get the turn order as unit dicts.
func get_turn_order_units() -> Array:
	var result: Array = []
	for idx in _turn_order:
		result.append(_units[idx])
	return result


## Get enemies adjacent to a position (within attack range).
func get_attackable_enemies(from_pos: Vector2i, attack_range: int) -> Array:
	var result: Array = []
	for i in _units.size():
		var u: Dictionary = _units[i]
		if u["type"] == "enemy" and u["alive"]:
			var dist: int = absi(u["grid_pos"].x - from_pos.x) + absi(u["grid_pos"].y - from_pos.y)
			if dist <= attack_range:
				result.append({"unit_idx": i, "unit": u, "distance": dist})
	return result


## Get all alive enemies.
func get_alive_enemies() -> Array:
	var result: Array = []
	for u in _units:
		if u["type"] == "enemy" and u["alive"]:
			result.append(u)
	return result


# ══════════════════════════════════════════════════════════════════════════════
# ROUND / TURN FLOW
# ══════════════════════════════════════════════════════════════════════════════

func _start_round():
	_round += 1

	# Reset per-round flags
	for unit in _units:
		unit["has_moved"] = false
		unit["has_acted"] = false
		# Re-roll initiative each round
		if unit["alive"]:
			unit["speed"] = _get_base_speed(unit) + randi_range(1, 6)

	# Sort by speed (descending) — highest goes first
	_turn_order.clear()
	for i in _units.size():
		if _units[i]["alive"]:
			_turn_order.append(i)

	_turn_order.sort_custom(func(a, b): return _units[a]["speed"] > _units[b]["speed"])

	turn_order_changed.emit(get_turn_order_units())

	_current_unit_idx = -1
	_advance_turn()


func _advance_turn():
	# Check win/loss
	if _check_end():
		return

	_current_unit_idx += 1

	# Skip dead units
	while _current_unit_idx < _turn_order.size():
		var u: Dictionary = _units[_turn_order[_current_unit_idx]]
		if u["alive"]:
			break
		_current_unit_idx += 1

	if _current_unit_idx >= _turn_order.size():
		# End of round — start next
		_start_round()
		return

	var unit_idx: int = _turn_order[_current_unit_idx]
	var unit: Dictionary = _units[unit_idx]

	# Reset temp bonuses at start of each unit's turn
	GameData.ac_bonus_temp = 0
	GameData.counter_active = false

	unit_turn_started.emit(unit)

	if unit["type"] == "player":
		_start_player_turn(unit_idx)
	elif unit["type"] == "companion":
		_start_companion_turn(unit_idx)
	else:
		_start_enemy_turn(unit_idx)


func _start_player_turn(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]

	# Sync player HP from GameData
	unit["hp"] = GameData.hp
	unit["hp_max"] = GameData.hp_max
	unit["attack"] = GameData.get_attack_power()
	unit["defense"] = GameData.get_total_ac()

	# Show movement range
	var occupied: Array[Vector2i] = _get_occupied_positions(unit_idx)
	_move_tiles = tactical_grid.get_movement_range(unit["grid_pos"], unit["move_range"], occupied)

	tactical_grid.clear_all()
	_show_unit_positions()
	tactical_grid.highlight_move(_move_tiles)
	tactical_grid.highlight_player(unit["grid_pos"])

	phase = Phase.MOVE
	move_phase_started.emit(unit, _move_tiles)


func _start_enemy_turn(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	phase = Phase.ENEMY_THINKING

	# Frozen: skip this turn, thaw next
	if unit.get("frozen_turns", 0) > 0:
		unit["frozen_turns"] -= 1
		_flash_unit(unit)
		if tactical_grid:
			_fx_float_text(
				tactical_grid.grid_to_world(unit["grid_pos"]) + Vector3(0, 1.4, 0),
				"FROZEN!", Color(0.4, 0.85, 1.0)
			)
		action_resolved.emit("[color=cyan]%s is frozen solid and cannot act![/color]" % unit["name"])
		await get_tree().create_timer(0.6).timeout
		_advance_turn()
		return

	# Simple AI: move toward nearest player-faction unit, attack if in range
	var nearest_target_idx: int = _get_nearest_player_faction(unit["grid_pos"])
	if nearest_target_idx < 0:
		action_resolved.emit("%s watches warily." % unit["name"])
		_advance_turn()
		return

	var target_pos_grid: Vector2i = _units[nearest_target_idx]["grid_pos"]
	var dist_to_target: int = absi(unit["grid_pos"].x - target_pos_grid.x) + absi(unit["grid_pos"].y - target_pos_grid.y)

	# Flash the enemy to show it's their turn
	_flash_unit(unit)

	await get_tree().create_timer(0.3).timeout

	if dist_to_target > unit["attack_range"]:
		# Move toward target
		var path: Array[Vector2i] = tactical_grid.find_path(unit["grid_pos"], target_pos_grid)
		if not path.is_empty():
			# Move up to move_range steps along path
			var steps := mini(unit["move_range"], path.size() - 1)  # don't step ON target
			if steps > 0:
				var move_target: Vector2i = path[steps - 1]
				# Make sure we don't step on another unit
				var occupied := _get_occupied_positions(unit_idx)
				while steps > 0 and move_target in occupied:
					steps -= 1
					if steps > 0:
						move_target = path[steps - 1]
				if steps > 0:
					_move_unit(unit_idx, move_target)
					await get_tree().create_timer(0.2).timeout

	# Re-check nearest target after moving
	nearest_target_idx = _get_nearest_player_faction(unit["grid_pos"])
	if nearest_target_idx >= 0:
		target_pos_grid = _units[nearest_target_idx]["grid_pos"]
		dist_to_target = absi(unit["grid_pos"].x - target_pos_grid.x) + absi(unit["grid_pos"].y - target_pos_grid.y)
		if dist_to_target <= unit["attack_range"]:
			_do_enemy_attack(unit_idx, nearest_target_idx)
			await get_tree().create_timer(0.4).timeout
		else:
			action_resolved.emit("%s watches warily." % unit["name"])
	else:
		action_resolved.emit("%s watches warily." % unit["name"])

	_advance_turn()


## Returns index of nearest alive unit with type "player" or "companion"
## from the given grid position. Defenders are weighted as if twice as close
## so enemies preferentially target them.
func _get_nearest_player_faction(from_pos: Vector2i) -> int:
	var best_idx: int = -1
	var best_dist: float = INF
	for i in _units.size():
		var u: Dictionary = _units[i]
		if not u["alive"]:
			continue
		if u["type"] != "player" and u["type"] != "companion":
			continue
		var d: float = float(absi(u["grid_pos"].x - from_pos.x) + absi(u["grid_pos"].y - from_pos.y))
		# Defender tactic: appear twice as close — enemies prefer targeting them
		if u["type"] == "companion":
			var cdata: Dictionary = GameData.get_companion(u.get("entity_key", ""))
			if cdata.get("tactic", "") == "defender":
				d *= 0.5
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


## Returns index of nearest alive enemy from the given grid position, or -1.
func _get_nearest_enemy(from_pos: Vector2i) -> int:
	var best_idx: int = -1
	var best_dist: int = 9999
	for i in _units.size():
		var u: Dictionary = _units[i]
		if not u["alive"] or u["type"] != "enemy":
			continue
		var d: int = absi(u["grid_pos"].x - from_pos.x) + absi(u["grid_pos"].y - from_pos.y)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


## Returns index of alive enemy with the lowest current HP, or -1.
func _get_weakest_enemy() -> int:
	var best_idx: int = -1
	var best_hp: int = 9999
	for i in _units.size():
		var u: Dictionary = _units[i]
		if not u["alive"] or u["type"] != "enemy":
			continue
		if u["hp"] < best_hp:
			best_hp = u["hp"]
			best_idx = i
	return best_idx


## Returns index of the alive enemy closest to the player unit, or -1.
func _get_enemy_nearest_player() -> int:
	if _units.is_empty():
		return -1
	var player_pos: Vector2i = _units[0]["grid_pos"]
	return _get_nearest_enemy(player_pos)


## Read the tactic string from GameData for a companion unit.
func _get_companion_tactic(unit: Dictionary) -> String:
	var cdata: Dictionary = GameData.get_companion(unit.get("entity_key", ""))
	return cdata.get("tactic", "balanced")


## Shared move helper: move unit_idx toward target_pos. Returns true if moved.
func _companion_move_toward(unit_idx: int, target_pos: Vector2i) -> bool:
	var unit: Dictionary = _units[unit_idx]
	var path: Array[Vector2i] = tactical_grid.find_path(unit["grid_pos"], target_pos)
	if path.is_empty():
		return false
	var steps := mini(unit["move_range"], path.size() - 1)
	if steps <= 0:
		return false
	var move_target: Vector2i = path[steps - 1]
	var occupied := _get_occupied_positions(unit_idx)
	while steps > 0 and move_target in occupied:
		steps -= 1
		if steps > 0:
			move_target = path[steps - 1]
	if steps <= 0:
		return false
	_move_unit(unit_idx, move_target)
	return true


## Shared: attack the nearest in-range enemy. Returns true if attacked.
func _companion_attack_nearest(unit_idx: int) -> bool:
	var unit: Dictionary = _units[unit_idx]
	var enemy_idx: int = _get_nearest_enemy(unit["grid_pos"])
	if enemy_idx < 0:
		return false
	var enemy_pos: Vector2i = _units[enemy_idx]["grid_pos"]
	var dist: int = absi(unit["grid_pos"].x - enemy_pos.x) + absi(unit["grid_pos"].y - enemy_pos.y)
	if dist <= unit["attack_range"]:
		_do_companion_attack(unit_idx, enemy_idx)
		return true
	return false


## Shared: use first backpack consumable on target. Returns true if used.
## pass player_unit=true to use on player, false to use on self (unit_idx).
func _companion_use_heal_item(unit_idx: int, on_player: bool) -> bool:
	var unit: Dictionary = _units[unit_idx]
	for bi in GameData.backpack.size():
		var item: Dictionary = GameData.backpack[bi]
		var t: int = item.get("type", -1)
		if t != ItemDB.ItemType.FOOD and t != ItemDB.ItemType.POTION:
			continue
		var item_name: String = item.get("name", "item")
		if on_player:
			ItemDB.use_item(item)
			ItemDB.remove_from_backpack(bi)
			_units[0]["hp"] = GameData.hp
			action_resolved.emit("[color=lime]%s uses your %s on you![/color]" % [unit["name"], item_name])
		else:
			var heal: int = item.get("heal_amount", item.get("heal", 10))
			unit["hp"] = mini(unit["hp"] + heal, unit["hp_max"])
			GameData.update_companion_hp(unit.get("entity_key", ""), unit["hp"])
			ItemDB.remove_from_backpack(bi)
			action_resolved.emit("[color=lime]%s uses a %s![/color]" % [unit["name"], item_name])
		return true
	return false


## Companion AI turn: dispatches to the companion's assigned tactic.
func _start_companion_turn(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	phase = Phase.ENEMY_THINKING

	_flash_unit(unit)
	await get_tree().create_timer(0.3).timeout

	match _get_companion_tactic(unit):
		"healer":   await _tactic_healer(unit_idx)
		"berserker":await _tactic_berserker(unit_idx)
		"defender": await _tactic_defender(unit_idx)
		_:          await _tactic_balanced(unit_idx)

	_advance_turn()


## BALANCED — heal critical allies, pursue nearest enemy.
func _tactic_balanced(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	var used_item: bool = false
	var player_ratio: float = float(GameData.hp) / float(maxi(1, GameData.hp_max))
	var self_ratio: float  = float(unit["hp"]) / float(maxi(1, unit["hp_max"]))

	if player_ratio <= 0.25:
		used_item = _companion_use_heal_item(unit_idx, true)
	elif self_ratio <= 0.10:
		used_item = _companion_use_heal_item(unit_idx, false)

	var enemy_idx: int = _get_nearest_enemy(unit["grid_pos"])
	if enemy_idx < 0:
		if not used_item:
			action_resolved.emit("%s stands guard." % unit["name"])
		return

	var moved: bool = _companion_move_toward(unit_idx, _units[enemy_idx]["grid_pos"])
	if moved:
		await get_tree().create_timer(0.2).timeout

	if _companion_attack_nearest(unit_idx):
		await get_tree().create_timer(0.4).timeout
	elif not used_item:
		action_resolved.emit("%s stands guard." % unit["name"])


## HEALER — aggressive item use on any low-HP ally, retreats when engaged.
func _tactic_healer(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	var used_item: bool = false
	var player_ratio: float = float(GameData.hp) / float(maxi(1, GameData.hp_max))
	var self_ratio: float  = float(unit["hp"]) / float(maxi(1, unit["hp_max"]))

	# Proactive thresholds: 50% player, 30% self
	if player_ratio <= 0.50:
		used_item = _companion_use_heal_item(unit_idx, true)
	if not used_item and self_ratio <= 0.30:
		used_item = _companion_use_heal_item(unit_idx, false)

	# Check for adjacent enemies — retreat toward player if threatened
	var adjacent_enemy: bool = false
	for u in _units:
		if u["type"] == "enemy" and u["alive"]:
			var d: int = absi(unit["grid_pos"].x - u["grid_pos"].x) + absi(unit["grid_pos"].y - u["grid_pos"].y)
			if d <= 1:
				adjacent_enemy = true
				break

	if adjacent_enemy:
		var moved: bool = _companion_move_toward(unit_idx, _units[0]["grid_pos"])
		if moved:
			await get_tree().create_timer(0.2).timeout
		# Still attack if something is in range after retreating
		if _companion_attack_nearest(unit_idx):
			await get_tree().create_timer(0.4).timeout
		elif not used_item:
			action_resolved.emit("[color=cyan]%s retreats to safety![/color]" % unit["name"])
	else:
		# No immediate threat — move toward nearest enemy and attack
		var enemy_idx: int = _get_nearest_enemy(unit["grid_pos"])
		if enemy_idx >= 0:
			var moved: bool = _companion_move_toward(unit_idx, _units[enemy_idx]["grid_pos"])
			if moved:
				await get_tree().create_timer(0.2).timeout
			if _companion_attack_nearest(unit_idx):
				await get_tree().create_timer(0.4).timeout
			elif not used_item:
				action_resolved.emit("%s stands ready." % unit["name"])
		elif not used_item:
			action_resolved.emit("%s stands ready." % unit["name"])


## BERSERKER — ignores items, always charges the lowest-HP enemy.
func _tactic_berserker(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]

	# Target weakest enemy (lowest HP) for the kill
	var target_idx: int = _get_weakest_enemy()
	if target_idx < 0:
		action_resolved.emit("[color=red]%s rages, finding no prey![/color]" % unit["name"])
		return

	var target_pos: Vector2i = _units[target_idx]["grid_pos"]
	var moved: bool = _companion_move_toward(unit_idx, target_pos)
	if moved:
		await get_tree().create_timer(0.15).timeout

	# Attack the in-range enemy (prefer the weakest, but take nearest)
	if _companion_attack_nearest(unit_idx):
		await get_tree().create_timer(0.4).timeout
	else:
		action_resolved.emit("[color=red]%s charges forward![/color]" % unit["name"])


## DEFENDER — interposes between the player and the nearest threat.
## Enemies already prefer targeting Defenders (see _get_nearest_player_faction).
func _tactic_defender(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	var used_item: bool = false

	# Still rescues a critically wounded player
	var player_ratio: float = float(GameData.hp) / float(maxi(1, GameData.hp_max))
	if player_ratio <= 0.25:
		used_item = _companion_use_heal_item(unit_idx, true)

	var enemy_idx: int = _get_enemy_nearest_player()
	if enemy_idx < 0:
		if not used_item:
			action_resolved.emit("[color=cyan]%s holds the line.[/color]" % unit["name"])
		return

	# Interpose: move toward midpoint between player and the threat
	var player_pos: Vector2i = _units[0]["grid_pos"]
	var enemy_pos: Vector2i  = _units[enemy_idx]["grid_pos"]
	var mid := Vector2i(
		(player_pos.x + enemy_pos.x) / 2,
		(player_pos.y + enemy_pos.y) / 2
	)

	var moved: bool = _companion_move_toward(unit_idx, mid)
	if moved:
		await get_tree().create_timer(0.2).timeout

	# Attack any enemy now in range
	if _companion_attack_nearest(unit_idx):
		await get_tree().create_timer(0.4).timeout
	elif not used_item:
		action_resolved.emit("[color=cyan]%s holds the line.[/color]" % unit["name"])


## Companion melee/ranged attack.
func _do_companion_attack(attacker_idx: int, target_idx: int):
	var attacker: Dictionary = _units[attacker_idx]
	var target: Dictionary = _units[target_idx]

	var atk_roll: int = _clash_roll(attacker["attack"])
	var def_roll: int = _clash_roll(target["defense"])

	if atk_roll > def_roll:
		var dmg: int = maxi(1, atk_roll - def_roll)
		_apply_damage(target_idx, dmg)
		action_resolved.emit("[color=lime]%s[/color] strikes %s! [color=white]%d vs %d[/color] → [color=red]%d damage![/color]" % [
			attacker["name"], target["name"], atk_roll, def_roll, dmg])
	elif def_roll > atk_roll:
		var dmg: int = maxi(1, def_roll - atk_roll)
		action_resolved.emit("[color=gray]%s attacks but %s deflects![/color]" % [attacker["name"], target["name"]])
		if tactical_grid:
			_fx_float_text(tactical_grid.grid_to_world(attacker["grid_pos"]) + Vector3(0, 1.2, 0),
				"Miss!", Color(0.7, 0.7, 0.7))
		_fx_play_sfx(_SFX_MISS, randf_range(0.9, 1.1))
	else:
		action_resolved.emit("[color=gray]%s and %s clash to a stalemate![/color]" % [attacker["name"], target["name"]])


## Player attempts to recruit target enemy.
func _do_recruit(attacker_idx: int, target_idx: int):
	if target_idx < 0 or target_idx >= _units.size():
		action_resolved.emit("No valid recruit target.")
		return

	var target: Dictionary = _units[target_idx]
	if not target["alive"] or target["type"] != "enemy":
		action_resolved.emit("Can't recruit that target.")
		return

	var is_boss: bool = target.get("variant", "normal") == "boss"
	var chance: float = GameData.get_recruit_chance(target["hp"], target["hp_max"], is_boss)
	var pct: int = int(chance * 100.0)

	if randf() < chance:
		action_resolved.emit("[color=lime]%s seems interested! Attempting to recruit…[/color]" % target["name"])
		_attempt_recruit(target_idx)
	else:
		action_resolved.emit("[color=orange]%s refuses! (%d%% chance)[/color]" % [target["name"], pct])


## Internal: handle roster/slot checks before finalising recruit.
func _attempt_recruit(target_idx: int):
	var unit: Dictionary = _units[target_idx]
	var ekey: String = unit.get("entity_key", "")

	var already_in_roster: bool = GameData.has_companion_type(ekey)

	# Count active companions currently in this combat
	var active_count: int = 0
	for u in _units:
		if u["type"] == "companion" and u["alive"]:
			active_count += 1

	var max_slots: int = GameData.get_companion_slots()

	if already_in_roster:
		_waiting_for_recruit_decision = true
		companion_replace_needed.emit(target_idx, ekey)
	elif active_count >= max_slots:
		_waiting_for_recruit_decision = true
		companion_swap_needed.emit(target_idx)
	else:
		_finalize_recruit(target_idx)


## Convert an enemy unit into a companion and register it.
func _finalize_recruit(target_idx: int):
	var unit: Dictionary = _units[target_idx]
	var ekey: String = unit.get("entity_key", "")

	unit["type"] = "companion"

	# Build companion roster entry
	var comp_dict: Dictionary = {
		"key":             ekey,
		"name":            unit["name"],
		"hp":              unit["hp"],
		"hp_max":          unit["hp_max"],
		"attack":          unit["attack"],
		"defense":         unit["defense"],
		"speed":           unit.get("speed", 4),
		"move_range":      unit.get("move_range", ENEMY_MOVE_RANGE),
		"attack_range":    unit.get("attack_range", ENEMY_ATTACK_RANGE),
		"equip_weapon":    {},
		"equip_armor":     {},
		"recruited_floor": GameData.current_floor,
	}
	GameData.add_companion(comp_dict)
	GameData.active_companions.append(ekey)

	if tactical_grid:
		tactical_grid.highlight_companion(unit["grid_pos"])

	turn_order_changed.emit(get_turn_order_units())
	action_resolved.emit("[color=gold]★ %s joined your party![/color]" % unit["name"])

	# Unblock player_act() if it was waiting for this decision
	if _waiting_for_recruit_decision:
		recruit_decision_made.emit()


## Called by UI when the player declines a recruit (keeps old companion).
## Unblocks player_act() without finalizing a new recruit.
func recruit_decision_complete():
	if _waiting_for_recruit_decision:
		_waiting_for_recruit_decision = false
		recruit_decision_made.emit()


## Dismiss a companion from the current combat (send to camp roster but not active).
func dismiss_companion_for(dismissed_unit_idx: int):
	if dismissed_unit_idx < 0 or dismissed_unit_idx >= _units.size():
		return
	var unit: Dictionary = _units[dismissed_unit_idx]
	var msg: String = _DISMISSAL_MSGS[randi() % _DISMISSAL_MSGS.size()] % unit["name"]
	action_resolved.emit("[color=gray]%s[/color]" % msg)
	unit["type"] = "dismissed"
	unit["alive"] = false
	tactical_grid.set_blocked(unit["grid_pos"], false)
	if is_instance_valid(unit.get("entity", null)):
		(unit["entity"] as Node3D).visible = false
	var ckey: String = unit.get("entity_key", "")
	var aidx: int = GameData.active_companions.find(ckey)
	if aidx >= 0:
		GameData.active_companions.remove_at(aidx)
	# HP is preserved in roster — companion is benched, not dead


# ══════════════════════════════════════════════════════════════════════════════
# ACTIONS
# ══════════════════════════════════════════════════════════════════════════════

func _do_attack(attacker_idx: int, target_idx: int):
	var attacker: Dictionary = _units[attacker_idx]

	# If no valid target, try nearest enemy
	if target_idx < 0 or target_idx >= _units.size():
		var nearby := get_attackable_enemies(attacker["grid_pos"], attacker["attack_range"])
		if nearby.is_empty():
			action_resolved.emit("No enemies in range!")
			return
		target_idx = nearby[0]["unit_idx"]

	var target: Dictionary = _units[target_idx]
	var is_ranged: bool = attacker.get("attack_range", 1) > 1
	var weapon_id: String = GameData.equip_weapon.get("id", "") if attacker["type"] == "player" else ""

	# Clash roll
	var player_roll: int = GameData.clash_roll(attacker["attack"])
	var enemy_roll: int = _clash_roll(target["defense"])

	if player_roll > enemy_roll:
		var dmg := maxi(1, player_roll - enemy_roll)
		if is_ranged and tactical_grid:
			# Fire the projectile — it will trigger impact FX on landing
			var from_wpos: Vector3 = tactical_grid.grid_to_world(attacker["grid_pos"]) + Vector3(0, 1.1, 0)
			var to_wpos: Vector3   = tactical_grid.grid_to_world(target["grid_pos"])   + Vector3(0, 1.1, 0)

			# Highlight the flight path on the grid before launching
			var from_gpos: Vector2i = attacker["grid_pos"]
			var to_gpos: Vector2i   = target["grid_pos"]
			var path_tiles: Array[Vector2i]
			if weapon_id == "boomerang":
				path_tiles = _get_boomerang_path_tiles(from_gpos, to_gpos)
			else:
				path_tiles = _get_line_path_tiles(from_gpos, to_gpos)
			tactical_grid.highlight_ranged_path(path_tiles)

			# Build weapon-specific impact callback
			var impact_cb: Callable
			match weapon_id:
				"ice_bow":
					impact_cb = func() -> void:
						if not is_instance_valid(self): return
						if tactical_grid and is_instance_valid(tactical_grid):
							tactical_grid.clear_ranged_path()
						_fx_ice_impact(to_wpos)
						_fx_float_text(to_wpos, "-%d  FROZEN!" % dmg, Color(0.4, 0.9, 1.0))
						_fx_play_sfx(_SFX_HIT, randf_range(0.85, 1.15))
						_fx_camera_shake(0.10)
				"fire_staff":
					impact_cb = func() -> void:
						if not is_instance_valid(self): return
						if tactical_grid and is_instance_valid(tactical_grid):
							tactical_grid.clear_ranged_path()
						_fx_fire_impact(to_wpos)
						_fx_float_text(to_wpos, "-%d" % dmg, Color(1.0, 0.5, 0.1))
						_fx_play_sfx(_SFX_HIT, randf_range(0.85, 1.15))
						_fx_camera_shake(0.18)
						# AoE splash — half damage to all units adjacent to target
						var aoe_dmg: int = maxi(1, dmg / 2)
						for i in _units.size():
							if i == target_idx:
								continue
							var u: Dictionary = _units[i]
							if not u["alive"]:
								continue
							var d: int = absi(u["grid_pos"].x - to_gpos.x) + absi(u["grid_pos"].y - to_gpos.y)
							if d <= 1:
								_apply_damage(i, aoe_dmg)
				"throwing_knives":
					impact_cb = func() -> void:
						if not is_instance_valid(self): return
						if tactical_grid and is_instance_valid(tactical_grid):
							tactical_grid.clear_ranged_path()
						_fx_impact(to_wpos, "slash")
						_fx_float_text(to_wpos, "-%d  Pierce!" % dmg, Color(0.8, 0.9, 1.0))
						_fx_play_sfx(_SFX_HIT, randf_range(0.85, 1.15))
						_fx_camera_shake(0.10)
						# Pierce: apply half damage to all enemies along the line path
						var knife_path: Array[Vector2i] = _get_line_path_tiles(from_gpos, to_gpos)
						var pierce_dmg: int = maxi(1, dmg / 2)
						for i in _units.size():
							if i == target_idx:
								continue
							var u: Dictionary = _units[i]
							if not u["alive"] or u["type"] == "player":
								continue
							if u["grid_pos"] in knife_path:
								_apply_damage(i, pierce_dmg)
				_:
					impact_cb = func() -> void:
						if not is_instance_valid(self): return
						if tactical_grid and is_instance_valid(tactical_grid):
							tactical_grid.clear_ranged_path()
						_fx_impact(to_wpos, "slash")
						_fx_float_text(to_wpos, "-%d" % dmg, Color(1.0, 0.9, 0.25))
						_fx_play_sfx(_SFX_HIT, randf_range(0.85, 1.15))
						_fx_camera_shake(0.10)

			# Apply damage (suppress FX — projectile handles impact visuals)
			_apply_damage(target_idx, dmg, true)

			# Weapon-specific status effects
			if weapon_id == "ice_bow":
				target["frozen_turns"] = 1

			# Launch projectile
			if weapon_id == "boomerang":
				_fx_boomerang(from_wpos, to_wpos, impact_cb)
			elif weapon_id == "throwing_knives":
				_fx_throwing_knives(from_wpos, to_wpos, impact_cb)
			else:
				_fx_projectile(from_wpos, to_wpos, weapon_id, impact_cb)

			# Build log suffix for special effects
			var log_suffix := ""
			if weapon_id == "ice_bow":
				log_suffix = "  [color=cyan](Frozen!)[/color]"
			elif weapon_id == "fire_staff":
				log_suffix = "  [color=orange](+AoE)[/color]"
			elif weapon_id == "throwing_knives":
				log_suffix = "  [color=lightblue](Pierce)[/color]"
			action_resolved.emit("[color=yellow]%s[/color] %s %s! [color=white]%d vs %d[/color] → [color=red]%d damage![/color]%s" % [
				attacker["name"], _ranged_verb(weapon_id), target["name"], player_roll, enemy_roll, dmg, log_suffix])
		else:
			_apply_damage(target_idx, dmg)
			action_resolved.emit("[color=yellow]%s[/color] strikes %s! [color=white]%d vs %d[/color] → [color=red]%d damage![/color]" % [
				attacker["name"], target["name"], player_roll, enemy_roll, dmg])
	elif enemy_roll > player_roll:
		var dmg := maxi(1, enemy_roll - player_roll)
		_apply_damage(attacker_idx, dmg)
		action_resolved.emit("%s attacks but %s counters! [color=white]%d vs %d[/color] → [color=red]%d damage![/color]" % [
			attacker["name"], target["name"], player_roll, enemy_roll, dmg])
	else:
		action_resolved.emit("%s and %s clash! [color=white]%d vs %d[/color] — stalemate!" % [
			attacker["name"], target["name"], player_roll, enemy_roll])
		if tactical_grid:
			_fx_float_text(tactical_grid.grid_to_world(target["grid_pos"]) + Vector3(0, 1.2, 0),
				"Clash!", Color(0.8, 0.8, 0.5))
		_fx_play_sfx(_SFX_MISS, randf_range(0.9, 1.1))


func _do_enemy_attack(attacker_idx: int, target_idx: int):
	var attacker: Dictionary = _units[attacker_idx]
	var target: Dictionary = _units[target_idx]

	# Flash the enemy's world sprite to its attack pose
	var entity_key: String = attacker.get("entity_key", "")
	if entity_key != "" and is_instance_valid(attacker.get("entity", null)):
		EntityManager.play_attack_flash(
			attacker["entity"],
			EnemyDB.get_attack_texture_path(entity_key)
		)

	var enemy_roll: int = _clash_roll(attacker["attack"])
	var ac_bonus: int = GameData.ac_bonus_temp if target["type"] == "player" else 0
	var player_roll: int = _clash_roll(target["defense"] + ac_bonus)

	if GameData.counter_active and target["type"] == "player" and player_roll >= enemy_roll:
		# Counter-attack!
		var counter_dmg := maxi(1, player_roll - enemy_roll)
		_apply_damage(attacker_idx, counter_dmg)
		action_resolved.emit("[color=yellow]Counter![/color] %s's attack reflected for [color=red]%d damage![/color]" % [
			attacker["name"], counter_dmg])
	elif enemy_roll > player_roll:
		var dmg := maxi(1, enemy_roll - player_roll)
		_apply_damage(target_idx, dmg)
		action_resolved.emit("[color=orange]%s[/color] strikes %s! [color=white]%d vs %d[/color] → [color=red]%d damage![/color]" % [
			attacker["name"], target["name"], enemy_roll, player_roll, dmg])
	else:
		action_resolved.emit("[color=gray]%s attacks %s but misses! [color=white]%d vs %d[/color][/color]" % [
			attacker["name"], target["name"], enemy_roll, player_roll])
		if tactical_grid:
			_fx_float_text(tactical_grid.grid_to_world(target["grid_pos"]) + Vector3(0, 1.2, 0),
				"Dodge!", Color(0.4, 1.0, 0.6))
		_fx_play_sfx(_SFX_MISS, randf_range(1.0, 1.3))


func _do_defend(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	GameData.ac_bonus_temp = 4
	action_resolved.emit("%s takes a defensive stance. (+4 AC)" % unit["name"])


func _do_counter(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	GameData.ac_bonus_temp = 4
	GameData.counter_active = true
	action_resolved.emit("%s readies a counter. (+4 AC, counter)" % unit["name"])


func _do_guts(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	if GameData.guts >= GameData.guts_max:
		# Guts unleash — powerful attack on all nearby enemies
		var targets := get_attackable_enemies(unit["grid_pos"], 2)  # AoE range 2
		var total_dmg := 0
		for t in targets:
			var guts_power: int = GameData.stat_str + GameData.get_attack_power()
			var roll: int = GameData.clash_roll(guts_power) + GameData.roll_die(GameData.stat_str)
			var dmg: int = maxi(1, roll - _units[t["unit_idx"]]["defense"])
			_apply_damage(t["unit_idx"], dmg)
			total_dmg += dmg
		GameData.guts = 0
		action_resolved.emit("[color=red]GUTS UNLEASHED![/color] %d total damage to %d enemies!" % [total_dmg, targets.size()])
		if tactical_grid:
			_fx_guts_burst(tactical_grid.grid_to_world(unit["grid_pos"]) + Vector3(0, 0.5, 0))
		_fx_play_sfx(_SFX_GUTS, 0.9)
		_fx_camera_shake(0.40)
	else:
		GameData.guts += 1
		GameData.ac_bonus_temp = 2
		action_resolved.emit("%s charges guts! (%d/%d) (+2 AC)" % [unit["name"], GameData.guts, GameData.guts_max])
		if tactical_grid:
			_fx_float_text(tactical_grid.grid_to_world(unit["grid_pos"]) + Vector3(0, 1.4, 0),
				"GUTS %d/%d" % [GameData.guts, GameData.guts_max], Color(1.0, 0.55, 0.1))
		_fx_camera_shake(0.06)


func _do_flee():
	var flee_chance := 0.50 + GameData.stat_lck * 0.05
	if randf() < flee_chance:
		action_resolved.emit("[color=yellow]Escaped![/color]")
		phase = Phase.ENDED
		_cleanup()
		combat_ended.emit(false)
	else:
		action_resolved.emit("[color=gray]Can't escape![/color]")


# ══════════════════════════════════════════════════════════════════════════════
# MOVEMENT
# ══════════════════════════════════════════════════════════════════════════════

func _move_unit(unit_idx: int, target_pos: Vector2i):
	var unit: Dictionary = _units[unit_idx]
	var old_pos: Vector2i = unit["grid_pos"]

	# Update grid blocking
	tactical_grid.set_blocked(old_pos, false)
	tactical_grid.set_blocked(target_pos, true)

	unit["grid_pos"] = target_pos

	# Move the entity in 3D space
	if unit["type"] in ["enemy", "companion"] and is_instance_valid(unit.get("entity", null)):
		unit["entity"].global_position = tactical_grid.grid_to_world(target_pos)

	unit_moved.emit(unit, old_pos, target_pos)


func _get_occupied_positions(exclude_idx: int = -1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in _units.size():
		if i != exclude_idx and _units[i]["alive"]:
			result.append(_units[i]["grid_pos"])
	return result


# ══════════════════════════════════════════════════════════════════════════════
# DAMAGE / DEATH
# ══════════════════════════════════════════════════════════════════════════════

func _apply_damage(unit_idx: int, damage: int, suppress_fx: bool = false):
	var unit: Dictionary = _units[unit_idx]
	unit["hp"] = maxi(0, unit["hp"] - damage)

	if unit["type"] == "player":
		GameData.take_raw_damage(damage)
		unit["hp"] = GameData.hp
	else:
		# Update entity meta (works for both enemies and companions)
		if is_instance_valid(unit.get("entity", null)):
			unit["entity"].set_meta("hp", unit["hp"])
			# Flash red
			var sprite: Sprite3D = unit["entity"].get_meta("sprite", null)
			if sprite:
				sprite.modulate = Color.RED
				get_tree().create_timer(0.15).timeout.connect(func():
					if is_instance_valid(sprite):
						sprite.modulate = Color.WHITE
				)

	# ── Impact FX ────────────────────────────────────────────────────────────
	# suppress_fx=true means a projectile is in flight and will trigger FX on landing
	if tactical_grid and not suppress_fx:
		var wpos: Vector3 = tactical_grid.grid_to_world(unit["grid_pos"]) + Vector3(0, 1.1, 0)
		var is_player_hit: bool = unit["type"] == "player"
		_fx_impact(wpos, "blunt" if is_player_hit else "slash")
		var num_col := Color(1.0, 0.35, 0.2) if is_player_hit else Color(1.0, 0.9, 0.25)
		_fx_float_text(wpos, "-%d" % damage, num_col)
		_fx_play_sfx(_SFX_HIT, randf_range(0.85, 1.15))
		_fx_camera_shake(0.18 if is_player_hit else 0.10)

	if unit["hp"] <= 0:
		_kill_unit(unit_idx)


func _kill_unit(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	unit["alive"] = false

	tactical_grid.set_blocked(unit["grid_pos"], false)

	if unit["type"] == "enemy":
		if is_instance_valid(unit["entity"]):
			EntityManager.despawn_entity(unit["entity"])

		GameData.total_kills += 1
		var gold_drop := randi_range(1, 5) + GameData.current_floor
		GameData.add_gold(gold_drop)

		# Roll for item drop
		var loot: Dictionary = ItemDB.roll_loot(GameData.current_floor)
		var loot_msg := ""
		if not loot.is_empty():
			if ItemDB.add_to_backpack(loot):
				loot_msg = "  Found [color=cyan]%s[/color]!" % loot.get("name", "item")
			else:
				loot_msg = "  Found %s but backpack full!" % loot.get("name", "item")

		unit_defeated.emit(unit)
		action_resolved.emit("[color=green]%s defeated![/color] +%d gold%s" % [unit["name"], gold_drop, loot_msg])

	elif unit["type"] == "companion":
		if is_instance_valid(unit.get("entity", null)):
			EntityManager.despawn_entity(unit["entity"])
		unit_defeated.emit(unit)
		action_resolved.emit("[color=orange]%s has fallen![/color] (Permadeath)" % unit["name"])

	elif unit["type"] == "player":
		unit_defeated.emit(unit)


# ══════════════════════════════════════════════════════════════════════════════
# HIGHLIGHTS
# ══════════════════════════════════════════════════════════════════════════════

func _show_unit_positions():
	for unit in _units:
		if not unit["alive"]:
			continue
		if unit["type"] == "player":
			tactical_grid.highlight_player(unit["grid_pos"])
		elif unit["type"] == "companion":
			tactical_grid.highlight_companion(unit["grid_pos"])
		else:
			tactical_grid.highlight_enemy(unit["grid_pos"])


func _compute_attack_targets(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	_attack_tiles.clear()

	# Clear any leftover flight-path tiles from a previous ranged attack
	if tactical_grid and is_instance_valid(tactical_grid):
		tactical_grid.clear_ranged_path()

	var a_range: int = unit["attack_range"]
	for dx in range(-a_range, a_range + 1):
		for dz in range(-a_range, a_range + 1):
			if absi(dx) + absi(dz) > a_range:
				continue
			if dx == 0 and dz == 0:
				continue
			var pos: Vector2i = unit["grid_pos"] + Vector2i(dx, dz)
			_attack_tiles.append(pos)

	# Ranged weapons get a teal zone instead of the melee red
	if a_range > 1:
		tactical_grid.highlight_ranged_zone(_attack_tiles)
	else:
		tactical_grid.highlight_attack(_attack_tiles)


func _flash_unit(unit: Dictionary):
	if unit["type"] not in ["enemy", "companion"]:
		return
	if not is_instance_valid(unit.get("entity", null)):
		return
	var sprite: Sprite3D = unit["entity"].get_meta("sprite", null)
	if sprite:
		var flash_color: Color = Color(1.0, 1.0, 0.3) if unit["type"] == "enemy" else Color(0.5, 1.0, 0.6)
		sprite.modulate = flash_color
		get_tree().create_timer(0.25).timeout.connect(func():
			if is_instance_valid(sprite):
				sprite.modulate = Color.WHITE
		)


# ══════════════════════════════════════════════════════════════════════════════
# WIN / LOSE
# ══════════════════════════════════════════════════════════════════════════════

func _check_end() -> bool:
	var enemies_alive := false
	for u in _units:
		if u["type"] == "enemy" and u["alive"]:
			enemies_alive = true
			break

	if not enemies_alive:
		phase = Phase.ENDED
		action_resolved.emit("[color=green]VICTORY![/color]")
		_cleanup()
		combat_ended.emit(true)
		return true

	if GameData.hp <= 0:
		phase = Phase.ENDED
		action_resolved.emit("[color=red]DEFEAT...[/color]")
		_cleanup()
		combat_ended.emit(false)
		return true

	return false


func _cleanup():
	# Sync companion HP / permadeath
	for unit in _units:
		var ckey: String = unit.get("entity_key", "")
		if ckey == "":
			continue
		if unit["type"] == "dismissed":
			# Sent to bench — already removed from active_companions; keep roster entry
			continue
		if unit["type"] == "companion":
			if not unit.get("alive", false):
				# Permadeath: remove from roster entirely
				GameData.remove_companion(ckey)
			else:
				GameData.update_companion_hp(ckey, unit["hp"])

	# Despawn all companion/dismissed combat entities — the dungeon follower entities
	# will be re-shown instead. Dead companions were already despawned in _kill_unit;
	# despawn_entity() safely no-ops if the entity is no longer in the pool.
	for unit in _units:
		if unit["type"] in ["companion", "dismissed"]:
			if is_instance_valid(unit.get("entity", null)):
				EntityManager.despawn_entity(unit["entity"])

	# Remove tactical grid
	if tactical_grid and is_instance_valid(tactical_grid):
		tactical_grid.clear_all()
		tactical_grid.queue_free()
		tactical_grid = null

	# Reset temp bonuses
	GameData.ac_bonus_temp = 0
	GameData.counter_active = false


# ══════════════════════════════════════════════════════════════════════════════
# UTILITY
# ══════════════════════════════════════════════════════════════════════════════

func _get_base_speed(unit: Dictionary) -> int:
	if unit["type"] == "player":
		return GameData.stat_spd
	return unit.get("speed", 4)


## Get all alive units in the current combat (for UI).
func get_alive_companions() -> Array:
	var result: Array = []
	for u in _units:
		if u["type"] == "companion" and u["alive"]:
			result.append(u)
	return result


func _clash_roll(power: int) -> int:
	var dice: Array[int] = [20, 12, 10, 8, 6, 4]
	for die_size in dice:
		if power >= die_size:
			var bonus: int = power - die_size
			return randi_range(1, die_size) + bonus
	return randi_range(1, 4)


# ══════════════════════════════════════════════════════════════════════════════
# COMBAT FX — impact sprites, floating numbers, screen shake, audio
# ══════════════════════════════════════════════════════════════════════════════

func _init_fx() -> void:
	if is_instance_valid(_sfx_player):
		_sfx_player.queue_free()
	_sfx_player = AudioStreamPlayer.new()
	_scene_root.add_child(_sfx_player)

	# Cache slash sweep shader
	var shader_path := "res://dungeon_break/combat/slash_effect.gdshader"
	if ResourceLoader.exists(shader_path):
		_slash_shader = load(shader_path)


func _fx_camera_shake(trauma: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.has_method("shake"):
		cam.shake(trauma)


func _fx_play_sfx(path: String, pitch: float = 1.0) -> void:
	if not is_instance_valid(_sfx_player) or not ResourceLoader.exists(path):
		return
	_sfx_player.stream = load(path)
	_sfx_player.pitch_scale = pitch
	_sfx_player.play()


## Spawn an impact flash sprite at world_pos.
## type: "slash" (warm yellow-white), "blunt" (orange-red spark, enemy hit on player).
func _fx_impact(world_pos: Vector3, impact_type: String = "slash") -> void:
	if _scene_root == null:
		return

	var tex_list: Array
	var tint: Color
	match impact_type:
		"slash":
			tex_list = _FX_SLASH
			tint = Color(1.5, 1.1, 0.6)   # warm emissive yellow-white
		"blunt":
			tex_list = _FX_SPARK
			tint = Color(1.3, 0.4, 0.2)   # orange-red impact
		_:
			tex_list = _FX_SLASH
			tint = Color(1.2, 1.0, 0.8)

	if tex_list.is_empty():
		return
	var path: String = tex_list[randi() % tex_list.size()]
	if not ResourceLoader.exists(path):
		return

	var sprite := Sprite3D.new()
	sprite.texture = load(path)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.render_priority = 10
	sprite.pixel_size = 0.006
	sprite.double_sided = true
	sprite.modulate = tint
	sprite.scale = Vector3.ZERO
	sprite.rotation_degrees.z = randf_range(-35.0, 35.0)
	_scene_root.add_child(sprite)
	sprite.global_position = world_pos + Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.1, 0.1))

	var tw := sprite.create_tween().set_parallel(true)
	tw.tween_property(sprite, "scale", Vector3.ONE * 1.5, 0.11).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.26)
	tw.chain().tween_callback(sprite.queue_free)

	# Shader-based slash sweep overlay (slash impacts only)
	if impact_type == "slash":
		_fx_slash_sweep(world_pos, tint)

	# Secondary spark burst
	if not _FX_SPARK.is_empty():
		var spath: String = _FX_SPARK[randi() % _FX_SPARK.size()]
		if ResourceLoader.exists(spath):
			var spark := Sprite3D.new()
			spark.texture = load(spath)
			spark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			spark.no_depth_test = true
			spark.render_priority = 9
			spark.pixel_size = 0.004
			spark.modulate = Color(1.5, 1.2, 0.4, 0.9)
			spark.scale = Vector3.ZERO
			spark.rotation_degrees.z = randf_range(0.0, 360.0)
			_scene_root.add_child(spark)
			spark.global_position = world_pos + Vector3(randf_range(-0.4, 0.4), randf_range(0.1, 0.5), randf_range(-0.3, 0.3))
			var stw := spark.create_tween().set_parallel(true)
			stw.tween_property(spark, "scale", Vector3.ONE * 0.8, 0.12).set_ease(Tween.EASE_OUT)
			stw.tween_property(spark, "modulate:a", 0.0, 0.28)
			stw.chain().tween_callback(spark.queue_free)


## Floating damage / status text — rises and fades over 0.65s.
func _fx_float_text(world_pos: Vector3, text: String, color: Color = Color.WHITE) -> void:
	if _scene_root == null:
		return

	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 32
	lbl.modulate = color
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 12
	lbl.double_sided = true
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	lbl.pixel_size = 0.008
	_scene_root.add_child(lbl)
	lbl.global_position = world_pos + Vector3(randf_range(-0.25, 0.25), 0.1, randf_range(-0.1, 0.1))

	var tween := lbl.create_tween().set_parallel(true)
	tween.tween_property(lbl, "global_position", lbl.global_position + Vector3(0.0, 1.8, 0.0), 0.65) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.65).set_delay(0.22)
	tween.chain().tween_callback(lbl.queue_free)


## Expanding magic circle + star spray for Guts Unleashed.
func _fx_guts_burst(world_pos: Vector3) -> void:
	if _scene_root == null:
		return

	# Two expanding magic circles
	for ci in mini(2, _FX_MAGIC.size()):
		var cpath: String = _FX_MAGIC[ci]
		if not ResourceLoader.exists(cpath):
			continue
		var circle := Sprite3D.new()
		circle.texture = load(cpath)
		circle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		circle.no_depth_test = true
		circle.render_priority = 8
		circle.pixel_size = 0.010
		circle.modulate = Color(1.5, 0.15, 0.15, 0.9)
		circle.scale = Vector3.ZERO
		circle.rotation_degrees.y = float(ci) * 45.0
		_scene_root.add_child(circle)
		circle.global_position = world_pos

		var ctw := circle.create_tween().set_parallel(true)
		ctw.tween_property(circle, "scale", Vector3.ONE * (2.2 + ci * 0.7), 0.4) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		ctw.tween_property(circle, "modulate:a", 0.0, 0.5)
		ctw.chain().tween_callback(circle.queue_free)

	# Six-way star burst
	for i in 6:
		if _FX_STAR.is_empty():
			break
		var spath: String = _FX_STAR[randi() % _FX_STAR.size()]
		if not ResourceLoader.exists(spath):
			continue
		var star := Sprite3D.new()
		star.texture = load(spath)
		star.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star.no_depth_test = true
		star.render_priority = 9
		star.pixel_size = 0.005
		star.modulate = Color(1.5, 0.7, 0.2, 1.0)
		star.scale = Vector3.ZERO
		star.rotation_degrees.z = randf_range(0.0, 360.0)
		_scene_root.add_child(star)

		var angle := (float(i) / 6.0) * TAU + randf_range(-0.3, 0.3)
		var radius := randf_range(0.8, 1.6)
		star.global_position = world_pos + Vector3(cos(angle) * radius, randf_range(0.3, 1.2), sin(angle) * radius)

		var stw := star.create_tween().set_parallel(true)
		stw.tween_property(star, "scale", Vector3.ONE * randf_range(0.7, 1.1), 0.20).set_ease(Tween.EASE_OUT)
		stw.tween_property(star, "modulate:a", 0.0, 0.45).set_delay(0.10)
		stw.chain().tween_callback(star.queue_free)


## Attack verb for ranged weapons (used in combat log).
func _ranged_verb(weapon_id: String) -> String:
	match weapon_id:
		"fire_staff":      return "blasts"
		"ice_bow":         return "freezes"
		"crossbow":        return "shoots"
		"boomerang":       return "hurls"
		"throwing_knives": return "hurls knives at"
		_:                 return "launches at"


## Flying projectile from `from_pos` to `to_pos`.
## `on_land` callback fires when the sprite reaches the target.
func _fx_projectile(from_pos: Vector3, to_pos: Vector3, weapon_id: String, on_land: Callable = Callable()) -> void:
	if _scene_root == null:
		if on_land.is_valid():
			on_land.call()
		return

	var tex_path: String
	var tint: Color
	var travel_time := 0.28

	match weapon_id:
		"fire_staff":
			tex_path    = _FX_MAGIC[0]               # magic_01.png — fireball
			tint        = Color(2.0, 0.5, 0.1, 1.0)  # bright orange
		"ice_bow":
			tex_path    = _FX_SPARK[0]               # spark_01.png — frost bolt
			tint        = Color(0.5, 1.5, 2.5, 1.0)  # icy blue
			travel_time = 0.22
		"crossbow":
			tex_path    = _FX_SPARK[1]               # spark_03.png — crossbow bolt
			tint        = Color(1.8, 1.5, 0.9, 1.0)  # bright white-gold
			travel_time = 0.20
		_:
			tex_path    = _FX_STAR[0]                # star_01.png — generic thrown
			tint        = Color(1.5, 1.2, 0.5, 1.0)

	if not ResourceLoader.exists(tex_path):
		if on_land.is_valid():
			on_land.call()
		return

	var proj := Sprite3D.new()
	proj.texture         = load(tex_path)
	proj.billboard       = BaseMaterial3D.BILLBOARD_ENABLED
	proj.no_depth_test   = true
	proj.render_priority = 11
	proj.pixel_size      = 0.005
	proj.modulate        = tint
	proj.scale           = Vector3.ONE * 0.55
	_scene_root.add_child(proj)
	proj.global_position = from_pos

	# Guard prevents on_land firing twice if both tween and fallback timer trigger
	var landed := false

	var tw := proj.create_tween()
	tw.tween_property(proj, "global_position", to_pos, travel_time) \
		.set_trans(Tween.TRANS_LINEAR)
	tw.tween_callback(func() -> void:
		if landed:
			return
		landed = true
		if is_instance_valid(proj):
			proj.queue_free()
		if on_land.is_valid():
			on_land.call()
	)

	# Fallback: free proj and fire on_land if tween dies before completing
	get_tree().create_timer(travel_time + 0.4).timeout.connect(func() -> void:
		if landed:
			return
		landed = true
		if is_instance_valid(proj):
			proj.queue_free()
		if on_land.is_valid():
			on_land.call()
	)


## Bresenham line path tiles from player to target (skips player's own tile).
func _get_line_path_tiles(from_gpos: Vector2i, to_gpos: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var x0: int = from_gpos.x
	var y0: int = from_gpos.y
	var x1: int = to_gpos.x
	var y1: int = to_gpos.y
	var dx: int = absi(x1 - x0)
	var dy: int = absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy

	while true:
		var gp := Vector2i(x0, y0)
		if gp != from_gpos:
			tiles.append(gp)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy

	return tiles


## Boomerang Bezier arc path tiles — samples both the outbound LEFT arc and the
## mirrored return RIGHT arc, matching the same parameters used in _fx_boomerang.
func _get_boomerang_path_tiles(from_gpos: Vector2i, to_gpos: Vector2i) -> Array[Vector2i]:
	if tactical_grid == null or not is_instance_valid(tactical_grid):
		return []

	var tiles: Array[Vector2i] = []
	var seen: Dictionary = {}

	var from_w: Vector3 = tactical_grid.grid_to_world(from_gpos)
	var to_w: Vector3   = tactical_grid.grid_to_world(to_gpos)

	# Flatten to XZ for direction/distance (Y doesn't affect grid tiles)
	var fwd_flat := Vector2(to_w.x - from_w.x, to_w.z - from_w.z).normalized()
	var fwd: Vector3 = Vector3(fwd_flat.x, 0.0, fwd_flat.y)
	var dist: float  = Vector2(from_w.x, from_w.z).distance_to(Vector2(to_w.x, to_w.z))

	# Outbound arc — LEFT of travel (matches _fx_boomerang perp_out)
	var perp_out: Vector3 = Vector3(-fwd.z, 0.0, fwd.x)
	var off_out: Vector3  = perp_out * (dist * 0.42)
	var p0: Vector3 = from_w
	var p1: Vector3 = from_w + fwd * (dist * 0.33) + off_out
	var p2: Vector3 = from_w + fwd * (dist * 0.66) + off_out
	var p3: Vector3 = to_w

	# Return arc — RIGHT of travel (matches _fx_boomerang perp_ret)
	var perp_ret: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)
	var off_ret: Vector3  = perp_ret * (dist * 0.42)
	var r0: Vector3 = to_w
	var r1: Vector3 = to_w - fwd * (dist * 0.33) + off_ret
	var r2: Vector3 = to_w - fwd * (dist * 0.66) + off_ret
	var r3: Vector3 = from_w

	# Sample both arcs at 32 points and collect unique grid tiles
	for i in 32:
		var t: float  = float(i) / 31.0
		var mt: float = 1.0 - t

		# Outbound
		var wp: Vector3  = mt*mt*mt*p0 + 3.0*mt*mt*t*p1 + 3.0*mt*t*t*p2 + t*t*t*p3
		var gp: Vector2i = tactical_grid.world_to_grid(wp)
		if not gp in seen:
			seen[gp] = true
			tiles.append(gp)

		# Return
		wp = mt*mt*mt*r0 + 3.0*mt*mt*t*r1 + 3.0*mt*t*t*r2 + t*t*t*r3
		gp = tactical_grid.world_to_grid(wp)
		if not gp in seen:
			seen[gp] = true
			tiles.append(gp)

	return tiles


## Boomerang arc FX — V-shaped 3D mesh flies a Bezier arc to target, triggers on_land,
## then arcs back on a mirrored curve and disappears.
func _fx_boomerang(from_pos: Vector3, to_pos: Vector3, on_land: Callable = Callable()) -> void:
	if _scene_root == null:
		if on_land.is_valid():
			on_land.call()
		return

	# ── Build V-shaped boomerang mesh ──────────────────────────────────────────
	var boom := Node3D.new()
	_scene_root.add_child(boom)
	boom.global_position = from_pos

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.50, 0.28)   # wood brown
	mat.roughness    = 0.55
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.55, 1.0)         # magical blue glow
	mat.emission_energy_multiplier = 1.8

	var left_mesh := BoxMesh.new()
	left_mesh.size = Vector3(0.55, 0.09, 0.13)
	var left_arm := MeshInstance3D.new()
	left_arm.mesh = left_mesh
	left_arm.position = Vector3(-0.27, 0.0, 0.0)
	left_arm.rotation_degrees = Vector3(0.0, 0.0, 22.0)
	left_arm.material_override = mat
	boom.add_child(left_arm)

	var right_mesh := BoxMesh.new()
	right_mesh.size = Vector3(0.55, 0.09, 0.13)
	var right_arm := MeshInstance3D.new()
	right_arm.mesh = right_mesh
	right_arm.position = Vector3(0.27, 0.0, 0.0)
	right_arm.rotation_degrees = Vector3(0.0, 0.0, -22.0)
	right_arm.material_override = mat
	boom.add_child(right_arm)

	var glow := OmniLight3D.new()
	glow.light_color   = Color(0.3, 0.6, 1.0)
	glow.light_energy  = 2.2
	glow.omni_range    = 2.8
	glow.shadow_enabled = false
	boom.add_child(glow)

	# ── Cubic Bezier curves ────────────────────────────────────────────────────
	var fwd: Vector3  = (to_pos - from_pos).normalized()
	var dist: float   = from_pos.distance_to(to_pos)

	# Outbound — arc to the LEFT of travel
	var perp_out: Vector3 = Vector3(-fwd.z, 0.0, fwd.x).normalized()
	var off_out: Vector3  = perp_out * (dist * 0.42)
	var p0: Vector3 = from_pos
	var p1: Vector3 = from_pos + fwd * (dist * 0.33) + off_out
	var p2: Vector3 = from_pos + fwd * (dist * 0.66) + off_out
	var p3: Vector3 = to_pos

	# Return — arc to the RIGHT (mirror)
	var perp_ret: Vector3 = Vector3(fwd.z, 0.0, -fwd.x).normalized()
	var off_ret: Vector3  = perp_ret * (dist * 0.42)
	var r0: Vector3 = to_pos
	var r1: Vector3 = to_pos - fwd * (dist * 0.33) + off_ret
	var r2: Vector3 = to_pos - fwd * (dist * 0.66) + off_ret
	var r3: Vector3 = from_pos

	# ── Tween outbound then return ─────────────────────────────────────────────
	# Tween lives on boom (not self) so it survives combat_manager cleanup
	var tw: Tween = boom.create_tween()

	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(boom):
			return
		var mt: float = 1.0 - t
		boom.global_position = mt*mt*mt*p0 + 3.0*mt*mt*t*p1 + 3.0*mt*t*t*p2 + t*t*t*p3
		# Spin flat (around Y) like a frisbee, plus slight tilt into travel direction
		boom.rotation.y = Time.get_ticks_msec() * 0.014
		boom.rotation.x = deg_to_rad(80.0)
	, 0.0, 1.0, 0.40)

	tw.tween_callback(func() -> void:
		if on_land.is_valid():
			on_land.call()
	)

	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(boom):
			return
		var mt: float = 1.0 - t
		boom.global_position = mt*mt*mt*r0 + 3.0*mt*mt*t*r1 + 3.0*mt*t*t*r2 + t*t*t*r3
		boom.rotation.y = Time.get_ticks_msec() * 0.014
		boom.rotation.x = deg_to_rad(80.0)
	, 0.0, 1.0, 0.32)

	tw.tween_callback(func() -> void:
		if is_instance_valid(boom):
			boom.queue_free()
	)

	# Fallback: guarantee cleanup if tween is interrupted (e.g. scene change mid-flight)
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(boom):
			boom.queue_free()
	)


func _get_enemy_spawn_positions(room: Dictionary, ox: int, oz: int, count: int) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var cx: int = room["cx"] + ox
	var cy: int = room["cy"] + oz
	var rw: int = room["w"]
	var rh: int = room["h"]
	var rx: int = room["x"] + ox
	var ry: int = room["y"] + oz

	# Spread enemies around the room edges (away from centre where player spawns)
	var candidates: Array[Vector2i] = []
	for col in range(rx + 1, rx + rw - 1):
		for row in range(ry + 1, ry + rh - 1):
			var dist: int = absi(col - cx) + absi(row - cy)
			if dist >= 3:  # at least 3 tiles from centre
				candidates.append(Vector2i(col, row))

	candidates.shuffle()
	for i in mini(count, candidates.size()):
		positions.append(candidates[i])

	# Fill remaining with fallback positions
	while positions.size() < count:
		positions.append(Vector2i(cx + 3, cy + positions.size()))

	return positions


# ══════════════════════════════════════════════════════════════════════════════
# WEAPON SPECIAL EFFECTS
# ══════════════════════════════════════════════════════════════════════════════

## Ice bow impact — ring of ice shards bursting outward + blue light flash.
func _fx_ice_impact(world_pos: Vector3) -> void:
	if _scene_root == null:
		return

	# Ice shard ring (8 thin box shards)
	for i in 8:
		var shard := MeshInstance3D.new()
		var smesh := BoxMesh.new()
		smesh.size = Vector3(0.06, 0.06, 0.24)
		shard.mesh = smesh
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.9, 1.0, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.75, 1.0)
		mat.emission_energy_multiplier = 2.2
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shard.material_override = mat
		_scene_root.add_child(shard)
		shard.global_position = world_pos

		var angle: float = (float(i) / 8.0) * TAU
		var target_pos := world_pos + Vector3(cos(angle) * 1.1, randf_range(0.1, 0.7), sin(angle) * 1.1)
		shard.look_at(target_pos)

		var tw := shard.create_tween().set_parallel(true)
		tw.tween_property(shard, "global_position", target_pos, 0.28).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "modulate:a", 0.0, 0.35).set_delay(0.12)
		tw.chain().tween_callback(shard.queue_free)

	# Blue light flash
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.35, 0.75, 1.0)
	flash.light_energy = 4.5
	flash.omni_range = 3.5
	flash.shadow_enabled = false
	_scene_root.add_child(flash)
	flash.global_position = world_pos
	var ftw := flash.create_tween()
	ftw.tween_property(flash, "light_energy", 0.0, 0.35)
	ftw.tween_callback(flash.queue_free)


## Fire staff AoE impact — expanding fireball core + ember sparks + orange flash.
func _fx_fire_impact(world_pos: Vector3) -> void:
	if _scene_root == null:
		return

	# Expanding fireball core
	var core := MeshInstance3D.new()
	var cmesh := SphereMesh.new()
	cmesh.radius = 0.20
	cmesh.height = 0.40
	core.mesh = cmesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(1.0, 0.55, 0.1, 0.9)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.3, 0.0)
	cmat.emission_energy_multiplier = 3.5
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.material_override = cmat
	_scene_root.add_child(core)
	core.global_position = world_pos

	var ctw := core.create_tween().set_parallel(true)
	ctw.tween_property(core, "scale", Vector3.ONE * 3.5, 0.30).set_ease(Tween.EASE_OUT)
	ctw.tween_property(core, "modulate:a", 0.0, 0.36)
	ctw.chain().tween_callback(core.queue_free)

	# 8 ember sparks flying outward
	for i in 8:
		var ember := MeshInstance3D.new()
		var emesh := SphereMesh.new()
		emesh.radius = 0.07
		emesh.height = 0.14
		ember.mesh = emesh
		ember.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(1.0, 0.40, 0.0, 1.0)
		emat.emission_enabled = true
		emat.emission = Color(1.0, 0.2, 0.0)
		emat.emission_energy_multiplier = 2.8
		emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ember.material_override = emat
		_scene_root.add_child(ember)
		ember.global_position = world_pos

		var angle: float = (float(i) / 8.0) * TAU + randf_range(-0.3, 0.3)
		var radius: float = randf_range(0.7, 1.5)
		var target_pos := world_pos + Vector3(cos(angle) * radius, randf_range(0.2, 1.0), sin(angle) * radius)

		var etw := ember.create_tween().set_parallel(true)
		etw.tween_property(ember, "global_position", target_pos, 0.35).set_ease(Tween.EASE_OUT)
		etw.tween_property(ember, "modulate:a", 0.0, 0.40).set_delay(0.10)
		etw.chain().tween_callback(ember.queue_free)

	# Orange light flash
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.50, 0.1)
	flash.light_energy = 5.5
	flash.omni_range = 4.5
	flash.shadow_enabled = false
	_scene_root.add_child(flash)
	flash.global_position = world_pos
	var ftw := flash.create_tween()
	ftw.tween_property(flash, "light_energy", 0.0, 0.38)
	ftw.tween_callback(flash.queue_free)


## Three throwing knives fly from `from_pos` to `to_pos` in quick succession.
## `on_land` fires after the last knife arrives.
func _fx_throwing_knives(from_pos: Vector3, to_pos: Vector3, on_land: Callable = Callable()) -> void:
	if _scene_root == null:
		if on_land.is_valid():
			on_land.call()
		return

	var travel_time := 0.18
	var knife_count := 3
	var offsets: Array = [
		Vector3(-0.14, 0.06, 0.0),
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.14, 0.06, 0.0),
	]

	var dir := (to_pos - from_pos).normalized()

	for ki in knife_count:
		var delay: float = ki * 0.09
		var off: Vector3 = offsets[ki]
		var knife_from := from_pos + off
		var knife_to := to_pos + off * 0.25  # converge slightly on impact

		var knife := MeshInstance3D.new()
		var kmesh := BoxMesh.new()
		kmesh.size = Vector3(0.05, 0.05, 0.28)
		knife.mesh = kmesh
		knife.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var kmat := StandardMaterial3D.new()
		kmat.albedo_color = Color(0.80, 0.85, 0.95)
		kmat.metallic = 0.92
		kmat.roughness = 0.12
		kmat.emission_enabled = true
		kmat.emission = Color(0.45, 0.50, 1.0)
		kmat.emission_energy_multiplier = 0.75
		kmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		knife.material_override = kmat
		_scene_root.add_child(knife)
		knife.global_position = knife_from

		# Orient knife along direction of travel
		if dir.length_squared() > 0.01:
			knife.look_at(knife_from + dir)

		var tw := knife.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(knife, "global_position", knife_to, travel_time) \
			.set_trans(Tween.TRANS_LINEAR)
		tw.tween_callback(func() -> void:
			if is_instance_valid(knife):
				knife.queue_free()
		)

		# Fallback: guarantee knife is freed even if tween is interrupted
		var knife_timeout := delay + travel_time + 0.4
		get_tree().create_timer(knife_timeout).timeout.connect(func() -> void:
			if is_instance_valid(knife):
				knife.queue_free()
		)

	# Fire on_land after the last knife arrives (SceneTree timer survives node cleanup)
	var last_land := (knife_count - 1) * 0.09 + travel_time + 0.02
	if on_land.is_valid():
		get_tree().create_timer(last_land).timeout.connect(on_land)


## Shader-based slash sweep — billboarded quad at impact point.
## Layered on top of the sprite-based _fx_impact for melee/arrow hits.
func _fx_slash_sweep(world_pos: Vector3, tint: Color) -> void:
	if _scene_root == null or _slash_shader == null:
		return

	var quad := MeshInstance3D.new()
	var qmesh := QuadMesh.new()
	qmesh.size = Vector2(1.3, 1.3)
	quad.mesh = qmesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var smat := ShaderMaterial.new()
	smat.shader = _slash_shader
	if not _FX_SLASH.is_empty() and ResourceLoader.exists(_FX_SLASH[0]):
		smat.set_shader_parameter("mask_texture", load(_FX_SLASH[0]))
	smat.set_shader_parameter("color", tint * 1.2)
	smat.set_shader_parameter("intensity", 1.8)
	smat.set_shader_parameter("speed", 3.2)
	smat.set_shader_parameter("threshold", 0.28)
	smat.set_shader_parameter("fade", 1.0)
	quad.material_override = smat
	_scene_root.add_child(quad)
	quad.global_position = world_pos
	quad.scale = Vector3.ZERO

	var tw := quad.create_tween().set_parallel(true)
	tw.tween_property(quad, "scale", Vector3.ONE * 1.4, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(quad):
			smat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.22).set_delay(0.06)
	tw.chain().tween_callback(quad.queue_free)
