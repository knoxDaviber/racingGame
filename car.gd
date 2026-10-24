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
var siren_t: float = 0.0
var siren_lights: Array = []
var siren_mats: Array = []

var reset_cd: float = 0.0
var prev_vel_ang: float = 0.0
var drift_t: float = 0.0
var hb_amount: float = 0.0     # 0..1 how engaged the handbrake slide is
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
	box.size = Vector3(1.8, 0.5, 4.2)
	col.shape = box
	col.position = Vector3(0, 0.1, 0)
	add_child(col)
	var col2 := CollisionShape3D.new()
	var box2 := BoxShape3D.new()
	box2.size = Vector3(1.5, 0.5, 2.0)
	col2.shape = box2
	col2.position = Vector3(0, 0.6, 0.35)
	add_child(col2)

	_build_visual()
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
		_box(Vector3(1.8, 0.5, 4.2), Vector3(0, 0.1, 0), _paint(body_color, 0.6, 0.3))
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


## Busted cars stay visible but stop colliding with other cars (they'd be a wreck
## blocking the road for everyone else). Cars live on layer 2; the world on layer 1.
func set_ghost(on: bool) -> void:
	collision_layer = 4 if on else 2
	collision_mask = 1 if on else 3


func respawn() -> void:
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
			grip *= lerpf(1.0, HANDBRAKE_REAR_GRIP, hb_amount)
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
		return
	var w: float = angular_velocity.y
	var beta: float = slip_angle()
	var target: float
	var gain: float
	if hb_amount > 0.25:
		if absf(in_steer) > 0.8:
			drift_t += delta
		else:
			drift_t = maxf(0.0, drift_t - 2.0 * delta)
		var slip_t: float = -in_steer * (DRIFT_SLIP + DRIFT_SLIP_EXTRA * clampf((drift_t - 0.7) / 1.3, 0.0, 1.0))
		target = w_v - DRIFT_K * (slip_t - beta)
		gain = DRIFT_ASSIST * hb_amount
	else:
		drift_t = 0.0
		var drive_t: float = fspeed * tan(steering) / WHEELBASE
		var w_max: float = YAW_GRIP_G / maxf(fspeed, 8.0)
		drive_t = clampf(drive_t, -w_max, w_max)
		var rec_t: float = w_v + DRIFT_K * beta  # straighten out after a slide
		target = lerpf(drive_t, rec_t, clampf((absf(beta) - 0.1) / 0.3, 0.0, 1.0))
		gain = YAW_ASSIST
	angular_velocity.y = w + (target - w) * clampf(gain * delta, 0.0, 1.0)


func _animate_siren(delta: float) -> void:
	siren_t += delta
	var phase: bool = int(siren_t * 7.0) % 2 == 0
	siren_mats[0].emission_energy_multiplier = 4.0 if phase else 0.2
	siren_mats[1].emission_energy_multiplier = 0.2 if phase else 4.0
	siren_lights[0].light_energy = 3.0 if phase else 0.0
	siren_lights[1].light_energy = 0.0 if phase else 3.0


# -------------------------------------------------------------- main update
func _physics_process(delta: float) -> void:
	if track != null:
		_set_idx(track.nearest_index(global_position, idx, 20))
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
	elif in_throttle > 0.05:
		var fade: float = clampf(1.0 - pow(speed / top_speed, 2.0), 0.0, 1.0)
		eng = ENGINE_FORCE * in_throttle * fade
	else:
		brk = 3.0  # rolling resistance / engine braking
	engine_force = eng * engine_scale
	brake = brk
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
	var target: Vector3 = track.points[look_idx] + track.right_at(look_idx) * lane

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
	var tgt: float = minf(ai_speed * pace, limit)
	if pursuing:
		tgt = minf(maxf(tgt, target_car.linear_velocity.length() + 3.0), limit * 1.1)
	# Robbers don't rear-end each other: ease off behind a slower car in front.
	if not is_cop:
		var f: Vector3 = forward_world()
		var l: Vector3 = Vector3.UP.cross(f)
		for o in get_tree().get_nodes_in_group("cars"):
			if o == self or o.is_cop or o.busted:
				continue
			var rel: Vector3 = o.global_position - pos
			var ahead: float = rel.dot(f)
			if ahead > 0.0 and ahead < 16.0 and absf(rel.dot(l)) < 3.3:
				var ov: float = maxf(o.linear_velocity.dot(f), 0.0)
				tgt = minf(tgt, ov + (ahead - 7.0) * 1.2)
	if absf(alpha) > 0.9:
		tgt = minf(tgt, 12.0)  # pointing the wrong way: slow down and sort it out

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
