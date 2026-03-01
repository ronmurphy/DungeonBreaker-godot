extends Node
## Enemy database — loads entity definitions from entities.json.
##
## Provides enemy stat lookups, floor scaling, and variant generation.
## Autoloaded as "EnemyDB".

# ── Loaded data ──────────────────────────────────────────────────────────────
var _monsters: Dictionary = {}   # key → full dict from JSON
var _friendly: Dictionary = {}   # friendly NPCs
var _bosses: Array = []          # list of boss keys (tier 4+)

# ── Floor scaling constants ───────────────────────────────────────────────────
# Applied AFTER normalisation, so values are smaller.
const FLOOR_HP_BONUS     := 2    # +2 HP per floor
const FLOOR_AC_BONUS     := 0.4  # +0.4 defense per floor
const FLOOR_STR_BONUS    := 0.3  # +0.3 attack per floor

# ── Variant chances ──────────────────────────────────────────────────────────
const GHOST_CHANCE := 0.15  # 15% ghost variant
const ELITE_CHANCE := 0.10  # 10% elite variant

# ── Sprite base path ─────────────────────────────────────────────────────────
const ENTITY_ART_PATH := "res://assets/art/entities/"


func _ready():
	_load_database()


func _load_database():
	var path := ENTITY_ART_PATH + "entities.json"
	if not FileAccess.file_exists(path):
		push_warning("EnemyDB: entities.json not found at %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()

	if err != OK:
		push_error("EnemyDB: Failed to parse entities.json — %s" % json.get_error_message())
		return

	var data: Dictionary = json.data
	if data.has("monsters"):
		_monsters = data["monsters"]

	# Identify bosses (tier 4+)
	for key in _monsters:
		var m: Dictionary = _monsters[key]
		if m.get("tier", 1) >= 4:
			_bosses.append(key)
		if m.get("type", "enemy") == "friendly":
			_friendly[key] = m


## Get raw stats dict for an enemy by key (e.g. "goblin_grunt").
func get_enemy(key: String) -> Dictionary:
	return _monsters.get(key, {})


## Get a list of all enemy keys.
func get_all_enemy_keys() -> Array:
	var keys: Array = []
	for key in _monsters:
		if _monsters[key].get("type", "enemy") == "enemy":
			keys.append(key)
	return keys


## Get enemies appropriate for a floor (tier filtering).
## Floor 1–2: tier 1, Floor 3–4: tier 1–2, Floor 5–6: tier 1–3, Floor 7+: all.
func get_enemies_for_floor(floor_num: int) -> Array:
	var max_tier: int
	if floor_num <= 2:
		max_tier = 1
	elif floor_num <= 4:
		max_tier = 2
	elif floor_num <= 6:
		max_tier = 3
	else:
		max_tier = 5

	var result: Array = []
	for key in _monsters:
		var m: Dictionary = _monsters[key]
		if m.get("type", "enemy") != "enemy":
			continue
		if m.get("tier", 1) <= max_tier:
			result.append(key)
	return result


## Scale an enemy's stats for a given floor. Returns a new dict.
## The source entities.json uses a different RPG system with much higher
## HP / defense numbers, so we normalise first then apply per-floor bonuses.
func get_scaled_enemy(key: String, floor_num: int) -> Dictionary:
	var base := get_enemy(key)
	if base.is_empty():
		return {}

	var scaled := base.duplicate(true)

	# ── Normalise from source-game scale ──
	# HP:  source 45–200+ → our 8–30  (0.15x + 2, min 8)
	# DEF: source 20–30   → our 5–10  (0.35x, min 4)
	# ATK: already in a reasonable 3–12 range, keep as-is (min 3)
	var norm_hp  := maxi(8, int(base.get("hp", 20) * 0.15 + 2))
	var norm_def := maxi(4, int(base.get("defense", 10) * 0.35))
	var norm_atk := maxi(3, int(base.get("attack", 5)))

	# ── Floor scaling on top of normalised stats ──
	var floor_bonus := maxi(0, floor_num - 1)
	scaled["hp"]      = norm_hp  + floor_bonus * FLOOR_HP_BONUS
	scaled["defense"] = norm_def + int(floor_bonus * FLOOR_AC_BONUS)
	scaled["attack"]  = norm_atk + int(floor_bonus * FLOOR_STR_BONUS)
	scaled["floor"]   = floor_num

	return scaled


## Roll a variant (ghost / elite / normal). Returns modified stat dict.
func apply_variant(stats: Dictionary) -> Dictionary:
	var roll := randf()

	if roll < GHOST_CHANCE:
		# Ghost: 60% HP, -1 AC, translucent
		stats["hp"] = int(stats.get("hp", 20) * 0.6)
		stats["defense"] = maxi(0, stats.get("defense", 10) - 1)
		stats["variant"] = "ghost"
	elif roll < GHOST_CHANCE + ELITE_CHANCE:
		# Elite: 1.5x all stats, red glow
		stats["hp"] = int(stats.get("hp", 20) * 1.5)
		stats["defense"] = int(stats.get("defense", 10) * 1.5)
		stats["attack"] = int(stats.get("attack", 3) * 1.5)
		stats["variant"] = "elite"
	else:
		stats["variant"] = "normal"

	return stats


## Get the ready-pose texture path for an entity key.
func get_ready_texture_path(key: String) -> String:
	var m := get_enemy(key)
	var rdy: Variant = m.get("sprite_ready", null)
	if rdy != null and rdy is String and (rdy as String) != "":
		return ENTITY_ART_PATH + (rdy as String)
	return ENTITY_ART_PATH + key + "_ready_pose_enhanced.png"


## Get the attack-pose texture path for an entity key.
func get_attack_texture_path(key: String) -> String:
	var m := get_enemy(key)
	var atk: Variant = m.get("sprite_attack", null)
	if atk != null and atk is String and (atk as String) != "":
		return ENTITY_ART_PATH + (atk as String)
	return ENTITY_ART_PATH + key + "_attack_pose_enhanced.png"


## Get the portrait texture path for an entity key (used in combat UI cards).
func get_portrait_path(key: String) -> String:
	var m := get_enemy(key)
	if m.has("sprite_portrait") and m["sprite_portrait"] != null:
		return ENTITY_ART_PATH + m["sprite_portrait"]
	return ""


## Get a random boss key.
func get_random_boss() -> String:
	if _bosses.is_empty():
		return ""
	return _bosses[randi() % _bosses.size()]


## Get all boss keys.
func get_boss_keys() -> Array:
	return _bosses.duplicate()
