extends Node3D
## Cops & Robbers racer: set-up, match flow, camera, FX and HUD.
##
## Boot: calibrate the car, warm up the shaders, then the main menu (menu.gd). A match is four levels (track.gd MAPS),
## each harder than the last, played as a RACER (you + three AI racers, the cops hunt everybody) or as a COP
## (you + AI backup cops chase four AI racers). Every racer has an ARREST bar that fills while a cop is near; a full
## bar = busted. Game modes: STORY (a place to reach per level) and POINTS (points per level, eliminations,
## cop strikes and two rankings: all of that lives in rules.gd). Results screens: results_view.gd.

const VERSION: String = "v0.4.2"

const TrackScript = preload("res://track.gd")
const CarScript = preload("res://car.gd")
const MinimapScript = preload("res://minimap.gd")
const SpeedFxScript = preload("res://speedfx.gd")
const MenuScript = preload("res://menu.gd")
const MarkersScript = preload("res://markers.gd")
const RulesScript = preload("res://rules.gd")
const ResultsScript = preload("res://results_view.gd")

## Shown one at a time during each countdown.
const TIPS: Array = [
	"The red ARREST bar fills when a cop is close. Full bar = busted. Drive away from them!",
	"Cops are the blue dots on the minimap (top right).",
	"Hold SPACE while turning to drift. Drifting refills your nitro fast.",
	"SHIFT = nitro boost. Use it on straights to get away from cops.",
	"Yellow signs mark dirt shortcuts: shorter, but slippery.",
	"Flipped over or stuck? Press R.",
	"You don't need to win. Just finish the laps without getting busted.",
	"Press ESC (or P) any time for the menu, settings and how to play.",
]

## Tips shown during the countdown when you play as the cop.
const COP_TIPS: Array = [
	"Stay within 12 m of a racer and its ARREST bar fills. Full bar = busted!",
	"Racers are the coloured dots on the minimap (top right). Your own dot has a white ring.",
	"SHIFT = nitro boost. Use it on straights to catch up, then drift to refill it.",
	"A bust by another cop breaks your strike. Keep busting racers yourself and every bust scores more.",
	"Dispatch drops spike strips and roadblocks ahead of the racers. Spikes can't hurt cops.",
	"The cops need a minimum number of busts every level. Check NEED at the top left.",
	"Flipped over or stuck? Press R. Press F to turn the siren sound off.",
	"ESC or P = pause menu. G = Garage.",
]

## Tips for the points race (racer side).
const POINTS_TIPS: Array = [
	"Every place pays points: 1st 10, 2nd 7, 3rd 4, 4th 2. Getting busted pays nothing.",
	"The red ARREST bar fills when a cop is close. Full bar = busted = 0 points. Drive away from them!",
	"Cops are the blue dots on the minimap (top right).",
	"Hold SPACE while turning to drift. Drifting refills your nitro fast.",
	"SHIFT = nitro boost. Use it on straights to get away from cops.",
	"Yellow signs mark dirt shortcuts: shorter, but slippery.",
	"Flipped over or stuck? Press R.",
	"When your own race is over, press ENTER to skip ahead to the results.",
	"Eliminated racers keep their points, so they can still beat the survivors in the points ranking.",
]

const COUNTDOWN_TIME: float = 3.0
const ARREST_GRACE: float = 6.0  # no arrests this early in a leg

## Difficulty per leg (same order as track.gd MAPS):
## laps, cops, cop cruise speed, cop top speed, cop start delay (s), obstacle every (s, 0 = none), arrest fill rate
const LEGS: Array = [
	[2, 2, 39.0, 47.0, 4.0, 0.0, 30.0],
	[2, 3, 39.5, 47.5, 3.5, 22.0, 31.0],
	[2, 3, 40.5, 48.0, 3.0, 16.0, 33.0],
	[2, 4, 41.5, 49.0, 2.5, 12.0, 35.0],
]
enum Obs { SPIKES, BARRICADE }

# TITLE = main menu. BUSTED = level failed (ENTER retries). ESCAPED = story won. RESULTS = points screen after a level.
# FINAL = end-of-match standings.
enum State { SETTLE, TEST, LOADING, TITLE, COUNTDOWN, RACING, BUSTED, ESCAPED, PTEST, LEG_CLEAR, RESULTS, FINAL }

# name, colour, AI cruising speed (m/s), lane offset
const ROBBERS: Array = [
	["BLAZE", Color(1.0, 0.45, 0.08), 41.0, -3.0],
	["GHOST", Color(0.2, 0.85, 0.95), 39.0, 3.0],
	["VIPER", Color(0.35, 0.9, 0.25), 37.0, 0.0],
]
# grid slots for robbers: [samples behind the line, lateral offset in metres]
const GRID: Array = [[1, -3.5], [1, 3.5], [3, -3.5], [3, 3.5]]
const PLAYER_SLOT: int = 2
const AI_SLOTS: Array = [0, 1, 3]
const COP_GRID: Array = [[10, 2.5], [13, -2.5], [16, 2.5], [19, -2.5]]
# --- cop side: you drive the police car and bust the racers (pick the side on the New Game page) ---
# The four AI racers: name, colour, AI cruising speed (m/s), lane offset. They take the whole starting grid.
const COP_ROBBERS: Array = [
	["BLAZE", Color(1.0, 0.45, 0.08), 41.0, -3.0],
	["GHOST", Color(0.2, 0.85, 0.95), 39.0, 3.0],
	["VIPER", Color(0.35, 0.9, 0.25), 37.0, 0.0],
	["RAVEN", Color(0.72, 0.3, 0.95), 38.0, 1.5],
]
const COP_AI_SLOTS: Array = [0, 1, 2, 3]
const COP_PLAYER_SLOT: Array = [5, 0.0]   # your police car: samples behind the line, lateral metres (just behind the pack)
## Difficulty per level in the cop modes (same order as LEGS): laps, backup cops (AI), speed bonus for the racers (m/s).
## Cop speeds, arrest rate and obstacles still come from LEGS. How many busts the cops need comes from rules.gd.
const COP_LEGS: Array = [
	[3, 1, 0.0],
	[3, 1, 1.0],
	[3, 2, 2.0],
	[3, 2, 3.0],
]
const WAIT_AFTER_YOU: float = 15.0   # points race: seconds the others get to finish after your own race is over (ENTER skips)
const COP_LEVEL_CAP: float = 360.0   # cop side: a racer still on the road after this long counts as having got away

var state: int = State.SETTLE
var track = null
var player = null
var racers: Array = []      # the racers in THIS level (eliminated ones are left out)
var all_racers: Array = []  # every racer car of the match, eliminated or not
var cops: Array = []        # the AI cops (in cop mode your own police car is cops[0])
var cop_mode: bool = false  # true = you drive the police car and bust the racers (set on the New Game page)
var story: bool = false     # racer side, story mode: a place to reach per level, no points
var rules                   # rules.gd: points, eliminations, cop strikes, rankings (points modes)
var rules_snap: Dictionary = {}   # rules state at the start of the level (for retries)
var results_view            # results_view.gd
var title_next: bool = false      # after the next load / leg start go to the main menu, not the countdown
var built_leg: int = -1           # the level the current track was built for
var start_leg: int = 0
var wait_t: float = 0.0           # points race: seconds since your own race ended
var target_racer = null     # cop mode: the racer closest to you (the arrest bar shows it)
var finish_order: Array = []
var cam: Camera3D
var cam_dir: Vector3 = Vector3(1, 0, 0)
var cam_roll: float = 0.0

var timer: float = 0.0
var contact_t: float = 0.0
var test_phase: int = 0
var test_fwd: float = 0.0
var race_time: float = 0.0
var nearest_cop: float = 999.0
var target_t: float = 0.0
var total_progress: float = 1.0
var fwd_axis: Vector3 = Vector3(0, 0, -1)
var engine_scale: float = 1.0

var leg: int = 0
var laps: int = 2
var run_time: float = 0.0            # whole escape, all legs
var leg_start_time: float = 0.0
var leg_snapshot: Dictionary = {}    # racer -> [busted, arrest, slot] at the start of the leg (for retries)
var obstacles: Array = []            # {node, prog, lat, kind, t0, hit: {}, warned}
var obs_t: float = 0.0
var obs_glow: StandardMaterial3D
var obs_mats: Dictionary = {}       # Color -> StandardMaterial3D (see _obs_mat)
var warmed_map: int = -1             # leg whose shaders are already compiled (see _begin_loading)
var load_steps: Array = []           # [camera transform, warm-rig position] per loading frame
var load_i: int = 0
var load_frame: int = -1
var load_layer: CanvasLayer
var load_bar: ProgressBar
var load_lbl: Label
var warm_rig: Node3D
var hitch_last: int = 0
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var wind: CPUParticles3D
var sfx: Dictionary = {}
var warn_t: float = 0.0
var last_beep: int = -1

# test / tuning hooks (headless only)
var autotest: bool = false
var no_arrest: bool = false
var ptest: String = ""
var pt_t: float = 0.0
var pt_phase: int = 0
var pt_phase_t: float = 0.0
var pt_log_t: float = 0.0
var pt_speed: float = 25.0
var pt_heading0: float = 0.0
var tune: Dictionary = {}
var lap_marks: Array = []
var sim_time: float = 0.0

# HUD
var hud: CanvasLayer
var lbl_lap: Label
var lbl_pos: Label
var lbl_time: Label
var lbl_cop: Label
var lbl_board: Label
var lbl_speed: Label
var lbl_arrest: Label
var lbl_msg: Label
var lbl_sub: Label
var lbl_ver: Label
var bar: ProgressBar
var bar_fill: StyleBoxFlat
var markers: Control        # cop mode: name tags over the racers
var minimap: Control
var bottom: VBoxContainer
var hint: Label
var fx: Control
var nbar: ProgressBar
var lbl_warn: Label
var lbl_tip: Label
var menu
var tip_t: float = 0.0
var tip_cd: Dictionary = {}        # tip id -> time it may show again
var wrong_t: float = 0.0
var stuck_t: float = 0.0
var last_prog: float = 0.0
var used_nitro: bool = false


func _ready() -> void:
	autotest = OS.get_cmdline_user_args().has("autotest")
	if autotest and not OS.get_cmdline_user_args().has("perf"):   # perf = real time, for frame timing
		Engine.time_scale = 4.0
	if OS.get_cmdline_user_args().has("perf"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # uncapped fps = real cost
	tune = _tuning_args()
	ptest = String(tune.get("ptest", ""))
	pt_speed = float(tune.get("ps", 25.0))
	no_arrest = OS.get_cmdline_user_args().has("noarrest")
	_build_world()
	if tune.has("leg"):
		leg = clampi(int(tune["leg"]), 0, LEGS.size() - 1)
	start_leg = leg

	rules = RulesScript.new()
	results_view = ResultsScript.new()
	add_child(results_view)
	menu = MenuScript.new()   # first: it loads the saved settings, car colour and the last match set-up
	add_child(menu)
	menu.version = VERSION
	menu.retry.connect(_restart)
	menu.new_run.connect(_restart_match)
	menu.closed.connect(_on_menu_closed)
	menu.start_requested.connect(_begin_match)
	menu.to_title_requested.connect(_to_title)
	cop_mode = String(menu.cfg["role"]) == "cop"
	if autotest or tune.has("role"):   # tests don't depend on the saved setting: add role=cop to test cop mode
		cop_mode = String(tune.get("role", "robber")) == "cop"
	if ptest != "" or OS.get_cmdline_user_args().has("solo"):
		cop_mode = false
	title_next = not autotest and ptest == ""   # tests start a match right away
	story = autotest or ptest != ""             # tests use the story rules unless they ask for role=cop / mode=points
	_make_track()

	# The start-up calibration car: always a getaway car. _build_field() replaces it with the real field.
	player = _new_car(0, menu.cfg["car_color"], 38.0, "YOU", GRID[PLAYER_SLOT][0], GRID[PLAYER_SLOT][1])
	player.set_meta("slot", PLAYER_SLOT)
	player.auto_drive = autotest
	if tune.has("pspeed"):
		player.ai_speed = float(tune["pspeed"])
	player.calibrating = true
	racers.append(player)
	all_racers.append(player)

	cam = Camera3D.new()
	cam.far = 500.0     # set per map in _apply_map (fog is opaque just before it)
	cam.fov = 68.0
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(cam)
	cam.current = true
	player.cam = cam
	_build_wind()
	_build_sfx()
	_build_loading_ui()

	_build_hud()
	_apply_role_ui()
	_apply_map()
	lbl_msg.text = "WARMING UP"
	lbl_sub.text = ""


# ------------------------------------------------------------------- set-up
func _build_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.ground_bottom_color = Color(0.1, 0.12, 0.14)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# bloom only on things brighter than white (lamps, sirens, flames, windows): lights for free
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	# depth fog: linear from fog_begin to just short of the far plane, so distant scenery fades out
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_curve = 1.4
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0   # only near shadows matter at speed
	add_child(sun)


## Sky, sun and fog for the current map; night legs switch car lights on and sun shadows off.
func _apply_map() -> void:
	var m: Dictionary = track.map
	sky_mat.sky_top_color = m["sky_top"]
	sky_mat.sky_horizon_color = m["sky_hor"]
	sky_mat.ground_horizon_color = m["sky_hor"]
	env.ambient_light_energy = m["ambient"]
	env.fog_light_color = m["fog_col"]
	env.fog_depth_begin = m["fog_begin"]
	# nothing is drawn past the fog: far plane and fog end at the map's view distance
	env.fog_depth_end = track.view_dist()
	cam.far = track.view_dist() + 10.0
	sun.rotation_degrees = m["sun_rot"]
	sun.light_color = m["sun_col"]
	sun.light_energy = m["sun_e"]
	sun.shadow_enabled = not m["night"]
	for c in racers + cops:
		c.set_night(m["night"])


func _make_track() -> void:
	if track != null:
		remove_child(track)   # out of the physics space right now, not at the end of the frame
		track.queue_free()
	track = TrackScript.new()
	track.map = TrackScript.MAPS[leg]
	if tune.has("alat"):
		track.a_lat = float(tune["alat"])
	add_child(track)
	track.build()
	warmed_map = -1   # new materials: compile again
	built_leg = leg
	_set_laps()
	for c in all_racers + cops:
		c.track = track
	if minimap != null:
		minimap.setup(track)


## Laps of the current level (the cop modes run longer levels: there is more time to catch the racers).
func _set_laps() -> void:
	var table: Array = COP_LEGS if cop_mode else LEGS
	laps = int(table[leg][0])
	total_progress = float(laps * track.count)


## Wind streaks in 3D: a ring of thin boxes flying past the camera (in camera space) at speed.
func _build_wind() -> void:
	wind = CPUParticles3D.new()
	wind.amount = 60
	wind.lifetime = 0.7
	wind.local_coords = true
	wind.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	wind.emission_ring_axis = Vector3(0, 0, 1)
	wind.emission_ring_radius = 11.0
	wind.emission_ring_inner_radius = 5.0
	wind.emission_ring_height = 2.0
	wind.position = Vector3(0, 0, -40)
	wind.direction = Vector3(0, 0, 1)
	wind.spread = 0.0
	wind.gravity = Vector3.ZERO
	wind.initial_velocity_min = 70.0
	wind.initial_velocity_max = 90.0
	wind.particle_flag_align_y = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 3.0, 0.03)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.25)
	bm.material = m
	wind.mesh = bm
	wind.emitting = false
	cam.add_child(wind)


func _build_sfx() -> void:
	for n in ["beep", "beep_go", "busted", "escaped", "crash"]:
		var p := AudioStreamPlayer.new()
		p.stream = load("res://Resources/Audio/%s.ogg" % n)
		p.volume_db = -12.0
		add_child(p)
		sfx[n] = p


func _play(n: String) -> void:
	sfx[n].play()


## kind: 0 = player (getaway car), 1 = AI robber, 2 = AI cop, 3 = player (police car, cop mode).
## back/lateral = starting grid slot.
## The start transform must be set BEFORE add_child (teleporting a body in the same
## frame it is created does not stick).
func _new_car(kind: int, color: Color, ai_speed: float, car_name: String, back: int, lateral: float):
	var car = CarScript.new()
	car.track = track
	car.is_player = (kind == 0 or kind == 3)
	car.is_cop = (kind == 2 or kind == 3)
	car.body_color = color
	car.driver_name = car_name
	car.name = car_name
	car.top_speed = 47.0 if kind == 2 else 50.0
	car.ai_speed = ai_speed
	car.fwd_local = fwd_axis
	car.engine_scale = engine_scale
	car.log_events = autotest
	car.cam = cam
	car.transform = _grid_transform(car, back, lateral)
	_place_state(car, back)
	add_child(car)
	return car


func _grid_transform(car, back: int, lateral: float) -> Transform3D:
	var i: int = posmod(track.count - back, track.count)
	var pos: Vector3 = track.points[i] + track.right_at(i) * lateral + Vector3(0, 0.75, 0)
	return car.spawn_transform(pos, track.tangents[i])


## Reset a car's bookkeeping to "standing on the grid".
func _place_state(car, back: int) -> void:
	var i: int = posmod(track.count - back, track.count)
	car.idx = i
	car.prog = float(i - track.count)
	car.watch_prog = car.prog
	car.watch_t = 0.0
	car.arrest = 0.0
	car.busted = false
	car.finished = false
	car.gone = false
	if car.is_inside_tree():
		car.set_ghost(false)
	car.pace = 1.0
	car.controls_enabled = false


# ---------------------------------------------------------------------- HUD
func _label(parent: Node, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 7)
	parent.add_child(l)
	return l


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	fx = SpeedFxScript.new()
	hud.add_child(fx)
	markers = MarkersScript.new()   # cop mode: name tags over the racers
	markers.cam = cam
	markers.racers = racers
	hud.add_child(markers)

	var tl := VBoxContainer.new()
	tl.position = Vector2(22, 14)
	hud.add_child(tl)
	lbl_lap = _label(tl, 36)
	lbl_pos = _label(tl, 30, Color(1, 0.9, 0.4))
	lbl_time = _label(tl, 22)
	lbl_cop = _label(tl, 22)
	lbl_board = _label(tl, 20, Color(0.92, 0.92, 0.92))

	minimap = MinimapScript.new()
	minimap.custom_minimum_size = Vector2(230, 170)
	hud.add_child(minimap)
	minimap.setup(track)

	bottom = VBoxContainer.new()
	bottom.custom_minimum_size = Vector2(460, 0)
	hud.add_child(bottom)
	lbl_speed = _label(bottom, 48)
	lbl_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_arrest = _label(bottom, 22, Color(1.0, 0.45, 0.4))
	lbl_arrest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar = ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(460, 22)
	bar_fill = StyleBoxFlat.new()   # red for robbers, green for cops (see _apply_role_ui)
	bar_fill.bg_color = Color(0.9, 0.15, 0.15)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	bar.add_theme_stylebox_override("fill", bar_fill)
	bar.add_theme_stylebox_override("background", back)
	bottom.add_child(bar)
	nbar = ProgressBar.new()
	nbar.max_value = 1.0
	nbar.show_percentage = false
	nbar.custom_minimum_size = Vector2(460, 12)
	var nfill := StyleBoxFlat.new()
	nfill.bg_color = Color(0.3, 0.7, 1.0)
	nbar.add_theme_stylebox_override("fill", nfill)
	nbar.add_theme_stylebox_override("background", back)
	bottom.add_child(nbar)

	lbl_warn = _label(hud, 34, Color(1.0, 0.75, 0.2))
	lbl_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hint = _label(hud, 17, Color(0.9, 0.9, 0.9))
	hint.text = "W/S  gas / brake     A/D  steer     SPACE  drift (refills nitro)     SHIFT  nitro     R  reset     ESC  menu / help"

	lbl_tip = _label(hud, 24, Color(0.55, 0.9, 1.0))
	lbl_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	lbl_ver = _label(hud, 16, Color(0.8, 0.8, 0.8))
	lbl_ver.text = "Cops & Robbers Racer " + VERSION

	lbl_msg = _label(hud, 96, Color(1, 0.95, 0.5))
	lbl_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	lbl_sub = _label(hud, 30)
	lbl_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Place HUD pieces from the real window size (robust to resizing / web canvas).
func _layout_hud() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	fx.size = vp
	markers.size = vp
	markers.active = cop_mode and state >= State.COUNTDOWN
	minimap.position = Vector2(vp.x - minimap.custom_minimum_size.x - 16.0, 16.0)
	bottom.size = Vector2(460, 0)
	bottom.position = Vector2((vp.x - 460.0) * 0.5, vp.y - bottom.get_combined_minimum_size().y - 44.0)
	hint.position = Vector2(16.0, vp.y - hint.get_combined_minimum_size().y - 12.0)
	lbl_ver.position = Vector2(vp.x - lbl_ver.get_combined_minimum_size().x - 16.0, vp.y - 30.0)
	lbl_msg.size = Vector2(vp.x, 120.0)
	lbl_msg.position = Vector2(0.0, vp.y * 0.36 - 60.0)
	lbl_sub.size = Vector2(vp.x, 50.0)
	lbl_sub.position = Vector2(0.0, vp.y * 0.36 + 70.0)
	lbl_warn.size = Vector2(vp.x, 50.0)
	lbl_warn.position = Vector2(0.0, vp.y * 0.16)
	lbl_tip.size = Vector2(minf(vp.x - 40.0, 900.0), 70.0)
	lbl_tip.position = Vector2((vp.x - lbl_tip.size.x) * 0.5, vp.y * 0.36 + 120.0)
	hint.visible = menu.cfg["controls"]
	minimap.visible = menu.cfg["minimap"]


func _time_str(t: float) -> String:
	return "%d:%02d.%02d" % [int(t) / 60, int(t) % 60, int(fmod(t, 1.0) * 100.0)]


## Racers sorted by race position: finished (in order), then running by progress, then busted.
func _standings() -> Array:
	var running: Array = []
	var out: Array = []
	var busted_list: Array = []
	for r in racers:
		if r.finished:
			continue
		if r.busted:
			busted_list.append(r)
		else:
			running.append(r)
	running.sort_custom(func(a, b): return a.prog > b.prog)
	busted_list.sort_custom(func(a, b): return a.prog > b.prog)
	out.append_array(finish_order)
	out.append_array(running)
	out.append_array(busted_list)
	return out


func _update_hud() -> void:
	if cop_mode:
		_update_cop_hud()
	else:
		var lap: int = clampi(int(floorf(player.prog / float(track.count))) + 1, 1, laps)
		lbl_lap.text = "LEVEL %d/%d  %s   LAP %d/%d" % [leg + 1, LEGS.size(), track.map["name"], lap, laps]
		var order: Array = _standings()
		lbl_pos.text = "POSITION  %d / %d" % [order.find(player) + 1, order.size()]
		if rules.active:
			lbl_pos.text += "     %d PTS" % rules.racer_points(player.driver_name)
		elif story and leg > 0:
			lbl_pos.text += "     NEED TOP %d" % int(RulesScript.STORY_MAX_PLACE[leg])
		lbl_time.text = "TIME  " + _time_str(race_time)
		lbl_cop.text = "NEAREST COP  %d m" % int(nearest_cop)
		lbl_cop.add_theme_color_override("font_color", Color(1, 0.4, 0.35) if nearest_cop < 25.0 else Color.WHITE)
		var board: String = ""
		for i in range(order.size()):
			var r = order[i]
			var tag: String = ""
			if r.busted:
				tag = "  BUSTED"
			elif r.finished:
				tag = "  ESCAPED"
			if rules.active:
				tag += "  (%d)" % rules.racer_points(r.driver_name)
			board += "%d. %s%s\n" % [i + 1, r.driver_name, tag]
		lbl_board.text = board.strip_edges()
		bar.value = player.arrest
		lbl_arrest.text = "ARREST  %d%%" % int(player.arrest)
	var kmh: float = absf(player.forward_speed()) * 3.6
	lbl_speed.text = ("%d mph" % int(kmh * 0.621)) if menu.cfg["mph"] else ("%d km/h" % int(kmh))
	nbar.value = player.nitro
	warn_t -= get_physics_process_delta_time()
	if warn_t <= 0.0:
		lbl_warn.text = ""
	tip_t -= get_physics_process_delta_time()
	if tip_t <= 0.0 and state != State.COUNTDOWN:
		lbl_tip.text = ""


## Cop mode: how many racers are busted / got away, the racer closest to you, and its arrest bar.
func _update_cop_hud() -> void:
	var lead = null
	for r in racers:
		if not r.busted and not r.finished and (lead == null or r.prog > lead.prog):
			lead = r
	var lap: int = laps
	if lead != null:
		lap = clampi(int(floorf(lead.prog / float(track.count))) + 1, 1, laps)
	lbl_lap.text = "LEVEL %d/%d  %s   LEAD RACER LAP %d/%d" % [leg + 1, LEGS.size(), track.map["name"], lap, laps]
	lbl_pos.text = "BUSTED  %d / %d     NEED  %d     YOUR PTS  %s" % [_count_busted(), racers.size(), rules.cop_required(), RulesScript.fmt(rules.cop_points("YOU"))]
	lbl_time.text = "TIME  " + _time_str(race_time)
	target_racer = null
	var best: float = INF
	for r in racers:
		if r.busted or r.finished:
			continue
		var d: float = player.global_position.distance_to(r.global_position)
		if d < best:
			best = d
			target_racer = r
	if target_racer != null:
		lbl_cop.text = "NEAREST RACER  %s  %d m" % [target_racer.driver_name, int(best)]
		lbl_cop.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if best < 25.0 else Color.WHITE)
	else:
		lbl_cop.text = ""
	var board: String = ""
	var order: Array = _standings()
	for i in range(order.size()):
		var r = order[i]
		var tag: String = "  %d%%" % int(r.arrest)
		if r.busted:
			tag = "  BUSTED"
		elif r.finished:
			tag = "  GOT AWAY"
		board += "%d. %s%s\n" % [i + 1, r.driver_name, tag]
	board += "\nCOPS"
	for n in rules.cop_board_points():   # the other cops compete with you
		board += "\n%s   %s pts   %d busts" % [n, RulesScript.fmt(rules.cop_points(n)), rules.cop_elims(n)]
	lbl_board.text = board.strip_edges()
	if target_racer != null and best < 45.0:
		bar.value = target_racer.arrest
		lbl_arrest.text = "ARRESTING  %s  %d%%" % [target_racer.driver_name, int(target_racer.arrest)]
	else:
		bar.value = 0.0
		lbl_arrest.text = "NO RACER IN REACH"


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	sim_time += delta
	menu.can_pause = not autotest and ptest == "" and state >= State.COUNTDOWN
	if state < State.LOADING:   # start-up calibration fills the first part of the loading bar
		load_bar.value = minf(15.0, load_bar.value + delta * 8.0)
	match state:
		State.SETTLE:
			_state_settle(delta)
		State.TEST:
			_state_test(delta)
		State.LOADING:
			_state_loading()
		State.COUNTDOWN:
			_state_countdown(delta)
		State.RACING:
			_state_racing(delta)
		State.BUSTED, State.ESCAPED:
			_state_over(delta)
		State.LEG_CLEAR:
			_state_leg_clear(delta)
		State.RESULTS:
			_state_results(delta)
		State.FINAL:
			_state_final(delta)
		State.PTEST:
			_state_ptest(delta)
	if state != State.LOADING:
		_update_camera(delta)
	_layout_hud()
	if state >= State.COUNTDOWN and state != State.PTEST:
		_update_hud()
	if autotest:
		_autotest_log(delta)


## 1) let the player's car drop onto its springs
func _state_settle(delta: float) -> void:
	player.engine_force = 0.0
	player.brake = 30.0
	if player.wheels_in_contact() >= 4:
		contact_t += delta
	timer += delta
	if contact_t > 0.4 or timer > 3.0:
		state = State.TEST
		timer = 0.0
		test_fwd = 0.0
		player.brake = 0.0


## 2) self-test, so the same code works whatever the engine's force units and
##    forward axis are:  phase 0 measures how hard the engine pushes (and sets the
##    engine scale), phase 1 re-runs at full power to see which way is "forward".
##    This only ever runs once, at start-up; restarting a race skips it.
func _state_test(delta: float) -> void:
	timer += delta
	player.brake = 0.0
	var v: Vector3 = player.linear_velocity
	if test_phase == 0:
		player.engine_force = CarScript.ENGINE_FORCE
		if timer >= 0.5:
			engine_scale = clampf(3.5 / maxf(v.length(), 0.03), 0.3, 150.0)
			player.engine_scale = engine_scale
			print("[calibration] speed after 0.5s test: %.3f m/s -> engine scale %.1f" % [v.length(), engine_scale])
			test_phase = 1
			timer = 0.0
			test_fwd = 0.0
	else:
		player.engine_force = CarScript.ENGINE_FORCE * engine_scale
		test_fwd += v.dot(-player.global_transform.basis.z) * delta
		if timer >= 0.8:
			fwd_axis = Vector3(0, 0, -1) if test_fwd >= 0.0 else Vector3(0, 0, 1)
			print("[calibration] speed %.2f m/s, travelled %.2f m along -Z -> forward = %s" % [v.length(), test_fwd, str(fwd_axis)])
			player.calibrating = false
			player.set_forward(fwd_axis)
			_build_field()


## 3) spawn the rest of the field and put everyone on the grid
func _build_field() -> void:
	var solo: bool = OS.get_cmdline_user_args().has("solo")
	if autotest and ptest == "" and not solo:
		_begin_match()   # tests start a match right away (no main menu); this builds the field too
		return
	if ptest == "" and not solo:
		_spawn_field()
	elif ptest != "":
		track.get_node("Walls").queue_free()
	_start_leg()
	if ptest != "":
		state = State.PTEST


## Throw away every car (the start-up calibration car too) and build the field for the current side: your car (the
## getaway car in your colour, or the police car in cop mode) plus the AI racers. You are a racer: ROBBERS fill the
## grid around you. You are the cop: all four racers (COP_ROBBERS) are AI and take the whole grid.
func _spawn_field() -> void:
	for c in all_racers + cops:
		if is_instance_valid(c):
			remove_child(c)
			c.queue_free()
	racers.clear()
	all_racers.clear()
	cops.clear()
	if cop_mode:
		player = _new_car(3, Color.WHITE, 38.0, "YOU", COP_PLAYER_SLOT[0], COP_PLAYER_SLOT[1])
	else:
		player = _new_car(0, menu.cfg["car_color"], 38.0, "YOU", GRID[PLAYER_SLOT][0], GRID[PLAYER_SLOT][1])
		player.set_meta("slot", PLAYER_SLOT)
		all_racers.append(player)
	player.auto_drive = autotest
	if tune.has("pspeed"):
		player.ai_speed = float(tune["pspeed"])
	markers.me = player
	var specs: Array = COP_ROBBERS if cop_mode else ROBBERS
	var slots: Array = COP_AI_SLOTS if cop_mode else AI_SLOTS
	for k in range(specs.size()):
		var spec: Array = specs[k]
		var slot: Array = GRID[slots[k]]
		var ai = _new_car(1, spec[1], spec[2], spec[0], slot[0], slot[1])
		ai.lane = spec[3]
		ai.set_meta("slot", slots[k])
		ai.set_meta("base_speed", spec[2])
		all_racers.append(ai)
	for r in all_racers:
		racers.append(r)


## The pause menu closed (Garage): a new car colour repaints your car (and its minimap dot) at once.
func _on_menu_closed() -> void:
	if player != null and not cop_mode:
		player.set_body_color(menu.cfg["car_color"])
		_refresh_minimap()


## Everything on screen that depends on the role: the controls line, the arrest bar colour, the tags over the racers.
func _apply_role_ui() -> void:
	if cop_mode:
		hint.text = "W/S  gas / brake     A/D  steer     SPACE  drift (refills nitro)     SHIFT  nitro     F  siren sound     R  reset     G  garage     ESC  menu / help"
		bar_fill.bg_color = Color(0.2, 0.8, 0.35)
		lbl_arrest.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6))
	else:
		hint.text = "W/S  gas / brake     A/D  steer     SPACE  drift (refills nitro)     SHIFT  nitro     R  reset     G  garage     ESC  menu / help"
		bar_fill.bg_color = Color(0.9, 0.15, 0.15)
		lbl_arrest.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	markers.active = cop_mode


## The minimap dots: racers in their own colour, cops in blue. Your own dot gets a white ring.
func _refresh_minimap() -> void:
	var items: Array = []
	for r in racers:
		items.append([r, r.body_color, r == player])
	for c in cops:
		items.append([c, Color(0.3, 0.55, 1.0), c == player])
	minimap.items = items


## Grid slots for the racers of this level. `order` = the racers best first (the previous level's result): they line up
## front to back. Without an order (the first level) you start in the middle of the pack, or, as the cop, the four
## AI racers take the whole grid.
func _assign_slots(order: Array = []) -> void:
	if not order.is_empty():
		for k in range(order.size()):
			order[k].set_meta("slot", mini(k, GRID.size() - 1))
	elif cop_mode:
		for k in range(racers.size()):
			racers[k].set_meta("slot", COP_AI_SLOTS[mini(k, COP_AI_SLOTS.size() - 1)])
	else:
		player.set_meta("slot", PLAYER_SLOT)
		var k: int = 0
		for r in racers:
			if r != player:
				r.set_meta("slot", AI_SLOTS[mini(k, AI_SLOTS.size() - 1)])
				k += 1


## Starting slot [samples behind the line, lateral metres] of cops[k]. In cop mode cops[0] is your police car,
## right behind the racers; the backup cops line up further back (COP_GRID).
func _cop_slot(k: int) -> Array:
	if cop_mode:
		return COP_PLAYER_SLOT if k == 0 else COP_GRID[k - 1]
	return COP_GRID[k]


func _count_busted() -> int:
	var n: int = 0
	for r in racers:
		if r.busted:
			n += 1
	return n


func _count_away() -> int:
	var n: int = 0
	for r in racers:
		if r.finished and not r.busted:
			n += 1
	return n


## Cops for this leg (more, faster, earlier each leg), the minimap, lights, then the grid.
func _start_leg() -> void:
	for c in cops:
		if c == player:
			continue   # your police car (cop mode) stays for the whole run
		remove_child(c)
		c.queue_free()
	cops.clear()
	if cop_mode:
		cops.append(player)
	if ptest == "" and not OS.get_cmdline_user_args().has("solo"):
		var backup: int = int(COP_LEGS[leg][1]) if cop_mode else int(LEGS[leg][1])
		for k in range(backup):
			var cop = _new_car(2, Color.WHITE, LEGS[leg][2], "COP %d" % (k + 1), COP_GRID[k][0], COP_GRID[k][1])
			cop.top_speed = LEGS[leg][3]
			cop.lane = COP_GRID[k][1] * 0.6
			cops.append(cop)
	racers.clear()   # the racers of this level: everybody who is not eliminated
	for r in all_racers:
		var out: bool = rules.is_out(r.driver_name)
		r.visible = not out
		r.process_mode = Node.PROCESS_MODE_DISABLED if out else Node.PROCESS_MODE_INHERIT
		if not out:
			racers.append(r)
	if cop_mode:   # the racers get quicker level by level
		for r in racers:
			r.ai_speed = float(r.get_meta("base_speed", 38.0)) + float(COP_LEGS[leg][2])
	for o in obstacles:
		if is_instance_valid(o["node"]):
			o["node"].queue_free()
	obstacles.clear()
	obs_t = LEGS[leg][5]
	_refresh_minimap()
	_apply_map()
	leg_snapshot.clear()
	for r in racers:
		leg_snapshot[r] = [r.busted, r.arrest, r.get_meta("slot")]
	leg_start_time = run_time
	if autotest:
		for sc in track.shortcuts:
			print("[shortcut] %s a=%d b=%d (%d m cut vs %d m road)" % [track.map["name"], sc["a"], sc["b"], int(sc["pts"][0].distance_to(sc["pts"][-1])), int((sc["b"] - sc["a"]) * track.spacing)])
	_reset_grid()
	if ptest == "" and warmed_map != leg and DisplayServer.get_name() != "headless":   # headless draws no frames
		_begin_loading()
	else:
		load_layer.visible = false
		_after_load()


## The level is built and its shaders are warm: on to the main menu (boot, or back from a match) or the countdown.
func _after_load() -> void:
	if title_next:
		title_next = false
		_enter_title()
	else:
		state = State.COUNTDOWN
		_begin_countdown()


## Teleport everybody back to their starting slot (used at boot and on restart).
func _reset_grid() -> void:
	for r in racers:
		var gs: Array = GRID[r.get_meta("slot")]
		var keep: Array = leg_snapshot.get(r, [false, 0.0])
		r.teleport(_grid_transform(r, gs[0], gs[1]))
		_place_state(r, gs[0])
		r.busted = keep[0]
		r.arrest = keep[1]
		r.nitro = 1.0
		r.spiked_t = 0.0
		r.set_ghost(r.busted)
	for k in range(cops.size()):
		var c = cops[k]
		var slot: Array = _cop_slot(k)
		c.teleport(_grid_transform(c, slot[0], slot[1]))
		_place_state(c, slot[0])
		c.target_car = null
		c.nitro = 1.0
		c.spiked_t = 0.0


func _begin_countdown() -> void:
	timer = 0.0
	race_time = 0.0
	nearest_cop = 999.0
	finish_order.clear()
	lap_marks.clear()
	last_beep = -1
	fx.fade = 1.0
	wrong_t = 0.0
	stuck_t = 0.0
	last_prog = player.prog
	wait_t = 0.0
	hud.visible = true
	results_view.hide_screen()
	var tips: Array = COP_TIPS if cop_mode else TIPS
	if rules.active and not cop_mode:
		tips = POINTS_TIPS
	var tip: String = ("TIP: " + tips[randi() % tips.size()]) if menu.cfg["tips"] else ""
	var rule: String = rules.rules_line() if rules.active else _story_line()
	lbl_tip.text = (rule + "\n" + tip).strip_edges()
	lbl_msg.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	cam_dir = player.forward_world()
	cam_dir.y = 0.0
	cam_dir = cam_dir.normalized()


## A failed level (story, or too few busts as the cop) is retried as it started; the points are restored too.
## A won story goes back to the main menu. No reload, no recalibration.
func _restart() -> void:
	tip_t = 0.0
	if state == State.ESCAPED:
		_to_title()
		return
	if rules.active:
		rules.restore(rules_snap)
	run_time = leg_start_time
	for r in racers:   # undo whatever happened during the failed attempt
		var s: Array = leg_snapshot[r]
		r.busted = s[0]
		r.arrest = s[1]
		r.set_meta("slot", s[2])
	_start_leg()


## Load a level's map and set the grid up. `fresh` = the first level of a match (original grid, clock at zero).
## Every level starts with all remaining racers back on the road and their arrest bars empty.
func _goto_leg(i: int, fresh: bool) -> void:
	var order: Array = []   # the racers best first (last level's result), for the grid
	if not fresh:
		if rules.active:
			for n in rules.last_rank:
				for r in all_racers:
					if r.driver_name == n and not rules.is_out(n):
						order.append(r)
		else:
			order = _standings()
	leg = i
	if i != built_leg:
		_make_track()
	_set_laps()
	if fresh:
		run_time = 0.0
	for r in all_racers:
		r.busted = false
		r.arrest = 0.0
	if rules.active:
		rules.begin_level(i, _scoring_cops())
		rules_snap = rules.snapshot()
		for r in all_racers:   # eliminated racers are not on the grid
			if rules.is_out(r.driver_name):
				order.erase(r)
	_assign_slots(order)
	_start_leg()


# ------------------------------------------------------------------ the match
## START on the New Game page (the tests call it straight away): build the field for the chosen side and play level 1.
func _begin_match() -> void:
	cop_mode = String(menu.cfg["role"]) == "cop"
	var mode: String = String(menu.cfg["mode"])
	if autotest:   # tests: role=cop / mode=points / elim_last=1 ... on the command line (default: the story rules)
		cop_mode = String(tune.get("role", "robber")) == "cop"
		mode = String(tune.get("mode", "points" if cop_mode else "story"))
	story = (not cop_mode) and mode == "story"
	title_next = false
	_apply_role_ui()
	_spawn_field()
	rules.reset()
	if not story:
		rules.start_match(_match_config(), _racer_specs())
	results_view.hide_screen()
	_goto_leg(start_leg, true)


func _restart_match() -> void:
	_begin_match()


## The settings of this match for rules.gd (from the New Game page; in the tests from the command line).
func _match_config() -> Dictionary:
	var c: Dictionary = menu.cfg
	if autotest:
		return {
			"side": "cop" if cop_mode else "racer",
			"elim_last": int(tune.get("elim_last", 0)) == 1, "elim_busted": int(tune.get("elim_busted", 0)) == 1,
			"ending": String(tune.get("ending", "survival")), "scaled": String(tune.get("scale", "scaled")) == "scaled",
			"share": String(tune.get("share", "own")),
		}
	return {
		"side": "cop" if cop_mode else "racer",
		"elim_last": bool(c["elim_last"]), "elim_busted": bool(c["elim_busted"]),
		"ending": String(c["ending"]), "scaled": String(c["cop_scale"]) == "scaled", "share": String(c["cop_share"]),
	}


## Every racer of the match for rules.gd, in grid order.
func _racer_specs() -> Array:
	var specs: Array = []
	for r in all_racers:
		specs.append({"name": r.driver_name, "human": r == player})
	return specs


## The cops that score points this level (cop side): you and the AI backup cops.
func _scoring_cops() -> Array:
	var names: Array = []
	if cop_mode:
		names.append("YOU")
		for k in range(int(COP_LEGS[leg][1])):
			names.append("COP %d" % (k + 1))
	return names


## One line about this level's rules (story mode), shown during the countdown.
func _story_line() -> String:
	if not story:
		return ""
	var need: int = int(RulesScript.STORY_MAX_PLACE[leg])
	if need >= 4:
		return "Level %d: just survive. Do not get busted!" % (leg + 1)
	if need == 1:
		return "Level %d: win it to escape!" % (leg + 1)
	return "Level %d: finish in the top %d." % [leg + 1, need]


## The main menu: shown after the first warm-up and when a match is left. Nothing runs behind it.
func _enter_title() -> void:
	state = State.TITLE
	hud.visible = false
	fx.fade = 0.0
	results_view.hide_screen()
	menu.open_title()


## Back to the main menu (from the pause menu or after a match): a fresh field in your saved car as the backdrop.
func _to_title() -> void:
	rules.reset()
	story = false
	cop_mode = String(menu.cfg["role"]) == "cop"
	title_next = true
	results_view.hide_screen()
	_apply_role_ui()
	_spawn_field()
	_set_laps()
	_assign_slots()
	_start_leg()


## 4) 3-2-1-GO
func _state_countdown(delta: float) -> void:
	timer += delta
	var left: float = COUNTDOWN_TIME - timer
	fx.fade = maxf(0.0, fx.fade - delta * 2.0)
	if left > 0.0:
		var n: int = int(ceilf(left))
		if n != last_beep:
			last_beep = n
			_play("beep")
		lbl_msg.text = str(n)
		if cop_mode:
			lbl_sub.text = "LEVEL %d/%d  %s  (%s)   %d laps, %d racers: bust at least %d" % [leg + 1, LEGS.size(), track.map["name"], track.map["time"], laps, racers.size(), rules.cop_required()]
		else:
			lbl_sub.text = "LEVEL %d/%d  %s  (%s)   %d laps, %d racers, %d cops" % [leg + 1, LEGS.size(), track.map["name"], track.map["time"], laps, racers.size(), cops.size()]
	else:
		_play("beep_go")
		state = State.RACING
		race_time = 0.0
		lbl_msg.text = "GO!"
		lbl_sub.text = ""
		lbl_tip.text = ""
		timer = 0.0
		for r in racers:
			r.controls_enabled = true
		for c in cops:
			c.controls_enabled = (c == player)  # AI cops are released after the leg's cop delay; your police car (cop mode) goes now


## 5) the race
func _state_racing(delta: float) -> void:
	race_time += delta
	run_time += delta
	timer += delta
	if timer > 1.2:
		lbl_msg.text = ""
	_update_pace()
	_update_cop_targets(delta)
	_update_arrests(delta)
	_update_obstacles(delta)
	_update_finishes()
	_check_level_end(delta)
	if player.on_dirt and warn_t <= 0.0:
		_warn("SHORTCUT  -  loose dirt", 0.5)
	_update_tips(delta)


## Plain-language hints for whatever the player seems to be struggling with.
func _update_tips(delta: float) -> void:
	var spd: float = player.linear_velocity.length()
	var dp: float = player.prog - last_prog
	last_prog = player.prog
	wrong_t = wrong_t + delta if dp < 0.0 and spd > 6.0 else 0.0
	if wrong_t > 1.5 and warn_t <= 0.0 and not player.busted:
		_warn("WRONG WAY!  Turn around  (or press R)", 1.0)
	if player.boosting:
		used_nitro = true
	if not menu.cfg["tips"] or player.busted or player.finished:
		return
	stuck_t = stuck_t + delta if spd < 1.5 else 0.0
	if race_time > 4.0 and race_time < 6.0 and spd < 2.0:
		_tip("go", "Hold W (or the UP arrow) to drive!")
	elif stuck_t > 4.0 and race_time > 8.0:
		_tip("stuck", "Stuck? Press R to put your car back on the road.")
	elif cop_mode:
		if player.nitro < 0.05:
			_tip("nitro_out", "Out of nitro. Drift (hold SPACE while turning) to refill it fast.")
		elif not used_nitro and race_time > 12.0 and player.nitro > 0.95:
			_tip("nitro", "Your nitro is full (blue bar). Press SHIFT to catch up with the racers!")
	elif player.arrest > 25.0 and nearest_cop < 14.0:
		_tip("arrest", "A cop is right on you! Get away (SHIFT for nitro) before the red bar fills.")
	elif player.spiked_t > 0.0:
		_tip("spikes", "Spikes popped your tyres! Grip comes back in a few seconds. Avoid the flashing strips.")
	elif player.nitro < 0.05:
		_tip("nitro_out", "Out of nitro. Drift (hold SPACE while turning) to refill it fast.")
	elif not used_nitro and race_time > 12.0 and player.nitro > 0.95:
		_tip("nitro", "Your nitro is full (blue bar). Press SHIFT for a speed boost!")


## Show a tip unless the same one was shown in the last 40 s.
func _tip(id: String, text: String) -> void:
	if tip_t > 0.0 or sim_time < float(tip_cd.get(id, -1.0)):
		return
	tip_cd[id] = sim_time + 40.0
	lbl_tip.text = "TIP: " + text
	tip_t = 5.0


## Rubber-banding. Cops speed up when far behind their target and ease off when
## ahead of it. AI robbers stay roughly within reach of the player.
func _update_pace() -> void:
	for c in cops:
		if c.target_car == null:
			c.pace = 0.9
			continue
		var gap: float = (c.target_car.prog - c.prog) * track.spacing  # + = target is ahead of the cop
		if gap > 0.0:
			c.pace = clampf(0.94 + gap / 500.0, 0.94, 1.08)
		else:
			c.pace = clampf(0.92 + gap / 100.0, 0.55, 0.92)
	for r in racers:
		if r == player:
			continue
		var gp: float = (r.prog - player.prog) * track.spacing  # + = this robber is ahead of the player
		if gp > 90.0:
			r.pace = clampf(1.0 - (gp - 90.0) / 700.0, 0.85, 1.0)
		elif gp < -50.0:
			r.pace = clampf(1.0 + (-gp - 50.0) / 800.0, 1.0, 1.07)
		else:
			r.pace = 1.0


## Each cop hunts the closest robber still on the road (slightly biased to the player).
func _update_cop_targets(delta: float) -> void:
	target_t -= delta
	if target_t > 0.0:
		return
	target_t = 0.4
	for c in cops:
		if c == player and not c.auto_drive:
			continue   # you choose your own target
		var best = null
		var best_score: float = INF
		for r in racers:
			if r.busted or r.finished:
				continue
			var sc: float = c.global_position.distance_to(r.global_position)
			if r == player:
				sc *= 0.8
			if sc < best_score:
				best_score = sc
				best = r
		c.target_car = best
		if c != player:
			c.controls_enabled = best != null and race_time > LEGS[leg][4]
	var near_cop = null
	for c in cops:
		c.siren_on = false
		if near_cop == null or c.global_position.distance_squared_to(cam.global_position) < near_cop.global_position.distance_squared_to(cam.global_position):
			near_cop = c
	if near_cop != null:
		near_cop.siren_on = true


func _update_arrests(delta: float) -> void:
	nearest_cop = 999.0
	if race_time < ARREST_GRACE:
		return
	for r in racers:
		if r.busted or r.finished:
			continue
		var rate: float = 0.0
		var capt: Array = []   # the cops within reach: they all share this arrest
		for c in cops:
			var d: float = c.global_position.distance_to(r.global_position)
			if r == player:
				nearest_cop = minf(nearest_cop, d)
			rate += clampf((12.0 - d) / 12.0, 0.0, 1.0) * LEGS[leg][6]   # every cop, the AI ones too, fills the bar equally fast
			if d < 12.0:
				capt.append(c.driver_name)
		if rate > 0.0:
			r.arrest += rate * delta
		else:
			r.arrest -= 12.0 * delta
		r.arrest = clampf(r.arrest, 0.0, 100.0)
		if r.arrest >= 100.0 and not no_arrest:
			_bust(r, capt)


## A racer's arrest bar is full. `capturers` = the cops that were within reach (they share the bust in cop mode).
func _bust(r, capturers: Array) -> void:
	r.busted = true
	r.controls_enabled = false
	r.set_ghost(true)
	var pts: Dictionary = {}
	if rules.active:
		pts = rules.record_bust(r.driver_name, capturers)
	if cop_mode:   # you or a backup cop busted a racer
		_play("beep_go")
		var msg: String = "%s BUSTED!   %d / %d" % [r.driver_name, _count_busted(), racers.size()]
		if pts.has("YOU"):
			msg += "   +%s pts" % RulesScript.fmt(float(pts["YOU"]))
		_warn(msg, 2.5)
		return
	if r == player:
		_play("busted")
		if story:   # story: the level is lost, retry it
			_end_race(State.BUSTED, 0)
		else:       # points race: 0 points for this level, the race goes on without you
			_warn("BUSTED!  0 points this level", 4.0)
			lbl_tip.text = "ENTER  =  skip ahead to the results"
			tip_t = 999.0
	elif not story:
		_warn("%s BUSTED" % r.driver_name, 2.0)


func _update_finishes() -> void:
	for r in racers:
		if r.finished or r.busted:
			continue
		if r.prog < total_progress:
			continue
		r.finished = true
		finish_order.append(r)
		if cop_mode:
			_racer_leaves(r, "%s GOT AWAY!" % r.driver_name)
		elif story:
			if r == player:
				_story_finish(finish_order.size())
		elif r == player:
			_player_finished(finish_order.size())
		else:
			_racer_leaves(r, "%s FINISHED %s" % [r.driver_name, RulesScript.ordinal(finish_order.size())])


## Story: you crossed the line. Good enough for this level's place? Then on to the next level, else retry.
func _story_finish(place: int) -> void:
	var lenient: bool = autotest and int(tune.get("strict", 0)) != 1   # the dev tests clear every level like before
	if lenient or RulesScript.story_ok(leg, place):
		_play("escaped")
		_end_race(State.LEG_CLEAR if leg < LEGS.size() - 1 else State.ESCAPED, place)
	else:
		_play("busted")
		_end_race(State.BUSTED, place)


## Points race: you crossed the line. The others still have to finish (or ENTER skips ahead).
func _player_finished(place: int) -> void:
	_play("escaped")
	_warn("YOU FINISHED %s" % RulesScript.ordinal(place), 4.0)
	player.controls_enabled = false
	player.set_ghost(true)
	player.gone = true   # the other drivers ignore your parked car
	lbl_tip.text = "Waiting for the others...   ENTER  =  skip ahead"
	tip_t = 999.0


## A racer crossed the line (it got away, or finished its race): its car drives off (hidden, no collisions) and
## nobody chases it any more.
func _racer_leaves(r, msg: String) -> void:
	r.gone = true
	r.controls_enabled = false
	r.engine_force = 0.0
	r.brake = CarScript.BRAKE_FORCE
	r.set_ghost(true)
	r.set_sounds(false)
	r.visible = false
	r.process_mode = Node.PROCESS_MODE_DISABLED
	_warn(msg, 2.5)


## Points modes: is the level over? Racer side: when everybody has finished or been busted, or WAIT_AFTER_YOU seconds
## after your own race ended (ENTER skips). Cop side: when every racer is busted or got away; the level is failed as
## soon as the quota of busts is out of reach. Story ends in _update_finishes / _bust instead.
func _check_level_end(delta: float) -> void:
	if story or not rules.active or state != State.RACING:
		return
	var unresolved: int = 0
	for r in racers:
		if not r.busted and not r.finished:
			unresolved += 1
	if cop_mode:
		if race_time > COP_LEVEL_CAP and unresolved > 0:   # a racer is stuck somewhere: it got away
			for r in racers:
				if not r.busted and not r.finished:
					r.finished = true
					finish_order.append(r)
					_racer_leaves(r, "%s GOT AWAY!" % r.driver_name)
			unresolved = 0
		if not rules.cop_can_pass(_count_away()):
			_play("busted")
			_end_race(State.BUSTED, 0)
		elif unresolved == 0:
			_finish_points_level()
		return
	var mine_over: bool = player.busted or player.finished
	if mine_over:
		wait_t += delta
	var skip: bool = wait_t > 1.0 and (Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER))
	if unresolved == 0 or (mine_over and (wait_t > WAIT_AFTER_YOU or skip)):
		_finish_points_level()


## Points modes: hand out the points, eliminate, and show the results of the level.
func _finish_points_level() -> void:
	state = State.RESULTS
	timer = 0.0
	for r in racers:
		r.controls_enabled = false
	for c in cops:
		c.controls_enabled = false
	var fin: Array = []
	for r in finish_order:
		fin.append(r.driver_name)
	var running: Array = []
	for r in _standings():
		if not r.finished and not r.busted:
			running.append(r.driver_name)
	var res: Dictionary = rules.finish_level(fin, running)
	var scr: Dictionary = rules.level_screen(res)
	var title: String = "LEVEL %d / %d  -  %s" % [leg + 1, LEGS.size(), track.map["name"]]
	var foot: String = "ENTER  =  final standings"
	if not rules.over:
		foot = "ENTER  =  next level:  %s" % TrackScript.MAPS[leg + 1]["name"]
	hud.visible = false
	results_view.show_screen(title, scr["sub"], "", scr["tables"], foot)
	_play("escaped")


func _state_results(delta: float) -> void:
	timer += delta
	if autotest and timer > 1.0:
		_results_continue()
	elif timer > 0.7 and (Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER)):
		_results_continue()


func _results_continue() -> void:
	if rules.over:
		_show_final()
	else:
		results_view.hide_screen()
		_goto_leg(leg + 1, false)


func _show_final() -> void:
	state = State.FINAL
	timer = 0.0
	var scr: Dictionary = rules.final_screen()
	results_view.show_screen(scr["title"], scr["line1"], scr["line2"], scr["tables"], "ENTER  =  main menu")


func _state_final(delta: float) -> void:
	timer += delta
	if autotest:
		return   # _autotest_log prints the result and quits
	if timer > 0.7 and (Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER)):
		_to_title()


## Story (and a failed cop level): the level is over. BUSTED = failed, ENTER retries. LEG_CLEAR = on to the next level
## by itself. ESCAPED = the story is won, ENTER goes back to the main menu.
func _end_race(result: int, place: int) -> void:
	state = result
	timer = 0.0
	for r in racers:
		r.controls_enabled = false
	for c in cops:
		c.controls_enabled = false
	if cop_mode:
		_cop_fail_text()
		return
	var ordinal: String = RulesScript.ordinal(place)
	if result == State.BUSTED:
		lbl_msg.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		if player.busted:
			lbl_msg.text = "BUSTED!"
			lbl_sub.text = "The cops got you on level %d.   Press ENTER to retry the level." % (leg + 1)
			lbl_tip.text = "TIP: when the red ARREST bar starts filling, use nitro (SHIFT) to get away from the cop."
		else:
			lbl_msg.text = "TOO SLOW!"
			lbl_sub.text = "You finished %s but needed the top %d.   Press ENTER to retry the level." % [ordinal, int(RulesScript.STORY_MAX_PLACE[leg])]
			lbl_tip.text = "TIP: use nitro (SHIFT) on the straights, and drift (SPACE while turning) to refill it."
		tip_t = 999.0
	elif result == State.LEG_CLEAR:
		lbl_msg.text = "LEVEL %d CLEAR" % (leg + 1)
		lbl_msg.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		lbl_sub.text = "%s in %s.   Next: %s (%s)" % [ordinal, _time_str(race_time), TrackScript.MAPS[leg + 1]["name"], TrackScript.MAPS[leg + 1]["time"]]
	else:
		lbl_msg.text = "YOU ESCAPED!"
		lbl_msg.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		lbl_sub.text = "Out of the city, %s on the last level. Total %s.   Press ENTER for the main menu." % [ordinal, _time_str(run_time)]


## Cop side: too many racers got away to make the quota of busts. ENTER retries the level.
func _cop_fail_text() -> void:
	lbl_msg.text = "THEY GOT AWAY!"
	lbl_msg.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	lbl_sub.text = "The cops needed %d busts: %d racers got away, %d busted.   Press ENTER to retry the level." % [rules.cop_required(), _count_away(), _count_busted()]
	lbl_tip.text = "TIP: stay within 12 m of a racer until its ARREST bar is full. Use nitro (SHIFT) to catch up."
	tip_t = 999.0


func _state_over(_delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		_restart()


## Short pause on the result, fade to black, then the next map (the chase continues).
func _state_leg_clear(delta: float) -> void:
	timer += delta
	if timer > 2.5:
		fx.fade = minf(1.0, fx.fade + delta * 2.5)
	if timer > 3.0 and fx.fade >= 1.0:
		_goto_leg(leg + 1, false)


func _warn(text: String, t: float = 2.0) -> void:
	lbl_warn.text = text
	warn_t = t


# ------------------------------------------------------------------ obstacles
## Spike strips and barricades. Dispatch drops them ~150 m ahead of the leading robber (out of sight
## in the fog), or a cop that has got ahead of its target lays spikes right behind itself.
func _update_obstacles(delta: float) -> void:
	if obs_glow != null:
		obs_glow.emission_energy_multiplier = 3.0 if int(race_time * 4.0) % 2 == 0 else 0.3
	var every: float = LEGS[leg][5]
	if every > 0.0 and race_time > 8.0:
		obs_t -= delta
		if obs_t <= 0.0:
			obs_t = every * randf_range(0.8, 1.2)
			if obstacles.size() < 3:
				_spawn_obstacle()
	if obstacles.is_empty():
		for c in racers + cops:
			c.dodge = INF
		return
	var min_prog: float = INF
	for r in racers:
		if not r.busted and not r.finished:
			min_prog = minf(min_prog, r.prog)
	for o in obstacles.duplicate():
		if min_prog > o["prog"] + 15.0 or race_time - o["t0"] > 50.0:
			o["node"].queue_free()
			obstacles.erase(o)
	for c in racers + cops:
		c.dodge = INF
		for o in obstacles:
			var ahead: float = (o["prog"] - c.prog) * track.spacing
			if ahead > 0.0 and ahead < 70.0 and (o["kind"] == Obs.BARRICADE or not c.is_cop):
				c.dodge = -signf(o["lat"]) * track.width * 0.27
			if c == player and not o["warned"] and ahead > 0.0 and ahead < 200.0:
				o["warned"] = true
				var spikes_text: String = "SPIKE STRIP AHEAD  (cops are immune)" if cop_mode else "SPIKE STRIP AHEAD"
				_warn(spikes_text if o["kind"] == Obs.SPIKES else "ROADBLOCK AHEAD")
			if o["kind"] == Obs.SPIKES and not c.is_cop and not o["hit"].has(c) and absf(ahead) < 2.0:
				var i: int = posmod(int(o["prog"]), track.count)
				var lat: float = (c.global_position - track.points[i]).dot(track.right_at(i))
				if absf(lat - o["lat"]) < track.width * 0.25 + 0.6:
					o["hit"][c] = true
					c.hit_spikes()
					if c == player:
						_warn("TYRES SHREDDED!", 1.5)


func _spawn_obstacle() -> void:
	var p: float = -INF
	for r in racers:
		if not r.busted and not r.finished:
			p = maxf(p, r.prog + 150.0 / track.spacing)
	var kind: int = Obs.SPIKES if randf() < 0.5 else Obs.BARRICADE
	for c in cops:
		if c.controls_enabled and c.target_car != null and (c.prog - c.target_car.prog) * track.spacing > 25.0:
			p = c.prog - 4.0 / track.spacing
			kind = Obs.SPIKES
			break
	if p == -INF or p >= total_progress - 5.0:
		return
	var i: int = posmod(int(p), track.count)
	if track.shortcut_near(i, 6) >= 0 or i < 10 or i > track.count - 10:
		return  # never at a shortcut mouth or on the start line
	var lat: float = (-1.0 if randf() < 0.5 else 1.0) * track.width * 0.25
	var node := _build_obstacle(kind)
	node.transform = Transform3D(Basis.looking_at(track.tangents[i], Vector3.UP), track.points[i] + track.right_at(i) * lat)
	if autotest:
		print("[obstacle] %s at idx=%d lat=%.1f" % ["spikes" if kind == Obs.SPIKES else "barricade", i, lat])
	track.add_child(node)
	obstacles.append({"node": node, "prog": floorf(p), "lat": lat, "kind": kind, "t0": race_time, "hit": {}, "warned": false})


# -------------------------------------------------------------------- loading
## The first time the GPU draws a material (with this map's lights and fog) it compiles a shader, which
## freezes the game for 0.1-0.5 s (worse on the web). So before each new map, behind a loading bar, the
## camera visits the whole road and every shortcut once with a rig of the things that only show up later
## (obstacles, a siren light, the headlight, nitro flames), one stop per drawn frame.
func _begin_loading() -> void:
	state = State.LOADING
	load_i = 0
	load_frame = -1
	load_steps.clear()
	var step: int = maxi(1, int(45.0 / track.spacing))
	for i in range(0, track.count, step):
		var t: Vector3 = track.tangents[i]
		var eye: Vector3 = track.points[i] - t * 7.0 + Vector3(0, 3.0, 0)
		load_steps.append([Transform3D.IDENTITY.looking_at(t * 7.0 + Vector3(0, -2.0, 0), Vector3.UP).translated(eye), track.points[i] + t * 4.0])
	for sc in track.shortcuts:
		var pts: PackedVector3Array = sc["pts"]
		for k in range(0, pts.size() - 1, maxi(1, pts.size() / 4)):
			var t2: Vector3 = (pts[k + 1] - pts[k]).normalized()
			load_steps.append([Transform3D.IDENTITY.looking_at(t2 * 7.0 + Vector3(0, -2.0, 0), Vector3.UP).translated(pts[k] - t2 * 7.0 + Vector3(0, 3.0, 0)), pts[k] + t2 * 4.0])
	for c in cops + racers:   # every car model under the rig's lights (night: headlight + siren light on paint)
		var cf: Vector3 = c.forward_world()
		load_steps.append([Transform3D.IDENTITY.looking_at(cf * 7.0 + Vector3(0, -2.0, 0), Vector3.UP).translated(c.global_position - cf * 7.0 + Vector3(0, 3.0, 0)), c.global_position])
	var fwd: Vector3 = player.forward_world()
	var chase: Vector3 = player.global_position - fwd * 7.0 + Vector3(0, 3.0, 0)
	load_steps.append([Transform3D.IDENTITY.looking_at(fwd * 7.0 + Vector3(0, -2.0, 0), Vector3.UP).translated(chase), player.global_position + fwd * 5.0])
	_build_warm_rig()
	wind.emitting = true
	AudioServer.set_bus_mute(0, true)   # cameras flying past cars would start and stop their sounds
	for n in sfx:
		sfx[n].play()   # registers each sound with the web audio backend now, muted
	player.snd_crash.play()
	load_lbl.text = "LOADING  LEVEL %d: %s" % [leg + 1, track.map["name"]]
	load_layer.visible = true



## Shown from the first frame (covers start-up and calibration too) until the map's shaders are ready.
func _build_loading_ui() -> void:
	load_layer = CanvasLayer.new()
	load_layer.layer = 100
	add_child(load_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	load_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	load_layer.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	load_lbl = _label(box, 30, Color(1.0, 0.85, 0.3))
	load_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_bar = ProgressBar.new()
	load_bar.show_percentage = false
	load_bar.custom_minimum_size = Vector2(460, 18)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.75, 0.2)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	load_bar.add_theme_stylebox_override("fill", fill)
	load_bar.add_theme_stylebox_override("background", back)
	box.add_child(load_bar)
	load_lbl.text = "LOADING"


func _build_warm_rig() -> void:
	warm_rig = Node3D.new()
	for kind in [Obs.SPIKES, Obs.BARRICADE]:
		var o := _build_obstacle(kind)
		o.position = Vector3(-2.0 if kind == Obs.SPIKES else 2.0, 0, 0)
		for rb in o.get_children():
			if rb is RigidBody3D:
				rb.freeze = true
				rb.collision_layer = 0
				rb.collision_mask = 0
		warm_rig.add_child(o)
	var omni := OmniLight3D.new()   # same setup as a cop's siren light
	omni.omni_range = 14.0
	omni.light_energy = 3.0
	omni.light_color = Color(1, 0.1, 0.1)
	omni.position = Vector3(0, 1.4, 0)
	warm_rig.add_child(omni)
	if player.headlight != null:
		var spot: SpotLight3D = player.headlight.duplicate()
		spot.visible = true
		spot.position = Vector3(0, 1.0, 6.0)
		warm_rig.add_child(spot)
	if not player.flames.is_empty():
		var f: Node3D = player.flames[0].duplicate()
		f.visible = true
		f.position = Vector3(0, 1.0, 0)
		warm_rig.add_child(f)
	track.add_child(warm_rig)


func _state_loading() -> void:
	if Engine.get_frames_drawn() == load_frame:
		return   # one stop per drawn frame, or the GPU never sees the earlier ones
	load_frame = Engine.get_frames_drawn()
	load_bar.value = maxf(load_bar.value, 15.0 + 85.0 * load_i / load_steps.size())
	if load_i >= load_steps.size():
		warm_rig.queue_free()
		warm_rig = null
		wind.emitting = false
		for n in sfx:
			sfx[n].stop()
		player.snd_crash.stop()
		AudioServer.set_bus_mute(0, false)
		load_layer.visible = false
		warmed_map = leg
		load_bar.value = 0.0
		if autotest:
			print("[loading] %d stops, done at t=%.2f" % [load_steps.size(), sim_time])
		_after_load()
		return
	cam.global_transform = load_steps[load_i][0]
	warm_rig.global_position = load_steps[load_i][1]
	warm_rig.look_at(cam.global_position * Vector3(1, 0, 1) + Vector3(0, warm_rig.global_position.y, 0), Vector3.UP)
	load_i += 1


## perf runs: report any frame over 50 ms, so no freeze goes unnoticed
func _process(_d: float) -> void:
	if not autotest or Engine.time_scale != 1.0:
		return
	var now: int = Time.get_ticks_usec()
	if hitch_last > 0 and now - hitch_last > 50000 and state != State.LOADING:
		print("HITCH t=%.2f %.0fms state=%d idx=%d" % [sim_time, (now - hitch_last) / 1000.0, state, player.idx])
	hitch_last = now


func _build_obstacle(kind: int) -> Node3D:
	if obs_glow == null:
		obs_glow = StandardMaterial3D.new()
		obs_glow.albedo_color = Color(1.0, 0.6, 0.1)
		obs_glow.emission_enabled = true
		obs_glow.emission = Color(1.0, 0.5, 0.05)
	var node: Node3D
	var half_w: float = track.width * 0.25
	if kind == Obs.SPIKES:
		node = Node3D.new()
		_obs_box(node, Vector3(half_w * 2.0, 0.08, 0.7), Vector3(0, 0.08, 0), Color(0.12, 0.12, 0.14))
		for s in [-1.0, 1.0]:
			_obs_box(node, Vector3(0.4, 0.15, 0.4), Vector3(half_w * s, 0.12, 0), obs_glow)
	else:
		# barricade: a row of loose barrels. Real rigid bodies, so a car ploughs through and loses speed
		# instead of wedging (a static wall here would trap the AI); they settle and sleep, costing nothing.
		node = Node3D.new()
		for k in range(4):
			var rb := RigidBody3D.new()
			rb.mass = 90.0
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.55
			cyl.height = 1.2
			cs.shape = cyl
			rb.add_child(cs)
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.55
			cm.bottom_radius = 0.55
			cm.height = 1.2
			cm.radial_segments = 8
			mi.mesh = cm
			mi.material_override = _obs_mat(Color(0.95, 0.4, 0.05) if k % 2 == 0 else Color(0.95, 0.95, 0.95))
			rb.add_child(mi)
			_obs_box(rb, Vector3(0.25, 0.25, 0.25), Vector3(0, 0.75, 0), obs_glow)
			rb.position = Vector3((float(k) - 1.5) * half_w * 0.55, 0.62, 0)
			node.add_child(rb)
	return node


func _obs_box(parent: Node3D, size: Vector3, pos: Vector3, look) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	if look is Material:
		mi.material_override = look
	else:
		mi.material_override = _obs_mat(look)
	parent.add_child(mi)


## One material per colour for the whole run, so obstacle shaders are never freed and recompiled.
func _obs_mat(c: Color) -> StandardMaterial3D:
	if not obs_mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		obs_mats[c] = m
	return obs_mats[c]


# --------------------------------------------------------------------- camera
func _update_camera(delta: float) -> void:
	var fwd: Vector3 = player.forward_world()
	fwd.y = 0.0
	if fwd.length() > 0.01:
		cam_dir = cam_dir.lerp(fwd.normalized(), clampf(5.0 * delta, 0.0, 1.0)).normalized()
	var spd: float = player.linear_velocity.length()
	var sn: float = clampf((spd - 18.0) / 34.0, 0.0, 1.0)   # 0 at <=65 km/h, 1 at ~190 km/h
	var back: float = 7.0 + 2.2 * sn
	var height: float = 3.0 - 0.7 * sn
	cam.global_position = player.global_position - cam_dir * back + Vector3(0, height, 0)
	cam.look_at(player.global_position + cam_dir * (5.0 + 5.0 * sn) + Vector3(0, 1.0, 0), Vector3.UP)
	# lean into turns
	var roll_t: float = clampf(-player.angular_velocity.y * 0.05 * (0.4 + sn), -0.12, 0.12) if menu.cfg["shake"] else 0.0
	cam_roll = lerpf(cam_roll, roll_t, clampf(5.0 * delta, 0.0, 1.0))
	cam.rotate_object_local(Vector3(0, 0, -1), cam_roll)
	# FOV widens hard with speed; a little shake when flat out
	var b: float = 1.0 if player.boosting else 0.0
	fx.boost = lerpf(fx.boost, b, clampf(6.0 * delta, 0.0, 1.0))
	cam.fov = lerpf(cam.fov, 66.0 + 34.0 * sn * sn + 6.0 * sn + 12.0 * fx.boost, clampf(4.0 * delta, 0.0, 1.0))
	if not menu.cfg["speed_fx"]:   # comfort setting: fixed view, no streaks
		cam.fov = 70.0
		fx.intensity = 0.0
		fx.boost = 0.0
	var shake: float = (0.05 * sn * sn + 0.06 * fx.boost) if menu.cfg["shake"] else 0.0
	cam.h_offset = randf_range(-1.0, 1.0) * shake
	cam.v_offset = randf_range(-1.0, 1.0) * shake
	if menu.cfg["speed_fx"]:
		fx.intensity = lerpf(fx.intensity, clampf((spd - 26.0) / 26.0, 0.0, 1.0), clampf(4.0 * delta, 0.0, 1.0))
	wind.emitting = spd > 32.0 or player.boosting
	wind.speed_scale = 0.7 + sn * 0.5 + fx.boost * 0.5
	if tune.has("top"):  # test hook: look straight down on centre-line sample `top` from 140 m up
		var tp: Vector3 = track.points[posmod(int(tune["top"]), track.count)]
		cam.global_position = tp + Vector3(0, 140, 0)
		cam.look_at(tp, Vector3(0, 0, -1))
		cam.fov = 70.0


# ------------------------------------------------------------------ test hook
## Headless test only:  godot --headless --path . -- autotest alat=12 noarrest ptest=drift ps=30
func _tuning_args() -> Dictionary:
	var d: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		if a.contains("="):
			var kv: PackedStringArray = a.split("=")
			d[kv[0]] = kv[1]
	return d


func _heading_deg(car) -> float:
	var f: Vector3 = car.forward_world()
	return rad_to_deg(atan2(-f.x, -f.z))


## Scripted drives for tuning the handling:  ptest=turn|turn_hold|drift|drift_long|brake ps=25
func _state_ptest(delta: float) -> void:
	var p = player
	p.controls_enabled = true
	p.scripted = true
	pt_t += delta
	pt_phase_t += delta
	var sp: float = p.forward_speed()
	p.in_handbrake = false
	p.in_steer = 0.0
	p.in_brake = 0.0
	p.in_throttle = 1.0
	var done: bool = false
	if pt_phase == 0:
		if sp >= pt_speed or pt_t > 25.0:
			pt_phase = 1
			pt_phase_t = 0.0
			pt_heading0 = _heading_deg(p)
			print("--- phase 1 begins at %.1f m/s (t=%.1f)" % [sp, pt_t])
	else:
		match ptest:
			"turn":
				p.in_steer = 1.0
				p.in_throttle = 0.5
				done = pt_phase_t > 3.0
			"turn_hold":
				p.in_steer = 1.0
				done = pt_phase_t > 3.0
			"drift":
				if pt_phase_t < 1.2:
					p.in_steer = 1.0
					p.in_handbrake = true
					p.in_throttle = 0.6
				elif pt_phase_t < 2.7:
					p.in_steer = 0.3
					p.in_throttle = 0.6
				else:
					p.in_throttle = 0.8
				done = pt_phase_t > 4.0
			"drift_long":
				p.in_steer = 1.0
				p.in_handbrake = true
				p.in_throttle = 0.6
				done = pt_phase_t > 3.5
			"hb_straight":   # SPACE held in a straight line: must cost speed and earn no nitro
				p.in_handbrake = true
				if pt_phase_t <= 0.1:   # (one tick is 0.067 s at the test's 4x speed)
					p.nitro = 0.5
				done = pt_phase_t > 2.0
				if done:
					print("hb_straight nitro=%.3f (started 0.500)" % p.nitro)
			"brake":
				p.in_throttle = 0.0
				p.in_brake = 1.0
				done = sp < 1.0 or pt_phase_t > 8.0
	pt_log_t += delta
	if pt_log_t >= 0.25 and pt_phase > 0:
		pt_log_t = 0.0
		var yaw: float = p.angular_velocity.y
		var hd: float = wrapf(_heading_deg(p) - pt_heading0, -180.0, 180.0)
		print("t=%4.2f spd=%5.1f yaw=%5.2f rad/s latG=%5.1f slip=%6.1f deg  turned=%6.1f deg  steer=%.2f hb=%.2f drift=%s nitro=%.2f" % [pt_phase_t, p.linear_velocity.length(), yaw, absf(yaw) * p.linear_velocity.length(), rad_to_deg(p.slip_angle()), hd, p.steering, p.hb_amount, str(p.drifting), p.nitro])
	if done:
		print("[ptest done]")
		get_tree().quit()


func _autotest_log(delta: float) -> void:
	if tune.has("shots"):  # test hook: shots=5,20 shotdir=/some/dir saves screenshots at those sim times
		for s in String(tune["shots"]).split(","):
			if sim_time >= float(s) and sim_time - delta < float(s):
				get_viewport().get_texture().get_image().save_png("%s/shot_%s.png" % [tune.get("shotdir", "."), s])
	if state == State.PTEST:
		return
	if OS.get_cmdline_user_args().has("perf") and int(sim_time * 2.0) != int((sim_time - delta) * 2.0):
		print("PERF t=%.1f idx=%d fps=%d frame=%.1fms phys=%.1fms draws=%d prims=%dk objs=%d cop=%d" % [sim_time, player.idx, Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), int(nearest_cop)])
	if tune.has("trace") and state == State.RACING and player.idx >= int(tune["trace"]) and player.idx <= int(tune["trace"]) + 24:
		pt_log_t += delta
		if pt_log_t > 0.2:
			pt_log_t = 0.0
			var off: float = (player.global_position - track.points[player.idx]).dot(track.right_at(player.idx))
			print("TRACE idx=%d spd=%5.1f off=%6.1f steer=%5.2f slip=%6.1f yaw=%5.2f  %s" % [player.idx, player.linear_velocity.length(), off, player.steering, rad_to_deg(player.slip_angle()), player.angular_velocity.y, player.dbg])
	if state == State.RACING:
		var laps_done: int = int(floorf(player.prog / float(track.count)))
		if laps_done > lap_marks.size() and laps_done > 0:
			lap_marks.append(race_time)
			print("[lap %d done at %.1fs]" % [laps_done, race_time])
	if int(sim_time) != int(sim_time - delta) and int(sim_time) % 5 == 0:
		var s: String = "t=%3d st=%d" % [int(sim_time), state]
		for r in racers:
			s += " | %s %4.1fm/s p=%5.0f a=%3.0f%s" % [r.driver_name.substr(0, 3), r.linear_velocity.length(), r.prog, r.arrest, "B" if r.busted else ("F" if r.finished else "")]
		for c in cops:
			s += " | cop %4.1f" % c.linear_velocity.length()
		print(s)
	if (state == State.BUSTED or state == State.ESCAPED) and OS.get_cmdline_user_args().has("restarttest") and lap_marks.size() < 90:
		lap_marks.resize(99)  # only do this once
		var t0: int = Time.get_ticks_msec()
		_restart()
		print("[restart] sim_time=%.2f done in %d ms -> state=%d, player prog=%.0f, busted=%s, finish_order=%d" % [sim_time, Time.get_ticks_msec() - t0, state, player.prog, str(player.busted), finish_order.size()])
		return
	if state == State.LEG_CLEAR and timer == 0.0:
		print("[leg %d clear] race_time=%.1f obstacles=%d shortcuts=%d" % [leg + 1, race_time, obstacles.size(), track.shortcuts.size()])
	if state == State.BUSTED or state == State.ESCAPED or state == State.FINAL or sim_time > 900.0:
		var res: String = "[autotest] result state=%d leg=%d race_time=%.1f run_time=%.1f order:" % [state, leg + 1, race_time, run_time]
		for r in _standings():
			res += " " + r.driver_name + ("(B)" if r.busted else "")
		print(res)
		if rules.active:
			print("[autotest] points ranking: ", rules.points_ranking(), "  cops by points: ", rules.cop_board_points())
		get_tree().quit()
