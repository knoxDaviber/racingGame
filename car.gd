extends VehicleBody3D
## One car. Player and cops share the same physics (Godot's raycast vehicle:
## spring/damper suspension, per-wheel tyre grip, weight transfer); only the
## "driver" differs: keyboard for the player, a pure-pursuit AI for the cops.

const ENGINE_FORCE: float = 32.0
const BRAKE_FORCE: float = 115.0
const REVERSE_FORCE: float = 18.0
const WHEEL_X: float = 0.85
const WHEEL_Z: float = 1.35
const WHEELBASE: float = 2.7

# --- hitbox: two boxes (the car body + the cabin). The 3D model is scaled to fit HITBOX_BASE's length.
const HITBOX_BASE: Vector3 = Vector3(1.8, 0.5, 4.2)
const HITBOX_CABIN: Vector3 = Vector3(1.5, 0.5, 2.0)
const CarModel = preload("res://car_model.gd")   # hooks a real 3D model onto this rig (falls back to boxes)

# --- handling tunables (v0.1) ---
const MASS: float = 800.0
const GRIP_FRONT: float = 2.3          # tyre grip multipliers (higher = more cornering force)
const GRIP_REAR: float = 2.5
const HANDBRAKE_REAR_GRIP: float = 0.6 # rear grip multiplier at full handbrake (was 0.4: too loose)
const STEER_RATE: float = 6.0          # rad/s the wheels can swing
const YAW_GRIP_G: float = 19.0         # lateral accel (m/s^2) the yaw assist aims for in normal driving
const YAW_ASSIST: float = 3.0          # how hard the assist drives yaw rate toward the target (1/s)
const DRIFT_SLIP: float = 0.5          # slide angle (rad, ~29 deg) a normal handbrake drift settles at
const DRIFT_SLIP_EXTRA: float = 0.8    # extra angle you can only reach by holding full lock + handbrake for ~2 s
const DRIFT_K: float = 4.5             # how quickly the slide angle converges (1/s)
const DRIFT_ASSIST: float = 9.0
const HANDBRAKE_FORCE: float = 70.0    # rear-wheel brake while SPACE is held: the handbrake costs speed
const HANDBRAKE_ENGINE: float = 0.3    # front wheels keep this share of engine power on the handbrake
const DRIFT_HOLD_GRIP: float = 0.75    # rear grip while a drift is held on throttle after letting go of SPACE

# --- nitrous (everyone has it). A full tank is ~3 s of boost; it refills slowly, and fast while drifting.
const NITRO_POWER: float = 1.9         # engine force multiplier while boosting
const NITRO_TOP: float = 1.22          # top speed multiplier while boosting
const NITRO_DRAIN: float = 0.33        # tank per second
const NITRO_REFILL: float = 0.035      # tank per second, always
const NITRO_DRIFT_REFILL: float = 0.3  # extra tank per second while sliding
const SPIKE_TIME: float = 2.6          # seconds of shredded tyres after a spike strip

const SND_ROBBER: AudioStream = preload("res://Resources/Audio/engine_robber.ogg")
const SND_COP: AudioStream = preload("res://Resources/Audio/engine_cop.ogg")
const SND_SIREN: AudioStream = preload("res://Resources/Audio/siren.ogg")
const SND_SKID: AudioStream = preload("res://Resources/Audio/skid.ogg")
const SND_NITRO: AudioStream = preload("res://Resources/Audio/nitro.ogg")
const SND_CRASH: AudioStream = preload("res://Resources/Audio/crash.ogg")
const AUDIO_RANGE: float = 140.0
const VOL: float = -8.0               # master trim for every car sound (dB)       # beyond this from the camera a car's sounds are stopped, not just quiet
const LIGHT_RANGE: float = 70.0        # siren lights further than this from the camera are switched off

var track = null          # Track node (set by Main before add_child)
var target_car = null     # who the AI chases (cops only)
var is_cop: bool = false
var is_player: bool = false
var auto_drive: bool = false   # lets the AI drive the player car (used for testing)
var body_color: Color = Color(1.0, 0.8, 0.1)

var fwd_local: Vector3 = Vector3(0, 0, -1)  # which local axis the engine pushes along
var engine_scale: float = 1.0
var top_speed: float = 44.0   # power fades to zero at this speed (m/s)
var ai_speed: float = 38.0    # AI cruising target before `pace` is applied
var pace: float = 1.0
var lane: float = 0.0         # AI lane offset from the centre line

var idx: int = 0              # nearest centre-line sample
var prog: float = 0.0         # cumulative progress in samples (0 = start line)

var controls_enabled: bool = false
var calibrating: bool = false

var in_throttle: float = 0.0
var in_brake: float = 0.0
var in_steer: float = 0.0     # +1 = left
var in_handbrake: bool = false

var wheels: Array = []
var visual: Node3D
var model = null                # CarModel when a real 3D model is in use, null for the box car
var siren_t: float = 0.0
var siren_lights: Array = []
var siren_mats: Array = []
var body_mat: StandardMaterial3D = null   # the box car's paint (only used when there is no 3D model)

var reset_cd: float = 0.0
var prev_vel_ang: float = 0.0
var drift_t: float = 0.0
var hb_amount: float = 0.0     # 0..1 how engaged the handbrake slide is
var drifting: bool = false     # a slide started with the handbrake, held on throttle + steering
var drift_dir: float = 0.0     # +1 = drifting left (in_steer sign when it started)
var scripted: bool = false     # test harness sets in_* directly
var busted: bool = false
var finished: bool = false
var arrest: float = 0.0
var driver_name: String = ""
var flipped_t: float = 0.0
var stuck_t: float = 0.0
var reverse_t: float = 0.0
var watch_t: float = 0.0
var watch_prog: float = 0.0
var log_events: bool = false
var dbg: String = ""

var nitro: float = 1.0          # tank 0..1
var boosting: bool = false
var in_nitro: bool = false
var spiked_t: float = 0.0
var on_dirt: bool = false
var dodge: float = INF          # temporary AI lane (set by Main to steer round obstacles); INF = none
var sc_plan: int = -1           # shortcut the AI has decided to take (-1 = none)
var sc_decided: int = -1
var night: bool = false
var siren_on: bool = false      # set by Main: the one audible siren (nearest cop)
var siren_muted: bool = false   # the police car you drive: F turns its siren sound off (the lights keep flashing)
var _siren_key_down: bool = false
var gone: bool = false          # cop mode: a racer that got away. Hidden, no collisions, ignored by the other drivers
var cam: Camera3D = null        # set by Main: used to cull sounds and lights far from the player

var snd_engine: AudioStreamPlayer3D
var snd_siren: AudioStreamPlayer3D
var snd_skid: AudioStreamPlayer3D
var snd_nitro: AudioStreamPlayer3D
var snd_crash: AudioStreamPlayer3D
var crash_cd: float = 0.0
var prev_v: Vector3 = Vector3.ZERO
var flames: Array = []
var headlight: SpotLight3D = null
var light_pool: MeshInstance3D = null


func _ready() -> void:
	mass = MASS
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.2, 0)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE   # ignore the project's default damping
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.02
	angular_damp = 0.5
	can_sleep = false
	set_ghost(false)
	add_to_group("cars")
	continuous_cd = true

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = HITBOX_BASE
	col.shape = box
	col.position = Vector3(0, 0.1, 0)
	add_child(col)
	var col2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = HITBOX_CABIN
	col2.shape = box2
	col2.position = Vector3(0, 0.6, 0.35)
	add_child(col2)

	_build_visual()
	_build_extras()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			wheels.append(_add_wheel(Vector3(WHEEL_X * sx, 0.35, WHEEL_Z * sz)))
	set_forward(fwd_local)


# ------------------------------------------------------------------ building
func _add_wheel(pos: Vector3) -> VehicleWheel3D:
	var w := VehicleWheel3D.new()
	w.position = pos
	w.wheel_radius = 0.35
	w.wheel_rest_length = 0.3
	w.suspension_travel = 0.3
	w.suspension_stiffness = 50.0
	w.suspension_max_force = 15000.0
	w.damping_compression = 3.5
	w.damping_relaxation = 5.0
	w.wheel_friction_slip = 1.5
	w.use_as_traction = true
	add_child(w)
	if model != null:
		return w   # the model's own wheels copy this wheel's motion (car_model.gd)

	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 0.28
	mi.mesh = cm
	mi.rotation_degrees = Vector3(0, 0, 90)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05)
	m.roughness = 0.9
	mi.material_override = m
	w.add_child(mi)
	# a light-coloured hub so you can see the wheel spinning
	var hub := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.3, 0.12, 0.5)
	hub.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.7, 0.7, 0.72)
	hub.material_override = hmat
	w.add_child(hub)
	return w


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	visual.add_child(mi)
	return mi


func _paint(color: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	return m


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	# A real 3D model if one is set up (see car_model.gd); otherwise fall through to the box car below.
	model = CarModel.new()
	if model.attach(visual, is_cop, driver_name, body_color, HITBOX_BASE.z):
		return
	model = null
	var glass: StandardMaterial3D = _paint(Color(0.05, 0.07, 0.1), 0.8, 0.1)
	if is_cop:
		_box(Vector3(1.8, 0.5, 4.2), Vector3(0, 0.1, 0), _paint(Color(0.93, 0.93, 0.95), 0.4, 0.35))
		_box(Vector3(1.83, 0.2, 2.1), Vector3(0, 0.12, 0.2), _paint(Color(0.04, 0.04, 0.05), 0.3, 0.4))
		_box(Vector3(1.5, 0.5, 2.0), Vector3(0, 0.6, 0.35), glass)
		_box(Vector3(1.4, 0.06, 0.9), Vector3(0, 0.88, 0.35), _paint(Color(0.93, 0.93, 0.95), 0.4, 0.35))
		var red: StandardMaterial3D = _glow(Color(1, 0.05, 0.05), 0.2)
		var blue: StandardMaterial3D = _glow(Color(0.1, 0.25, 1), 0.2)
		_box(Vector3(0.6, 0.14, 0.3), Vector3(-0.35, 0.98, 0.35), red)
		_box(Vector3(0.6, 0.14, 0.3), Vector3(0.35, 0.98, 0.35), blue)
		siren_mats = [red, blue]
		for k in range(2):
			var l := OmniLight3D.new()
			l.omni_range = 14.0
			l.light_energy = 0.0
			l.light_color = Color(1, 0.1, 0.1) if k == 0 else Color(0.2, 0.3, 1)
			l.position = Vector3(-0.35 if k == 0 else 0.35, 1.4, 0.35)
			visual.add_child(l)
			siren_lights.append(l)
	else:
		body_mat = _paint(body_color, 0.6, 0.3)
		_box(Vector3(1.8, 0.5, 4.2), Vector3(0, 0.1, 0), body_mat)
		_box(Vector3(1.5, 0.45, 1.9), Vector3(0, 0.58, 0.4), glass)
		_box(Vector3(1.6, 0.07, 0.5), Vector3(0, 0.7, 1.95), _paint(Color(0.08, 0.08, 0.1), 0.3, 0.5))
		_box(Vector3(0.08, 0.3, 0.2), Vector3(-0.6, 0.52, 1.95), _paint(Color(0.08, 0.08, 0.1), 0.3, 0.5))
		_box(Vector3(0.08, 0.3, 0.2), Vector3(0.6, 0.52, 1.95), _paint(Color(0.08, 0.08, 0.1), 0.3, 0.5))
	# lights (front is -Z in the visual; set_forward() rotates it if needed)
	var head: StandardMaterial3D = _glow(Color(1, 0.95, 0.75), 2.0)
	var tail: StandardMaterial3D = _glow(Color(1, 0.05, 0.02), 1.5)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.4, 0.14, 0.06), Vector3(0.6 * s, 0.2, -2.11), head)
		_box(Vector3(0.4, 0.14, 0.06), Vector3(0.6 * s, 0.2, 2.11), tail)


## Sounds, nitrous flames and night lights. All hang off `visual`, whose front is -Z.
func _build_extras() -> void:
	snd_engine = _snd(SND_COP if is_cop else SND_ROBBER, 0.0, 10.0)
	snd_skid = _snd(SND_SKID, -80.0, 6.0)
	snd_nitro = _snd(SND_NITRO, -80.0, 6.0)
	snd_crash = _snd(SND_CRASH, 0.0, 10.0)
	if is_cop:
		snd_siren = _snd(SND_SIREN, -80.0, 18.0)
	# exhaust flames: unshaded additive cones, invisible until boosting (bloom makes them glow)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(0.35, 0.6, 1.6)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for s in [-1.0, 1.0]:
		var f := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.16
		cm.height = 1.0
		cm.radial_segments = 6
		cm.rings = 1
		f.mesh = cm
		f.material_override = fm
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.rotation_degrees = Vector3(-90, 0, 0)   # cone tip points backwards (+Z)
		f.position = Vector3(0.42 * s, 0.05, 2.5)
		f.visible = false
		visual.add_child(f)
		flames.append(f)
	# fake headlights for everyone: a soft additive light pool on the road (no real light, no shadow)
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 0.95, 0.8, 1))
	g.set_color(1, Color(0, 0, 0, 1))
	tex.gradient = g
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.albedo_texture = tex
	pm.albedo_color = Color(0.55, 0.52, 0.45)
	pm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	light_pool = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(7.0, 13.0)
	light_pool.mesh = q
	light_pool.material_override = pm
	light_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light_pool.position = Vector3(0, -0.12, -8.5)
	light_pool.visible = false
	visual.add_child(light_pool)


func _snd(stream: AudioStream, db: float, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db + VOL
	p.unit_size = unit
	p.max_distance = AUDIO_RANGE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP  # sirens bend as cops pass
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = stream != SND_CRASH
	add_child(p)
	return p


## Night legs: everyone gets the fake light pool; only the player gets a real (shadowless) spotlight.
func set_night(on: bool) -> void:
	night = on
	light_pool.visible = on
	if is_player and on and headlight == null:
		headlight = SpotLight3D.new()
		headlight.spot_range = 55.0
		headlight.spot_angle = 32.0
		headlight.light_energy = 4.0
		headlight.light_color = Color(1.0, 0.95, 0.85)
		headlight.position = Vector3(0, 0.5, -2.3)
		headlight.rotation_degrees = Vector3(-6, 0, 0)
		visual.add_child(headlight)
	if headlight != null:
		headlight.visible = on


## Repaint the car's body (the Garage uses this). Cops keep their police paint.
func set_body_color(c: Color) -> void:
	body_color = c
	if is_cop:
		return
	if model != null:
		model.set_paint_color(c)
	elif body_mat != null:
		body_mat.albedo_color = c


func set_sounds(on: bool) -> void:
	for p in [snd_engine, snd_skid, snd_nitro, snd_siren]:
		if p == null:
			continue
		if on and not p.playing:
			p.play(randf() * 2.0)
		elif not on and p.playing:
			p.stop()


## Engine pitch follows speed; skid follows slide; siren only once the cop is rolling.
## Everything stops beyond AUDIO_RANGE from the camera, so far cars cost nothing.
func _update_audio(delta: float) -> void:
	crash_cd = maxf(0.0, crash_cd - delta)
	var dv: float = (linear_velocity - prev_v).length()
	prev_v = linear_velocity
	var near: bool = cam == null or cam.global_position.distance_squared_to(global_position) < AUDIO_RANGE * AUDIO_RANGE
	set_sounds(near and visible)
	if not near:
		return
	if dv > 5.0 and crash_cd <= 0.0 and not calibrating:
		snd_crash.volume_db = VOL - 4.0 + linear_to_db(clampf(dv / 18.0, 0.15, 1.0))
		snd_crash.pitch_scale = randf_range(0.8, 1.15)
		snd_crash.play()
		crash_cd = 0.35
	var speed: float = linear_velocity.length()
	var rpm: float = clampf(speed / top_speed, 0.0, 1.3)
	snd_engine.pitch_scale = 0.55 + rpm * 1.25 + in_throttle * 0.12 + (0.15 if boosting else 0.0)
	snd_engine.volume_db = VOL + lerpf(-16.0, -5.0, clampf(in_throttle * 0.6 + rpm * 0.5, 0.0, 1.0))
	var slide: float = 0.0
	if wheels_in_contact() >= 2 and speed > 8.0:
		slide = clampf((absf(slip_angle()) - 0.12) / 0.35, 0.0, 1.0)
		slide = maxf(slide, hb_amount * 0.8)
	snd_skid.volume_db = VOL - 10.0 + linear_to_db(maxf(slide, 0.0001))
	snd_skid.pitch_scale = 0.9 + speed / 160.0
	snd_nitro.volume_db = VOL - 8.0 if boosting else -80.0
	if snd_siren != null:   # only the cop Main picks as `siren_on` is heard: one siren, never a chorus
		snd_siren.volume_db = VOL - 6.0 if controls_enabled and siren_on and not siren_muted else -80.0


func _update_nitro(delta: float, fspeed: float) -> void:
	# only a real slide refills it (holding SPACE in a straight line slides nothing, so it earns nothing)
	var slide: float = absf(slip_angle())
	if slide > 0.2 and absf(fspeed) > 10.0 and wheels_in_contact() >= 2:
		nitro += NITRO_DRIFT_REFILL * clampf((slide - 0.2) / 0.3, 0.0, 1.0) * delta
	if boosting:
		nitro -= NITRO_DRAIN * delta
		if nitro <= 0.0 or not in_nitro or in_brake > 0.05:
			boosting = false
	else:
		nitro += NITRO_REFILL * delta
		boosting = in_nitro and nitro > 0.15 and in_brake < 0.05 and fspeed > 2.0
	nitro = clampf(nitro, 0.0, 1.0)
	for f in flames:
		f.visible = boosting
		if boosting:
			f.scale = Vector3(1.0, randf_range(0.8, 1.6), 1.0)
			f.position.z = 2.2 + f.scale.y * 0.5


## Spike strip: tyres shredded for a while (less grip, much less top speed).
func hit_spikes() -> void:
	spiked_t = SPIKE_TIME
	boosting = false
	snd_crash.play()


## Tell the car which local axis is "forward". The front wheels steer, and the
## visual (headlights, cabin) is flipped to match.
func set_forward(f: Vector3) -> void:
	fwd_local = f
	if visual != null:
		visual.rotation.y = 0.0 if f.z < 0.0 else PI
	for w in wheels:
		var front: bool = (w.position.z * f.z) > 0.0
		w.use_as_steering = front
		w.use_as_traction = true
		w.set_meta("grip", GRIP_FRONT if front else GRIP_REAR)
	hb_amount = 0.0
	_apply_grip()


# ------------------------------------------------------------------- helpers
func wheels_in_contact() -> int:
	var n := 0
	for w in wheels:
		if w.is_in_contact():
			n += 1
	return n


func forward_world() -> Vector3:
	return global_transform.basis * fwd_local


func forward_speed() -> float:
	return linear_velocity.dot(forward_world())


func spawn_transform(pos: Vector3, dir: Vector3) -> Transform3D:
	var b: Basis = Basis.looking_at(dir, Vector3.UP)
	if fwd_local.z > 0.0:
		b = b * Basis(Vector3.UP, PI)
	return Transform3D(b, pos)


func teleport(xf: Transform3D) -> void:
	var rid: RID = get_rid()
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	steering = 0.0
	flipped_t = 0.0
	stuck_t = 0.0
	reverse_t = 0.0
	drifting = false


## Busted cars stay visible but stop colliding with other cars (they'd be a wreck
## blocking the road for everyone else). Cars live on layer 2; the world on layer 1.
func set_ghost(on: bool) -> void:
	collision_layer = 4 if on else 2
	collision_mask = 1 if on else 3


func respawn() -> void:
	sc_plan = -1
	var i: int = track.nearest_index(global_position, idx, 30)
	_set_idx(i)
	teleport(spawn_transform(track.points[i] + Vector3(0, 0.8, 0), track.tangents[i]))


func max_steer_angle(speed: float) -> float:
	# much more lock at speed than v0.0 (it used to be 0.52 / (1 + 0.1 v))
	return maxf(0.09, 0.62 / (1.0 + 0.045 * speed))


## +ve = velocity points to the left of where the nose points.
func slip_angle() -> float:
	var v: Vector3 = linear_velocity
	var f: Vector3 = forward_world()
	var l: Vector3 = Vector3.UP.cross(f)
	return atan2(v.dot(l), maxf(absf(v.dot(f)), 0.5))


func _set_idx(new_idx: int) -> void:
	var d: int = new_idx - idx
	var half: int = int(track.count * 0.5)
	if d > half:
		d -= track.count
	elif d < -half:
		d += track.count
	prog += float(d)
	idx = new_idx


func _set_handbrake(on: bool, delta: float = 0.016) -> void:
	# grip fades in/out instead of snapping, so the slide builds and recovers smoothly
	hb_amount = move_toward(hb_amount, 1.0 if on else 0.0, (9.0 if on else 4.0) * delta)
	_apply_grip()


func _apply_grip() -> void:
	for w in wheels:
		var grip: float = w.get_meta("grip", GRIP_FRONT)
		if not w.use_as_steering:
			grip *= lerpf(DRIFT_HOLD_GRIP if drifting else 1.0, HANDBRAKE_REAR_GRIP, hb_amount)
		if on_dirt:
			grip *= track.SC_GRIP
		if spiked_t > 0.0:
			grip *= 0.7
		w.wheel_friction_slip = grip


## Arcade stability: steer the car's yaw rate toward what the driver is asking for.
## Normal driving: quick, grip-limited turn-in. Handbrake: the assist holds the
## SLIDE ANGLE (nose vs travel direction) at a controllable value, so a drift is
## smooth and snaps back when released; only a long full-lock drift pushes the
## angle far enough to really spin the car.
func _yaw_assist(delta: float, fspeed: float) -> void:
	var v: Vector3 = linear_velocity
	v.y = 0.0
	var vang: float = atan2(-v.x, -v.z)
	var w_v: float = clampf(wrapf(vang - prev_vel_ang, -PI, PI) / maxf(delta, 0.0001), -3.0, 3.0)
	prev_vel_ang = vang
	if wheels_in_contact() < 2 or fspeed < 3.0:
		drift_t = 0.0
		drifting = false
		return
	var w: float = angular_velocity.y
	var beta: float = slip_angle()
	var target: float
	var gain: float
	_update_drift(fspeed, beta)
	if drifting:
		# steer INTO the drift = wider angle (and, held ~2 s, wider still); a little steer = medium angle;
		# counter-steer = straighten up.
		var into: float = in_steer * drift_dir
		if into > 0.5:
			drift_t += delta
		else:
			drift_t = maxf(0.0, drift_t - 2.0 * delta)
		var amount: float = DRIFT_SLIP + DRIFT_SLIP_EXTRA * clampf((drift_t - 0.7) / 1.3, 0.0, 1.0)
		if into < -0.5:
			amount = DRIFT_SLIP * 0.3
		elif into < 0.5:
			amount = DRIFT_SLIP * 0.75
		var slip_t: float = -drift_dir * amount
		target = w_v - DRIFT_K * (slip_t - beta)
		# entry builds up with the handbrake (a stiff assist here kills the turn-in); held on throttle after
		# SPACE is released, it keeps a firm grip on the angle
		gain = DRIFT_ASSIST * (hb_amount if in_handbrake else maxf(hb_amount, 0.6))
	else:
		drift_t = 0.0
		var drive_t: float = fspeed * tan(steering) / WHEELBASE
		var w_max: float = YAW_GRIP_G / maxf(fspeed, 8.0)
		drive_t = clampf(drive_t, -w_max, w_max)
		var rec_t: float = w_v + DRIFT_K * beta  # straighten out after a slide
		target = lerpf(drive_t, rec_t, clampf((absf(beta) - 0.1) / 0.3, 0.0, 1.0))
		gain = YAW_ASSIST
	angular_velocity.y = w + (target - w) * clampf(gain * delta, 0.0, 1.0)


## Start a drift with SPACE + steering at speed. After SPACE is let go it holds while you keep the gas on
## and steer into the turn; braking, lifting off, centring the wheel or straightening out ends it.
func _update_drift(fspeed: float, beta: float) -> void:
	if not drifting:
		if hb_amount > 0.25 and absf(in_steer) > 0.5 and fspeed > 10.0:
			drifting = true
			drift_dir = signf(in_steer)
		return
	var steer_into: bool = in_steer * drift_dir > 0.2
	var holding: bool = in_handbrake or (in_throttle > 0.05 and steer_into and absf(beta) > 0.12)
	if linear_velocity.length() < 8.0 or in_brake > 0.05 or not holding:
		drifting = false


func _animate_siren(delta: float) -> void:
	siren_t += delta
	var phase: bool = int(siren_t * 7.0) % 2 == 0
	# Real lights only on the nearest cop (Main's `siren_on`) and only when close: every real light
	# re-draws everything it touches in this renderer. Other cops flash their lens glow only, which
	# reads the same at a distance.
	var real: bool = siren_on and cam != null and cam.global_position.distance_squared_to(global_position) < LIGHT_RANGE * LIGHT_RANGE
	if model != null:
		model.set_siren(phase, real)
		return
	siren_mats[0].emission_energy_multiplier = 4.0 if phase else 0.2
	siren_mats[1].emission_energy_multiplier = 0.2 if phase else 4.0
	siren_lights[0].visible = real and phase
	siren_lights[1].visible = real and not phase
	siren_lights[0].light_energy = 3.0
	siren_lights[1].light_energy = 3.0


# -------------------------------------------------------------- main update
func _process(_delta: float) -> void:
	if model != null:
		model.sync_wheels(wheels)   # model wheels copy bounce / steer / spin of the physics wheels


func _physics_process(delta: float) -> void:
	if model != null:
		model.physics_tick(self, wheels)
	if track != null:
		_set_idx(track.locate(global_position, idx))
		on_dirt = track.last_on_shortcut
	_update_audio(delta)
	spiked_t = maxf(0.0, spiked_t - delta)
	if is_cop:
		_animate_siren(delta)
	reset_cd = maxf(0.0, reset_cd - delta)

	var speed: float = linear_velocity.length()
	apply_central_force(Vector3.DOWN * speed * speed * 0.5)  # a little downforce

	if calibrating:
		return  # Main drives engine/brake directly during the self-test

	if not controls_enabled:
		in_throttle = 0.0
		in_brake = 0.0
		in_steer = 0.0
		engine_force = 0.0
		brake = BRAKE_FORCE
		steering = move_toward(steering, 0.0, 4.0 * delta)
		_set_handbrake(false, delta)
		boosting = false
		_update_nitro(delta, 0.0)
		return

	var fspeed: float = forward_speed()
	if scripted:
		pass
	elif is_player and not auto_drive:
		_read_player()
	else:
		_drive_ai(delta, fspeed)
	_apply_controls(delta, fspeed)
	_check_flip(delta)


func _apply_controls(delta: float, fspeed: float) -> void:
	var speed: float = absf(fspeed)
	steering = move_toward(steering, in_steer * max_steer_angle(speed), STEER_RATE * delta)

	var eng: float = 0.0
	var brk: float = 0.0
	if in_brake > 0.05 and fspeed > 1.5:
		brk = BRAKE_FORCE * in_brake
	elif in_brake > 0.05:
		if fspeed > -12.0:
			eng = -REVERSE_FORCE * in_brake
	elif in_throttle > 0.05 and fspeed < -1.5:
		brk = BRAKE_FORCE * in_throttle
	elif in_throttle > 0.05 or boosting:
		var top: float = top_speed * (NITRO_TOP if boosting else 1.0) * (0.55 if spiked_t > 0.0 else 1.0)
		var fade: float = clampf(1.0 - pow(speed / top, 2.0), 0.0, 1.0)
		eng = ENGINE_FORCE * (NITRO_POWER if boosting else maxf(in_throttle, 0.0)) * fade
	else:
		brk = 3.0  # rolling resistance / engine braking
	engine_force = eng * engine_scale
	brake = brk
	# Handbrake without steering: rear brake + less power, so it just slows you down (and, with no
	# slide, earns no nitro). With steering it starts a drift instead (the slide itself costs speed).
	var straight: float = 0.0 if drifting or absf(in_steer) > 0.3 else hb_amount
	if straight > 0.0:
		for w in wheels:
			if not w.use_as_steering:
				w.engine_force = 0.0   # Godot ignores a wheel's brake while it has engine force
				w.brake = brk + HANDBRAKE_FORCE * straight
			else:
				w.engine_force = engine_force * lerpf(1.0, HANDBRAKE_ENGINE, straight)
	_update_nitro(delta, fspeed)
	_set_handbrake(in_handbrake, delta)
	_yaw_assist(delta, fspeed)


func _check_flip(delta: float) -> void:
	if global_transform.basis.y.dot(Vector3.UP) < 0.35:
		flipped_t += delta
	else:
		flipped_t = 0.0
	if flipped_t > 2.0:
		respawn()


# ------------------------------------------------------------- player driver
func _read_player() -> void:
	var up: bool = Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var down: bool = Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var left: bool = Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right: bool = Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	in_throttle = 1.0 if up else 0.0
	in_brake = 1.0 if down else 0.0
	in_steer = (1.0 if left else 0.0) - (1.0 if right else 0.0)
	in_handbrake = Input.is_physical_key_pressed(KEY_SPACE)
	in_nitro = Input.is_physical_key_pressed(KEY_SHIFT)
	if is_cop:   # F = siren sound on / off
		var f_down: bool = Input.is_physical_key_pressed(KEY_F)
		if f_down and not _siren_key_down:
			siren_muted = not siren_muted
		_siren_key_down = f_down
	if Input.is_physical_key_pressed(KEY_R) and reset_cd <= 0.0:
		respawn()
		reset_cd = 1.5


# ------------------------------------------------------------------- AI driver
func _drive_ai(delta: float, fspeed: float) -> void:
	in_handbrake = false
	var speed: float = absf(fspeed)

	# Watchdog: no real progress along the track for a while (wedged, spun out...)?
	# Put the car back on the road. Cops sitting next to their target are fine.
	watch_t += delta
	if prog - watch_prog >= 3.0:
		watch_prog = prog
		watch_t = 0.0
	elif watch_t > 7.0:
		var near_target: bool = target_car != null and global_position.distance_to(target_car.global_position) < 30.0
		if not near_target:
			if log_events:
				print("[respawn] %s at %s idx=%d" % [name, str(global_position), idx])
			respawn()
		watch_prog = prog
		watch_t = 0.0

	# Stuck against something? Back out for a moment.
	if reverse_t > 0.0:
		reverse_t -= delta
		in_throttle = 0.0
		in_brake = 1.0
		in_steer = 0.0
		return
	if in_throttle > 0.4 and speed < 1.0:
		stuck_t += delta
		if stuck_t > 1.5:
			reverse_t = 1.2
			stuck_t = 0.0
	else:
		stuck_t = 0.0

	var pos: Vector3 = global_position
	var look_dist: float = 10.0 + speed * 0.8
	var look_idx: int = (idx + int(look_dist / track.spacing) + 1) % track.count
	var target: Vector3 = track.points[look_idx] + track.right_at(look_idx) * (dodge if dodge != INF else lane)

	# Shortcuts: robbers decide once per approach (about 30% take it). Cops stick to the main road.
	var sc: int = track.shortcut_near(idx, 8)
	if sc < 0:
		sc_decided = -1
		sc_plan = -1
	elif sc_decided != sc:
		sc_decided = sc
		sc_plan = sc if (not is_cop and randf() < 0.3) else -1
	if sc_plan >= 0 and not on_dirt and idx > int(track.shortcuts[sc_plan]["a"]) + 4:
		sc_plan = -1   # missed the mouth (or got reset onto the main road): stay on the main road
	var on_sc: bool = sc_plan >= 0 and sc == sc_plan
	if on_sc:
		var p: PackedVector3Array = track.shortcuts[sc]["pts"]
		var bk: int = 0
		var bd: float = INF
		for k in range(p.size()):
			var d: float = p[k].distance_squared_to(pos)
			if d < bd:
				bd = d
				bk = k
		if idx < int(track.shortcuts[sc]["a"]) and not on_dirt:
			target = p[2]   # line up on the mouth first; cutting across early hits the wall beside it
		else:
			var step: int = int(look_dist / 4.0) + 1
			if bk + step < p.size():
				target = p[bk + step]

	# Close behind the target and roughly ahead of us on the track? Go straight at them.
	var pursuing: bool = false
	if target_car != null:
		var along: float = (target_car.prog - prog) * track.spacing
		var dist_p: float = pos.distance_to(target_car.global_position)
		if dist_p < 45.0 and along > 0.0 and along < 60.0:
			var lp: Vector3 = global_transform.affine_inverse() * target_car.global_position
			if lp.dot(fwd_local) > 0.0:
				target = target_car.global_position + target_car.linear_velocity * 0.35
				pursuing = true

	# Steering: pure pursuit toward the target point.
	var local: Vector3 = global_transform.affine_inverse() * target
	var lf: float = local.dot(fwd_local)
	var lat: float = local.dot(Vector3.UP.cross(fwd_local))  # + = target is on our left
	var alpha: float = atan2(lat, maxf(lf, 0.01))
	var ld: float = maxf(local.length(), 4.0)
	var wanted: float = atan(2.0 * WHEELBASE * sin(alpha) / ld)
	in_steer = clampf(wanted / max_steer_angle(speed), -1.0, 1.0)

	# Speed: cruise target, capped by what the upcoming corners allow.
	var limit: float = track.speed_limit_ahead(idx, 20.0 + speed * speed / 16.0, 8.0)
	if on_sc and (on_dirt or idx >= int(track.shortcuts[sc]["a"]) - 3):
		limit = minf(limit, track.SC_SPEED)   # brake at the mouth only: earlier, the cars behind queue up
	var tgt: float = minf(ai_speed * pace, limit)
	if pursuing:
		tgt = minf(maxf(tgt, target_car.linear_velocity.length() + 3.0), limit * 1.1)
	# Robbers don't rear-end each other: ease off behind a slower car in front.
	if not is_cop:
		var f: Vector3 = forward_world()
		var l: Vector3 = Vector3.UP.cross(f)
		for o in get_tree().get_nodes_in_group("cars"):
			if o == self or o.is_cop or o.busted or o.gone:
				continue
			var rel: Vector3 = o.global_position - pos
			var ahead: float = rel.dot(f)
			if ahead > 0.0 and ahead < 16.0 and absf(rel.dot(l)) < 3.3:
				var ov: float = maxf(o.linear_velocity.dot(f), 0.0)
				tgt = minf(tgt, ov + (ahead - 7.0) * 1.2)
	if absf(alpha) > 0.9:
		tgt = minf(tgt, 12.0)  # pointing the wrong way: slow down and sort it out

	# Nitrous: only on a clear road ahead. Robbers use it to break away from a cop (or to catch up);
	# cops only when well behind their target, so it closes the gap but never makes an arrest cheap.
	var open_road: bool = limit > speed + 10.0 and absf(alpha) < 0.15 and not on_sc and dodge == INF
	var want: bool = false
	if is_cop:
		want = target_car != null and (target_car.prog - prog) * track.spacing > 70.0
	else:
		want = pace > 1.02 or _cop_near(30.0)
	in_nitro = open_road and want and (boosting or nitro > 0.5)
	if boosting:
		tgt = minf(tgt * NITRO_TOP, limit)

	if speed < tgt - 1.0:
		in_throttle = clampf((tgt - speed) / 4.0, 0.3, 1.0)
		in_brake = 0.0
	elif speed > tgt + 1.5:
		in_throttle = 0.0
		in_brake = clampf((speed - tgt) / 8.0, 0.2, 1.0)
	else:
		in_throttle = 0.25
		in_brake = 0.0
	dbg = "tgt=%.1f limit=%.1f thr=%.2f brk=%.2f steer=%.2f" % [tgt, limit, in_throttle, in_brake, in_steer]


func _cop_near(r: float) -> bool:
	for o in get_tree().get_nodes_in_group("cars"):
		if o.is_cop and o.global_position.distance_squared_to(global_position) < r * r:
			return true
	return false
