extends RefCounted
## Hooks a real 3D car model (.glb / .gltf / .tscn) onto the car physics in car.gd.
##
## This file does NOT change the hitbox, the wheel physics or the controls. The model is
## pure decoration. It gets:
##   1. scaled to fit the hitbox and stood on the road, nose pointing the way the car drives,
##   2. wheels that copy what the real VehicleWheel3D nodes do (bounce, steer, spin),
##   3. siren lights that flash on cop cars (hidden on everybody else),
##   4. the racer's colour on its body paint (player + robbers only): the model's red paint is swapped for the colour.
##
## Your model needs nodes with these names (case, spaces, "_" and ".001" are ignored):
##     Wheel FL   Wheel FR   Wheel BL   Wheel BR      F/B = front/back, L/R = left/right
##     RedLight   BlueLigh(t)                          optional, cops only
## A name can sit on a plain Node3D, a MeshInstance3D, a Light3D, or a group with several
## meshes inside it. Nothing else in the model has to be named.

# ================================ SETTINGS ================================
# res:// paths (right-click a file in the FileSystem dock -> Copy Path).
# Leave "" and the project is searched for a scene that contains the four wheel nodes.
const COP_MODEL: String = "res://Resources/Models/Cars/PoliceCar/PoliceCar.gltf"
const ROBBER_MODEL: String = "res://Resources/Models/Cars/RacingCar/RacingCar.gltf"          # player + AI robbers. "" = reuse the cop model (sirens off)
const MODEL_BY_DRIVER: Dictionary = {}   # optional per-car override, e.g. {"YOU": "res://cars/sport.glb", "COP 2": "res://cars/swat.glb"}

const FIT_TO_HITBOX: bool = true         # scale each model to exactly the hitbox length (4.2 m). false = keep its own size
const YAW_OFFSET_DEG: float = 0.0        # set to 180 if a car drives backwards (its F / B wheel names are swapped)
const TINT_ROBBERS: bool = true          # paint the player / robbers in their racer colour
const ROAD_SURFACE: float = 0.05         # height of the visible road above the physics ground (track.gd)
const TIRE_SINK: float = 0.01            # how far the tyres sink into the visible road
const RIDE_HEIGHT_GUESS: float = 0.225   # car origin above the ground when parked; measured for real at runtime

const SIREN_GLOW_ON: float = 4.0
const SIREN_GLOW_OFF: float = 0.2
const SIREN_LIGHT_ENERGY: float = 3.0
const SIREN_LIGHT_RANGE: float = 14.0

# Racing car: the materials that are its RED body paint, by their material names in the model (FileSystem: double-click the
# model -> Materials). Only the red of these is replaced by the racer's colour (paint_recolor.gdshader), so the flames, trim,
# chrome, rubber, seats and lights keep their texture. They are the red body (3 materials sharing one texture), the flame
# panels and the red rims.
# Leave the list empty to use the old rule instead (multiply every textured, non-glass, non-wheel material by the colour).
const PAINT_MATERIALS: Array = ["material_4", "material_43", "material_49", "material_15", "material_19", "material_23", "material_27", "material_44"]
const PAINT_SHADER: String = "res://Resources/Shaders/paint_recolor.gdshader"
const PAINT_METALLIC: float = 0.3      # how metallic / how rough the repainted body looks
const PAINT_ROUGHNESS: float = 0.35
# ==========================================================================

const WHEEL_KEYS: Array = ["wheelfl", "wheelfr", "wheelbl", "wheelbr"]
const WHEEL_ALIASES: Dictionary = {"wheelrl": "wheelbl", "wheelrr": "wheelbr"}   # R = rear also accepted
const SIREN_COLORS: Array = [["red", Color(1.0, 0.05, 0.05)], ["blue", Color(0.1, 0.25, 1.0)]]

# shared by every car in the session
static var _scenes: Dictionary = {}      # path -> PackedScene (null = failed to load)
static var _auto_path: String = ""
static var _auto_done: bool = false
static var _auto_hint: String = ""       # why auto-find found nothing (shown to the user)
static var _said: Dictionary = {}
static var _rest: Dictionary = {}        # the physics rig's resting pose, measured once (see physics_tick)
static var _paint_shader: Shader = null  # paint_recolor.gdshader, loaded once
static var _paint_shader_tried: bool = false

var visual: Node3D                       # the car's "visual" node we live under
var model_root: Node3D
var wheel_groups: Array = []             # [{hub, radius, nodes: [{node, inv, rest_v}]}]
var sirens: Array = []                   # [{red: bool, mats: [], lights: [], energy: []}]
var y_bottom: float = 0.0                # lowest point of the tyres in `visual` space
var _age: int = 0
var _calm: int = 0
var _tries: int = 0
var _placed_c: float = -1.0


# ================================ building ================================
## Returns false when no usable model exists; car.gd then builds its box car instead.
func attach(p_visual: Node3D, is_cop: bool, driver: String, color: Color, fit_length: float) -> bool:
	visual = p_visual
	var path: String = _resolve_path(is_cop, driver)
	var scene: PackedScene = _load_scene(path)
	if scene == null:
		var why: String = _auto_hint if (path == "" and _auto_hint != "") else "put your model's path in COP_MODEL / ROBBER_MODEL at the top of car_model.gd"
		_say("none", "no usable car model, using the built-in box car. " + why, true)
		return false
	var inst: Node = scene.instantiate()
	if not (inst is Node3D):
		inst.free()
		_say(path, "%s is not a 3D scene" % path, true)
		return false

	var root: Node3D = _strip_physics(inst as Node3D)
	var named: Dictionary = _find_named(root)
	var missing: Array = []
	for k in WHEEL_KEYS:
		if (named[k] as Array).is_empty():
			missing.append(k)
	if not missing.is_empty():
		_say(path, "%s has no node for %s. Wheel-like names in it: %s. Name them Wheel FL, Wheel FR, Wheel BL, Wheel BR" % [path, str(missing), str(_names_like(root, ["wheel", "tyre", "tire"]))], true)
		root.free()
		return false

	# `holder` only exists so transforms can be measured relative to a clean origin.
	var holder := Node3D.new()
	holder.add_child(root)

	# --- wheel hubs (centre of each wheel's meshes), and which way the nose points
	var wmeshes: Dictionary = {}
	var hub0: Dictionary = {}
	for k in WHEEL_KEYS:
		var list: Array = []
		for n in named[k]:
			list.append_array(_meshes(n, holder))
		var b: AABB = _box_of(list, Transform3D.IDENTITY)
		if b.size.length() < 0.0001:
			_say(path, "%s: the '%s' node has no visible mesh inside it" % [path, k], true)
			holder.free()
			return false
		wmeshes[k] = list
		hub0[k] = b.get_center()
	var front: Vector3 = ((hub0["wheelfl"] as Vector3) + (hub0["wheelfr"] as Vector3)) * 0.5
	var back: Vector3 = ((hub0["wheelbl"] as Vector3) + (hub0["wheelbr"] as Vector3)) * 0.5
	var d: Vector3 = front - back
	var yaw: float = snappedf(atan2(d.x, -d.z), PI * 0.5) + deg_to_rad(YAW_OFFSET_DEG)   # turn the nose to -Z
	var rot := Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO)

	# --- size, scale and placement
	var body: AABB = _box_of(_meshes(root, holder), rot)      # whole model, nose along -Z
	var s: float = 1.0
	if FIT_TO_HITBOX and fit_length > 0.0 and body.size.z > 0.01:
		s = fit_length / body.size.z
	var wbox: Dictionary = {}
	var mid := Vector3.ZERO
	var bottoms: float = 0.0
	for k in WHEEL_KEYS:
		var wb: AABB = _box_of(wmeshes[k], rot)
		wbox[k] = wb
		mid += wb.get_center() * 0.25
		bottoms += wb.position.y * 0.25
	# centre the car on its axles so the model straddles the physics wheels like the box car did
	var fit := Transform3D(rot.basis.scaled(Vector3(s, s, s)), Vector3(-mid.x * s, 0.0, -mid.z * s))
	y_bottom = bottoms * s

	# --- the wheels: remember where each hub is and how each node sits at rest
	var radii: float = 0.0
	for k in WHEEL_KEYS:
		var wb: AABB = wbox[k]
		var recs: Array = []
		for n in named[k]:
			var node: Node3D = n
			var parent_xf: Transform3D = fit * _rel(node.get_parent(), holder)
			recs.append({"node": node, "inv": parent_xf.affine_inverse(), "rest_v": parent_xf * node.transform})
		var radius: float = maxf(wb.size.y, wb.size.z) * 0.5 * s
		radii += radius * 0.25
		wheel_groups.append({"hub": wb.get_center() * s + fit.origin, "radius": radius, "nodes": recs})

	# --- sirens, then paint
	var skip: Array = []
	for k in WHEEL_KEYS:
		skip.append_array(named[k])
	var siren_names: Array = []
	_setup_sirens(named, is_cop, holder, fit)
	for key in ["red", "blue"]:
		skip.append_array(named[key])
		for n in named[key]:
			siren_names.append(String((n as Node).name))
	var painted: int = 0
	if TINT_ROBBERS and not is_cop:
		painted = _tint(root, skip, color)

	# --- go live
	holder.remove_child(root)
	model_root = Node3D.new()
	model_root.name = "Model"
	model_root.transform = fit
	model_root.add_child(root)
	visual.add_child(model_root)
	holder.free()
	_place(RIDE_HEIGHT_GUESS)

	_say("ok:" + path, "%s: turned %d deg to face forward, native %.2f x %.2f x %.2f m (L x W x H) -> scaled x%.3f (model now %.1f m long), tyre radius %.2f m, sirens %s, repainted %d materials" % [path, int(roundf(rad_to_deg(wrapf(yaw, -PI, PI)))), body.size.z, body.size.x, body.size.y, s, body.size.z * s, radii, str(siren_names), painted], false)
	return true


## Sirens: cops flash them, everybody else hides them.
func _setup_sirens(named: Dictionary, is_cop: bool, holder: Node3D, fit: Transform3D) -> void:
	for pair in SIREN_COLORS:
		var nodes: Array = named[pair[0]]
		var color: Color = pair[1]
		if not is_cop:
			for n in nodes:
				(n as Node3D).visible = false
			continue
		if nodes.is_empty():
			continue
		var rec: Dictionary = {"red": pair[0] == "red", "mats": [], "lights": [], "energy": []}
		var meshes: Array = []
		for n in nodes:
			var lights: Array = (n as Node).find_children("*", "Light3D", true, false)
			if n is Light3D:
				lights.push_front(n)
			for l in lights:
				var lt: Light3D = l
				rec["energy"].append(lt.light_energy if lt.light_energy > 0.01 else SIREN_LIGHT_ENERGY)
				lt.light_color = color
				lt.light_energy = 0.0
				rec["lights"].append(lt)
			meshes.append_array(_meshes(n, holder))
		for e in meshes:
			var mi: MeshInstance3D = e[0]
			for si in range(mi.mesh.get_surface_count()):
				var base: Material = mi.get_active_material(si)
				var m: BaseMaterial3D
				if base is BaseMaterial3D:
					m = (base as BaseMaterial3D).duplicate()
				else:
					m = StandardMaterial3D.new()
				m.albedo_color = Color(color.r, color.g, color.b, m.albedo_color.a)
				m.emission_enabled = true
				m.emission = color
				m.emission_energy_multiplier = SIREN_GLOW_OFF
				mi.set_surface_override_material(si, m)
				rec["mats"].append(m)
		if (rec["lights"] as Array).is_empty() and not meshes.is_empty():
			# the model only has the lens meshes: add a real light so the road flashes too
			var box: AABB = _box_of(meshes, Transform3D.IDENTITY)
			var omni := OmniLight3D.new()
			omni.omni_range = SIREN_LIGHT_RANGE
			omni.light_color = color
			omni.light_energy = 0.0
			omni.position = fit * box.get_center() + Vector3(0.0, 0.15, 0.0)
			visual.add_child(omni)
			rec["lights"].append(omni)
			rec["energy"].append(SIREN_LIGHT_ENERGY)
		sirens.append(rec)


## Same call the box car's siren uses: phase true = red on / blue off.
func set_siren(phase: bool, lights: bool = true) -> void:
	for rec in sirens:
		var on: bool = phase if rec["red"] else not phase
		for m in rec["mats"]:
			(m as BaseMaterial3D).emission_energy_multiplier = SIREN_GLOW_ON if on else SIREN_GLOW_OFF
		for i in range((rec["lights"] as Array).size()):
			((rec["lights"] as Array)[i] as Light3D).light_energy = (rec["energy"] as Array)[i] if on and lights else 0.0


## Paint the racer's body paint in its colour. Returns how many surfaces were repainted.
## With PAINT_MATERIALS set, exactly those materials are repainted (wherever they sit, rims included) and only their red
## is swapped. With the list empty, the old rule applies: every textured, non-glass surface outside the wheels is multiplied.
func _tint(root: Node, skip: Array, color: Color) -> int:
	var done: int = 0
	var cache: Dictionary = {}
	var listed: bool = not PAINT_MATERIALS.is_empty()
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null:
			continue
		var skipped: bool = _under(mi, skip)
		if skipped and not listed:
			continue
		for si in range(mi.mesh.get_surface_count()):
			var base: Material = mi.get_active_material(si)
			if not (base is BaseMaterial3D):
				continue
			var bm: BaseMaterial3D = base as BaseMaterial3D
			if listed:
				if not _is_listed_paint(bm):
					continue
			elif skipped or not _is_paint(bm):
				continue
			if not cache.has(base):
				cache[base] = _repainted(bm, color)
			mi.set_surface_override_material(si, cache[base])
			done += 1
	return done


## True when the material's name is in PAINT_MATERIALS (case ignored).
static func _is_listed_paint(m: BaseMaterial3D) -> bool:
	var nm: String = m.resource_name.to_lower()
	for p in PAINT_MATERIALS:
		if nm == String(p).to_lower():
			return true
	return false


## The same material with its red turned into `color`: keeps the model's own colour texture.
## Falls back to a plain colour multiply if the shader file is missing.
func _repainted(base: BaseMaterial3D, color: Color) -> Material:
	if not _paint_shader_tried:
		_paint_shader_tried = true
		if ResourceLoader.exists(PAINT_SHADER):
			_paint_shader = load(PAINT_SHADER) as Shader
		if _paint_shader == null:
			_say("paint_shader", "'%s' not found, so the paint falls back to a plain colour multiply (red paint will look dark)" % PAINT_SHADER, true)
	if _paint_shader != null and base.albedo_texture != null:
		var sm := ShaderMaterial.new()
		sm.shader = _paint_shader
		sm.set_shader_parameter("albedo_tex", base.albedo_texture)
		sm.set_shader_parameter("paint_color", color)
		sm.set_shader_parameter("metallic_amount", PAINT_METALLIC)
		sm.set_shader_parameter("roughness_amount", PAINT_ROUGHNESS)
		return sm
	var m: BaseMaterial3D = base.duplicate() as BaseMaterial3D
	if m.albedo_texture == null:
		m.albedo_color = Color(color.r, color.g, color.b, m.albedo_color.a)
	else:
		m.albedo_color = m.albedo_color * color     # textured: multiply, keeps the detail
	return m


static func _is_paint(m: BaseMaterial3D) -> bool:
	if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.albedo_color.a < 0.95 or m.emission_enabled:
		return false
	var nm: String = m.resource_name.to_lower()
	for bad in ["glass", "window", "tire", "tyre", "rubber", "headlight", "taillight", "lamp", "chrome", "plate", "interior", "seat", "grill", "mirror", "brake", "rim", "wheel", "siren"]:
		if nm.contains(bad):
			return false
	if m.albedo_texture == null:
		var c: Color = m.albedo_color
		if c.r * 0.299 + c.g * 0.587 + c.b * 0.114 < 0.3:       # dark trim / rubber / glass
			return false
	return true


# ============================== every frame ===============================
## Called from car.gd's _physics_process. Learns the rig's resting pose once, then keeps the
## model standing on the road.
func physics_tick(car, pw: Array) -> void:
	_age += 1
	if pw.size() < 4:
		return
	# frame 3: the car is still in the air, wheels un-steered and un-spun = the engine's rest pose
	if not _rest.has("basis") and _age >= 3:
		_init_rest(pw)
	if not _rest.has("basis"):
		return
	if not _rest.has("c"):
		var calm: bool = absf(car.steering) < 0.02 and car.linear_velocity.length() < 0.05 and car.angular_velocity.length() < 0.05
		for w in pw:
			if not (w as VehicleWheel3D).is_in_contact():
				calm = false
		_calm = _calm + 1 if calm else 0
		if _calm >= 20:
			_measure(car, pw)
	if _rest.has("c") and not is_equal_approx(_placed_c, float(_rest["c"])):
		_place(float(_rest["c"]))


func _quadrant(p: Vector3) -> int:
	return (0 if p.x < 0.0 else 2) + (0 if p.z < 0.0 else 1)


func _init_rest(pw: Array) -> void:
	var g: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var basis: Array = [null, null, null, null]
	var pos: Array = [null, null, null, null]
	var idx: Array = [0, 0, 0, 0]
	for k in range(pw.size()):
		var w: VehicleWheel3D = pw[k]
		var q: int = _quadrant(w.position)
		idx[q] = k
		basis[q] = w.transform.basis
		# equilibrium of the spring: it sags g / (4 * stiffness) from its fully-extended pose
		pos[q] = w.position + Vector3(0.0, g / (4.0 * w.suspension_stiffness), 0.0)
	_rest = {"basis": basis, "pos": pos, "idx": idx}


## Once the car sits still on all four wheels, measure the real height of its origin above
## the road with a ray, and the wheels' real resting positions.
func _measure(car, pw: Array) -> void:
	var from: Vector3 = car.global_position + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, car.global_position + Vector3.DOWN * 2.0, 1, [car.get_rid()])
	var hit: Dictionary = car.get_world_3d().direct_space_state.intersect_ray(query)
	var c: float = RIDE_HEIGHT_GUESS
	if hit.has("position"):
		var measured: float = car.global_position.y - (hit["position"] as Vector3).y
		if measured > 0.02 and measured < 1.0:
			c = measured
			for w in pw:
				_rest["pos"][_quadrant((w as VehicleWheel3D).position)] = (w as VehicleWheel3D).position
	else:
		_tries += 1
		if _tries < 5:
			return
	_rest["c"] = c


## Put the tyres on the visible road (ROAD_SURFACE above the physics ground).
func _place(c: float) -> void:
	visual.position.y = (-c + ROAD_SURFACE - TIRE_SINK) - y_bottom
	_placed_c = c


## Called every rendered frame. Each model wheel copies the matching physics wheel:
## the same bounce, steering and spin, but rotating about ITS OWN hub centre.
func sync_wheels(pw: Array) -> void:
	if _age < 3 or not _rest.has("basis") or pw.size() < 4:
		return
	var rf := Basis(Vector3.UP, visual.rotation.y)     # visual is turned PI when the car drives toward +Z
	var rfi: Basis = rf.inverse()
	for grp in wheel_groups:
		var hub: Vector3 = grp["hub"]
		var q: int = _quadrant(rf * hub)               # which physics wheel sits where this one is
		var w: VehicleWheel3D = pw[(_rest["idx"] as Array)[q]]
		var rot: Basis = rfi * (w.transform.basis * ((_rest["basis"] as Array)[q] as Basis).inverse()) * rf
		var shift: Vector3 = rfi * (w.position - ((_rest["pos"] as Array)[q] as Vector3))
		var pivot := Transform3D(rot, hub - rot * hub + shift)
		for rec in grp["nodes"]:
			((rec as Dictionary)["node"] as Node3D).transform = ((rec as Dictionary)["inv"] as Transform3D) * (pivot * ((rec as Dictionary)["rest_v"] as Transform3D))


# ============================ finding the model ============================
static func _resolve_path(is_cop: bool, driver: String) -> String:
	var p: String = String(MODEL_BY_DRIVER.get(driver, ""))
	if p == "":
		if is_cop:
			p = COP_MODEL if COP_MODEL != "" else ROBBER_MODEL
		else:
			p = ROBBER_MODEL if ROBBER_MODEL != "" else COP_MODEL
	if p == "":
		p = _auto_find()
	return p


static func _load_scene(path: String) -> PackedScene:
	if path == "":
		return null
	if not _scenes.has(path):
		var res: Resource = null
		if ResourceLoader.exists(path):
			res = load(path)
		_scenes[path] = res if res is PackedScene else null
		if _scenes[path] == null:
			_say(path, "could not load '%s'. Check the path (FileSystem dock -> right-click the file -> Copy Path)" % path, true)
	return _scenes[path]


## Search the project for a scene that has all four wheel nodes (.tscn first, then raw imports).
static func _auto_find() -> String:
	if _auto_done:
		return _auto_path
	_auto_done = true
	var found: Array = []
	_scan("res://", found)
	found.sort_custom(func(a: String, b: String) -> bool:
		var ra: int = _ext_rank(a)
		var rb: int = _ext_rank(b)
		return ra < rb or (ra == rb and a < b))
	var near: String = ""
	for p in found:
		var res: Resource = load(p)
		if res is PackedScene:
			var inst: Node = (res as PackedScene).instantiate()
			var missing: Array = []
			var named: Dictionary = _find_named(inst)
			for k in WHEEL_KEYS:
				if (named[k] as Array).is_empty():
					missing.append(k)
			if missing.is_empty():
				_auto_path = p
				_say("auto", "auto-found the car model at %s (set COP_MODEL / ROBBER_MODEL to choose explicitly)" % p, false)
			elif missing.size() < 4 and near == "":
				near = "%s looks like a car but is missing a node for %s. Wheel-like names in it: %s. Name them Wheel FL, Wheel FR, Wheel BL, Wheel BR" % [p, str(missing), str(_names_like(inst, ["wheel", "tyre", "tire"]))]
			inst.free()
			if _auto_path != "":
				break
	if _auto_path == "":
		if near != "":
			_auto_hint = near
		elif found.is_empty():
			_auto_hint = "no .glb / .gltf / .tscn file exists in the project yet"
		else:
			_auto_hint = "searched %d scene file(s) but none has nodes named Wheel FL / Wheel FR / Wheel BL / Wheel BR" % found.size()
	return _auto_path


static func _ext_rank(p: String) -> int:
	return ["tscn", "scn", "glb", "gltf"].find(p.get_extension().to_lower())


static func _main_scene() -> String:
	var s: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	if s.begins_with("uid://"):
		var id: int = ResourceUID.text_to_id(s)
		if ResourceUID.has_id(id):
			s = ResourceUID.get_id_path(id)
	return s


static func _scan(dir: String, out: Array) -> void:
	var main_scene: String = _main_scene()
	for f in DirAccess.get_files_at(dir):
		var fname: String = f
		if fname.ends_with(".import") or fname.ends_with(".remap"):
			fname = fname.get_basename()
		if _ext_rank(fname) >= 0:
			var full: String = dir.path_join(fname)
			if full != main_scene and not out.has(full):
				out.append(full)
	for sub in DirAccess.get_directories_at(dir):
		if not String(sub).begins_with(".") and sub != "addons":
			_scan(dir.path_join(sub), out)


# ================================= helpers =================================
static func _say(key: String, msg: String, warn: bool) -> void:
	if _said.has(key):
		return
	_said[key] = true
	print("[CarModel] ", msg)
	if warn:
		push_warning("[CarModel] " + msg)


## Lower-case letters and digits only, trailing digits dropped: "Wheel FL.001" -> "wheelfl"
static func _norm(s: String) -> String:
	var out: String = ""
	for i in range(s.length()):
		var ch: String = s.substr(i, 1).to_lower()
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	while out.length() > 0 and out.substr(out.length() - 1, 1) >= "0" and out.substr(out.length() - 1, 1) <= "9":
		out = out.substr(0, out.length() - 1)
	return out


static func _find_named(root: Node) -> Dictionary:
	var out: Dictionary = {"wheelfl": [], "wheelfr": [], "wheelbl": [], "wheelbr": [], "red": [], "blue": []}
	for n in root.find_children("*", "Node3D", true, false):
		var key: String = _norm(String(n.name))
		key = String(WHEEL_ALIASES.get(key, key))
		if key.begins_with("wheel") and out.has(key):
			out[key].append(n)
		elif key.begins_with("redlig") or (key.contains("siren") and key.contains("red")):
			out["red"].append(n)
		elif key.begins_with("bluelig") or (key.contains("siren") and key.contains("blue")):
			out["blue"].append(n)
	for k in out.keys():
		out[k] = _outermost(out[k])
	return out


## Drop matches that sit inside another match (we move the outer one, the inner follows).
static func _outermost(list: Array) -> Array:
	var out: Array = []
	for n in list:
		var nested: bool = false
		for m in list:
			if m != n and (m as Node).is_ancestor_of(n):
				nested = true
				break
		if not nested:
			out.append(n)
	return out


static func _names_like(root: Node, words: Array) -> Array:
	var out: Array = []
	for n in root.find_children("*", "", true, false):
		var key: String = _norm(String(n.name))
		for w in words:
			if key.contains(String(w)):
				out.append(String(n.name))
				break
	return out


## A model must be decoration only. If it brings physics nodes (a VehicleBody3D root,
## StaticBody3D "collision" children...), flatten them so they can't fight the real car.
static func _strip_physics(root: Node3D) -> Node3D:
	var out: Node3D = root
	if root is CollisionObject3D:
		out = Node3D.new()
		out.name = root.name
		out.transform = root.transform
		for c in root.get_children():
			root.remove_child(c)
			out.add_child(c)
		root.free()
	for n in out.find_children("*", "CollisionObject3D", true, false):
		var body: Node = n
		var parent: Node = body.get_parent()
		for c in body.get_children():
			if c is CollisionShape3D or c is CollisionPolygon3D:
				continue
			body.remove_child(c)
			if c is Node3D and body is Node3D:
				(c as Node3D).transform = (body as Node3D).transform * (c as Node3D).transform
			parent.add_child(c)
		parent.remove_child(body)
		body.free()
	for n in out.find_children("*", "Camera3D", true, false):
		n.get_parent().remove_child(n)
		n.free()
	return out


## `node`'s transform relative to `top`, composed by hand (works on a scene that isn't in the tree).
static func _rel(node: Node, top: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != top:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _shown(node: Node, top: Node) -> bool:
	var n: Node = node
	while n != null and n != top:
		if n is Node3D and not (n as Node3D).visible:
			return false
		n = n.get_parent()
	return true


static func _under(node: Node, list: Array) -> bool:
	for s in list:
		if s == node or (s as Node).is_ancestor_of(node):
			return true
	return false


## [[MeshInstance3D, transform relative to top], ...] for every visible mesh at or below `node`.
static func _meshes(node: Node, top: Node) -> Array:
	var out: Array = []
	var list: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		list.push_front(node)
	for n in list:
		var mi: MeshInstance3D = n
		if mi.mesh != null and _shown(mi, top):
			out.append([mi, _rel(mi, top)])
	return out


## Bounding box of those meshes after applying `pre`. Size zero = nothing there.
static func _box_of(meshes: Array, pre: Transform3D) -> AABB:
	var have: bool = false
	var box := AABB()
	for e in meshes:
		var mi: MeshInstance3D = e[0]
		var xf: Transform3D = pre * (e[1] as Transform3D)
		var a: AABB = mi.get_aabb()
		for i in range(8):
			var p: Vector3 = xf * a.get_endpoint(i)
			if not have:
				box = AABB(p, Vector3.ZERO)
				have = true
			else:
				box = box.expand(p)
	return box
