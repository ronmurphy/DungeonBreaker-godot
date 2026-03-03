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
		"voice_pitch":   2.0,
		"voice_speed":   0.85,
	},
	"conner": {
		"name":          "Conner",
		"role":          "potion_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/conner",
		"greeting":      "Potions and sundries. Keep you breathing between fights.",
		"voice_pitch":   2.9,
		"voice_speed":   0.95,
	},
	"zara": {
		"name":          "Zara",
		"role":          "magic_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/zara",
		"greeting":      "The arcane demands respect. And gold.",
		"voice_pitch":   3.5,
		"voice_speed":   0.80,
	},
	"michelle": {
		"name":          "Michelle",
		"role":          "structure_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/michelle",
		"greeting":      "You want it built, I'll price it out.",
		"voice_pitch":   2.5,
		"voice_speed":   0.90,
	},
	"mahan": {
		"name":          "Mahan",
		"role":          "enhanced_armor_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/mahan",
		"greeting":      "Every blade tells a story. Let me find yours.",
		"voice_pitch":   2.6,
		"voice_speed":   0.85,
	},
	"steven": {
		"name":          "Steven",
		"role":          "enhanced_weapons_shop",
		"sprite_prefix": "res://assets/art/npc_sprites/steven",
		"greeting":      "Looking for something with an edge? You found the right guy.",
		"voice_pitch":   2.3,
		"voice_speed":   0.90,
	},
	"claude": {
		"name":          "Claude",
		"role":          "sage",
		"sprite_prefix": "res://assets/art/npc_sprites/claude",
		"greeting":      "Ask me anything. I have seen much in my years.",
		"voice_pitch":   2.2,
		"voice_speed":   0.75,
	},
}

## Role → shop label shown in the HUD prompt.
const ROLE_LABELS: Dictionary = {
	"armor_shop":              "General Store",
	"potion_shop":             "Potion Shop",
	"magic_shop":              "Magic Shop",
	"structure_shop":          "Build Shop",
	"enhanced_weapons_shop":   "Weapons Shop",
	"enhanced_armor_shop":     "Armor Shop",
	"sage":                    "Speak to Sage",
}


## Return the definition dict for a key, or {} if unknown.
func get_def(key: String) -> Dictionary:
	return NPC_DEFS.get(key, {})


## Return the HUD label for a role.
func get_role_label(role: String) -> String:
	return ROLE_LABELS.get(role, "Talk")
