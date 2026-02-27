# Container for all block types.
# It is not a resource because it references scripts that can depend on it,
# causing cycles. So instead, it's more convenient to make it a node in the tree.
# IMPORTANT: Needs to be first in tree. Other nodes may use it in _ready().
extends Node

const Block = preload("./block.gd")
const Util = preload("res://common/util.gd")

const ROTATION_TYPE_NONE = 0
const ROTATION_TYPE_AXIAL = 1
const ROTATION_TYPE_Y = 2
const ROTATION_TYPE_CUSTOM_BEHAVIOR = 3

const ROTATION_Y_NEGATIVE_X = 0
const ROTATION_Y_POSITIVE_X = 1
const ROTATION_Y_NEGATIVE_Z = 2
const ROTATION_Y_POSITIVE_Z = 3

const _opposite_y_rotation : Array[int] = [
	ROTATION_Y_POSITIVE_X,
	ROTATION_Y_NEGATIVE_X,
	ROTATION_Y_POSITIVE_Z,
	ROTATION_Y_NEGATIVE_Z
]

const _y_dir : Array[Vector3] = [
	Vector3(-1, 0, 0),
	Vector3(1, 0, 0),
	Vector3(0, 0, -1),
	Vector3(0, 0, 1)
]

const ROOT = "res://blocky_game/blocks"

const AIR_ID = 0

class RawMapping:
	var block_id := 0
	var variant_index := 0


var _voxel_library := preload("res://blocky_game/blocks/voxel_library.tres")
var _blocks = []
var _raw_mappings = []
var _block_colors = {}  # Cache for sampled block colors {block_id: Color}


func _init():
	print("Constructing blocks.gd")
	_create_block({
		"name": "air",
		"directory": "",
		"gui_model": "",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["air"],
		"transparent": true
	})
	_create_block({
		"name": "dirt",
		"gui_model": "dirt.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["dirt"],
		"transparent": false
	})
	_create_block({
		"name": "grass",
		"gui_model": "grass.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["grass"],
		"transparent": false
	})
	_create_block({
		"name": "log",
		"gui_model": "log_y.obj",
		"rotation_type": ROTATION_TYPE_AXIAL,
		"voxels": ["log_x", "log_y", "log_z"],
		"transparent": false
	})
	_create_block({
		"name": "planks",
		"gui_model": "planks.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["planks"],
		"transparent": false
	})
	_create_block({
		"name": "stairs",
		"gui_model": "stairs_nx.obj",
		"rotation_type": ROTATION_TYPE_Y,
		"voxels": ["stairs_nx", "stairs_px", "stairs_nz", "stairs_pz"],
		"transparent": false
	})
	_create_block({
		"name": "tall_grass",
		"gui_model": "tall_grass.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["tall_grass"],
		"transparent": true,
		"backface_culling": false
	})
	_create_block({
		"name": "glass",
		"gui_model": "glass.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["glass"],
		"transparent": true,
		"backface_culling": true
	})
	_create_block({
		"name": "water",
		"gui_model": "water_full.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["water_full", "water_top"],
		"transparent": true,
		"backface_culling": true
	})
	_create_block({
		"name": "rail",
		"gui_model": "rail_x.obj",
		"rotation_type": ROTATION_TYPE_CUSTOM_BEHAVIOR,
		"voxels": [
			# Order matters, see rail.gd
			"rail_x", "rail_z",
			"rail_turn_nx", "rail_turn_px", "rail_turn_nz", "rail_turn_pz",
			"rail_slope_nx", "rail_slope_px","rail_slope_nz", "rail_slope_pz"
		],
		"transparent": true,
		"backface_culling": true,
		"behavior": "rail.gd"
	})
	_create_block({
		"name": "leaves",
		"gui_model": "leaves.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["leaves"],
		"transparent": true
	})
	_create_block({
		"name": "dead_shrub",
		"gui_model": "dead_shrub.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["dead_shrub"],
		"transparent": true,
		"backface_culling": false
	})
	_create_block({
		"name": "pumpkin",
		"gui_model": "pumpkin.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["pumpkin"],
		"transparent": false
	})
	_create_block({
		"name": "bedrock",
		"gui_model": "bedrock.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["bedrock"],
		"transparent": false
	})
	_create_block({
		"name": "stone",
		"gui_model": "stone.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["stone"],
		"transparent": false
	})
	_create_block({
		"name": "gold_ore",
		"gui_model": "gold_ore.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["gold_ore"],
		"transparent": false
	})
	_create_block({
		"name": "iron_ore",
		"gui_model": "iron_ore.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["iron_ore"],
		"transparent": false
	})
	_create_block({
		"name": "tilled_dirt",
		"gui_model": "tilled_dirt.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["tilled_dirt"],
		"transparent": false
	})
	_create_block({
		"name": "ruin_stone",
		"gui_model": "ruin_stone.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["ruin_stone"],
		"transparent": false
	})
	_create_block({
		"name": "ruin_floor",
		"gui_model": "ruin_floor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["ruin_floor"],
		"transparent": false
	})
	_create_block({
		"name": "teleport_stone",
		"gui_model": "teleport_stone.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["teleport_stone"],
		"transparent": false
	})
	_create_block({
		"name": "birch_log",
		"gui_model": "birch_log_y.obj",
		"rotation_type": ROTATION_TYPE_AXIAL,
		"voxels": ["birch_log_y", "birch_log_x", "birch_log_z"],
		"transparent": false
	})
	_create_block({
		"name": "water_block_",
		"gui_model": "water_block_.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["water_block_"],
		"transparent": false
	})
	_create_block({
		"name": "sand",
		"gui_model": "sand.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["sand"],
		"transparent": false
	})
	_create_block({
		"name": "sand_stone",
		"gui_model": "sand_stone.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["sand_stone"],
		"transparent": false
	})
	_create_block({
		"name": "crate",
		"gui_model": "crate.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["crate"],
		"transparent": false
	})
	_create_block({
		"name": "push_block",
		"gui_model": "push_block.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["push_block"],
		"transparent": false
	})
	_create_block({
		"name": "ice",
		"gui_model": "ice.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["ice"],
		"transparent": false
	})
	_create_block({
		"name": "chest",
		"gui_model": "chest.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["chest"],
		"transparent": false
	})
	_create_block({
		"name": "rust_block",
		"gui_model": "",  # Uses texture atlas
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["rust_block"],
		"transparent": false
	})
	_create_block({
		"name": "rust_pipe",
		"gui_model": "",  # Uses texture atlas
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["rust_pipe"],
		"transparent": false
	})
	_create_block({
		"name": "rust_cube",
		"gui_model": "",  # Uses texture atlas
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["rust_cube"],
		"transparent": false
	})
	_create_block({
		"name": "rust_floor",
		"gui_model": "",  # Uses texture atlas
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["rust_floor"],
		"transparent": false
	})
	_create_block({
		"name": "void_stone",
		"gui_model": "void_stone.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["void_stone"],
		"transparent": false
	})
	_create_block({
		"name": "void_stone_active",
		"gui_model": "void_stone_active.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["void_stone_active"],
		"transparent": false
	})
	_create_block({
		"name": "void_fog",
		"gui_model": "void_fog.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["void_fog"],
		"transparent": true
	})
	_create_block({
		"name": "pipe_block",
		"gui_model": "pipe_block.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["pipe_block"],
		"transparent": false
	})
	_create_block({
		"name": "void_beacon",
		"gui_model": "void_beacon.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["void_beacon"],
		"transparent": false
	})
	_create_block({
		"name": "ruin_stone_",
		"gui_model": "ruin_stone_.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["ruin_stone_"],
		"transparent": false
	})
	_create_block({
		"name": "ruin_void_lamp",
		"gui_model": "ruin_void_lamp.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["ruin_void_lamp"],
		"transparent": false
	})
	_create_block({
		"name": "void_gas",
		"gui_model": "void_gas.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["void_gas"],
		"transparent": false
	})
	_create_block({
		"name": "rune_core",
		"gui_model": "rune_core.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["rune_core"],
		"transparent": false
	})
	_create_block({
		"name": "rune_marker",
		"gui_model": "rune_marker.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["rune_marker"],
		"transparent": false
	})
	_create_block({
		"name": "stone_bricks",
		"gui_model": "stone_bricks.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["stone_bricks"],
		"transparent": false
	})
	_create_block({
		"name": "void_stone_bricks",
		"gui_model": "void_stone_bricks.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["void_stone_bricks"],
		"transparent": false
	})
	_create_block({
		"name": "test",
		"gui_model": "test.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["test"],
		"transparent": false
	})
	_create_block({
		"name": "browncolor",
		"gui_model": "browncolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["browncolor"],
		"transparent": false
	})
	_create_block({
		"name": "orangecolor",
		"gui_model": "orangecolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["orangecolor"],
		"transparent": false
	})
	_create_block({
		"name": "yellowcolor",
		"gui_model": "yellowcolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["yellowcolor"],
		"transparent": false
	})
	_create_block({
		"name": "limecolor",
		"gui_model": "limecolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["limecolor"],
		"transparent": false
	})
	_create_block({
		"name": "greencolor",
		"gui_model": "greencolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["greencolor"],
		"transparent": false
	})
	_create_block({
		"name": "blgrncolor",
		"gui_model": "blgrncolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["blgrncolor"],
		"transparent": false
	})
	_create_block({
		"name": "cyancolor",
		"gui_model": "cyancolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["cyancolor"],
		"transparent": false
	})
	_create_block({
		"name": "lbluecolor",
		"gui_model": "lbluecolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["lbluecolor"],
		"transparent": false
	})
	_create_block({
		"name": "bluecolor",
		"gui_model": "bluecolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["bluecolor"],
		"transparent": false
	})
	_create_block({
		"name": "burplecolor",
		"gui_model": "burplecolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["burplecolor"],
		"transparent": false
	})
	_create_block({
		"name": "purlpecolor",
		"gui_model": "purlpecolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["purlpecolor"],
		"transparent": false
	})
	_create_block({
		"name": "magentacolor",
		"gui_model": "magentacolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["magentacolor"],
		"transparent": false
	})
	_create_block({
		"name": "dgreycolor",
		"gui_model": "dgreycolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["dgreycolor"],
		"transparent": false
	})
	_create_block({
		"name": "mgreycolor",
		"gui_model": "mgreycolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["mgreycolor"],
		"transparent": false
	})
	_create_block({
		"name": "lgreycolor",
		"gui_model": "lgreycolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["lgreycolor"],
		"transparent": false
	})
	_create_block({
		"name": "redcolor",
		"gui_model": "redcolor.obj",
		"rotation_type": ROTATION_TYPE_NONE,
		"voxels": ["redcolor"],
		"transparent": false
	})


































func get_block(id: int) -> Block:
	assert(id >= 0)
	return _blocks[id]


func get_model_library() -> VoxelBlockyLibrary:
	return _voxel_library


func get_block_by_name(block_name: String) -> Block:
	for b in _blocks:
		if b.base_info.name == block_name:
			return b
	assert(false)
	return null


# Gets the corresponding block ID and variant index from a raw voxel value
func get_raw_mapping(raw_id: int) -> RawMapping:
	assert(raw_id >= 0)
	var rm = _raw_mappings[raw_id]
	assert(rm != null)
	return rm


func get_block_count() -> int:
	return len(_blocks)


func get_block_color(block_id: int) -> Color:
	"""Get cached color for a block, or sample it from the texture if not cached"""
	# Return cached color if available
	if _block_colors.has(block_id):
		return _block_colors[block_id]

	# Sample color from terrain texture (center of block texture in atlas)
	var block = get_block(block_id)
	if block == null:
		return Color.WHITE  # Fallback

	# For now, use a simplified color sampling
	# This will work with seasonal textures as long as we sample after seasonal swap
	var sampled_color = _sample_block_color_from_texture(block)
	_block_colors[block_id] = sampled_color
	print("Cached color for block %d: %s" % [block_id, sampled_color])
	return sampled_color


func _sample_block_color_from_texture(block: Block) -> Color:
	"""Sample the average color from a block's texture in the terrain atlas"""
	var block_name = block.base_info.name

	# Load terrain.png directly as an Image (not as a compiled texture resource)
	var image = Image.new()
	var error = image.load("res://blocky_game/blocks/terrain.png")
	if error != OK:
		print("Warning: Could not load terrain.png for color sampling, error code: %d" % error)
		return Color.WHITE

	if image.is_empty():
		print("Warning: terrain.png is empty")
		return Color.WHITE

	# Define which blocks to sample and where in the atlas (UV coordinates in texture units)
	# Terrain atlas is 16x16 blocks, so each block is 1/16th of the texture
	# These are [column, row] indices in the grid (0-15 each)
	var block_uv_map = {
		"leaves": Vector2i(1, 0),      # Column 1, Row 0
		"grass": Vector2i(0, 0),       # Column 0, Row 0 - grass block top
		"tall_grass": Vector2i(0, 1),  # Column 0, Row 1 - tall grass texture
		"dead_shrub": Vector2i(1, 1),  # Column 1, Row 1 - dead shrub texture
		"log": Vector2i(2, 0),         # Column 2, Row 0 - log side
		"birch_log": Vector2i(3, 0),   # Column 3, Row 0 - birch log side
		"dirt": Vector2i(2, 1),        # Column 2, Row 1 - dirt block
		"stone": Vector2i(3, 1),       # Column 3, Row 1 - stone block
		"pumpkin": Vector2i(14, 0),    # Column 14, Row 0 - pumpkin
		"water": Vector2i(14, 1),      # Column 14, Row 1 - water
		"sand": Vector2i(15, 2),       # Column 15, Row 2 - sand
		"planks": Vector2i(4, 0)       # Column 4, Row 0 - planks
	}

	if not block_uv_map.has(block_name):
		print("Block '%s' not in UV map, returning white" % block_name)
		return Color.WHITE

	# Get the UV coordinates for this block
	var uv = block_uv_map[block_name]
	var block_size = image.get_width() / 16  # Assume 16x16 grid

	# Sample from the center of the block's texture
	var sample_x = (uv.x * block_size) + (block_size / 2)
	var sample_y = (uv.y * block_size) + (block_size / 2)

	# Convert to integers and clamp to valid range
	sample_x = clampi(int(sample_x), 0, image.get_width() - 1)
	sample_y = clampi(int(sample_y), 0, image.get_height() - 1)

	# Sample the pixel color
	var color = image.get_pixel(sample_x, sample_y)
	print("Sampled %s at UV(%d,%d) pixel(%d,%d): %s" % [block_name, uv.x, uv.y, sample_x, sample_y, color])

	return color


func _create_block(params: Dictionary):
	_defaults(params, {
		"rotation_type": ROTATION_TYPE_NONE,
		"transparent": false,
		"backface_culling": true,
		"directory": params.name,
		"behavior": ""
	})

	var block : Block
	if params.behavior != "":
		# Block with special behavior
		var behavior_path := str(ROOT, "/", params.directory, "/", params.behavior)
		var behavior = load(behavior_path)
		block = behavior.new()
	else:
		# Generic
		block = Block.new()

	# Fill in base info
	var base_info := block.base_info
	base_info.id = len(_blocks)
	
	for i in len(params.voxels):
		var vname : String = params.voxels[i]
		var id := _voxel_library.get_model_index_from_resource_name(vname)
		if id == -1:
			push_error("Could not find voxel named {0}".format([vname]))
		assert(id != -1)
		params.voxels[i] = id
		var rm := RawMapping.new()
		rm.block_id = base_info.id
		rm.variant_index = i
		if id >= len(_raw_mappings):
			_raw_mappings.resize(id + 1)
		_raw_mappings[id] = rm

	base_info.name = params.name
	base_info.directory = params.directory
	base_info.rotation_type = params.rotation_type
	base_info.voxels = params.voxels
	base_info.transparent = params.transparent
	base_info.backface_culling = params.backface_culling
	if base_info.directory != "":
		base_info.gui_model_path = str(ROOT, "/", params.directory, "/", params.gui_model)
		var sprite_path := str(ROOT, "/", params.directory, "/", params.name, "_sprite.png")
		base_info.sprite_texture = load(sprite_path)

	_blocks.append(block)
	add_child(block)


func _notification(what):
	match what:
		NOTIFICATION_PREDELETE:
			print("Deleting blocks.gd")


static func _defaults(d: Dictionary, defaults: Dictionary):
	for k in defaults:
		if not d.has(k):
			d[k] = defaults[k]


static func get_y_rotation_from_look_dir(dir: Vector3) -> int:
	var a = Util.get_direction_id4(Vector2(dir.x, dir.z))
	match a:
		0:
			return ROTATION_Y_NEGATIVE_X
		1:
			return ROTATION_Y_NEGATIVE_Z
		2:
			return ROTATION_Y_POSITIVE_X
		3:
			return ROTATION_Y_POSITIVE_Z
		_:
			assert(false)
	return -1


static func get_y_dir_vec(yid: int) -> Vector3:
	return _y_dir[yid]


static func get_opposite_y_dir(yid: int) -> int:
	return _opposite_y_rotation[yid]
