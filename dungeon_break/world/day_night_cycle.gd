extends Node
## Day/Night cycle for camp world.
##
## Adapted from theLongNights DayNightCycle.gd + JS camp cycle.
## 600s (10 min) full cycle. Interpolates sky colours, sun rotation,
## ambient light, and fog. Only active in the camp (dungeons are always dark).

# ── Cycle timing ─────────────────────────────────────────────────────────────
const FULL_CYCLE_S := 600.0      # 10 real minutes per full day

# ── References ───────────────────────────────────────────────────────────────
var _sun: DirectionalLight3D = null
var _env: WorldEnvironment = null

# ── Clock ────────────────────────────────────────────────────────────────────
var _time: float = 0.25          # 0…1, starts at dawn (0.25 = 6:00)
var _hour: float = 6.0           # 0–24 for display

# ── Sky/light colour keyframes (ported from JS 9-keyframe system) ────────────
# time (0–1), sky_top, sky_horizon, sun_color, sun_energy, ambient_color, ambient_energy, fog_color, fog_density
const KEYFRAMES := [
	# midnight
	{ "t": 0.000, "sky_top": Color(0.02, 0.02, 0.06), "sky_hor": Color(0.05, 0.04, 0.10),
	  "sun_col": Color(0.25, 0.25, 0.45), "sun_nrg": 0.25,
	  "amb_col": Color(0.06, 0.06, 0.12), "amb_nrg": 0.3,
	  "fog_col": Color(0.04, 0.03, 0.08), "fog_den": 0.004 },
	# pre-dawn 4:30
	{ "t": 0.188, "sky_top": Color(0.06, 0.04, 0.14), "sky_hor": Color(0.20, 0.12, 0.22),
	  "sun_col": Color(0.40, 0.30, 0.50), "sun_nrg": 0.35,
	  "amb_col": Color(0.10, 0.08, 0.15), "amb_nrg": 0.35,
	  "fog_col": Color(0.08, 0.06, 0.12), "fog_den": 0.003 },
	# dawn 6:00
	{ "t": 0.250, "sky_top": Color(0.25, 0.20, 0.40), "sky_hor": Color(0.85, 0.50, 0.35),
	  "sun_col": Color(1.0, 0.65, 0.40), "sun_nrg": 0.8,
	  "amb_col": Color(0.25, 0.20, 0.30), "amb_nrg": 0.45,
	  "fog_col": Color(0.30, 0.20, 0.25), "fog_den": 0.003 },
	# morning 9:00
	{ "t": 0.375, "sky_top": Color(0.30, 0.50, 0.80), "sky_hor": Color(0.55, 0.65, 0.80),
	  "sun_col": Color(1.0, 0.95, 0.85), "sun_nrg": 1.3,
	  "amb_col": Color(0.20, 0.22, 0.30), "amb_nrg": 0.55,
	  "fog_col": Color(0.25, 0.25, 0.30), "fog_den": 0.002 },
	# noon 12:00
	{ "t": 0.500, "sky_top": Color(0.35, 0.55, 0.90), "sky_hor": Color(0.60, 0.70, 0.85),
	  "sun_col": Color(1.0, 0.98, 0.92), "sun_nrg": 1.5,
	  "amb_col": Color(0.22, 0.24, 0.32), "amb_nrg": 0.6,
	  "fog_col": Color(0.30, 0.30, 0.35), "fog_den": 0.002 },
	# afternoon 15:00
	{ "t": 0.625, "sky_top": Color(0.30, 0.48, 0.78), "sky_hor": Color(0.55, 0.60, 0.75),
	  "sun_col": Color(1.0, 0.92, 0.80), "sun_nrg": 1.2,
	  "amb_col": Color(0.20, 0.20, 0.28), "amb_nrg": 0.55,
	  "fog_col": Color(0.28, 0.26, 0.30), "fog_den": 0.002 },
	# dusk 18:00
	{ "t": 0.750, "sky_top": Color(0.18, 0.12, 0.30), "sky_hor": Color(0.90, 0.50, 0.25),
	  "sun_col": Color(1.0, 0.55, 0.30), "sun_nrg": 0.7,
	  "amb_col": Color(0.18, 0.14, 0.25), "amb_nrg": 0.40,
	  "fog_col": Color(0.25, 0.15, 0.20), "fog_den": 0.003 },
	# twilight 20:00
	{ "t": 0.833, "sky_top": Color(0.06, 0.05, 0.15), "sky_hor": Color(0.12, 0.08, 0.18),
	  "sun_col": Color(0.35, 0.30, 0.50), "sun_nrg": 0.35,
	  "amb_col": Color(0.10, 0.08, 0.16), "amb_nrg": 0.35,
	  "fog_col": Color(0.08, 0.06, 0.12), "fog_den": 0.003 },
	# deep night 23:00  (wraps toward midnight keyframe)
	{ "t": 0.958, "sky_top": Color(0.03, 0.02, 0.07), "sky_hor": Color(0.06, 0.04, 0.10),
	  "sun_col": Color(0.25, 0.25, 0.45), "sun_nrg": 0.25,
	  "amb_col": Color(0.06, 0.06, 0.12), "amb_nrg": 0.30,
	  "fog_col": Color(0.04, 0.03, 0.08), "fog_den": 0.004 },
]


## Call after adding to tree. Needs references to sun + WorldEnvironment.
func setup(sun: DirectionalLight3D, world_env: WorldEnvironment):
	_sun = sun
	_env = world_env
	# Sync to shared world clock
	_time = GameData.world_time
	_apply_at_time(_time)


func _process(_delta: float):
	if _sun == null or _env == null:
		return

	# Read from the shared GameData clock (GameData._process advances it)
	_time = GameData.world_time
	_hour = _time * 24.0
	_apply_at_time(_time)


## Get the current hour (0–24) for display / game logic.
func get_hour() -> float:
	return _hour


## Get a human-friendly time-of-day string.
func get_time_name() -> String:
	if _hour >= 5.0 and _hour < 12.0:
		return "Morning"
	elif _hour >= 12.0 and _hour < 17.0:
		return "Afternoon"
	elif _hour >= 17.0 and _hour < 21.0:
		return "Evening"
	else:
		return "Night"


# ── Interpolation ────────────────────────────────────────────────────────────

func _apply_at_time(t: float):
	## Find the two surrounding keyframes and lerp between them.
	var kf_a: Dictionary
	var kf_b: Dictionary
	var blend: float = 0.0

	for i in KEYFRAMES.size():
		var next_i: int = (i + 1) % KEYFRAMES.size()
		var ta: float = KEYFRAMES[i]["t"]
		var tb: float = KEYFRAMES[next_i]["t"]

		# Handle wrap-around (last→first keyframe)
		if tb <= ta:
			tb += 1.0

		var tt := t
		if t < ta:
			tt += 1.0

		if tt >= ta and tt < tb:
			kf_a = KEYFRAMES[i]
			kf_b = KEYFRAMES[next_i]
			blend = (tt - ta) / (tb - ta)
			break

	if kf_a.is_empty():
		kf_a = KEYFRAMES[0]
		kf_b = KEYFRAMES[1]
		blend = 0.0

	# Sky material
	var sky_mat: ProceduralSkyMaterial = _env.environment.sky.sky_material as ProceduralSkyMaterial
	if sky_mat:
		sky_mat.sky_top_color = kf_a["sky_top"].lerp(kf_b["sky_top"], blend)
		sky_mat.sky_horizon_color = kf_a["sky_hor"].lerp(kf_b["sky_hor"], blend)
		sky_mat.ground_bottom_color = kf_a["sky_top"].lerp(kf_b["sky_top"], blend) * 0.3
		sky_mat.ground_horizon_color = kf_a["sky_hor"].lerp(kf_b["sky_hor"], blend) * 0.6

	# Sun light
	_sun.light_color = kf_a["sun_col"].lerp(kf_b["sun_col"], blend)
	_sun.light_energy = lerpf(kf_a["sun_nrg"], kf_b["sun_nrg"], blend)

	# Sun rotation — arc across sky
	# t=0.25 (dawn) → sun at horizon, t=0.5 (noon) → overhead, t=0.75 (dusk) → horizon
	var sun_angle := -(t * TAU) + (PI / 2.0)
	_sun.rotation.x = sun_angle

	# Ambient light
	_env.environment.ambient_light_color = kf_a["amb_col"].lerp(kf_b["amb_col"], blend)
	_env.environment.ambient_light_energy = lerpf(kf_a["amb_nrg"], kf_b["amb_nrg"], blend)

	# Fog
	_env.environment.fog_light_color = kf_a["fog_col"].lerp(kf_b["fog_col"], blend)
	_env.environment.fog_density = lerpf(kf_a["fog_den"], kf_b["fog_den"], blend)
