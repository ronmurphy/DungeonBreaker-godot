extends Node
## NPC definitions — roles, sprites, dialogue. Autoloaded as "NpcDB".
##
## Named NPCs are rescued one-per-floor from dungeons and join the camp.
## Generic (white-tinted) NPCs can fill remaining slots with random citizens.

# ── Named NPC definitions ─────────────────────────────────────────────────────
const NPC_DEFS: Dictionary = {
	"daniels": {
		"name":          "Daniels",
		"role":          "armor_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/daniels",
		"greeting":      "Need protection? I stock the finest armor in camp.",
	},
	"conner": {
		"name":          "Conner",
		"role":          "potion_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/conner",
		"greeting":      "Potions and sundries. Keep you breathing between fights.",
	},
	"zara": {
		"name":          "Zara",
		"role":          "magic_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/zara",
		"greeting":      "The arcane demands respect. And gold.",
	},
	"michelle": {
		"name":          "Michelle",
		"role":          "structure_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/michelle",
		"greeting":      "You want it built, I'll price it out.",
	},
	"mahan": {
		"name":          "Mahan",
		"role":          "weapon_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/mahan",
		"greeting":      "Every blade tells a story. Let me find yours.",
	},
	"claude": {
		"name":          "Claude",
		"role":          "sage",
		"sprite_prefix": "res://assets/art/npc_sprites/claude",
		"greeting":      "Ask me anything. I have seen much in my years.",
	},
}

## Role → shop label shown in the HUD prompt.
const ROLE_LABELS: Dictionary = {
	"armor_shop":     "Armor Shop",
	"potion_shop":    "Potion Shop",
	"magic_shop":     "Magic Shop",
	"structure_shop": "Build Shop",
	"weapon_shop":    "Weapon Shop",
	"sage":           "Speak to Sage",
}


## Return the definition dict for a key, or {} if unknown.
func get_def(key: String) -> Dictionary:
	return NPC_DEFS.get(key, {})


## Return the HUD label for a role.
func get_role_label(role: String) -> String:
	return ROLE_LABELS.get(role, "Talk")
