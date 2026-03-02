extends Node3D
## CampAnimals — ambient wildlife for the camp scene.
##
## Rabbits hop on the plateau and in the lowlands.
## Cats wander the camp plateau and sit occasionally.
## Birds fly in the air and periodically land on tree canopy tops.
##
## Call setup(camp_builder_ref) once after build_camp() completes.

const PIXEL_SIZE := 0.0012

enum AState { MOVING, RESTING }
enum AType  { RABBIT, CAT, BIRD_A, BIRD_B }

# Plateau ground bounds
const PLATEAU_RADIUS : float = 24.0   # XZ radius from origin kept clear of edge
const PLATEAU_Y_MIN  : int   = -2     # surface Y below this = off the island

# Lowland annulus
const LOWLAND_MIN_R : float = 46.0
const LOWLAND_MAX_R : float = 70.0

# Bird flight heights (absolute world Y, plateau surface ≈ y 3-5)
const BIRD_Y_MIN : float = 9.0
const BIRD_Y_MAX : float = 16.0

# How close a bird needs to be to count as "arrived at perch"
const PERCH_ARRIVE_R : float = 0.65

# Movement speeds (m/s)
const RABBIT_SPEED    : float = 2.4
const CAT_SPEED       : float = 1.8
const BIRD_SPEED      : float = 5.5
const BIRD_GLIDE      : float = 3.0   # slower on descent to perch

# State durations (seconds)
const MOVE_TIME_MIN : float = 3.5
const MOVE_TIME_MAX : float = 9.0
const REST_TIME_MIN : float = 2.5
const REST_TIME_MAX : float = 8.5

# Animation frame intervals (seconds)
const WALK_FPS : float = 0.22
const BIRD_FPS : float = 0.16

var _builder                        = null   # camp_builder ref (duck-typed)
var _rng   : RandomNumberGenerator  = RandomNumberGenerator.new()
var _animals : Array[Dictionary]    = []
var _perch_positions : Array[Vector3] = []   # tree canopy tops for birds


# ── Public ─────────────────────────────────────────────────────────────────────

func setup(builder) -> void:
	_builder = builder
	_rng.seed = 77
	_build_perch_list()
	_spawn_all()


# ── Perch list ─────────────────────────────────────────────────────────────────

func _build_perch_list() -> void:
	# Plateau trees (TREE_POSITIONS is a const array on camp_builder)
	for tp: Vector2i in _builder.TREE_POSITIONS:
		var sy: int = _builder._surface_y(tp.x, tp.y)
		if sy < PLATEAU_Y_MIN:
			continue
		_perch_positions.append(Vector3(float(tp.x) + 0.5, float(sy) + 6.5, float(tp.y) + 0.5))
	# Lowland trees
	for tp: Vector2i in _builder.LOWLAND_TREE_POSITIONS:
		var sy: int = _builder._surface_y(tp.x, tp.y)
		if sy < -22:
			continue
		_perch_positions.append(Vector3(float(tp.x) + 0.5, float(sy) + 6.5, float(tp.y) + 0.5))


# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_all() -> void:
	_rng.seed = 77   # deterministic — same layout each session
	for _i in 3: _do_spawn(AType.RABBIT, "plateau")
	for _i in 2: _do_spawn(AType.CAT,    "plateau")
	for _i in 3: _do_spawn(AType.RABBIT, "lowland")
	for _i in 3: _do_spawn(AType.BIRD_A, "air")
	for _i in 2: _do_spawn(AType.BIRD_B, "air")


func _do_spawn(atype: AType, zone: String) -> void:
	var spawn_pos := _rand_zone_pos(zone)

	var node := Node3D.new()
	node.name = "Animal_%d" % _animals.size()
	add_child(node)
	node.global_position = spawn_pos

	var sprite := Sprite3D.new()
	sprite.billboard  = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = PIXEL_SIZE
	sprite.alpha_cut  = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.render_priority = 1
	node.add_child(sprite)

	var is_bird: bool = (atype == AType.BIRD_A or atype == AType.BIRD_B)

	var tex1     : Texture2D
	var tex2     : Texture2D
	var tex_rest : Texture2D = null

	match atype:
		AType.RABBIT:
			tex1     = load("res://assets/art/animals/rabbit_move_1.png")
			tex2     = load("res://assets/art/animals/rabbit_move_2.png")
			tex_rest = load("res://assets/art/animals/rabbit_rest.png")
		AType.CAT:
			tex1     = load("res://assets/art/animals/cat_walk_1.png")
			tex2     = load("res://assets/art/animals/cat_walk_2.png")
			tex_rest = load("res://assets/art/animals/cat_sit.png")
		AType.BIRD_A:
			tex1 = load("res://assets/art/animals/birdA_1.png")
			tex2 = load("res://assets/art/animals/birdA_2.png")
		_:  # BIRD_B
			tex1 = load("res://assets/art/animals/birdB_1.png")
			tex2 = load("res://assets/art/animals/birdB_2.png")

	sprite.texture = tex1

	var spd: float = BIRD_SPEED if is_bird else (RABBIT_SPEED if atype == AType.RABBIT else CAT_SPEED)

	var animal: Dictionary = {
		"atype":         int(atype),
		"zone":          zone,
		"state":         int(AState.MOVING),
		"is_bird":       is_bird,
		"node":          node,
		"sprite":        sprite,
		"tex1":          tex1,
		"tex2":          tex2,
		"tex_rest":      tex_rest,
		"target":        spawn_pos,
		"perch_arrived": false,
		"speed":         spd,
		"anim_frame":    0,
		"anim_timer":    _rng.randf_range(0.0, 0.35),   # stagger initial frames
		"state_timer":   _rng.randf_range(0.5, 3.5),    # stagger initial transitions
		"frame_rate":    BIRD_FPS if is_bird else WALK_FPS,
		"facing_right":  true,
	}
	_animals.append(animal)

	# Set initial movement target
	if is_bird:
		animal["target"] = _rand_air_pos()
	else:
		animal["target"] = _rand_ground_target(spawn_pos, zone)


# ── Position helpers ──────────────────────────────────────────────────────────

func _rand_zone_pos(zone: String) -> Vector3:
	match zone:
		"plateau": return _rand_plateau_pos()
		"lowland": return _rand_lowland_pos()
		_:         return _rand_air_pos()


func _rand_plateau_pos() -> Vector3:
	for _attempt in 50:
		var angle := _rng.randf() * TAU
		var dist  := _rng.randf_range(5.0, PLATEAU_RADIUS)
		var tx    := cos(angle) * dist
		var tz    := sin(angle) * dist
		var sy: int = _builder._surface_y(int(tx), int(tz))
		if sy < PLATEAU_Y_MIN:
			continue
		return Vector3(tx, float(sy) + 1.2, tz)
	return Vector3(8.0, 4.2, 8.0)


func _rand_lowland_pos() -> Vector3:
	for _attempt in 60:
		var angle := _rng.randf() * TAU
		var dist  := _rng.randf_range(LOWLAND_MIN_R, LOWLAND_MAX_R)
		var tx    := cos(angle) * dist
		var tz    := sin(angle) * dist
		var sy: int = _builder._surface_y(int(tx), int(tz))
		if sy < -22 or sy > -3:
			continue
		return Vector3(tx, float(sy) + 1.2, tz)
	return Vector3(0.0, -10.0, 58.0)


func _rand_air_pos() -> Vector3:
	var angle := _rng.randf() * TAU
	var dist  := _rng.randf_range(5.0, 22.0)
	var y     := _rng.randf_range(BIRD_Y_MIN, BIRD_Y_MAX)
	return Vector3(cos(angle) * dist, y, sin(angle) * dist)


## Pick a nearby ground waypoint within the animal's zone.
func _rand_ground_target(from_pos: Vector3, zone: String) -> Vector3:
	for _attempt in 30:
		var dx := _rng.randf_range(-7.0, 7.0)
		var dz := _rng.randf_range(-7.0, 7.0)
		var tx := from_pos.x + dx
		var tz := from_pos.z + dz

		if zone == "plateau":
			if sqrt(tx * tx + tz * tz) > PLATEAU_RADIUS:
				continue
			var sy: int = _builder._surface_y(int(tx), int(tz))
			if sy < PLATEAU_Y_MIN:
				continue
			# Don't hop to a much higher or lower surface (steep cliff)
			if abs(sy - int(from_pos.y - 1.0)) > 4:
				continue
			return Vector3(tx, float(sy) + 1.2, tz)
		else:  # lowland
			var d2 := sqrt(tx * tx + tz * tz)
			if d2 < LOWLAND_MIN_R or d2 > LOWLAND_MAX_R:
				continue
			var sy: int = _builder._surface_y(int(tx), int(tz))
			if sy < -22 or sy > -3:
				continue
			return Vector3(tx, float(sy) + 1.2, tz)

	# Fallback: head back toward zone centre
	if zone == "plateau":
		return Vector3(0.0, float(_builder._surface_y(0, 0)) + 1.2, 0.0)
	return Vector3(0.0, -10.0, 58.0)


# ── Per-frame update ──────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _builder == null:
		return
	for a in _animals:
		_update_animal(a, delta)


func _update_animal(a: Dictionary, delta: float) -> void:
	var node    : Node3D   = a["node"]   as Node3D
	var sprite  : Sprite3D = a["sprite"] as Sprite3D
	var state   : int      = a["state"]  as int
	var is_bird : bool     = a["is_bird"] as bool

	# ── State timer ────────────────────────────────────────────────────────
	a["state_timer"] = (a["state_timer"] as float) - delta

	if (a["state_timer"] as float) <= 0.0:
		if state == AState.MOVING:
			# Transition to rest / perch
			a["state"] = int(AState.RESTING)
			a["state_timer"] = _rng.randf_range(REST_TIME_MIN, REST_TIME_MAX)

			if is_bird:
				# Pick a tree perch to fly to
				a["perch_arrived"] = false
				if _perch_positions.size() > 0:
					a["target"] = _perch_positions[_rng.randi() % _perch_positions.size()]
				# Bird will glide to perch during RESTING below — no texture swap yet
			else:
				# Show rest / sit frame
				var tex_rest: Texture2D = a["tex_rest"] as Texture2D
				if tex_rest != null:
					sprite.texture = tex_rest
					if (a["atype"] as int) == int(AType.CAT):
						sprite.flip_h = false   # cat_sit faces camera, never mirror

		else:  # RESTING → MOVING
			a["state"] = int(AState.MOVING)
			a["state_timer"] = _rng.randf_range(MOVE_TIME_MIN, MOVE_TIME_MAX)

			if is_bird:
				a["perch_arrived"] = false
				a["target"] = _rand_air_pos()
			else:
				var cur_pos: Vector3 = node.global_position
				a["target"] = _rand_ground_target(cur_pos, a["zone"] as String)

			# Restore walk/fly texture
			sprite.texture = a["tex1"] as Texture2D

		# Re-read state after transition
		state = a["state"] as int

	# ── Ground animals: idle during RESTING ───────────────────────────────
	if state == AState.RESTING and not is_bird:
		return

	# ── Movement ──────────────────────────────────────────────────────────
	var cur := node.global_position
	var tgt : Vector3 = a["target"] as Vector3

	if is_bird:
		var perch_arrived: bool = a["perch_arrived"] as bool

		# Already perched — nothing to do until state timer wakes us
		if state == AState.RESTING and perch_arrived:
			return

		var spd: float = BIRD_GLIDE if state == AState.RESTING else BIRD_SPEED
		var diff       := tgt - cur

		if diff.length() < PERCH_ARRIVE_R:
			if state == AState.RESTING:
				# Land on the perch
				node.global_position  = tgt
				a["perch_arrived"]    = true
				sprite.texture        = a["tex1"] as Texture2D   # wings still = frame 1
			else:
				# Reached air waypoint — pick the next one
				a["target"] = _rand_air_pos()
		else:
			var dir := diff.normalized()
			node.global_position = cur + dir * spd * delta
			# Face left/right based on horizontal motion
			if abs(dir.x) > 0.08:
				sprite.flip_h = dir.x < 0.0

		# Wing-flap animation while airborne (stops when truly perched)
		if not (state == AState.RESTING and (a["perch_arrived"] as bool)):
			a["anim_timer"] = (a["anim_timer"] as float) - delta
			if (a["anim_timer"] as float) <= 0.0:
				a["anim_timer"] = a["frame_rate"] as float
				a["anim_frame"] = 1 - (a["anim_frame"] as int)
				if (a["anim_frame"] as int) == 0:
					sprite.texture = a["tex1"] as Texture2D
				else:
					sprite.texture = a["tex2"] as Texture2D

	else:
		# Ground animal movement
		var xz_diff := Vector2(tgt.x - cur.x, tgt.z - cur.z)

		if xz_diff.length() < 0.4:
			# Reached waypoint — pick another without changing state
			a["target"] = _rand_ground_target(cur, a["zone"] as String)
		else:
			var dir2  := xz_diff.normalized()
			var new_x := cur.x + dir2.x * (a["speed"] as float) * delta
			var new_z := cur.z + dir2.y * (a["speed"] as float) * delta
			var new_sy: int = _builder._surface_y(int(new_x), int(new_z))

			# Boundary safety: don't step off plateau or out of lowland
			var can_move := true
			var zone: String = a["zone"] as String
			if zone == "plateau":
				if new_sy < PLATEAU_Y_MIN or sqrt(new_x * new_x + new_z * new_z) > PLATEAU_RADIUS + 2.0:
					can_move = false
			else:  # lowland
				if new_sy < -22 or new_sy > -3:
					can_move = false

			if can_move:
				node.global_position = Vector3(new_x, float(new_sy) + 1.2, new_z)
				if abs(dir2.x) > 0.08:
					a["facing_right"] = dir2.x > 0.0
					# Side-facing sprites: flip for leftward movement
					sprite.flip_h = not (a["facing_right"] as bool)
			else:
				# Hit boundary — bounce back toward zone centre
				a["target"] = _rand_ground_target(cur, zone)

		# Walk / hop animation (runs during MOVING; RESTING returns early above)
		a["anim_timer"] = (a["anim_timer"] as float) - delta
		if (a["anim_timer"] as float) <= 0.0:
			a["anim_timer"] = a["frame_rate"] as float
			a["anim_frame"] = 1 - (a["anim_frame"] as int)
			if (a["anim_frame"] as int) == 0:
				sprite.texture = a["tex1"] as Texture2D
			else:
				sprite.texture = a["tex2"] as Texture2D
