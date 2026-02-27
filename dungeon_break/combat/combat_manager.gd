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

signal combat_ended(victory: bool)
signal combat_started()
signal turn_order_changed(order: Array)
signal unit_turn_started(unit: Dictionary)
signal move_phase_started(unit: Dictionary, tiles: Array)
signal act_phase_started(unit: Dictionary)
signal action_resolved(log_text: String)
signal unit_defeated(unit: Dictionary)
signal unit_moved(unit: Dictionary, from: Vector2i, to: Vector2i)


# ── Constants ────────────────────────────────────────────────────────────────
const PLAYER_MOVE_RANGE := 4    # tiles per turn
const PLAYER_ATTACK_RANGE := 1  # melee = 1 tile (Manhattan)
const ENEMY_MOVE_RANGE := 3
const ENEMY_ATTACK_RANGE := 1

# ── Combat phases ────────────────────────────────────────────────────────────
enum Phase { IDLE, MOVE, ACT, RESOLVING, ENEMY_THINKING, ENDED }

var phase: int = Phase.IDLE

# ── Grid ─────────────────────────────────────────────────────────────────────
var tactical_grid: Node3D = null   # TacticalGrid instance

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

# Currently highlighted move tiles (player)
var _move_tiles: Array[Vector2i] = []
var _attack_tiles: Array[Vector2i] = []

# Scene parent for adding the tactical grid Node3D
var _scene_root: Node3D = null


## Start tactical combat in a room.
func start_combat(enemies: Array, room: Dictionary, scene_root: Node3D):
	_room = room
	_scene_root = scene_root
	_units.clear()
	_turn_order.clear()
	_round = 0
	phase = Phase.IDLE

	# Create tactical grid
	tactical_grid = TacticalGridScript.new()
	tactical_grid.name = "TacticalGrid"
	scene_root.add_child(tactical_grid)

	# Get dungeon offset from room meta if available
	var ox: int = room.get("_offset_x", 0)
	var oz: int = room.get("_offset_z", 0)

	tactical_grid.setup_room(room, ox, oz, 0)

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

	print("TacticalCombat: started with %d enemies in room %d" % [enemies.size(), room["id"]])
	combat_started.emit()

	# Start first round
	_start_round()


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
		"wait":
			action_resolved.emit("%s waits." % unit["name"])
		"flee":
			_do_flee()

	unit["has_acted"] = true

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

	# Simple AI: move toward nearest player, attack if adjacent
	var player_pos: Vector2i = _units[0]["grid_pos"]
	var dist_to_player: int = absi(unit["grid_pos"].x - player_pos.x) + absi(unit["grid_pos"].y - player_pos.y)

	# Flash the enemy to show it's their turn
	_flash_unit(unit)

	await get_tree().create_timer(0.3).timeout

	if dist_to_player > unit["attack_range"]:
		# Move toward player
		var path: Array[Vector2i] = tactical_grid.find_path(unit["grid_pos"], player_pos)
		if not path.is_empty():
			# Move up to move_range steps along path
			var steps := mini(unit["move_range"], path.size() - 1)  # don't step ON player
			if steps > 0:
				var target_pos: Vector2i = path[steps - 1]
				# Make sure we don't step on another unit
				var occupied := _get_occupied_positions(unit_idx)
				while steps > 0 and target_pos in occupied:
					steps -= 1
					if steps > 0:
						target_pos = path[steps - 1]
				if steps > 0:
					_move_unit(unit_idx, target_pos)
					await get_tree().create_timer(0.2).timeout

	# Re-check distance after moving
	dist_to_player = absi(unit["grid_pos"].x - player_pos.x) + absi(unit["grid_pos"].y - player_pos.y)

	if dist_to_player <= unit["attack_range"]:
		# Attack player
		_do_enemy_attack(unit_idx, 0)
		await get_tree().create_timer(0.4).timeout
	else:
		action_resolved.emit("%s watches warily." % unit["name"])

	_advance_turn()


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

	# Clash roll
	var player_roll: int = GameData.clash_roll(attacker["attack"])
	var enemy_roll: int = _clash_roll(target["defense"])

	if player_roll > enemy_roll:
		var dmg := maxi(1, player_roll - enemy_roll)
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


func _do_enemy_attack(attacker_idx: int, target_idx: int):
	var attacker: Dictionary = _units[attacker_idx]
	var target: Dictionary = _units[target_idx]

	var enemy_roll: int = _clash_roll(attacker["attack"])
	var player_roll: int = _clash_roll(target["defense"] + GameData.ac_bonus_temp)

	if GameData.counter_active and player_roll >= enemy_roll:
		# Counter-attack!
		var counter_dmg := maxi(1, player_roll - enemy_roll)
		_apply_damage(attacker_idx, counter_dmg)
		action_resolved.emit("[color=yellow]Counter![/color] %s's attack reflected for [color=red]%d damage![/color]" % [
			attacker["name"], counter_dmg])
	elif enemy_roll > player_roll:
		var dmg := maxi(1, enemy_roll - player_roll)
		_apply_damage(target_idx, dmg)
		action_resolved.emit("[color=orange]%s[/color] strikes! [color=white]%d vs %d[/color] → [color=red]%d damage![/color]" % [
			attacker["name"], enemy_roll, player_roll, dmg])
	else:
		action_resolved.emit("[color=gray]%s attacks but misses! [color=white]%d vs %d[/color][/color]" % [
			attacker["name"], enemy_roll, player_roll])


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
	else:
		GameData.guts += 1
		GameData.ac_bonus_temp = 2
		action_resolved.emit("%s charges guts! (%d/%d) (+2 AC)" % [unit["name"], GameData.guts, GameData.guts_max])


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
	if unit["type"] == "enemy" and is_instance_valid(unit["entity"]):
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

func _apply_damage(unit_idx: int, damage: int):
	var unit: Dictionary = _units[unit_idx]
	unit["hp"] = maxi(0, unit["hp"] - damage)

	if unit["type"] == "player":
		GameData.take_raw_damage(damage)
		unit["hp"] = GameData.hp
	else:
		# Update entity meta
		if is_instance_valid(unit["entity"]):
			unit["entity"].set_meta("hp", unit["hp"])
			# Flash red
			var sprite: Sprite3D = unit["entity"].get_meta("sprite", null)
			if sprite:
				sprite.modulate = Color.RED
				get_tree().create_timer(0.15).timeout.connect(func():
					if is_instance_valid(sprite):
						sprite.modulate = Color.WHITE
				)

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
		else:
			tactical_grid.highlight_enemy(unit["grid_pos"])


func _compute_attack_targets(unit_idx: int):
	var unit: Dictionary = _units[unit_idx]
	_attack_tiles.clear()

	var a_range: int = unit["attack_range"]
	for dx in range(-a_range, a_range + 1):
		for dz in range(-a_range, a_range + 1):
			if absi(dx) + absi(dz) > a_range:
				continue
			if dx == 0 and dz == 0:
				continue
			var pos: Vector2i = unit["grid_pos"] + Vector2i(dx, dz)
			_attack_tiles.append(pos)

	tactical_grid.highlight_attack(_attack_tiles)


func _flash_unit(unit: Dictionary):
	if unit["type"] != "enemy" or not is_instance_valid(unit["entity"]):
		return
	var sprite: Sprite3D = unit["entity"].get_meta("sprite", null)
	if sprite:
		sprite.modulate = Color(1.0, 1.0, 0.3)
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


func _clash_roll(power: int) -> int:
	var dice: Array[int] = [20, 12, 10, 8, 6, 4]
	for die_size in dice:
		if power >= die_size:
			var bonus: int = power - die_size
			return randi_range(1, die_size) + bonus
	return randi_range(1, 4)


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
