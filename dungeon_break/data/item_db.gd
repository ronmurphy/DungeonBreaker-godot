extends Node
## Item Database — weapons, armor, food, potions, and loot tables.
##
## All items use existing art assets in assets/art/tools/ and assets/art/food/.
## Autoloaded as "ItemDB".

# ── Item Types ───────────────────────────────────────────────────────────────
enum ItemType { WEAPON, HELM, CHEST, LEGS, BOOTS, FOOD, POTION, KEY, MISC }

const TYPE_NAMES := {
	ItemType.WEAPON: "Weapon",
	ItemType.HELM:   "Helm",
	ItemType.CHEST:  "Chest",
	ItemType.LEGS:   "Legs",
	ItemType.BOOTS:  "Boots",
	ItemType.FOOD:   "Food",
	ItemType.POTION: "Potion",
	ItemType.KEY:    "Key",
	ItemType.MISC:   "Misc",
}

# ── Item slot mapping ────────────────────────────────────────────────────────
const EQUIP_SLOTS := {
	ItemType.WEAPON: "equip_weapon",
	ItemType.HELM:   "equip_helm",
	ItemType.CHEST:  "equip_chest",
	ItemType.LEGS:   "equip_legs",
	ItemType.BOOTS:  "equip_boots",
}

# ══════════════════════════════════════════════════════════════════════════════
# ITEM DEFINITIONS
# ══════════════════════════════════════════════════════════════════════════════
# Each item: { id, name, type, icon, description, ... type-specific fields }
#
# Weapons: attack_bonus
# Armor:   ac_bonus
# Food:    heal_amount
# Potion:  effect (heal / buff)

const ITEMS := {
	# ── WEAPONS ──────────────────────────────────────────────────────────────
	"club": {
		"id": "club", "name": "Club", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/club.png",
		"description": "A sturdy wooden club.",
		"attack_bonus": 1, "value": 5,
	},
	"sword": {
		"id": "sword", "name": "Short Sword", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/sword.png",
		"description": "A simple short sword.",
		"attack_bonus": 2, "value": 15,
	},
	"blade": {
		"id": "blade", "name": "Steel Blade", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/blade.png",
		"description": "A sharp steel blade.",
		"attack_bonus": 3, "value": 30,
	},
	"knights_sword": {
		"id": "knights_sword", "name": "Knight's Sword", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/knights_sword.png",
		"description": "A finely crafted knight's sword.",
		"attack_bonus": 5, "value": 60,
	},
	"magic_knife": {
		"id": "magic_knife", "name": "Magic Knife", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/magic_knife.png",
		"description": "A dagger infused with arcane energy. Scales with INT.",
		"attack_bonus": 4, "value": 45,
	},
	"crossbow": {
		"id": "crossbow", "name": "Crossbow", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/crossbow.png",
		"description": "A mechanical crossbow. +2 attack range.",
		"attack_bonus": 3, "value": 40, "range_bonus": 2,
	},
	"morningstar": {
		"id": "morningstar", "name": "Morningstar", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/morningstar.png",
		"description": "A brutal spiked flail.",
		"attack_bonus": 6, "value": 80,
	},
	"fire_staff": {
		"id": "fire_staff", "name": "Fire Staff", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/fire_staff.png",
		"description": "A staff wreathed in flames. +3 attack range.",
		"attack_bonus": 4, "value": 70, "range_bonus": 3,
	},
	"ice_bow": {
		"id": "ice_bow", "name": "Ice Bow", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/ice_bow.png",
		"description": "A bow that fires frost arrows. +3 attack range.",
		"attack_bonus": 3, "value": 55, "range_bonus": 3,
	},
	"stone_spear": {
		"id": "stone_spear", "name": "Stone Spear", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/stone_spear.png",
		"description": "A crude spear. Better than nothing.",
		"attack_bonus": 1, "value": 3,
	},
	"boomerang": {
		"id": "boomerang", "name": "Boomerang", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/boomerang.png",
		"description": "A carved wooden boomerang. Hits from range. +2 attack range.",
		"attack_bonus": 2, "value": 12, "range_bonus": 2,
	},
	"axe": {
		"id": "axe", "name": "Battle Axe", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/axe.png",
		"description": "A heavy battle axe.",
		"attack_bonus": 4, "value": 35,
	},
	"throwing_knives": {
		"id": "throwing_knives", "name": "Throwing Knives", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/throwing_knives.png",
		"description": "Balanced blades that pierce through enemies in a line. +2 attack range.",
		"attack_bonus": 3, "value": 35, "range_bonus": 2, "pierce": true,
	},

	# ── ARMOR (HELM) ────────────────────────────────────────────────────────
	"helm_iron": {
		"id": "helm_iron", "name": "Iron Helm", "type": ItemType.HELM,
		"icon": "res://assets/art/tools/shield.png",
		"description": "A simple iron helmet.",
		"ac_bonus": 1, "value": 15,
	},
	"helm_knight": {
		"id": "helm_knight", "name": "Knight's Helm", "type": ItemType.HELM,
		"icon": "res://assets/art/tools/shield_crusader.png",
		"description": "A finely crafted helm.",
		"ac_bonus": 2, "value": 40,
	},

	# ── ARMOR (CHEST) ───────────────────────────────────────────────────────
	"chest_leather": {
		"id": "chest_leather", "name": "Leather Vest", "type": ItemType.CHEST,
		"icon": "res://assets/art/tools/fur.png",
		"description": "A simple leather vest.",
		"ac_bonus": 1, "value": 20,
	},
	"chest_chain": {
		"id": "chest_chain", "name": "Chainmail", "type": ItemType.CHEST,
		"icon": "res://assets/art/tools/iron.png",
		"description": "Links of iron chain protect the torso.",
		"ac_bonus": 3, "value": 50,
	},

	# ── ARMOR (BOOTS) ───────────────────────────────────────────────────────
	"boots_leather": {
		"id": "boots_leather", "name": "Leather Boots", "type": ItemType.BOOTS,
		"icon": "res://assets/art/tools/boots_speed.png",
		"description": "Light boots. +1 SPD.",
		"ac_bonus": 0, "value": 12, "spd_bonus": 1,
	},
	"boots_iron": {
		"id": "boots_iron", "name": "Iron Boots", "type": ItemType.BOOTS,
		"icon": "res://assets/art/tools/boots_speed.png",
		"description": "Heavy iron boots.",
		"ac_bonus": 1, "value": 25,
	},

	# ── ACCESSORIES ──────────────────────────────────────────────────────────
	"blood_pendant": {
		"id": "blood_pendant", "name": "Blood Pendant", "type": ItemType.MISC,
		"icon": "res://assets/art/tools/blood_pendant.png",
		"description": "Gain 1 HP per kill.",
		"value": 50, "on_kill_heal": 1,
	},
	"ancient_amulet": {
		"id": "ancient_amulet", "name": "Ancient Amulet", "type": ItemType.MISC,
		"icon": "res://assets/art/tools/ancientAmulet.png",
		"description": "+1 to all stats.",
		"value": 100, "all_stats_bonus": 1,
	},

	# ── FOOD ─────────────────────────────────────────────────────────────────
	"apple": {
		"id": "apple", "name": "Apple", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/apple.png",
		"description": "A fresh apple. Heals 3 HP.",
		"heal_amount": 3, "value": 2,
	},
	"bread": {
		"id": "bread", "name": "Bread", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/bread.png",
		"description": "A loaf of bread. Heals 5 HP.",
		"heal_amount": 5, "value": 4,
	},
	"mushroom": {
		"id": "mushroom", "name": "Mushroom", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/mushroom.png",
		"description": "A dungeon mushroom. Heals 2 HP.",
		"heal_amount": 2, "value": 1,
	},
	"berry": {
		"id": "berry", "name": "Wild Berry", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/berry.png",
		"description": "Sweet forest berries. Heals 2 HP.",
		"heal_amount": 2, "value": 1,
	},
	"grilled_fish": {
		"id": "grilled_fish", "name": "Grilled Fish", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/grilled_fish.png",
		"description": "Hearty grilled fish. Heals 8 HP.",
		"heal_amount": 8, "value": 8,
	},
	"mushroom_soup": {
		"id": "mushroom_soup", "name": "Mushroom Soup", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/mushroom_soup.png",
		"description": "Warm mushroom soup. Heals 10 HP.",
		"heal_amount": 10, "value": 10,
	},
	"super_stew": {
		"id": "super_stew", "name": "Super Stew", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/super_stew.png",
		"description": "A legendary stew! Heals 20 HP.",
		"heal_amount": 20, "value": 25,
	},
	"energy_bar": {
		"id": "energy_bar", "name": "Energy Bar", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/energy_bar.png",
		"description": "Quick energy. Heals 4 HP + 1 Guts.",
		"heal_amount": 4, "value": 6, "guts_bonus": 1,
	},
	"honey": {
		"id": "honey", "name": "Honey", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/honey.png",
		"description": "Pure honey. Heals 6 HP.",
		"heal_amount": 6, "value": 5,
	},
	"cookie": {
		"id": "cookie", "name": "Cookie", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/cookie.png",
		"description": "A tasty cookie. Heals 3 HP.",
		"heal_amount": 3, "value": 3,
	},

	# ── BUFF FOODS (attribute-boosting) ──────────────────────────────────────
	"baked_potato": {
		"id": "baked_potato", "name": "Baked Potato", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/baked_potato.png",
		"description": "Hearty spud. +1 STR for 3 combats.",
		"heal_amount": 3, "value": 8, "buff_stat": "str", "buff_amount": 1,
	},
	"pepper": {
		"id": "pepper", "name": "Fire Pepper", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/pepper.png",
		"description": "Burns going down! +1 DEX for 3 combats.",
		"heal_amount": 2, "value": 8, "buff_stat": "dex", "buff_amount": 1,
	},
	"fish_rice": {
		"id": "fish_rice", "name": "Fish & Rice", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/fish_rice.png",
		"description": "A balanced meal. +1 SPD for 3 combats.",
		"heal_amount": 6, "value": 12, "buff_stat": "spd", "buff_amount": 1,
	},
	"cooked_egg": {
		"id": "cooked_egg", "name": "Cooked Egg", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/cooked_egg.png",
		"description": "Brain food. +1 INT for 3 combats.",
		"heal_amount": 3, "value": 8, "buff_stat": "int", "buff_amount": 1,
	},
	"pumpkin_pie": {
		"id": "pumpkin_pie", "name": "Pumpkin Pie", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/pumpkin_pie.png",
		"description": "Decadent pie. Heals 12 HP, +2 AC for 3 combats.",
		"heal_amount": 12, "value": 18, "ac_bonus_temp": 2,
	},
	"honey_bread": {
		"id": "honey_bread", "name": "Honey Bread", "type": ItemType.FOOD,
		"icon": "res://assets/art/food/honey_bread.png",
		"description": "Sweet and filling. Heals 8 HP, +1 STR for 3 combats.",
		"heal_amount": 8, "value": 14, "buff_stat": "str", "buff_amount": 1,
	},

	# ── POTIONS ──────────────────────────────────────────────────────────────
	"potion_red": {
		"id": "potion_red", "name": "Health Potion", "type": ItemType.POTION,
		"icon": "res://assets/art/tools/potion_red.png",
		"description": "Restores 15 HP.",
		"heal_amount": 15, "value": 20,
	},
	"potion_blue": {
		"id": "potion_blue", "name": "Mana Tonic", "type": ItemType.POTION,
		"icon": "res://assets/art/tools/potion_blue.png",
		"description": "+2 Guts charge.",
		"guts_bonus": 2, "value": 18,
	},
	"potion_green": {
		"id": "potion_green", "name": "Vigor Potion", "type": ItemType.POTION,
		"icon": "res://assets/art/tools/potion_green.png",
		"description": "+2 SPD for 3 combats.",
		"spd_bonus": 2, "value": 22,
	},
	"potion_yellow": {
		"id": "potion_yellow", "name": "Strength Elixir", "type": ItemType.POTION,
		"icon": "res://assets/art/tools/potion_yellow.png",
		"description": "+3 ATK for 3 combats.",
		"atk_bonus": 3, "value": 25,
	},
	"potion_purple": {
		"id": "potion_purple", "name": "Shield Draught", "type": ItemType.POTION,
		"icon": "res://assets/art/tools/potion_purple.png",
		"description": "+3 AC for 3 combats.",
		"ac_bonus_temp": 3, "value": 22,
	},

	# ── KEYS ─────────────────────────────────────────────────────────────────
	"dungeon_key": {
		"id": "dungeon_key", "name": "Dungeon Key", "type": ItemType.KEY,
		"icon": "res://assets/art/tools/key_1.png",
		"description": "Opens a locked room.",
		"value": 0,
	},
}

# ══════════════════════════════════════════════════════════════════════════════
# LOOT TABLES — weighted by floor
# ══════════════════════════════════════════════════════════════════════════════

# floor_min, floor_max, weight, item_id
const ENEMY_LOOT := [
	# Common food drops (all floors)
	[1, 99, 30, "mushroom"],
	[1, 99, 20, "berry"],
	[1, 99, 15, "apple"],
	[1, 99, 10, "bread"],
	[2, 99, 8,  "cookie"],
	[3, 99, 5,  "honey"],
	[4, 99, 4,  "grilled_fish"],
	[5, 99, 3,  "mushroom_soup"],
	[7, 99, 1,  "super_stew"],
	[2, 99, 5,  "energy_bar"],

	# Buff foods
	[2, 99, 5,  "baked_potato"],
	[2, 99, 5,  "pepper"],
	[3, 99, 4,  "fish_rice"],
	[3, 99, 4,  "cooked_egg"],
	[4, 99, 3,  "pumpkin_pie"],
	[4, 99, 3,  "honey_bread"],

	# Potions (rarer)
	[1, 99, 8,  "potion_red"],
	[2, 99, 4,  "potion_blue"],
	[3, 99, 3,  "potion_green"],
	[3, 99, 3,  "potion_yellow"],
	[4, 99, 3,  "potion_purple"],

	# Weapons
	[1, 2,  6,  "club"],
	[1, 2,  5,  "stone_spear"],
	[1, 3,  4,  "boomerang"],
	[1, 3,  5,  "sword"],
	[2, 5,  4,  "blade"],
	[2, 5,  4,  "axe"],
	[3, 6,  3,  "crossbow"],
	[3, 6,  3,  "throwing_knives"],
	[4, 7,  2,  "magic_knife"],
	[5, 99, 2,  "knights_sword"],
	[6, 99, 1,  "morningstar"],
	[5, 99, 1,  "fire_staff"],
	[5, 99, 1,  "ice_bow"],

	# Armor
	[1, 3,  5,  "chest_leather"],
	[2, 5,  4,  "helm_iron"],
	[3, 6,  3,  "boots_leather"],
	[4, 7,  2,  "chest_chain"],
	[5, 99, 2,  "helm_knight"],
	[4, 99, 2,  "boots_iron"],

	# Key
	[1, 99, 3,  "dungeon_key"],

	# Rare accessories
	[3, 99, 1,  "blood_pendant"],
	[5, 99, 1,  "ancient_amulet"],
]

# Drop chance per enemy kill (out of 100)
const DROP_CHANCE := 45  # 45% base drop chance per kill


## Get a random item instance dict from the loot table for the given floor.
## Returns empty dict if no drop.
func roll_loot(floor_num: int) -> Dictionary:
	if randi_range(1, 100) > DROP_CHANCE:
		return {}

	# Filter loot table for this floor
	var eligible: Array = []
	var total_weight := 0
	for entry in ENEMY_LOOT:
		var f_min: int = entry[0]
		var f_max: int = entry[1]
		var weight: int = entry[2]
		if floor_num >= f_min and floor_num <= f_max:
			eligible.append(entry)
			total_weight += weight

	if eligible.is_empty() or total_weight == 0:
		return {}

	# Weighted random selection
	var roll := randi_range(1, total_weight)
	var cumulative := 0
	for entry in eligible:
		cumulative += entry[2]
		if roll <= cumulative:
			var item_id: String = entry[3]
			return create_item(item_id)

	return {}


## Create an item instance dict from an item definition.
func create_item(item_id: String) -> Dictionary:
	if item_id not in ITEMS:
		push_warning("ItemDB: unknown item '%s'" % item_id)
		return {}
	var base: Dictionary = ITEMS[item_id]
	return base.duplicate(true)


## Get the item definition (read-only).
func get_item_def(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})


## Use a consumable item (food/potion). Returns description of effect, or "" if unusable.
func use_item(item: Dictionary) -> String:
	var item_type: int = item.get("type", -1)

	if item_type == ItemType.FOOD or item_type == ItemType.POTION:
		if not GameData.in_combat:
			return ""

		var msg := ""

		var guts_bonus: int = item.get("guts_bonus", 0)
		if guts_bonus > 0:
			GameData.guts = mini(GameData.guts + guts_bonus, GameData.guts_max)
			msg += "+%d Guts  " % guts_bonus

		var spd_bonus: int = item.get("spd_bonus", 0)
		if spd_bonus > 0:
			GameData.combat_buff_spd += spd_bonus
			msg += "+%d SPD  " % spd_bonus

		var atk_bonus: int = item.get("atk_bonus", 0)
		if atk_bonus > 0:
			GameData.combat_buff_atk += atk_bonus
			msg += "+%d ATK  " % atk_bonus

		var ac_temp: int = item.get("ac_bonus_temp", 0)
		if ac_temp > 0:
			GameData.combat_buff_ac += ac_temp
			msg += "+%d AC  " % ac_temp

		var buff_stat: String = item.get("buff_stat", "")
		var buff_amt: int = item.get("buff_amount", 0)
		if buff_stat != "" and buff_amt > 0:
			match buff_stat:
				"str":
					GameData.combat_buff_str += buff_amt
					msg += "+%d STR  " % buff_amt
				"dex":
					GameData.combat_buff_dex += buff_amt
					msg += "+%d DEX  " % buff_amt
				"int":
					GameData.combat_buff_int += buff_amt
					msg += "+%d INT  " % buff_amt
				"spd":
					GameData.combat_buff_spd += buff_amt
					msg += "+%d SPD  " % buff_amt
				"lck":
					GameData.combat_buff_lck += buff_amt
					msg += "+%d LCK  " % buff_amt

		return msg.strip_edges()

	return ""


## Equip an item. Returns the previously equipped item (or empty dict).
func equip_item(item: Dictionary) -> Dictionary:
	var item_type: int = item.get("type", -1)
	if item_type not in EQUIP_SLOTS:
		return {}

	var slot_name: String = EQUIP_SLOTS[item_type]
	var old_item: Dictionary = GameData.get(slot_name)
	GameData.set(slot_name, item.duplicate(true))

	# Apply boot SPD bonus
	if item_type == ItemType.BOOTS:
		var spd_bonus: int = item.get("spd_bonus", 0)
		if spd_bonus > 0:
			GameData.stat_spd += spd_bonus
		# Remove old boot bonus
		if old_item:
			var old_spd: int = old_item.get("spd_bonus", 0)
			if old_spd > 0:
				GameData.stat_spd -= old_spd

	GameData.equipment_changed.emit()
	return old_item


## Unequip an item from a slot. Returns the item (or empty dict).
func unequip_slot(slot_type: int) -> Dictionary:
	if slot_type not in EQUIP_SLOTS:
		return {}

	var slot_name: String = EQUIP_SLOTS[slot_type]
	var item: Dictionary = GameData.get(slot_name)
	GameData.set(slot_name, {})

	if item and slot_type == ItemType.BOOTS:
		var spd_bonus: int = item.get("spd_bonus", 0)
		if spd_bonus > 0:
			GameData.stat_spd -= spd_bonus

	GameData.equipment_changed.emit()
	return item


## Add item to backpack. Returns true if added, false if full.
func add_to_backpack(item: Dictionary) -> bool:
	if GameData.backpack.size() >= GameData.BACKPACK_SIZE:
		return false
	GameData.backpack.append(item.duplicate(true))
	GameData.inventory_changed.emit()
	return true


## Remove item from backpack by index.
func remove_from_backpack(index: int) -> Dictionary:
	if index < 0 or index >= GameData.backpack.size():
		return {}
	var item: Dictionary = GameData.backpack[index]
	GameData.backpack.remove_at(index)
	GameData.inventory_changed.emit()
	return item
