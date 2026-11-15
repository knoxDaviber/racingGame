extends Node3D
## Cops & Robbers racer v0.2: set-up, race flow, camera, FX and HUD.
##
## One escape in four legs (track.gd MAPS), each harder than the last. You and three AI
## robbers race each leg; cop cars hunt whichever robber is closest. Every robber has an
## ARREST bar that fills while a cop is near; a full bar = busted (out for the rest of the run).
## Finish the last leg to escape.

const VERSION: String = "v0.2"

const TrackScript = preload("res://track.gd")
const CarScript = preload("res://car.gd")
const MinimapScript = preload("res://minimap.gd")
const SpeedFxScript = preload("res://speedfx.gd")
const MenuScript = preload("res://menu.gd")

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

const COUNTDOWN_TIME: float = 3.0
const ARREST_GRACE: float = 6.0  # no arrests this early in a leg
const ARREST_CARRY: float = 0.5  # share of each arrest bar carried into the next leg

## Difficulty per leg (same order as track.gd MAPS):
## laps, cops, cop cruise speed, cop top speed, cop start delay (s), obstacle every (s, 0 = none), arrest fill rate
const LEGS: Array = [
	[2, 2, 39.0, 47.0, 4.0, 0.0, 30.0],
	[2, 3, 39.5, 47.5, 3.5, 22.0, 31.0],
	[2, 3, 40.5, 48.0, 3.0, 16.0, 33.0],
	[2, 4, 41.5, 49.0, 2.5, 12.0, 35.0],
]
enum Obs { SPIKES, BARRICADE }

enum State { SETTLE, TEST, COUNTDOWN, RACING, BUSTED, ESCAPED, PTEST, LEG_CLEAR }

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

var state: int = State.SETTLE
var track = null
var player = null
var racers: Array = []      # player first, then AI robbers
var cops: Array = []
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
	_make_track()

	player = _new_car(0, Color(1.0, 0.8, 0.05), 38.0, "YOU", GRID[PLAYER_SLOT][0], GRID[PLAYER_SLOT][1])
	player.set_meta("slot", PLAYER_SLOT)
	player.auto_drive = autotest
	if tune.has("pspeed"):
		player.ai_speed = float(tune["pspeed"])
	player.calibrating = true
	racers.append(player)

	cam = Camera3D.new()
	cam.far = 500.0     # set per map in _apply_map (fog is opaque just before it)
	cam.fov = 68.0
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(cam)
	cam.current = true
	player.cam = cam
	_build_wind()
	_build_sfx()

	_build_hud()
	menu = MenuScript.new()
	add_child(menu)
	menu.retry.connect(_restart)
	menu.new_run.connect(func(): _goto_leg(0, true))
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
	laps = int(LEGS[leg][0])
	total_progress = float(laps * track.count)
	for c in racers + cops:
		c.track = track
	if minimap != null:
		minimap.setup(track)


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


## kind: 0 = player, 1 = AI robber, 2 = cop.  back/lateral = starting grid slot.
## The start transform must be set BEFORE add_child (teleporting a body in the same
## frame it is created does not stick).
func _new_car(kind: int, color: Color, ai_speed: float, car_name: String, back: int, lateral: float):
	var car = CarScript.new()
	car.track = track
	car.is_player = (kind == 0)
	car.is_cop = (kind == 2)
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
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.15, 0.15)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.55)
	bar.add_theme_stylebox_override("fill", fill)
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
	var lap: int = clampi(int(floorf(player.prog / float(track.count))) + 1, 1, laps)
	lbl_lap.text = "LEG %d/%d  %s   LAP %d/%d" % [leg + 1, LEGS.size(), track.map["name"], lap, laps]
	var order: Array = _standings()
	lbl_pos.text = "POSITION  %d / %d" % [order.find(player) + 1, order.size()]
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
		board += "%d. %s%s\n" % [i + 1, r.driver_name, tag]
	lbl_board.text = board.strip_edges()
	var kmh: float = absf(player.forward_speed()) * 3.6
	lbl_speed.text = ("%d mph" % int(kmh * 0.621)) if menu.cfg["mph"] else ("%d km/h" % int(kmh))
	bar.value = player.arrest
	nbar.value = player.nitro
	lbl_arrest.text = "ARREST  %d%%" % int(player.arrest)
	warn_t -= get_physics_process_delta_time()
	if warn_t <= 0.0:
		lbl_warn.text = ""
	tip_t -= get_physics_process_delta_time()
	if tip_t <= 0.0 and state != State.COUNTDOWN:
		lbl_tip.text = ""


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	sim_time += delta
	menu.can_pause = not autotest and ptest == "" and state >= State.COUNTDOWN
	if menu.can_pause and not menu.cfg["seen_help"]:   # first launch: explain the game before the first race
		menu.cfg["seen_help"] = true
		menu.open("help")
	match state:
		State.SETTLE:
			_state_settle(delta)
		State.TEST:
			_state_test(delta)
		State.COUNTDOWN:
			_state_countdown(delta)
		State.RACING:
			_state_racing(delta)
		State.BUSTED, State.ESCAPED:
			_state_over(delta)
		State.LEG_CLEAR:
			_state_leg_clear(delta)
		State.PTEST:
			_state_ptest(delta)
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
	if ptest == "" and not OS.get_cmdline_user_args().has("solo"):
		for k in range(ROBBERS.size()):
			var spec: Array = ROBBERS[k]
			var slot: Array = GRID[AI_SLOTS[k]]
			var ai = _new_car(1, spec[1], spec[2], spec[0], slot[0], slot[1])
			ai.lane = spec[3]
			ai.set_meta("slot", AI_SLOTS[k])
			racers.append(ai)
	elif ptest != "":
		track.get_node("Walls").queue_free()
	_start_leg()
	if ptest != "":
		state = State.PTEST


## Cops for this leg (more, faster, earlier each leg), the minimap, lights, then the grid.
func _start_leg() -> void:
	for c in cops:
		remove_child(c)
		c.queue_free()
	cops.clear()
	if ptest == "" and not OS.get_cmdline_user_args().has("solo"):
		for k in range(int(LEGS[leg][1])):
			var cop = _new_car(2, Color.WHITE, LEGS[leg][2], "COP %d" % (k + 1), COP_GRID[k][0], COP_GRID[k][1])
			cop.top_speed = LEGS[leg][3]
			cop.lane = COP_GRID[k][1] * 0.6
			cops.append(cop)
	for o in obstacles:
		if is_instance_valid(o["node"]):
			o["node"].queue_free()
	obstacles.clear()
	obs_t = LEGS[leg][5]
	var items: Array = []
	for r in racers:
		items.append([r, r.body_color])
		r.visible = not r.busted   # robbers busted on an earlier leg sit the rest of the run out
		r.process_mode = Node.PROCESS_MODE_INHERIT if not r.busted else Node.PROCESS_MODE_DISABLED
	for c in cops:
		items.append([c, Color(0.3, 0.55, 1.0)])
	minimap.items = items
	_apply_map()
	leg_snapshot.clear()
	for r in racers:
		leg_snapshot[r] = [r.busted, r.arrest, r.get_meta("slot")]
	leg_start_time = run_time
	if autotest:
		for sc in track.shortcuts:
			print("[shortcut] %s a=%d b=%d (%d m cut vs %d m road)" % [track.map["name"], sc["a"], sc["b"], int(sc["pts"][0].distance_to(sc["pts"][-1])), int((sc["b"] - sc["a"]) * track.spacing)])
	_reset_grid()
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
		c.teleport(_grid_transform(c, COP_GRID[k][0], COP_GRID[k][1]))
		_place_state(c, COP_GRID[k][0])
		c.target_car = null


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
	lbl_tip.text = ("TIP: " + TIPS[randi() % TIPS.size()]) if menu.cfg["tips"] else ""
	lbl_msg.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	cam_dir = player.forward_world()
	cam_dir.y = 0.0
	cam_dir = cam_dir.normalized()


## Busted: retry this leg as it started. Escaped: a fresh run from leg 1. No reload, no recalibration.
func _restart() -> void:
	tip_t = 0.0
	if state == State.ESCAPED:
		_goto_leg(0, true)
		return
	run_time = leg_start_time
	for r in racers:   # undo whatever happened during the failed attempt
		var s: Array = leg_snapshot[r]
		r.busted = s[0]
		r.arrest = s[1]
		r.set_meta("slot", s[2])
	_start_leg()


## Load a leg's map. `fresh` = new run (everyone back, bars empty, original grid).
func _goto_leg(i: int, fresh: bool) -> void:
	var order: Array = _standings()
	leg = i
	_make_track()
	if fresh:
		run_time = 0.0
		for r in racers:
			r.busted = false
			r.arrest = 0.0
		player.set_meta("slot", PLAYER_SLOT)
		for k in range(1, racers.size()):
			racers[k].set_meta("slot", AI_SLOTS[k - 1])
	else:
		# grid in finishing order; arrest bars carry over in part
		var s: int = 0
		for r in order:
			r.set_meta("slot", s)
			s += 1
			r.arrest *= ARREST_CARRY
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
		lbl_sub.text = "LEG %d/%d  %s  (%s)   %d laps, %d cops" % [leg + 1, LEGS.size(), track.map["name"], track.map["time"], laps, cops.size()]
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
			c.controls_enabled = false  # released after the leg's cop delay


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
		for c in cops:
			var d: float = c.global_position.distance_to(r.global_position)
			if r == player:
				nearest_cop = minf(nearest_cop, d)
			rate += clampf((12.0 - d) / 12.0, 0.0, 1.0) * LEGS[leg][6]
		if rate > 0.0:
			r.arrest += rate * delta
		else:
			r.arrest -= 12.0 * delta
		r.arrest = clampf(r.arrest, 0.0, 100.0)
		if r.arrest >= 100.0 and not no_arrest:
			_bust(r)


func _bust(r) -> void:
	r.busted = true
	r.controls_enabled = false
	r.set_ghost(true)
	if r == player:
		var order: Array = _standings()
		_play("busted")
		_end_race(State.BUSTED, order.find(player) + 1)


func _update_finishes() -> void:
	for r in racers:
		if r.finished or r.busted:
			continue
		if r.prog >= total_progress:
			r.finished = true
			finish_order.append(r)
			if r == player:
				_play("escaped")
				if leg < LEGS.size() - 1:
					_end_race(State.LEG_CLEAR, finish_order.size())
				else:
					_end_race(State.ESCAPED, finish_order.size())


func _end_race(result: int, place: int) -> void:
	state = result
	timer = 0.0
	for r in racers:
		r.controls_enabled = false
	for c in cops:
		c.controls_enabled = false
	var ordinal: String = ["", "1st", "2nd", "3rd", "4th", "5th"][clampi(place, 0, 5)]
	if result == State.BUSTED:
		lbl_msg.text = "BUSTED!"
		lbl_msg.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		lbl_sub.text = "The cops got you on leg %d.   Press ENTER to retry the leg." % (leg + 1)
		lbl_tip.text = "TIP: when the red ARREST bar starts filling, use nitro (SHIFT) to get away from the cop."
		tip_t = 999.0
	elif result == State.LEG_CLEAR:
		lbl_msg.text = "LEG %d CLEAR" % (leg + 1)
		lbl_msg.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		lbl_sub.text = "%s in %s.   Next: %s (%s)" % [ordinal, _time_str(race_time), TrackScript.MAPS[leg + 1]["name"], TrackScript.MAPS[leg + 1]["time"]]
	else:
		lbl_msg.text = "YOU ESCAPED!"
		lbl_msg.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		lbl_sub.text = "Out of the city, %s on the last leg. Total %s.   Press ENTER for a new run." % [ordinal, _time_str(run_time)]


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
				_warn("SPIKE STRIP AHEAD" if o["kind"] == Obs.SPIKES else "ROADBLOCK AHEAD")
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
			var bm := StandardMaterial3D.new()
			bm.albedo_color = Color(0.95, 0.4, 0.05) if k % 2 == 0 else Color(0.95, 0.95, 0.95)
			mi.material_override = bm
			rb.add_child(mi)
			_obs_box(rb, Vector3(0.25, 0.25, 0.25), Vector3(0, 0.75, 0), obs_glow)
			rb.position = Vector3((float(k) - 1.5) * half_w * 0.55, 0.62, 0)
			node.add_child(rb)
	node.transform = Transform3D(Basis.looking_at(track.tangents[i], Vector3.UP), track.points[i] + track.right_at(i) * lat)
	if autotest:
		print("[obstacle] %s at idx=%d lat=%.1f" % ["spikes" if kind == Obs.SPIKES else "barricade", i, lat])
	track.add_child(node)
	obstacles.append({"node": node, "prog": floorf(p), "lat": lat, "kind": kind, "t0": race_time, "hit": {}, "warned": false})


func _obs_box(parent: Node3D, size: Vector3, pos: Vector3, look) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	if look is Material:
		mi.material_override = look
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = look
		mi.material_override = m
	parent.add_child(mi)


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
	if state == State.BUSTED or state == State.ESCAPED or sim_time > 900.0:
		var res: String = "[autotest] result state=%d leg=%d race_time=%.1f run_time=%.1f order:" % [state, leg + 1, race_time, run_time]
		for r in _standings():
			res += " " + r.driver_name + ("(B)" if r.busted else "")
		print(res)
		get_tree().quit()
