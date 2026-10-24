extends Node3D
## Cops & Robbers racer v0.1: set-up, race flow, camera, FX and HUD.
##
## You and three AI robbers race TOTAL_LAPS laps. Two cop cars hunt whichever
## robber is closest. Every robber has an ARREST bar that fills while a cop is
## near; a full bar = busted (out). Finish the laps first to escape.

const VERSION: String = "v0.1"

const TrackScript = preload("res://track.gd")
const CarScript = preload("res://car.gd")
const MinimapScript = preload("res://minimap.gd")
const SpeedFxScript = preload("res://speedfx.gd")

const TOTAL_LAPS: int = 3
const COP_COUNT: int = 2
const COUNTDOWN_TIME: float = 3.0
const COP_DELAY: float = 4.0     # seconds after GO before the cops start moving
const ARREST_GRACE: float = 6.0  # no arrests this early in the race
const COP_SPEED: float = 39.0

enum State { SETTLE, TEST, COUNTDOWN, RACING, BUSTED, ESCAPED, PTEST }

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
const COP_GRID: Array = [[10, 2.5], [13, -2.5], [16, 2.5]]

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


func _ready() -> void:
	autotest = OS.get_cmdline_user_args().has("autotest")
	if autotest:
		Engine.time_scale = 4.0
	tune = _tuning_args()
	ptest = String(tune.get("ptest", ""))
	pt_speed = float(tune.get("ps", 25.0))
	no_arrest = OS.get_cmdline_user_args().has("noarrest")
	_build_world()
	track = TrackScript.new()
	add_child(track)
	if tune.has("alat"):
		track.a_lat = float(tune["alat"])
	track.build()
	total_progress = float(TOTAL_LAPS * track.count)

	player = _new_car(0, Color(1.0, 0.8, 0.05), 38.0, "YOU", GRID[PLAYER_SLOT][0], GRID[PLAYER_SLOT][1])
	player.auto_drive = autotest
	if tune.has("pspeed"):
		player.ai_speed = float(tune["pspeed"])
	player.calibrating = true
	racers.append(player)

	cam = Camera3D.new()
	cam.far = 1500.0
	cam.fov = 68.0
	add_child(cam)
	cam.current = true

	_build_hud()
	lbl_msg.text = "WARMING UP"
	lbl_sub.text = ""


# ------------------------------------------------------------------- set-up
func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.12, 0.17, 0.38)
	sky_mat.sky_horizon_color = Color(0.95, 0.6, 0.4)
	sky_mat.ground_horizon_color = Color(0.95, 0.6, 0.4)
	sky_mat.ground_bottom_color = Color(0.1, 0.12, 0.14)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.6, 0.5)
	env.fog_density = 0.0009
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28, -50, 0)
	sun.light_color = Color(1.0, 0.82, 0.65)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)


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

	hint = _label(hud, 17, Color(0.9, 0.9, 0.9))
	hint.text = "W/S  gas / brake-reverse     A/D  steer     SPACE  handbrake drift     R  flip-reset"

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
	bottom.position = Vector2((vp.x - 460.0) * 0.5, vp.y - bottom.get_combined_minimum_size().y - 22.0)
	hint.position = Vector2(16.0, vp.y - hint.get_combined_minimum_size().y - 12.0)
	lbl_ver.position = Vector2(vp.x - lbl_ver.get_combined_minimum_size().x - 16.0, vp.y - 30.0)
	lbl_msg.size = Vector2(vp.x, 120.0)
	lbl_msg.position = Vector2(0.0, vp.y * 0.36 - 60.0)
	lbl_sub.size = Vector2(vp.x, 50.0)
	lbl_sub.position = Vector2(0.0, vp.y * 0.36 + 70.0)


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
	var lap: int = clampi(int(floorf(player.prog / float(track.count))) + 1, 1, TOTAL_LAPS)
	lbl_lap.text = "LAP %d / %d" % [lap, TOTAL_LAPS]
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
	lbl_speed.text = "%d km/h" % int(absf(player.forward_speed()) * 3.6)
	bar.value = player.arrest
	lbl_arrest.text = "ARREST  %d%%" % int(player.arrest)


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	sim_time += delta
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
			racers.append(ai)
		for k in range(COP_COUNT):
			var cop = _new_car(2, Color.WHITE, COP_SPEED, "COP %d" % (k + 1), COP_GRID[k][0], COP_GRID[k][1])
			cop.lane = COP_GRID[k][1] * 0.6
			cops.append(cop)
	elif ptest != "":
		track.get_node("Walls").queue_free()
	_reset_grid()

	var items: Array = []
	for r in racers:
		items.append([r, r.body_color])
	for c in cops:
		items.append([c, Color(0.3, 0.55, 1.0)])
	minimap.items = items

	state = State.PTEST if ptest != "" else State.COUNTDOWN
	_begin_countdown()


## Teleport everybody back to their starting slot (used at boot and on restart).
func _reset_grid() -> void:
	for k in range(racers.size()):
		var r = racers[k]
		var gs: Array = GRID[PLAYER_SLOT if r == player else AI_SLOTS[k - 1]]
		r.teleport(_grid_transform(r, gs[0], gs[1]))
		_place_state(r, gs[0])
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
	lbl_msg.add_theme_color_override("font_color", Color(1, 0.95, 0.5))
	cam_dir = player.forward_world()
	cam_dir.y = 0.0
	cam_dir = cam_dir.normalized()


## Instant restart: no scene reload, no re-calibration.
func _restart() -> void:
	_reset_grid()
	state = State.COUNTDOWN
	_begin_countdown()


## 4) 3-2-1-GO
func _state_countdown(delta: float) -> void:
	timer += delta
	var left: float = COUNTDOWN_TIME - timer
	if left > 0.0:
		lbl_msg.text = str(int(ceilf(left)))
		lbl_sub.text = "%d laps. Beat the other robbers. Don't get caught." % TOTAL_LAPS
	else:
		state = State.RACING
		race_time = 0.0
		lbl_msg.text = "GO!"
		lbl_sub.text = ""
		timer = 0.0
		for r in racers:
			r.controls_enabled = true
		for c in cops:
			c.controls_enabled = false  # released after COP_DELAY


## 5) the race
func _state_racing(delta: float) -> void:
	race_time += delta
	timer += delta
	if timer > 1.2:
		lbl_msg.text = ""
	_update_pace()
	_update_cop_targets(delta)
	_update_arrests(delta)
	_update_finishes()


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
		c.controls_enabled = best != null and race_time > COP_DELAY


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
			rate += clampf((12.0 - d) / 12.0, 0.0, 1.0) * 30.0
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
		_end_race(State.BUSTED, order.find(player) + 1)


func _update_finishes() -> void:
	for r in racers:
		if r.finished or r.busted:
			continue
		if r.prog >= total_progress:
			r.finished = true
			finish_order.append(r)
			if r == player:
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
		lbl_sub.text = "The cops got you.   Press ENTER to try again."
	else:
		lbl_msg.text = "YOU ESCAPED!"
		lbl_msg.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		lbl_sub.text = "Finished %s in %s.   Press ENTER to go again." % [ordinal, _time_str(race_time)]


func _state_over(_delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER):
		_restart()


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
	var roll_t: float = clampf(-player.angular_velocity.y * 0.05 * (0.4 + sn), -0.12, 0.12)
	cam_roll = lerpf(cam_roll, roll_t, clampf(5.0 * delta, 0.0, 1.0))
	cam.rotate_object_local(Vector3(0, 0, -1), cam_roll)
	# FOV widens hard with speed; a little shake when flat out
	cam.fov = lerpf(cam.fov, 66.0 + 34.0 * sn * sn + 6.0 * sn, clampf(4.0 * delta, 0.0, 1.0))
	var shake: float = 0.05 * sn * sn
	cam.h_offset = randf_range(-1.0, 1.0) * shake
	cam.v_offset = randf_range(-1.0, 1.0) * shake
	fx.intensity = lerpf(fx.intensity, clampf((spd - 26.0) / 26.0, 0.0, 1.0), clampf(4.0 * delta, 0.0, 1.0))


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
			"brake":
				p.in_throttle = 0.0
				p.in_brake = 1.0
				done = sp < 1.0 or pt_phase_t > 8.0
	pt_log_t += delta
	if pt_log_t >= 0.25 and pt_phase > 0:
		pt_log_t = 0.0
		var yaw: float = p.angular_velocity.y
		var hd: float = wrapf(_heading_deg(p) - pt_heading0, -180.0, 180.0)
		print("t=%4.2f spd=%5.1f yaw=%5.2f rad/s latG=%5.1f slip=%6.1f deg  turned=%6.1f deg  steer=%.2f hb=%.2f" % [pt_phase_t, p.linear_velocity.length(), yaw, absf(yaw) * p.linear_velocity.length(), rad_to_deg(p.slip_angle()), hd, p.steering, p.hb_amount])
	if done:
		print("[ptest done]")
		get_tree().quit()


func _autotest_log(delta: float) -> void:
	if state == State.PTEST:
		return
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
	if state == State.BUSTED or state == State.ESCAPED or sim_time > 260.0:
		var res: String = "[autotest] result state=%d race_time=%.1f order:" % [state, race_time]
		for r in _standings():
			res += " " + r.driver_name + ("(B)" if r.busted else "")
		print(res)
		get_tree().quit()
