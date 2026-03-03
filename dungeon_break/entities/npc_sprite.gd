extends Sprite3D
class_name NpcSprite
## Stationary billboard sprite for camp NPCs.
##
## Loads a front and back PNG from a sprite prefix
## (e.g. "res://assets/art/npc_sprites/daniels" loads
##  daniels.png and daniels_back.png).
##
## Call update_facing(cam_pos) every frame from game.gd to show the
## correct side based on which way the camera is looking at the NPC.

# NPC sprites are similar dimensions to player avatars.
const PIXEL_SIZE := 0.0045

var _tex_front: Texture2D = null
var _tex_back:  Texture2D = null

# World-space XZ direction the NPC's face points toward.
# Set in setup() from the slot's face_dir.
var _face_dir: Vector3 = Vector3(0, 0, 1)


func _ready() -> void:
	billboard       = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter  = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pixel_size      = PIXEL_SIZE
	render_priority = 2

	# Drop shadow at feet
	_add_drop_shadow()


## Load textures and set the facing direction.
## sprite_prefix: path without extension, e.g. "res://assets/art/npc_sprites/zara"
## face_dir: world-space XZ direction the NPC's face points (normalised).
func setup(sprite_prefix: String, face_dir: Vector3 = Vector3(0, 0, 1)) -> void:
	_face_dir = Vector3(face_dir.x, 0.0, face_dir.z).normalized()

	var fp := sprite_prefix + ".png"
	var bp := sprite_prefix + "_back.png"

	if ResourceLoader.exists(fp):
		_tex_front = load(fp) as Texture2D
	if ResourceLoader.exists(bp):
		_tex_back  = load(bp) as Texture2D

	# Default to front
	texture = _tex_front if _tex_front else _tex_back


## Call every frame with the camera's world position.
## Shows the front texture when the camera is on the NPC's front side.
func update_facing(cam_pos: Vector3) -> void:
	var to_cam := cam_pos - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.01:
		return
	to_cam = to_cam.normalized()

	if to_cam.dot(_face_dir) >= 0.0:
		if _tex_front:
			texture = _tex_front
	else:
		if _tex_back:
			texture = _tex_back


## Add a flat dark ellipse below the NPC sprite as a drop shadow.
func _add_drop_shadow() -> void:
	# Skip on LOW preset
	if GraphicsManager and GraphicsManager.current_preset == 0:
		return
	var parent := get_parent()
	if parent == null:
		# Sprite is root — create a child MeshInstance3D directly
		parent = self
	var mi := MeshInstance3D.new()
	mi.name = "Shadow"
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.9, 0.55)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.position = Vector3(0, -1.45, 0)  # at feet level (sprite origin is ~1.5 up)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
