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

const ARMOR_TYPES := [
	ItemType.HELM,
	ItemType.CHEST,
	ItemType.LEGS,
	ItemType.BOOTS,
]

const CONSUMABLE_TYPES := [
	ItemType.FOOD,
	ItemType.POTION,
]

## Item types that stack in the backpack (multiple units share one slot).
## Weapons and armor are always count=1 (each occupies its own slot).
const STACKABLE_TYPES := [
	ItemType.FOOD,
	ItemType.POTION,
	ItemType.KEY,
	ItemType.MISC,
]

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

	# ── MAGIC WEAPONS ────────────────────────────────────────────────────────
	"poison_dart": {
		"id": "poison_dart", "name": "Poison Dart", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/dart.png",
		"description": "A hollow dart loaded with toxin. Poisons the target for 2 turns. +3 attack range.",
		"attack_bonus": 2, "value": 12, "range_bonus": 3, "on_hit": "poison",
	},
	"crystal_wand": {
		"id": "crystal_wand", "name": "Crystal Wand", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/cryatal.png",
		"description": "A wand carved from raw crystal. Pierces 50% of the target's armor. +3 attack range.",
		"attack_bonus": 3, "value": 18, "range_bonus": 3, "on_hit": "armor_pierce",
	},
	"shuriken": {
		"id": "shuriken", "name": "Shuriken", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/shuriken.png",
		"description": "A spinning blade that ricochets to nearby foes. Hits up to 2 extra enemies for reduced damage. +2 attack range.",
		"attack_bonus": 2, "value": 30, "range_bonus": 2, "on_hit": "ricochet",
	},
	"skull_wand": {
		"id": "skull_wand", "name": "Skull Wand", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/skull.png",
		"description": "A necrotic focus that siphons life from its victims. Heals attacker for 25% of damage dealt. +2 attack range.",
		"attack_bonus": 4, "value": 55, "range_bonus": 2, "on_hit": "life_steal",
	},
	"storm_staff": {
		"id": "storm_staff", "name": "Storm Staff", "type": ItemType.WEAPON,
		"icon": "res://assets/art/tools/stick_2.png",
		"description": "A gnarled staff crackling with lightning. Chains half damage to one adjacent enemy. +3 attack range.",
		"attack_bonus": 5, "value": 75, "range_bonus": 3, "on_hit": "chain_lightning",
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

	# ── TOOLS (Michelle's structure shop) ────────────────────────────────────
	"torch": {
		"id": "torch", "name": "Torch", "type": ItemType.MISC,
		"icon": "res://assets/art/tools/torch.png",
		"description": "Refills 25 torch fuel. Use outside of combat.",
		"value": 4, "torch_fuel": 25,
	},
	"crystal_light_orb": {
		"id": "crystal_light_orb", "name": "Light Orb", "type": ItemType.MISC,
		"icon": "res://assets/art/tools/crystal_light_orb.png",
		"description": "A glowing crystal. Restores torch to full. Use outside combat.",
		"value": 18, "torch_fuel": 999,
	},
	"grapple": {
		"id": "grapple", "name": "Grappling Hook", "type": ItemType.MISC,
		"icon": "res://assets/art/tools/grapple.png",
		"description": "Escape any combat. Take 5 damage and flee to the room entrance.",
		"value": 15, "special_effect": "flee",
	},
	"net_trap": {
		"id": "net_trap", "name": "Net Trap", "type": ItemType.MISC,
		"icon": "res://assets/art/tools/net.png",
		"description": "Hurl a weighted net at an enemy, causing them to skip their next turn.",
		"value": 10, "special_effect": "snare",
	},
	"blast_charge": {
		"id": "blast_charge", "name": "Blast Charge", "type": ItemType.MISC,
		"icon": "res://assets/art/tools/demolition_charge.png",
		"description": "Detonates on impact dealing 10 damage to all enemies in the room.",
		"value": 25, "special_effect": "aoe_blast",
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

	# Magic weapons
	[1, 4,  4,  "poison_dart"],
	[1, 4,  3,  "crystal_wand"],
	[3, 6,  2,  "shuriken"],
	[4, 99, 1,  "skull_wand"],
	[6, 99, 1,  "storm_staff"],

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
	var item: Dictionary = normalize_item(base.duplicate(true))
	item["count"] = 1
	return item


## Get the item definition (read-only).
func get_item_def(item_id: String) -> Dictionary:
	return ITEMS.get(item_id, {})


## Return the canonical type for an item dict.
## Falls back to item id definition for old saves missing/invalid type.
func resolve_item_type(item: Dictionary) -> int:
	var t = item.get("type", -1)
	if t is int:
		return int(t)
	var item_id: String = item.get("id", "")
	if item_id != "":
		var def: Dictionary = get_item_def(item_id)
		if not def.is_empty():
			return int(def.get("type", -1))
	# Legacy flags fallback
	if bool(item.get("is_food", false)):
		return ItemType.FOOD
	if bool(item.get("is_potion", false)):
		return ItemType.POTION
	if bool(item.get("is_weapon", false)):
		return ItemType.WEAPON
	if bool(item.get("is_armor", false)):
		return ItemType.CHEST
	return int(t)


func is_consumable(item: Dictionary) -> bool:
	return resolve_item_type(item) in CONSUMABLE_TYPES


func is_weapon(item: Dictionary) -> bool:
	return resolve_item_type(item) == ItemType.WEAPON


func is_armor(item: Dictionary) -> bool:
	return resolve_item_type(item) in ARMOR_TYPES


func is_stackable(item: Dictionary) -> bool:
	return resolve_item_type(item) in STACKABLE_TYPES


## Normalize a loaded/runtime item dict to the canonical schema.
func normalize_item(item: Dictionary) -> Dictionary:
	if item.is_empty():
		return {}

	var out: Dictionary = item.duplicate(true)
	var item_id: String = out.get("id", "")
	if item_id != "":
		var def: Dictionary = get_item_def(item_id)
		if not def.is_empty():
			# Keep dynamic/runtime fields (e.g. durability) from save item,
			# but enforce canonical metadata/type from database.
			for k in ["id", "name", "icon", "description"]:
				out[k] = def.get(k, out.get(k, ""))
			out["type"] = int(def.get("type", resolve_item_type(out)))
			return out

	out["type"] = resolve_item_type(out)
	return out


func normalize_item_array(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		if v is Dictionary:
			out.append(normalize_item(v as Dictionary))
	return out


## Convert a flat item array (old format) to stacked format.
## Stackable items with the same id are merged into one entry with a "count" field.
## Idempotent: running on already-stacked data is safe (items with count>1 stay merged).
func stack_item_array(arr: Array) -> Array:
	var out: Array = []
	var id_map: Dictionary = {}
	for raw in arr:
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw as Dictionary
		var item_id: String = item.get("id", "")
		var count: int = int(item.get("count", 1))
		if item_id != "" and is_stackable(item):
			if item_id in id_map:
				var idx: int = id_map[item_id]
				out[idx]["count"] = int(out[idx].get("count", 1)) + count
			else:
				id_map[item_id] = out.size()
				var entry: Dictionary = item.duplicate(true)
				entry["count"] = count
				out.append(entry)
		else:
			var entry: Dictionary = item.duplicate(true)
			entry["count"] = 1
			out.append(entry)
	return out


## Use a consumable item (food/potion/misc). Returns description of effect, or "" if unusable.
func use_item(item: Dictionary) -> String:
	var item_type: int = resolve_item_type(item)

	# ── MISC: torch fuel items usable outside combat ──
	if item_type == ItemType.MISC:
		var fuel: int = item.get("torch_fuel", 0)
		if fuel > 0:
			if GameData.in_combat:
				return ""
			var max_fuel: int = GameData.get_torch_fuel_max()
			var gained: int = mini(fuel, max_fuel - GameData.torch_fuel)
			if gained <= 0:
				return ""  # already full
			GameData.torch_fuel = mini(GameData.torch_fuel + fuel, max_fuel)
			return "+%d torch fuel" % gained
		# Combat special effects are handled by combat_manager via "special:key" string
		var special: String = item.get("special_effect", "")
		if special != "":
			if not GameData.in_combat:
				return ""
			return "special:" + special
		return ""

	if item_type == ItemType.FOOD or item_type == ItemType.POTION:
		if not GameData.in_combat:
			return ""

		var msg := ""
		var heal_amount: int = item.get("heal_amount", 0)
		if heal_amount > 0:
			var old_hp: int = GameData.hp
			GameData.heal(heal_amount)
			var gained_hp: int = GameData.hp - old_hp
			if gained_hp > 0:
				msg += "+%d HP  " % gained_hp

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
	item = normalize_item(item)
	var item_type: int = resolve_item_type(item)
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
## Stackable items (food/potion/key/misc) merge into an existing stack instead of taking a new slot.
func add_to_backpack(item: Dictionary) -> bool:
	item = normalize_item(item)
	var add_count: int = int(item.get("count", 1))
	if is_stackable(item):
		var item_id: String = item.get("id", "")
		if item_id != "":
			for i in GameData.backpack.size():
				var entry: Dictionary = GameData.backpack[i]
				if entry.get("id", "") == item_id:
					GameData.backpack[i]["count"] = int(GameData.backpack[i].get("count", 1)) + add_count
					GameData.inventory_changed.emit()
					return true
	# No existing stack (or not stackable) — need a new slot
	if GameData.backpack.size() >= GameData.BACKPACK_SIZE + GameData.backpack_bonus_slots:
		return false
	item["count"] = add_count
	GameData.backpack.append(item)
	GameData.inventory_changed.emit()
	return true


## Remove item(s) from backpack by index.
## For stackable items with count > amount, decrements the count and returns a copy with the removed amount.
## Pass amount equal to item["count"] (or any value >= current count) to remove the entire stack.
func remove_from_backpack(index: int, amount: int = 1) -> Dictionary:
	if index < 0 or index >= GameData.backpack.size():
		return {}
	var item: Dictionary = GameData.backpack[index]
	var current_count: int = int(item.get("count", 1))
	if is_stackable(item) and current_count > amount:
		# Partial removal — decrement count, keep the slot
		GameData.backpack[index]["count"] = current_count - amount
		var out: Dictionary = item.duplicate(true)
		out["count"] = amount
		GameData.inventory_changed.emit()
		return out
	# Remove the entire slot
	GameData.backpack.remove_at(index)
	GameData.inventory_changed.emit()
	return item
