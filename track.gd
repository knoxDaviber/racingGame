extends Node3D
## Procedural circuit: a closed Catmull-Rom spline with walls, a road ribbon,
## a start/finish gantry, and helper data (tangents, arc length, safe corner
## speeds) used by the lap counter and the cop AI.

const SUBDIV: int = 12
const LAYOUT_SCALE: float = 1.5  # blow the layout up for longer straights and wider sweepers

## The four legs of the escape, played in order. Time of day moves on with each leg, so the run
## reads as one chase out of town: afternoon suburbs -> sunset coast -> dusk canyon -> night city.
## Control points (x, z); index 0 sits mid-straight (start/finish), loop runs counter-clockwise.
const MAPS: Array = [
	{"name": "SUBURBS", "shortcuts": 1, "time": "Afternoon", "width": 18.0, "scenery": "pines", "lamps": 3,
	"ctrl": [Vector2(-40, 0), Vector2(70, 0), Vector2(150, -10), Vector2(210, -70), Vector2(200, -150),
		Vector2(130, -190), Vector2(60, -170), Vector2(20, -120), Vector2(-30, -140), Vector2(-100, -190),
		Vector2(-170, -150), Vector2(-190, -80), Vector2(-150, -20), Vector2(-95, 2)],
	"ground": Color(0.16, 0.30, 0.14), "road": Color(0.18, 0.18, 0.2), "walls": [Color(0.85, 0.12, 0.12), Color(0.92, 0.92, 0.92)],
	"sky_top": Color(0.22, 0.42, 0.78), "sky_hor": Color(0.75, 0.82, 0.9), "sun_rot": Vector3(-42, -50, 0),
	"sun_col": Color(1.0, 0.93, 0.82), "sun_e": 1.25, "ambient": 0.8, "fog_col": Color(0.72, 0.8, 0.9), "fog_begin": 220.0,
	"lamp": 0.4, "night": false},
	{"name": "COAST ROAD", "shortcuts": 1, "time": "Sunset", "width": 20.0, "scenery": "palms", "lamps": 3,
	"ctrl": [Vector2(-60, 0), Vector2(120, 0), Vector2(260, -20), Vector2(330, -90), Vector2(310, -170),
		Vector2(220, -200), Vector2(100, -180), Vector2(0, -200), Vector2(-110, -210), Vector2(-200, -160),
		Vector2(-220, -80), Vector2(-150, -15)],
	"ground": Color(0.62, 0.55, 0.38), "road": Color(0.2, 0.19, 0.2), "walls": [Color(0.1, 0.45, 0.85), Color(0.95, 0.95, 0.95)],
	"sky_top": Color(0.12, 0.17, 0.38), "sky_hor": Color(0.98, 0.58, 0.35), "sun_rot": Vector3(-14, -20, 0),
	"sun_col": Color(1.0, 0.7, 0.45), "sun_e": 1.1, "ambient": 0.7, "fog_col": Color(0.95, 0.6, 0.45), "fog_begin": 200.0,
	"lamp": 1.2, "night": false},
	{"name": "RED CANYON", "shortcuts": 0, "time": "Dusk", "width": 15.0, "scenery": "rocks", "lamps": 0,
	"ctrl": [Vector2(-40, 0), Vector2(60, 0), Vector2(110, -30), Vector2(100, -80), Vector2(40, -100),
		Vector2(20, -150), Vector2(70, -200), Vector2(150, -210), Vector2(180, -270), Vector2(110, -320),
		Vector2(0, -300), Vector2(-60, -240), Vector2(-130, -250), Vector2(-170, -190), Vector2(-120, -120),
		Vector2(-150, -60), Vector2(-110, -10)],
	"ground": Color(0.55, 0.3, 0.18), "road": Color(0.26, 0.21, 0.19), "walls": [Color(0.95, 0.55, 0.1), Color(0.2, 0.2, 0.22)],
	"sky_top": Color(0.08, 0.07, 0.2), "sky_hor": Color(0.7, 0.32, 0.3), "sun_rot": Vector3(-6, 30, 0),
	"sun_col": Color(1.0, 0.45, 0.3), "sun_e": 0.7, "ambient": 0.55, "fog_col": Color(0.5, 0.28, 0.3), "fog_begin": 140.0,
	"lamp": 2.0, "night": true},
	{"name": "NIGHT CITY", "shortcuts": 1, "time": "Midnight", "width": 16.0, "scenery": "city", "lamps": 2,
	"ctrl": [Vector2(-60, 0), Vector2(60, 0), Vector2(125, 0), Vector2(160, -35), Vector2(160, -85),
		Vector2(125, -120), Vector2(85, -120), Vector2(50, -155), Vector2(50, -185), Vector2(15, -220),
		Vector2(-65, -220), Vector2(-100, -185), Vector2(-100, -110), Vector2(-130, -75), Vector2(-130, -35),
		Vector2(-100, 0)],
	"ground": Color(0.1, 0.1, 0.12), "road": Color(0.1, 0.1, 0.12), "walls": [Color(0.9, 0.85, 0.1), Color(0.15, 0.15, 0.17)],
	"sky_top": Color(0.01, 0.01, 0.04), "sky_hor": Color(0.12, 0.08, 0.2), "sun_rot": Vector3(-50, 120, 0),
	"sun_col": Color(0.55, 0.65, 1.0), "sun_e": 0.18, "ambient": 0.35, "fog_col": Color(0.1, 0.07, 0.16), "fog_begin": 110.0,
	"lamp": 3.5, "night": true},
]

var map: Dictionary = MAPS[0]   # set by Main before build()
var width: float = 18.0
var wall_height: float = 1.6
var wall_thickness: float = 1.2
var a_lat: float = 12.0  # lateral acceleration (m/s^2) the AI assumes it can corner at

const SC_WIDTH: float = 11.0     # shortcuts: narrow,
const SC_GRIP: float = 0.8       # loose dirt,
const SC_SPEED: float = 21.0     # and the AI takes them slowly

var points: PackedVector3Array = PackedVector3Array()
## Shortcuts: [{a, b, pts: PackedVector3Array}]. A dirt cut from main sample a to b (b > a, no wrap).
var shortcuts: Array = []
var last_on_shortcut: bool = false   # set by locate(): did the last lookup land on a shortcut?
var tangents: PackedVector3Array = PackedVector3Array()
var corner_speed: PackedFloat32Array = PackedFloat32Array()  # max sensible speed at each sample
var length: float = 0.0
var count: int = 0
var spacing: float = 1.0  # average distance between samples (metres)


func build() -> void:
	width = float(map["width"])
	_make_centerline()
	_find_shortcuts(int(map.get("shortcuts", 0)))
	_make_ground()
	_make_road()
	_make_walls()
	_make_start_gantry()
	_make_scenery()


# ---------------------------------------------------------------- centerline
func _make_centerline() -> void:
	var ctrl: Array = (map["ctrl"] as Array).duplicate()
	var n: int = ctrl.size()
	for i in range(n):
		ctrl[i] = (ctrl[i] as Vector2) * LAYOUT_SCALE
	for i in range(n):
		var p0: Vector2 = ctrl[(i - 1 + n) % n]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n]
		for s in range(SUBDIV):
			var t: float = float(s) / float(SUBDIV)
			var t2: float = t * t
			var t3: float = t2 * t
			var p: Vector2 = 0.5 * ((2.0 * p1) + (-p0 + p2) * t \
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 \
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			points.append(Vector3(p.x, 0.0, p.y))
	count = points.size()

	for i in range(count):
		var a: Vector3 = points[(i - 1 + count) % count]
		var b: Vector3 = points[(i + 1) % count]
		var d: Vector3 = b - a
		d.y = 0.0
		tangents.append(d.normalized())
		length += points[i].distance_to(points[(i + 1) % count])
	spacing = length / float(count)

	# Curvature -> safe corner speed (smoothed over a few samples).
	var curv: PackedFloat32Array = PackedFloat32Array()
	for i in range(count):
		var t_a: Vector3 = tangents[(i - 1 + count) % count]
		var t_b: Vector3 = tangents[(i + 1) % count]
		var ang: float = acos(clampf(t_a.dot(t_b), -1.0, 1.0))
		curv.append(ang / (2.0 * spacing))
	for i in range(count):
		var k: float = 0.0
		for o in range(-2, 3):
			k = maxf(k, curv[posmod(i + o, count)])
		corner_speed.append(minf(80.0, sqrt(a_lat / maxf(k, 0.0001))))


## Closest centerline sample to `pos`, searching +-window samples around `hint`.
func nearest_index(pos: Vector3, hint: int, window: int) -> int:
	var best: int = hint
	var best_d: float = INF
	for k in range(-window, window + 1):
		var i: int = posmod(hint + k, count)
		var dx: float = points[i].x - pos.x
		var dz: float = points[i].z - pos.z
		var d: float = dx * dx + dz * dz
		if d < best_d:
			best_d = d
			best = i
	return best


## Like nearest_index, but a car out on a shortcut maps to the matching fraction of the
## main loop it skips, so lap progress keeps counting smoothly through the cut.
func locate(pos: Vector3, hint: int) -> int:
	last_on_shortcut = false
	var i: int = nearest_index(pos, hint, 20)
	if shortcuts.is_empty():
		return i
	var lim: float = width * 0.5 + 2.0
	if Vector2(points[i].x - pos.x, points[i].z - pos.z).length_squared() < lim * lim:
		return i
	for sc in shortcuts:
		var p: PackedVector3Array = sc["pts"]
		var bk: int = -1
		var bd: float = INF
		for k in range(p.size()):
			var d: float = Vector2(p[k].x - pos.x, p[k].z - pos.z).length_squared()
			if d < bd:
				bd = d
				bk = k
		if bd < pow(SC_WIDTH * 0.5 + 3.0, 2.0):
			last_on_shortcut = true
			return int(lerpf(float(sc["a"]), float(sc["b"]), float(bk) / float(p.size() - 1)))
	return i


## Shortcut index whose entry is within `ahead` samples of idx (or that idx is inside), else -1.
func shortcut_near(idx: int, ahead: int) -> int:
	for s in range(shortcuts.size()):
		var a: int = shortcuts[s]["a"]
		if idx >= a - ahead and idx < int(shortcuts[s]["b"]) - 1:
			return s
	return -1


## Pick shortcut chords automatically: two samples close as the crow flies but far apart along the
## road, with a clear infield between them (nothing else of the circuit near the cut).
func _find_shortcuts(want: int) -> void:
	var used: Array = []
	for _n in range(want):
		var best: Array = []
		var best_score: float = 0.0
		# windows in metres (maps have different sample spacing); keep clear of the start line
		for a in range(int(150.0 / spacing), count - int(300.0 / spacing), 2):
			for b in range(a + int(220.0 / spacing), mini(a + int(700.0 / spacing), count - int(150.0 / spacing)), 2):
				var chord: Vector3 = points[b] - points[a]
				var cl: float = chord.length()
				if cl < 50.0 or cl > 220.0:
					continue
				var arc: float = float(b - a) * spacing
				var dir: Vector3 = chord / cl
				var da: float = tangents[a].dot(dir)
				var db: float = tangents[b].dot(dir)
				if da < 0.25 or db < 0.25 or da > 0.93 or db > 0.93:
					continue  # mouths: no hairpins, but a clear branch (>~20 deg), never a lane hugging the road
				var clash: bool = false
				for u in used:
					if b > u[0] - 10 and a < u[1] + 10:
						clash = true
				if clash or not _chord_clear(a, b):
					continue
				var score: float = arc / cl
				if score > 1.5 and score > best_score:
					best_score = score
					best = [a, b]
		if best.is_empty():
			return
		used.append(best)
		shortcuts.append({"a": best[0], "b": best[1], "pts": _shortcut_curve(best[0], best[1])})


func _chord_clear(a: int, b: int) -> bool:
	var pa: Vector3 = points[a]
	var pb: Vector3 = points[b]
	var need: float = width + SC_WIDTH + 6.0
	for i in range(count):
		if absi(i - a) < 10 or absi(i - b) < 10 or absi(i - a + count) < 10 or absi(i - b - count) < 10:
			continue
		var q: Vector3 = Geometry3D.get_closest_point_to_segment(points[i], pa, pb)
		if q.distance_to(points[i]) < need:
			return false
	return true


## Straight cut through the infield, sampled every ~3 m (narrow + loose dirt is what makes it hard).
func _shortcut_curve(a: int, b: int) -> PackedVector3Array:
	var n: int = maxi(8, int(points[a].distance_to(points[b]) / 3.0))
	var out := PackedVector3Array()
	for k in range(n + 1):
		out.append(points[a].lerp(points[b], float(k) / float(n)))
	return out


## Does any shortcut pass within r of the wall segment a-b? (then that piece of wall is a mouth)
func _near_shortcut(a: Vector3, b: Vector3, r: float) -> bool:
	a.y = 0.0
	b.y = 0.0
	for sc in shortcuts:
		for p in sc["pts"]:
			if Geometry3D.get_closest_point_to_segment(p, a, b).distance_to(p) < r:
				return true
	return false


func right_at(i: int) -> Vector3:
	return tangents[posmod(i, count)].cross(Vector3.UP)


## Lowest speed the AI should be doing now to still make every corner within
## `look_dist` metres, given it can brake at `a_brake` m/s^2.
func speed_limit_ahead(idx: int, look_dist: float, a_brake: float) -> float:
	var best: float = 200.0
	var dist: float = 0.0
	var prev: int = idx
	var k: int = 0
	while dist < look_dist and k < count:
		var j: int = (idx + k) % count
		dist += points[j].distance_to(points[prev])
		prev = j
		var allowed: float = sqrt(corner_speed[j] * corner_speed[j] + 2.0 * a_brake * dist)
		best = minf(best, allowed)
		k += 1
	return best


# ------------------------------------------------------------------- visuals
func _mat(color: Color, rough: float = 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_ground() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
	var margin: float = 220.0
	var body := StaticBody3D.new()
	body.name = "Ground"
	add_child(body)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(hi.x - lo.x + margin * 2.0, 2.0, hi.y - lo.y + margin * 2.0)
	col.shape = shape
	col.position = Vector3((lo.x + hi.x) * 0.5, -1.0, (lo.y + hi.y) * 0.5)
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = shape.size
	mi.mesh = bm
	mi.position = col.position
	mi.material_override = _mat(map["ground"])
	body.add_child(mi)
	if map["scenery"] == "palms":
		_make_sea(lo, hi, margin)


func _make_road() -> void:
	var half: float = width * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(count):
		var j: int = (i + 1) % count
		var l0: Vector3 = points[i] - right_at(i) * half + Vector3(0, 0.05, 0)
		var r0: Vector3 = points[i] + right_at(i) * half + Vector3(0, 0.05, 0)
		var l1: Vector3 = points[j] - right_at(j) * half + Vector3(0, 0.05, 0)
		var r1: Vector3 = points[j] + right_at(j) * half + Vector3(0, 0.05, 0)
		for v in [l0, l1, r0, r0, l1, r1]:  # clockwise seen from above = front face up
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(map["road"], 0.8)
	add_child(mi)

	# Dashed centre line + solid edge lines, as thin boxes.
	# Dashed centre line: one MultiMesh (a draw call) instead of a node per dash.
	var dashes: Array = []
	for i in range(0, count, 2):
		dashes.append(Transform3D(Basis.looking_at(tangents[i], Vector3.UP) * Basis.from_scale(Vector3(0.35, 0.02, spacing * 0.9)), points[i] + Vector3(0, 0.07, 0)))
	_add_multimesh_xf(_box_mesh(Vector3.ONE), _mat(Color(0.9, 0.9, 0.9)), dashes)

	# Chequered start/finish strip.
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(width, 0.02, 2.0)
	strip.mesh = sm
	strip.material_override = _mat(Color(1, 1, 1), 0.5)
	strip.transform = Transform3D(Basis.looking_at(tangents[0], Vector3.UP), points[0] + Vector3(0, 0.08, 0))
	add_child(strip)
	for c in range(8):
		var sq := MeshInstance3D.new()
		var qm := BoxMesh.new()
		qm.size = Vector3(width / 8.0, 0.03, 1.0)
		sq.mesh = qm
		sq.material_override = _mat(Color(0.05, 0.05, 0.05) if c % 2 == 0 else Color(1, 1, 1), 0.5)
		var off: Vector3 = right_at(0) * ((float(c) + 0.5) * width / 8.0 - width * 0.5)
		sq.transform = Transform3D(Basis.looking_at(tangents[0], Vector3.UP), points[0] + off + Vector3(0, 0.09, 0.0) + tangents[0] * (0.5 if c % 2 == 0 else -0.5))
		add_child(sq)


func _make_walls() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	var half: float = width * 0.5
	var vis: Array = [[], []]   # visuals batched per colour into 2 MultiMeshes (was ~340 nodes)
	for side in [-1.0, 1.0]:
		for i in range(count):
			var j: int = (i + 1) % count
			var edge_a: Vector3 = points[i] + right_at(i) * (half * side)
			var edge_b: Vector3 = points[j] + right_at(j) * (half * side)
			var mid: Vector3 = (edge_a + edge_b) * 0.5
			var dir: Vector3 = edge_b - edge_a
			var seg_len: float = dir.length()
			dir = dir.normalized()
			var outward: Vector3 = dir.cross(Vector3.UP) * side  # away from the road centre
			var centre: Vector3 = mid + outward * (wall_thickness * 0.5) + Vector3(0, wall_height * 0.5, 0)
			var xf := Transform3D(Basis.looking_at(dir, Vector3.UP), centre)
			var size := Vector3(wall_thickness, wall_height, seg_len * 1.25 + 0.6)

			if _near_shortcut(edge_a, edge_b, SC_WIDTH * 0.5 + 3.0):
				continue  # gap in the wall: a shortcut mouth
			_wall_box(body, xf, size)
			vis[(i / 2) % 2].append(Transform3D(xf.basis * Basis.from_scale(size), xf.origin))
	_make_shortcuts(body, vis)
	for k in range(2):
		_add_multimesh_xf(_box_mesh(Vector3.ONE), _mat(map["walls"][k], 0.7), vis[k])


func _wall_box(body: StaticBody3D, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = xf
	body.add_child(cs)


## Dirt ribbon + low walls along each shortcut. Walls stop short of the main road so the mouths stay open.
func _make_shortcuts(body: StaticBody3D, vis: Array) -> void:
	if shortcuts.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half: float = SC_WIDTH * 0.5
	for sc in shortcuts:
		var p: PackedVector3Array = sc["pts"]
		for k in range(p.size() - 1):
			var d: Vector3 = (p[k + 1] - p[k]).normalized()
			var r: Vector3 = d.cross(Vector3.UP)
			var y := Vector3(0, 0.035, 0)  # just under the main road, so it never z-fights at the mouths
			var l0: Vector3 = p[k] - r * half + y
			var r0: Vector3 = p[k] + r * half + y
			var l1: Vector3 = p[k + 1] - r * half + y
			var r1: Vector3 = p[k + 1] + r * half + y
			for v in [l0, l1, r0, r0, l1, r1]:  # clockwise seen from above = front face up
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
			for side in [-1.0, 1.0]:
				var c: Vector3 = (p[k] + p[k + 1]) * 0.5 + r * ((half + wall_thickness * 0.5) * side) + Vector3(0, wall_height * 0.5, 0)
				if _dist_to_main(c) < width * 0.5 + wall_thickness + 7.0:  # leave the fork wide open (no spear-tip wall in the lane)
					continue
				var xf := Transform3D(Basis.looking_at(d, Vector3.UP), c)
				var size := Vector3(wall_thickness, wall_height, p[k].distance_to(p[k + 1]) * 1.3 + 0.4)
				_wall_box(body, xf, size)
				vis[k % 2].append(Transform3D(xf.basis * Basis.from_scale(size), xf.origin))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(0.55, 0.42, 0.26), 1.0)
	add_child(mi)
	# entry chevrons: bright arrows at each mouth so you can read the risk early
	var arrows: Array = []
	for sc in shortcuts:
		var p: PackedVector3Array = sc["pts"]
		var d: Vector3 = (p[3] - p[1]).normalized()
		arrows.append(Transform3D(Basis.looking_at(d, Vector3.UP) * Basis.from_scale(Vector3(5.0, 2.2, 0.3)), p[2] + Vector3(0, 3.5, 0)))
	var am := _mat(Color(1.0, 0.75, 0.1))
	am.emission_enabled = true
	am.emission = Color(1.0, 0.6, 0.05)
	am.emission_energy_multiplier = 1.5
	_add_multimesh_xf(_box_mesh(Vector3.ONE), am, arrows)


func _dist_to_main(pos: Vector3) -> float:
	var best: float = INF
	for p in points:
		best = minf(best, Vector2(p.x - pos.x, p.z - pos.z).length_squared())
	return sqrt(best)


func _make_start_gantry() -> void:
	var half: float = width * 0.5 + 1.0
	var r: Vector3 = right_at(0)
	var post_mat: StandardMaterial3D = _mat(Color(0.2, 0.2, 0.25))
	for s in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.6, 7.0, 0.6)
		post.mesh = pm
		post.material_override = post_mat
		post.position = points[0] + r * (half * s) + Vector3(0, 3.5, 0)
		add_child(post)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(half * 2.0, 1.6, 0.5)
	beam.mesh = bm
	var bmat: StandardMaterial3D = _mat(Color(0.95, 0.8, 0.1))
	bmat.emission_enabled = true
	bmat.emission = Color(0.95, 0.7, 0.05)
	bmat.emission_energy_multiplier = 0.6
	beam.material_override = bmat
	beam.transform = Transform3D(Basis.looking_at(tangents[0], Vector3.UP), points[0] + Vector3(0, 7.2, 0))
	add_child(beam)


# -------------------------------------------------------------------- scenery
## Trees and lamp posts along the road: not decoration for its own sake, they
## are what makes 180 km/h *feel* like 180 km/h (things streaking past).
func _make_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var half: float = width * 0.5 + wall_thickness
	match map["scenery"]:
		"pines":
			var trunks: Array = []
			for i in range(count):
				for side in [-1.0, 1.0]:
					for k in range(2):
						var pos: Vector3 = _roadside(rng, i, side, half + 6.0, 38.0)
						if _dist_to_road(pos) > half + 5.0:
							trunks.append([pos, rng.randf_range(0.8, 1.7)])
			_add_multimesh(_cyl_mesh(0.35, 3.0), _mat(Color(0.3, 0.2, 0.12)), trunks, 1.5)
			_add_multimesh(_cone_mesh(2.6, 7.0), _mat(Color(0.1, 0.32, 0.14)), trunks, 6.0)
		"palms":
			var palms: Array = []
			for i in range(0, count, 2):
				for side in [-1.0, 1.0]:
					var pos: Vector3 = _roadside(rng, i, side, half + 4.0, 30.0)
					if _dist_to_road(pos) > half + 3.0:
						palms.append([pos, rng.randf_range(0.8, 1.3)])
			_add_multimesh(_cyl_mesh(0.22, 8.0), _mat(Color(0.45, 0.33, 0.2)), palms, 4.0)
			_add_multimesh(_cone_mesh(3.4, 1.4), _mat(Color(0.18, 0.42, 0.16)), palms, 8.3)
		"rocks":
			# sandstone pillars and mesas, crowded close to the road so the canyon feels narrow and fast
			var rocks: Array = []
			for i in range(count):
				for side in [-1.0, 1.0]:
					var pos: Vector3 = _roadside(rng, i, side, half + 8.0, 50.0)
					var r: float = rng.randf_range(3.0, 9.0)
					if _dist_to_road(pos) > half + r + 2.0:
						var h: float = rng.randf_range(6.0, 30.0)
						rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r, h, r * rng.randf_range(0.7, 1.3))), pos + Vector3(0, h * 0.5, 0)))
			_add_multimesh_xf(_cyl_mesh(0.5, 1.0, 0.85), _mat(Color(0.62, 0.32, 0.2)), rocks)
		"city":
			var blocks: Array = []
			for i in range(0, count, 2):
				for side in [-1.0, 1.0]:
					var w: float = rng.randf_range(10.0, 24.0)
					var pos: Vector3 = _roadside(rng, i, side, half + 6.0 + w * 0.5, 30.0)
					if _dist_to_road(pos) > half + w * 0.75 + 2.0:
						var h: float = rng.randf_range(14.0, 70.0)
						var b := Basis.looking_at(tangents[i], Vector3.UP)
						blocks.append(Transform3D(b * Basis.from_scale(Vector3(w, h, w * rng.randf_range(0.7, 1.2))), pos + Vector3(0, h * 0.5, 0)))
			var bm := ShaderMaterial.new()
			bm.shader = preload("res://Resources/Shaders/windows.gdshader")
			_add_multimesh_xf(_box_mesh(Vector3.ONE), bm, blocks)

	var every: int = int(map["lamps"])
	if every <= 0:
		return
	# lamp posts just outside the wall, alternating sides. They only glow (no real lights): bloom sells it.
	var posts: Array = []
	for i in range(0, count, every):
		for side in [-1.0, 1.0]:
			var pos: Vector3 = points[i] + right_at(i) * ((width * 0.5 + wall_thickness + 1.5) * side)
			pos.y = 0.0
			posts.append([pos, 1.0])
	_add_multimesh(_box_mesh(Vector3(0.25, 6.0, 0.25)), _mat(Color(0.25, 0.25, 0.3)), posts, 3.0)
	var glow := _mat(Color(1.0, 0.85, 0.5))
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.8, 0.4)
	glow.emission_energy_multiplier = float(map["lamp"])
	_add_multimesh(_box_mesh(Vector3(0.9, 0.25, 0.9)), glow, posts, 6.1)


## A random spot beside sample i, between `near` and `near + spread` metres from the centre line.
func _roadside(rng: RandomNumberGenerator, i: int, side: float, near: float, spread: float) -> Vector3:
	var pos: Vector3 = points[i] + right_at(i) * ((near + rng.randf() * spread) * side) + tangents[i] * (rng.randf_range(-0.5, 0.5) * spacing)
	pos.y = 0.0
	return pos


## A flat, glossy sea along the coast road's start straight (no collision: the walls keep cars out).
func _make_sea(lo: Vector2, hi: Vector2, margin: float) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(hi.x - lo.x + margin * 2.0, margin)
	mi.mesh = pm
	mi.position = Vector3((lo.x + hi.x) * 0.5, 0.02, hi.y + width + 18.0 + margin * 0.5)
	var m := _mat(Color(0.05, 0.25, 0.4), 0.08)
	m.metallic = 0.6
	mi.material_override = m
	add_child(mi)


## Distance to the nearest road edge, plus the main road's half width (callers add that back in).
func _dist_to_road(pos: Vector3) -> float:
	var best: float = _dist_to_main(pos)
	for sc in shortcuts:
		for p in sc["pts"]:
			best = minf(best, Vector2(p.x - pos.x, p.z - pos.z).length() + (width - SC_WIDTH) * 0.5)
	return best


func _cyl_mesh(r: float, h: float, taper: float = 0.7) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = r * taper
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 6
	return m


func _cone_mesh(r: float, h: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 7
	return m


func _box_mesh(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## items: [[position, scale], ...]; y_lift raises each instance by that much * scale.
func _add_multimesh(mesh: Mesh, mat: Material, items: Array, y_lift: float) -> void:
	var xfs: Array = []
	for it in items:
		var sc: float = it[1]
		xfs.append(Transform3D(Basis.IDENTITY.scaled(Vector3(sc, sc, sc)), it[0] + Vector3(0, y_lift * sc, 0)))
	_add_multimesh_xf(mesh, mat, xfs)


## One MultiMesh (a single draw call) for many copies of `mesh`.
func _add_multimesh_xf(mesh: Mesh, mat: Material, xfs: Array) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for n in range(xfs.size()):
		mm.set_instance_transform(n, xfs[n])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
