extends VoxelGeneratorScript
## Camp Island terrain generator for Dungeon Break.
##
## Produces a circular island with:
##   - Noise-based organic edges (mimics CA shoreline)
##   - Two Gaussian mountain peaks
##   - Gentle rolling base undulation
##   - Grass on top, dirt underneath, air above
##
## The island is centred at world (0, 0, 0). Radius ~46 voxels with 6-voxel taper.

# ── Block IDs (must match voxel_library.tres order) ──────────────────────────
const AIR   = 0
const DIRT  = 1
const GRASS = 2

const _CHANNEL = VoxelBuffer.CHANNEL_TYPE

# ── Island shape ─────────────────────────────────────────────────────────────
const ISLAND_RADIUS := 46.0   # hard cutoff from centre
const ISLAND_TAPER  :=  6.0   # width of the soft-fade shoreline
const SEA_LEVEL     :=  0     # base Y of the island surface

# ── Gaussian peaks (same as JS camp: two landmark hills) ─────────────────────
# Peak 1 — dominant mountain, east-southeast
const PEAK1_X      :=  16.0
const PEAK1_Z      := -14.0
const PEAK1_HEIGHT :=  7.0
const PEAK1_SIGMA  := 55.0    # controls width (higher = wider)

# Peak 2 — secondary peak, west-northwest
const PEAK2_X      := -18.0
const PEAK2_Z      :=  12.0
const PEAK2_HEIGHT :=  5.0
const PEAK2_SIGMA  := 40.0

# ── Noise ────────────────────────────────────────────────────────────────────
var _noise := FastNoiseLite.new()
var _edge_noise := FastNoiseLite.new()


func _init():
	_noise.seed = 42
	_noise.frequency = 1.0 / 40.0
	_noise.fractal_octaves = 3
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	# Separate noise for shoreline wobble so the edge isn't a perfect circle
	_edge_noise.seed = 1337
	_edge_noise.frequency = 1.0 / 16.0
	_edge_noise.fractal_octaves = 2
	_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX


func _get_used_channels_mask() -> int:
	return 1 << _CHANNEL


## Compute terrain height at world (x, z).
## Returns a float: 0 = sea level, positive = hill.
func _get_height_at(x: float, z: float) -> float:
	# Gaussian peaks
	var p1 := PEAK1_HEIGHT * exp(-((x - PEAK1_X) ** 2 + (z - PEAK1_Z) ** 2) / (2.0 * PEAK1_SIGMA))
	var p2 := PEAK2_HEIGHT * exp(-((x - PEAK2_X) ** 2 + (z - PEAK2_Z) ** 2) / (2.0 * PEAK2_SIGMA))

	# Gentle base undulation (0–0.6 range, keeps flat areas slightly alive)
	var base := (sin(x * 0.08) + cos(z * 0.08)) * 0.3

	# Small noise for micro-variation
	var micro := _noise.get_noise_2d(x, z) * 1.5

	return p1 + p2 + base + micro


## Check if world (x, z) is inside the island boundary.
## Returns probability 0.0–1.0 (used for edge taper).
func _island_mask(x: float, z: float) -> float:
	var dist := sqrt(x * x + z * z)

	# Wobble the edge with noise so it's not a perfect circle
	var wobble := _edge_noise.get_noise_2d(x, z) * 4.0
	var effective_radius := ISLAND_RADIUS + wobble

	if dist > effective_radius:
		return 0.0
	elif dist > effective_radius - ISLAND_TAPER:
		# Smooth taper at shoreline
		return (effective_radius - dist) / ISLAND_TAPER
	else:
		return 1.0


func _generate_block(buffer: VoxelBuffer, origin: Vector3i, _lod: int):
	var block_size := int(buffer.get_size().x)
	var oy := origin.y

	# Quick reject: if the entire chunk is way above or below the terrain range
	# Max possible height is ~PEAK1_HEIGHT + a bit of noise ≈ 10
	var max_terrain_y := int(PEAK1_HEIGHT + 3)

	if oy > max_terrain_y + block_size:
		# Entirely above terrain → all air
		buffer.fill(AIR, _CHANNEL)
		return

	if oy + block_size < -4:
		# Entirely underground (below any valley) → all dirt
		# But only if we're inside the island at the chunk centre
		# For simplicity, fill with dirt (the island mask check happens per-column)
		buffer.fill(DIRT, _CHANNEL)
		# We'll still need to check per-column in the border case, but this is
		# a fast path for deep chunks under the island interior
		return

	# Per-column generation
	var gz := origin.z
	for z in block_size:
		var gx := origin.x
		for x in block_size:
			var mask := _island_mask(float(gx), float(gz))

			if mask <= 0.0:
				# Outside island — all air in this column
				for y in block_size:
					buffer.set_voxel(AIR, x, y, z, _CHANNEL)
			else:
				# Inside island
				var terrain_h := _get_height_at(float(gx), float(gz))

				# Taper: reduce height at edges so the island slopes into void
				terrain_h *= mask

				var height_int := int(round(terrain_h)) + SEA_LEVEL
				var relative_top := height_int - oy

				for y in block_size:
					var gy := oy + y
					if gy > height_int:
						buffer.set_voxel(AIR, x, y, z, _CHANNEL)
					elif gy == height_int:
						buffer.set_voxel(GRASS, x, y, z, _CHANNEL)
					else:
						buffer.set_voxel(DIRT, x, y, z, _CHANNEL)

			gx += 1
		gz += 1

	buffer.compress_uniform_channels()
