extends Node
## Cross-Class Forge System — Skyshards, floor class tracking, forge & reforge.
##
## Autoloaded as "ForgeSystem".
## Design doc: assets/help/cross-class.md

# ── Signals ──────────────────────────────────────────────────────────────────
signal skyshard_earned(class_id: int, skyshard_id: String)
signal floor_tracking_invalidated(floor_num: int)
signal item_forged(item_id: String)
signal item_reforged(item_id: String)
signal forge_skill_changed()

# ── Class → Skyshard Mapping ─────────────────────────────────────────────────
## Maps PlayerClass enum → skyshard item id.
const CLASS_SKYSHARD_MAP := {
	GameData.PlayerClass.VANGUARD:   "vanguard_skyshard",
	GameData.PlayerClass.SCOUNDREL:  "scoundrel_skyshard",
	GameData.PlayerClass.ARCANIST:   "arcanist_skyshard",
	GameData.PlayerClass.CONFESSOR:  "confessor_skyshard",
	GameData.PlayerClass.STRIDER:    "strider_skyshard",
	GameData.PlayerClass.MINSTREL:   "minstrel_skyshard",
	GameData.PlayerClass.TEMPLAR:    "templar_skyshard",
	GameData.PlayerClass.REANIMATOR: "reanimator_skyshard",
	GameData.PlayerClass.TINKERER:   "tinkerer_skyshard",
}

## Maps PlayerClass enum → forged weapon item id.
const CLASS_FORGE_WEAPON_MAP := {
	GameData.PlayerClass.VANGUARD:   "vanguard_forged_sword",
	GameData.PlayerClass.SCOUNDREL:  "scoundrel_forged_daggers",
	GameData.PlayerClass.ARCANIST:   "arcanist_forged_staff",
	GameData.PlayerClass.CONFESSOR:  "confessor_forged_mace",
	GameData.PlayerClass.STRIDER:    "strider_forged_bow",
	GameData.PlayerClass.MINSTREL:   "minstrel_forged_rapier",
	GameData.PlayerClass.TEMPLAR:    "templar_forged_blade",
	GameData.PlayerClass.REANIMATOR: "reanimator_forged_sceptre",
	GameData.PlayerClass.TINKERER:   "tinkerer_forged_crossbow",
}

## Maps PlayerClass enum → forged armor item id.
const CLASS_FORGE_ARMOR_MAP := {
	GameData.PlayerClass.VANGUARD:   "vanguard_forged_plate",
	GameData.PlayerClass.SCOUNDREL:  "scoundrel_forged_leathers",
	GameData.PlayerClass.ARCANIST:   "arcanist_forged_robes",
	GameData.PlayerClass.CONFESSOR:  "confessor_forged_vestments",
	GameData.PlayerClass.STRIDER:    "strider_forged_chainmail",
	GameData.PlayerClass.MINSTREL:   "minstrel_forged_mantle",
	GameData.PlayerClass.TEMPLAR:    "templar_forged_cuirass",
	GameData.PlayerClass.REANIMATOR: "reanimator_forged_shroud",
	GameData.PlayerClass.TINKERER:   "tinkerer_forged_harness",
}

## Class tint colors for skyshard icons and forge VFX.
const CLASS_COLORS := {
	GameData.PlayerClass.VANGUARD:   Color("#cc3333"),
	GameData.PlayerClass.SCOUNDREL:  Color("#9933cc"),
	GameData.PlayerClass.ARCANIST:   Color("#3366cc"),
	GameData.PlayerClass.CONFESSOR:  Color("#ccaa33"),
	GameData.PlayerClass.STRIDER:    Color("#33aa55"),
	GameData.PlayerClass.MINSTREL:   Color("#cc66aa"),
	GameData.PlayerClass.TEMPLAR:    Color("#dddddd"),
	GameData.PlayerClass.REANIMATOR: Color("#336633"),
	GameData.PlayerClass.TINKERER:   Color("#cc7733"),
}

## Maps PlayerClass enum → the skill action string from JOB_SPECIAL_SKILL.
const CLASS_SKILL_ACTION := {
	GameData.PlayerClass.VANGUARD:   "skill_shield_wall",
	GameData.PlayerClass.SCOUNDREL:  "skill_shadowstep",
	GameData.PlayerClass.ARCANIST:   "skill_arcane_blast",
	GameData.PlayerClass.CONFESSOR:  "skill_bless",
	GameData.PlayerClass.STRIDER:    "skill_steady_shot",
	GameData.PlayerClass.MINSTREL:   "skill_war_song",
	GameData.PlayerClass.TEMPLAR:    "skill_holy_smite",
	GameData.PlayerClass.REANIMATOR: "skill_soul_drain",
	GameData.PlayerClass.TINKERER:   "skill_shock_mine",
}

# ── Costs ────────────────────────────────────────────────────────────────────
const FORGE_COST := 100       ## Gold to forge a base weapon or armor.
const REFORGE_COST := 150     ## Gold to merge two forged items.
const SKILL_RESPEC_COST := 50 ## Gold to re-pick skill slots.
const MAX_FORGE_SKILLS := 3   ## Maximum forge skill slots.

# ── Persistent State ─────────────────────────────────────────────────────────
## Floor-level class tracking for skyshard eligibility.
## Key = floor number (int), value = Dictionary:
##   "class": int (PlayerClass enum value — set on first room entry)
##   "rooms_cleared": int (count of rooms cleared as the tracked class)
##   "valid": bool (false if any room was cleared as a different class)
var floor_class_tracking: Dictionary = {}

## Set of class enum values for which the player has already earned a skyshard.
## Prevents duplicate skyshards.
var earned_skyshards: Array[int] = []

## Active forge skill action strings (up to MAX_FORGE_SKILLS).
## These are the skill actions from forged items that the player has slotted.
var forge_skill_slots: Array[String] = []


# ══════════════════════════════════════════════════════════════════════════════
# FLOOR CLASS TRACKING
# ══════════════════════════════════════════════════════════════════════════════

## Called when the player enters a room on the given floor.
## Records the player's current class for this floor on first call.
func track_room_entry(floor_num: int) -> void:
	if not floor_class_tracking.has(floor_num):
		floor_class_tracking[floor_num] = {
			"class": int(GameData.player_class),
			"rooms_cleared": 0,
			"valid": true,
		}


## Called when the player clears a room on the given floor.
## Checks class consistency and increments room count.
func track_room_clear(floor_num: int) -> void:
	if not floor_class_tracking.has(floor_num):
		# Room cleared without prior entry tracking — record now.
		track_room_entry(floor_num)

	var track: Dictionary = floor_class_tracking[floor_num]
	if int(GameData.player_class) != int(track["class"]):
		track["valid"] = false
		floor_tracking_invalidated.emit(floor_num)
	track["rooms_cleared"] += 1


## Returns true if the floor has valid class tracking (all rooms same class)
## AND the class hasn't already earned a skyshard.
func is_floor_skyshard_eligible(floor_num: int) -> bool:
	if not floor_class_tracking.has(floor_num):
		return false
	var track: Dictionary = floor_class_tracking[floor_num]
	if not bool(track.get("valid", false)):
		return false
	var cls: int = int(track["class"])
	if cls in earned_skyshards:
		return false
	return true


## Wipe all tracking for a floor (player pressed B to reset).
func reset_floor_tracking(floor_num: int) -> void:
	floor_class_tracking.erase(floor_num)


## Returns the tracked class for a floor, or -1 if untracked.
func get_floor_class(floor_num: int) -> int:
	if not floor_class_tracking.has(floor_num):
		return -1
	return int(floor_class_tracking[floor_num]["class"])


## Returns true if the floor tracking is still valid (no class mismatches).
func is_floor_valid(floor_num: int) -> bool:
	if not floor_class_tracking.has(floor_num):
		return true  # no tracking yet = still valid (nothing to invalidate)
	return bool(floor_class_tracking[floor_num].get("valid", true))


# ══════════════════════════════════════════════════════════════════════════════
# SKYSHARD AWARD
# ══════════════════════════════════════════════════════════════════════════════

## Called on boss kill. Awards a skyshard if the floor is eligible.
## Returns the skyshard item id if awarded, or "" if not.
func try_award_skyshard(floor_num: int) -> String:
	if not is_floor_skyshard_eligible(floor_num):
		return ""

	var track: Dictionary = floor_class_tracking[floor_num]
	var cls: int = int(track["class"])
	var shard_id: String = CLASS_SKYSHARD_MAP.get(cls, "")
	if shard_id == "":
		return ""

	# Award!
	earned_skyshards.append(cls)
	var item: Dictionary = ItemDB.create_item(shard_id)
	if not item.is_empty():
		ItemDB.add_to_backpack(item)
	skyshard_earned.emit(cls, shard_id)
	return shard_id


## Check if the player has a specific class skyshard in their backpack.
func has_skyshard_in_backpack(class_id: int) -> bool:
	var shard_id: String = CLASS_SKYSHARD_MAP.get(class_id, "")
	if shard_id == "":
		return false
	for item in GameData.backpack:
		if item.get("id", "") == shard_id:
			return true
	return false


## Remove a skyshard from the backpack (consumed during forging).
## Returns true if removed.
func consume_skyshard(class_id: int) -> bool:
	var shard_id: String = CLASS_SKYSHARD_MAP.get(class_id, "")
	if shard_id == "":
		return false
	for i in GameData.backpack.size():
		if GameData.backpack[i].get("id", "") == shard_id:
			ItemDB.remove_from_backpack(i)
			return true
	return false


# ══════════════════════════════════════════════════════════════════════════════
# FORGE — Create class weapon or armor from a skyshard
# ══════════════════════════════════════════════════════════════════════════════

## Forge a class weapon from a skyshard. Returns the forged item dict, or {}.
## Deducts gold, consumes skyshard, adds item to backpack.
func forge_weapon(class_id: int) -> Dictionary:
	return _do_forge(class_id, CLASS_FORGE_WEAPON_MAP)


## Forge class armor from a skyshard. Returns the forged item dict, or {}.
func forge_armor(class_id: int) -> Dictionary:
	return _do_forge(class_id, CLASS_FORGE_ARMOR_MAP)


func _do_forge(class_id: int, item_map: Dictionary) -> Dictionary:
	if not has_skyshard_in_backpack(class_id):
		return {}
	if GameData.gold < FORGE_COST:
		return {}
	var item_id: String = item_map.get(class_id, "")
	if item_id == "":
		return {}

	# Deduct cost
	GameData.add_gold(-FORGE_COST)
	consume_skyshard(class_id)

	# Create the forged item
	var item: Dictionary = ItemDB.create_item(item_id)
	if item.is_empty():
		push_warning("ForgeSystem: unknown forge item '%s'" % item_id)
		return {}

	ItemDB.add_to_backpack(item)
	item_forged.emit(item_id)
	return item


## Returns a list of class IDs for which the player has a skyshard in backpack
## and thus can forge. Used by the forge UI.
func get_available_forges() -> Array[int]:
	var result: Array[int] = []
	for cls: int in CLASS_SKYSHARD_MAP.keys():
		if has_skyshard_in_backpack(cls):
			result.append(cls)
	return result


# ══════════════════════════════════════════════════════════════════════════════
# REFORGE — Merge two forged items into one with combined skills
# ══════════════════════════════════════════════════════════════════════════════

## Attempt to reforge (merge) two forged items from the backpack.
## idx_a, idx_b are backpack indices. Both items must be forged and same type class
## (both weapons or both armor). Returns the merged item dict, or {}.
func reforge(idx_a: int, idx_b: int) -> Dictionary:
	if idx_a == idx_b:
		return {}
	if idx_a < 0 or idx_a >= GameData.backpack.size():
		return {}
	if idx_b < 0 or idx_b >= GameData.backpack.size():
		return {}
	if GameData.gold < REFORGE_COST:
		return {}

	var item_a: Dictionary = GameData.backpack[idx_a]
	var item_b: Dictionary = GameData.backpack[idx_b]

	# Both must be forged items (have forged_from field)
	if not item_a.has("forged_from") or not item_b.has("forged_from"):
		return {}

	# Both must be same broad type (weapon or armor/chest)
	var type_a: int = ItemDB.resolve_item_type(item_a)
	var type_b: int = ItemDB.resolve_item_type(item_b)
	if type_a != type_b:
		return {}

	# Check skill cap — combined skills can't exceed MAX_FORGE_SKILLS
	var skills_a: Array = item_a.get("forged_from", [])
	var skills_b: Array = item_b.get("forged_from", [])
	var combined_origins: Array = skills_a.duplicate()
	for origin in skills_b:
		if origin not in combined_origins:
			combined_origins.append(origin)
	if combined_origins.size() > MAX_FORGE_SKILLS:
		return {}

	# Deduct gold
	GameData.add_gold(-REFORGE_COST)

	# Build merged item
	var merged: Dictionary = item_a.duplicate(true)
	merged["forged_from"] = combined_origins

	# Combine stats — take max of each stat bonus, then apply -1 penalty to random stat
	var stat_keys: Array[String] = ["stat_str", "stat_dex", "stat_int", "stat_lck"]
	for sk in stat_keys:
		var va: int = int(item_a.get(sk, 0))
		var vb: int = int(item_b.get(sk, 0))
		merged[sk] = maxi(va, vb)

	# Apply -1 merge penalty to a random non-zero stat
	var nonzero_stats: Array[String] = []
	for sk2 in stat_keys:
		if int(merged.get(sk2, 0)) > 0:
			nonzero_stats.append(sk2)
	if not nonzero_stats.is_empty():
		var penalty_stat: String = nonzero_stats[randi() % nonzero_stats.size()]
		merged[penalty_stat] = maxi(0, int(merged[penalty_stat]) - 1)

	# Combine combat stats (attack_bonus / ac_bonus)
	merged["attack_bonus"] = maxi(int(item_a.get("attack_bonus", 0)), int(item_b.get("attack_bonus", 0)))
	merged["ac_bonus"] = maxi(int(item_a.get("ac_bonus", 0)), int(item_b.get("ac_bonus", 0)))

	# Build combined skill list
	var combined_skills: Array[String] = []
	for origin2 in combined_origins:
		var cls_int: int = _class_name_to_id(origin2)
		if cls_int >= 0:
			var action: String = CLASS_SKILL_ACTION.get(cls_int, "")
			if action != "" and action not in combined_skills:
				combined_skills.append(action)
	merged["grants_skills"] = combined_skills

	# Update name and description
	var merge_count: int = int(merged.get("forge_penalty", 0)) + 1
	merged["forge_penalty"] = merge_count
	if combined_origins.size() == 2:
		merged["name"] = "Forged %s" % ("Blade" if type_a == ItemDB.ItemType.WEAPON else "Armor")
	elif combined_origins.size() >= 3:
		merged["name"] = "Master %s" % ("Blade" if type_a == ItemDB.ItemType.WEAPON else "Armor")

	# Build description
	var skill_names: Array[String] = []
	for sk_action in combined_skills:
		var sk_name: String = _skill_action_to_name(sk_action)
		if sk_name != "":
			skill_names.append(sk_name)
	merged["description"] = "Reforged %dx. Grants: %s." % [merge_count, ", ".join(skill_names)]

	# Remove both source items (remove higher index first to avoid shifting)
	var hi: int = maxi(idx_a, idx_b)
	var lo: int = mini(idx_a, idx_b)
	ItemDB.remove_from_backpack(hi)
	ItemDB.remove_from_backpack(lo)

	# Add merged item
	ItemDB.add_to_backpack(merged)
	item_reforged.emit(merged.get("id", "reforged"))
	return merged


## Preview what a reforge would produce (no side effects).
func preview_reforge(idx_a: int, idx_b: int) -> Dictionary:
	# Quick validation
	if idx_a == idx_b or idx_a < 0 or idx_b < 0:
		return {}
	if idx_a >= GameData.backpack.size() or idx_b >= GameData.backpack.size():
		return {}
	var item_a: Dictionary = GameData.backpack[idx_a]
	var item_b: Dictionary = GameData.backpack[idx_b]
	if not item_a.has("forged_from") or not item_b.has("forged_from"):
		return {}
	var type_a: int = ItemDB.resolve_item_type(item_a)
	var type_b: int = ItemDB.resolve_item_type(item_b)
	if type_a != type_b:
		return {}
	var skills_a: Array = item_a.get("forged_from", [])
	var skills_b: Array = item_b.get("forged_from", [])
	var combined: Array = skills_a.duplicate()
	for o in skills_b:
		if o not in combined:
			combined.append(o)
	if combined.size() > MAX_FORGE_SKILLS:
		return {}

	return {
		"combined_origins": combined,
		"skill_count": combined.size(),
		"merge_penalty": int(item_a.get("forge_penalty", 0)) + 1,
		"cost": REFORGE_COST,
	}


# ══════════════════════════════════════════════════════════════════════════════
# FORGE SKILL SLOTS
# ══════════════════════════════════════════════════════════════════════════════

## Slot a forge skill action into the player's active skill list.
## Returns true on success.
func slot_forge_skill(skill_action: String) -> bool:
	if skill_action in forge_skill_slots:
		return false  # already slotted
	if forge_skill_slots.size() >= MAX_FORGE_SKILLS:
		return false
	forge_skill_slots.append(skill_action)
	forge_skill_changed.emit()
	return true


## Remove a forge skill from the active slots.
func unslot_forge_skill(skill_action: String) -> bool:
	var idx: int = forge_skill_slots.find(skill_action)
	if idx < 0:
		return false
	forge_skill_slots.remove_at(idx)
	forge_skill_changed.emit()
	return true


## Replace a specific slot with a new skill action.
func replace_forge_skill(slot_index: int, new_action: String) -> bool:
	if slot_index < 0 or slot_index >= forge_skill_slots.size():
		return false
	forge_skill_slots[slot_index] = new_action
	forge_skill_changed.emit()
	return true


## Get all currently active forge skill actions (for combat).
func get_active_forge_skills() -> Array[String]:
	return forge_skill_slots.duplicate()


## Get all forge skills the player has access to (from forged items in backpack + equipped).
func get_all_available_forge_skills() -> Array[String]:
	var skills: Array[String] = []
	# Check backpack
	for item in GameData.backpack:
		_collect_item_skills(item, skills)
	# Check equipment slots
	for slot_name in ItemDB.EQUIP_SLOTS.values():
		var equipped: Dictionary = GameData.get(slot_name) as Dictionary
		if equipped is Dictionary and not equipped.is_empty():
			_collect_item_skills(equipped, skills)
	return skills


func _collect_item_skills(item: Dictionary, out: Array[String]) -> void:
	# Single skill (base forged item)
	var single: String = item.get("grants_skill", "")
	if single != "" and single not in out:
		out.append(single)
	# Multiple skills (reforged item)
	var multi: Array = item.get("grants_skills", [])
	for sk in multi:
		if sk is String and sk not in out:
			out.append(sk as String)


# ══════════════════════════════════════════════════════════════════════════════
# FLOOR RESET
# ══════════════════════════════════════════════════════════════════════════════

## Reset a dungeon floor — wipe cleared rooms, tracking, force re-gen.
## Rescued NPCs and earned skyshards are NOT affected.
func reset_floor(floor_num: int) -> void:
	var fkey: String = str(floor_num)
	# Wipe cleared rooms for this floor
	GameData.cleared_rooms.erase(fkey)
	GameData.floor_room_counts.erase(fkey)
	# Wipe class tracking
	reset_floor_tracking(floor_num)
	# Force dungeon re-generation on next entry
	GameData.dungeon_seed = 0


# ══════════════════════════════════════════════════════════════════════════════
# SAVE / LOAD
# ══════════════════════════════════════════════════════════════════════════════

## Serialize forge state for save file.
func to_save_dict() -> Dictionary:
	# Convert floor_class_tracking keys to strings for JSON compatibility
	var fct_save: Dictionary = {}
	for fkey in floor_class_tracking:
		fct_save[str(fkey)] = floor_class_tracking[fkey].duplicate(true)

	return {
		"floor_class_tracking": fct_save,
		"earned_skyshards": earned_skyshards.duplicate(),
		"forge_skill_slots": forge_skill_slots.duplicate(),
	}


## Deserialize forge state from save file.
func from_save_dict(data: Dictionary) -> void:
	# Restore floor class tracking (JSON stores keys as strings)
	var saved_fct: Dictionary = data.get("floor_class_tracking", {})
	floor_class_tracking = {}
	for fkey: String in saved_fct:
		var track: Dictionary = saved_fct[fkey] as Dictionary
		floor_class_tracking[int(fkey)] = {
			"class": int(track.get("class", 0)),
			"rooms_cleared": int(track.get("rooms_cleared", 0)),
			"valid": bool(track.get("valid", true)),
		}

	# Restore earned skyshards (JSON stores as floats)
	var saved_es: Array = data.get("earned_skyshards", [])
	earned_skyshards = []
	for v in saved_es:
		earned_skyshards.append(int(v))

	# Restore forge skill slots
	var saved_fss: Array = data.get("forge_skill_slots", [])
	forge_skill_slots = []
	for v2 in saved_fss:
		forge_skill_slots.append(str(v2))


## Clear all forge state (new game).
func reset_all() -> void:
	floor_class_tracking.clear()
	earned_skyshards.clear()
	forge_skill_slots.clear()


# ══════════════════════════════════════════════════════════════════════════════
# HELPERS
# ══════════════════════════════════════════════════════════════════════════════

## Convert a class name string (e.g. "VANGUARD") to PlayerClass enum int, or -1.
func _class_name_to_id(class_name_str: String) -> int:
	var upper: String = class_name_str.to_upper()
	for cls_id: int in GameData.CLASS_NAMES.keys():
		if GameData.CLASS_NAMES[cls_id].to_upper() == upper:
			return cls_id
	# Try matching JOB_SLUGS
	for cls_id2: int in GameData.JOB_SLUGS.keys():
		if GameData.JOB_SLUGS[cls_id2].to_upper() == upper:
			return cls_id2
	return -1


## Convert a skill action string to its display name.
func _skill_action_to_name(action: String) -> String:
	for cls_id: int in GameData.JOB_SPECIAL_SKILL.keys():
		var skill: Dictionary = GameData.JOB_SPECIAL_SKILL[cls_id]
		if skill.get("action", "") == action:
			return skill.get("name", action)
	return action


## Get the display name for a class enum value.
func get_class_name(class_id: int) -> String:
	return GameData.CLASS_NAMES.get(class_id, "Unknown")


## Get the class color for tinting.
func get_class_color(class_id: int) -> Color:
	return CLASS_COLORS.get(class_id, Color.WHITE)
