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
	{"name": "HIGHLAND LOOP", "shortcuts": 0, "time": "Dawn", "width": 18.0, "verge_w": 9.0, "scenery": "pines", "lamps": 0,
	"cuts": [{"a": 4, "b": 17}, {"a": 33, "b": 48, "jump": true}],   # the square's dirt cut, and the ramp jump over the lobe
	"ctrl": [Vector2(-37.5, -150.0), Vector2(-57.9, -145.4), Vector2(-78.2, -140.9), Vector2(-94.3, -128.1), Vector2(-111.7, -116.7), Vector2(-129.9, -106.6), Vector2(-148.2, -96.5), Vector2(-166.4, -86.4), Vector2(-184.6, -76.1), Vector2(-202.7, -65.8), Vector2(-220.5, -54.9), Vector2(-228.5, -36.3), Vector2(-222.2, -16.6), Vector2(-213.9, 2.6), Vector2(-205.4, 21.7), Vector2(-196.7, 40.6), Vector2(-187.9, 59.5), Vector2(-179.4, 78.6), Vector2(-171.4, 97.8), Vector2(-163.3, 117.1), Vector2(-152.5, 134.6), Vector2(-138.5, 150.0), Vector2(-124.4, 165.4), Vector2(-107.1, 176.5), Vector2(-88.3, 185.6), Vector2(-69.4, 194.4), Vector2(-50.2, 202.5), Vector2(-30.1, 206.1), Vector2(-9.2, 205.8), Vector2(11.5, 204.5), Vector2(31.7, 199.3), Vector2(51.9, 194.1), Vector2(71.4, 186.8), Vector2(90.3, 178.0), Vector2(107.9, 181.0), Vector2(124.2, 194.0), Vector2(141.1, 205.6), Vector2(161.9, 206.2), Vector2(182.8, 206.9), Vector2(201.8, 199.4), Vector2(220.2, 189.7), Vector2(238.6, 179.9), Vector2(249.8, 162.3), Vector2(253.3, 142.5), Vector2(239.3, 127.8), Vector2(221.7, 116.6), Vector2(204.0, 105.6), Vector2(186.7, 94.0), Vector2(183.6, 74.5), Vector2(195.5, 57.4), Vector2(198.0, 37.3), Vector2(198.0, 16.5), Vector2(197.9, -4.4), Vector2(197.2, -25.2), Vector2(196.6, -46.1), Vector2(213.5, -56.3), Vector2(232.3, -65.5), Vector2(247.3, -79.0), Vector2(242.8, -98.3), Vector2(224.1, -107.2), Vector2(206.2, -117.4), Vector2(201.9, -137.0), Vector2(211.4, -155.5), Vector2(208.7, -175.0), Vector2(189.6, -180.6), Vector2(168.9, -177.8), Vector2(148.3, -174.9), Vector2(127.6, -172.0), Vector2(107.1, -168.5), Vector2(86.6, -164.6), Vector2(66.1, -160.7), Vector2(45.6, -156.7), Vector2(25.0, -153.5), Vector2(4.2, -152.5), Vector2(-16.7, -151.2)],
	"ground": Color(0.2, 0.3, 0.17), "road": Color(0.2, 0.2, 0.22), "walls": [Color(0.9, 0.9, 0.9), Color(0.25, 0.3, 0.4)],
	"sky_top": Color(0.25, 0.35, 0.6), "sky_hor": Color(0.98, 0.78, 0.6), "sun_rot": Vector3(-12, 60, 0),
	"sun_col": Color(1.0, 0.8, 0.6), "sun_e": 1.0, "ambient": 0.75, "fog_col": Color(0.85, 0.72, 0.62), "fog_begin": 200.0,
	"lamp": 0.4, "night": false},
]

var map: Dictionary = MAPS[0]   # set by Main before build()
var width: float = 18.0
var wall_height: float = 1.6
var wall_thickness: float = 1.2
var a_lat: float = 12.0  # lateral acceleration (m/s^2) the AI assumes it can corner at

const SC_WIDTH: float = 11.0     # shortcuts: narrow,
const SC_GRIP: float = 0.8       # loose dirt,
const SC_SPEED: float = 21.0     # and the AI takes them slowly
const VERGE_GRIP: float = 0.7    # the dirt between the road and the railing
const JUMP_APPROACH: float = 22.0   # the ramp jump: dirt run-up, ramp, pit, landing, exit
const JUMP_RAMP_LEN: float = 16.0
const JUMP_RAMP_H: float = 1.7
const JUMP_GAP: float = 34.0
const JUMP_LAND_LEN: float = 18.0
const JUMP_LAND_H: float = 1.2
const JUMP_HALF_W: float = 4.6   # inside the dirt cut's side walls (they stand at 5.5 m from the centre)

var points: PackedVector3Array = PackedVector3Array()
## Shortcuts: [{a, b, pts: PackedVector3Array}]. A dirt cut from main sample a to b (b > a, no wrap).
var shortcuts: Array = []
var last_on_shortcut: bool = false   # set by locate(): did the last lookup land on a shortcut?
var last_off_road: bool = false      # set by locate(): beside the road (in the verge) rather than on it
var verge: float = 12.0              # width of the open dirt/trees strip between the road and the railing
var jumps: Array = []                # pits under the ramp jumps (a car that falls in is put back on the road)
var tangents: PackedVector3Array = PackedVector3Array()
var corner_speed: PackedFloat32Array = PackedFloat32Array()  # max sensible speed at each sample
var length: float = 0.0
var count: int = 0
var spacing: float = 1.0  # average distance between samples (metres)

const VIEW_EXTRA: float = 230.0   # view distance = the map's fog_begin + this (fog is opaque there)
const CELL: float = 120.0         # scenery is split into CELL x CELL chunks so off-screen / far chunks are skipped


## How far the camera sees on this map; fog reaches full strength exactly there.
func view_dist() -> float:
	return float(map["fog_begin"]) + VIEW_EXTRA


func build() -> void:
	width = float(map["width"])
	verge = float(map.get("verge_w", 12.0))
	_make_centerline()
	if map.has("cuts"):
		_authored_cuts()
	else:
		_find_shortcuts(int(map.get("shortcuts", 0)))
	_make_ground()
	_make_road()
	_make_walls()
	_make_verge()
	_make_verge_props()
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
	last_off_road = absf((pos - points[i]).dot(right_at(i))) > width * 0.5 + 0.4
	if shortcuts.is_empty() or not last_off_road:
		return i   # on the road itself
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
			last_off_road = false
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
	var need: float = width + SC_WIDTH + 6.0 + verge
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


## True when `pos` is within `r` metres of any dirt cut's centre line (measured to the whole polyline, not just its sample
## points), so scenery and lamp posts never stand on or beside a cut.
func _on_cut(pos: Vector3, r: float) -> bool:
	var q := Vector2(pos.x, pos.z)
	for sc in shortcuts:
		var pts: PackedVector3Array = sc["pts"]
		for k in range(pts.size() - 1):
			var a := Vector2(pts[k].x, pts[k].z)
			var b := Vector2(pts[k + 1].x, pts[k + 1].z)
			var c: Vector2 = Geometry2D.get_closest_point_to_segment(q, a, b)
			if c.distance_to(q) < r:
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
	var road_mat: StandardMaterial3D = _mat(map["road"], 0.8)
	# one mesh per ~CELL metres of road, so the camera and lights skip the pieces they can't reach
	var per: int = maxi(1, int(CELL / spacing))
	for c0 in range(0, count, per):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(c0, mini(c0 + per, count)):
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
		mi.material_override = road_mat
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
	var half: float = width * 0.5 + verge   # the railing stands at the edge of the open verge
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
		if sc.get("jump", false):
			_make_jump(sc, body)
		for k in range(p.size() - 1):
			if sc.get("jump", false):
				var sd: float = p[0].distance_to(p[k])
				if sd > float(sc["skip0"]) and sd < float(sc["skip1"]):
					continue   # ramp, pit and landing replace the dirt here
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
				if _dist_to_main(c) < width * 0.5 + verge + wall_thickness + 7.0:  # leave the fork wide open (no spear-tip wall in the lane)
					continue
				var xf := Transform3D(Basis.looking_at(d, Vector3.UP), c)
				var size := Vector3(wall_thickness, wall_height, p[k].distance_to(p[k + 1]) * 1.3 + 0.4)
				_wall_box(body, xf, size)
				vis[k % 2].append(Transform3D(xf.basis * Basis.from_scale(size), xf.origin))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(0.55, 0.42, 0.26), 1.0)
	add_child(mi)
	_make_boulders(body)
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


## Cuts written into the map (instead of found automatically): [{a, b, jump?}] with a and b = control point numbers.
func _authored_cuts() -> void:
	for c in map["cuts"]:
		var a: int = int(c["a"]) * SUBDIV
		var b: int = int(c["b"]) * SUBDIV
		var sc: Dictionary = {"a": a, "b": b, "pts": _shortcut_curve(a, b)}
		if c.get("jump", false):
			sc["jump"] = true
		shortcuts.append(sc)


## The ramp jump: a run-up of dirt, a ramp, a pit you must fly over, a landing ramp, then dirt again.
## Too slow = you fall in the pit (back on the road, time lost) or hit the landing wall.
func _make_jump(sc: Dictionary, body: StaticBody3D) -> void:
	var pts: PackedVector3Array = sc["pts"]
	var o: Vector3 = pts[0]
	var d: Vector3 = pts[pts.size() - 1] - o
	d.y = 0.0
	d = d.normalized()
	var basis := Basis.looking_at(d, Vector3.UP)   # local -Z runs along the cut
	var s_gap0: float = JUMP_APPROACH + JUMP_RAMP_LEN
	var s_land: float = s_gap0 + JUMP_GAP
	_add_wedge(body, Transform3D(basis, o + d * JUMP_APPROACH), JUMP_HALF_W, JUMP_RAMP_LEN, JUMP_RAMP_H, true)
	_add_wedge(body, Transform3D(basis, o + d * s_land), JUMP_HALF_W + 0.5, JUMP_LAND_LEN, JUMP_LAND_H, false)
	sc["skip0"] = JUMP_APPROACH - 3.0
	sc["skip1"] = s_land + JUMP_LAND_LEN + 3.0
	jumps.append({"o": o, "d": d, "s0": s_gap0, "s1": s_land, "hw": JUMP_HALF_W + 0.5})
	var pit := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3((JUMP_HALF_W + 0.5) * 2.0, 0.1, JUMP_GAP)
	pit.mesh = bm
	var pm := _mat(Color(0.12, 0.05, 0.04), 1.0)
	pm.emission_enabled = true
	pm.emission = Color(1.0, 0.3, 0.05)
	pm.emission_energy_multiplier = 0.6
	pit.material_override = pm
	pit.transform = Transform3D(basis, o + d * (s_gap0 + JUMP_GAP * 0.5) + Vector3(0, 0.04, 0))
	add_child(pit)


## A curved ramp (trimesh collider; the car's chassis scrapes a straight wedge's sharp start). Rising: the profile
## eases up from the ground to `h` at the far end, where it stops in a vertical face. Not rising: the vertical face
## comes first and the profile eases back down to the ground (the landing).
func _add_wedge(body: StaticBody3D, xf: Transform3D, hw: float, length: float, h: float, rising: bool) -> void:
	var n: int = 12
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops: Array = []
	for k in range(n + 1):
		var u: float = float(k) / float(n)
		var f: float = h * pow(u, 1.8) if rising else h * pow(1.0 - u, 1.8)
		tops.append(f)
	for k in range(n):
		var z0: float = -length * float(k) / float(n)
		var z1: float = -length * float(k + 1) / float(n)
		var y0: float = tops[k]
		var y1: float = tops[k + 1]
		# top surface
		for v in [Vector3(-hw, y0, z0), Vector3(hw, y0, z0), Vector3(hw, y1, z1), Vector3(-hw, y0, z0), Vector3(hw, y1, z1), Vector3(-hw, y1, z1)]:
			st.add_vertex(v)
		# both sides
		for sx in [-hw, hw]:
			for v in [Vector3(sx, 0, z0), Vector3(sx, y0, z0), Vector3(sx, y1, z1), Vector3(sx, 0, z0), Vector3(sx, y1, z1), Vector3(sx, 0, z1)]:
				st.add_vertex(v)
	var zf: float = -length if rising else 0.0   # the vertical face
	var hf: float = h
	for v in [Vector3(-hw, 0, zf), Vector3(hw, 0, zf), Vector3(hw, hf, zf), Vector3(-hw, 0, zf), Vector3(hw, hf, zf), Vector3(-hw, hf, zf)]:
		st.add_vertex(v)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var cs := CollisionShape3D.new()
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	shape.backface_collision = true
	cs.shape = shape
	cs.transform = xf
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	mi.material_override = _mat(Color(0.9, 0.55, 0.1), 0.8)
	add_child(mi)


## Dirt cuts are not a free ride: boulders in a slalom just off the centre line. A clean line misses them (the AI
## drives it), a car that is sliding about does not.
func _make_boulders(body: StaticBody3D) -> void:
	var xfs: Array = []
	for sc in shortcuts:
		if sc.get("jump", false):
			continue
		var p: PackedVector3Array = sc["pts"]
		var total: float = p[0].distance_to(p[p.size() - 1])
		var step: float = total / float(p.size() - 1)
		var s: float = 30.0
		var side: float = 1.0
		while s < total - 30.0:
			var k: int = int(s / step)
			var d: Vector3 = (p[mini(k + 1, p.size() - 1)] - p[k]).normalized()
			var pos: Vector3 = p[k] + d.cross(Vector3.UP) * 2.8 * side
			pos.y = 0.0
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = 1.0
			shape.height = 1.8
			cs.shape = shape
			cs.position = pos + Vector3(0, 0.9, 0)
			body.add_child(cs)
			xfs.append(Transform3D(Basis.from_scale(Vector3(2.3, 1.8, 2.3)), pos + Vector3(0, 0.9, 0)))
			side = -side
			s += 30.0
	if not xfs.is_empty():
		_add_multimesh_xf(_cyl_mesh(0.5, 1.0, 0.8), _mat(Color(0.45, 0.4, 0.36), 1.0), xfs)


## A jump pit swallows whoever drops into it low and slow: back on the road, time lost.
func _physics_process(_delta: float) -> void:
	if jumps.is_empty():
		return
	for car in get_tree().get_nodes_in_group("cars"):
		if not is_instance_valid(car) or car.track != self or car.gone:
			continue
		for j in jumps:
			var rel: Vector3 = car.global_position - (j["o"] as Vector3)
			var s: float = rel.dot(j["d"])
			var t: float = rel.dot((j["d"] as Vector3).cross(Vector3.UP))
			if s > float(j["s0"]) + 0.5 and s < float(j["s1"]) - 1.5 and absf(t) < float(j["hw"]) and car.global_position.y < 0.7:
				car.respawn()


## The open strip between the road and the railing: dirt you can drive onto (slow and loose) before you hit anything.
func _make_verge() -> void:
	var half: float = width * 0.5
	var mat: StandardMaterial3D = _mat(map.get("verge", Color(0.42, 0.33, 0.2)), 1.0)
	var per: int = maxi(1, int(CELL / spacing))
	for c0 in range(0, count, per):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(c0, mini(c0 + per, count)):
			var j: int = (i + 1) % count
			for side in [-1.0, 1.0]:
				var in0: Vector3 = points[i] + right_at(i) * (half * side) + Vector3(0, 0.03, 0)
				var out0: Vector3 = points[i] + right_at(i) * ((half + verge) * side) + Vector3(0, 0.03, 0)
				var in1: Vector3 = points[j] + right_at(j) * (half * side) + Vector3(0, 0.03, 0)
				var out1: Vector3 = points[j] + right_at(j) * ((half + verge) * side) + Vector3(0, 0.03, 0)
				var quad: Array = [in0, in1, out0, out0, in1, out1] if side > 0.0 else [out0, out1, in0, in0, out1, in1]   # front face up on both sides
				for v in quad:
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		add_child(mi)


## Solid trees, boulders or blocks scattered in the verge: a mistake costs speed, not just a scrape on the railing.
func _make_verge_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var body := StaticBody3D.new()
	body.name = "VergeProps"
	add_child(body)
	var kind: String = String(map["scenery"])
	var step: int = maxi(2, int(17.0 / spacing))
	var items: Array = []   # [position, scale]
	var big: Array = []     # rocks: Transform3D
	for i in range(6, count - 6, step):
		if rng.randf() < 0.25:
			continue
		var side: float = -1.0 if rng.randf() < 0.5 else 1.0
		var lat: float = width * 0.5 + rng.randf_range(2.0, maxf(2.5, verge - 1.5))
		var pos: Vector3 = points[i] + right_at(i) * (lat * side) + tangents[i] * (rng.randf_range(-0.5, 0.5) * spacing)
		pos.y = 0.0
		if _dist_to_main(pos) < width * 0.5 + 2.0 or _on_cut(pos, SC_WIDTH * 0.5 + 6.0):
			continue
		var cs := CollisionShape3D.new()
		if kind == "rocks":
			var r: float = rng.randf_range(1.2, 2.2)
			var h: float = rng.randf_range(2.0, 4.0)
			var shape := CylinderShape3D.new()
			shape.radius = r * 0.45
			shape.height = h
			cs.shape = shape
			cs.position = pos + Vector3(0, h * 0.5, 0)
			big.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r, h, r)), cs.position))
		elif kind == "city":
			var shape := BoxShape3D.new()
			shape.size = Vector3(2.0, 1.2, 2.0)
			cs.shape = shape
			cs.position = pos + Vector3(0, 0.6, 0)
			big.append(Transform3D(Basis.from_scale(shape.size), cs.position))
		else:   # pines, palms
			var sc: float = rng.randf_range(0.8, 1.4)
			var shape := CylinderShape3D.new()
			shape.radius = 0.5 * sc
			shape.height = 4.0
			cs.shape = shape
			cs.position = pos + Vector3(0, 2.0, 0)
			items.append([pos, sc])
		body.add_child(cs)
	match kind:
		"rocks":
			_add_multimesh_xf(_cyl_mesh(0.5, 1.0, 0.85), _mat(Color(0.62, 0.32, 0.2)), big)
		"city":
			_add_multimesh_xf(_box_mesh(Vector3.ONE), _mat(Color(0.55, 0.55, 0.58), 0.9), big)
		"palms":
			_add_multimesh(_cyl_mesh(0.22, 8.0), _mat(Color(0.45, 0.33, 0.2)), items, 4.0)
			_add_multimesh(_cone_mesh(3.4, 1.4), _mat(Color(0.18, 0.42, 0.16)), items, 8.3)
		_:
			_add_multimesh(_cyl_mesh(0.35, 3.0), _mat(Color(0.3, 0.2, 0.12)), items, 1.5)
			_add_multimesh(_cone_mesh(2.6, 7.0), _mat(Color(0.1, 0.32, 0.14)), items, 6.0)


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
	var half: float = width * 0.5 + verge + wall_thickness
	match map["scenery"]:
		"pines":
			var trunks: Array = []
			for i in range(count):
				for side in [-1.0, 1.0]:
					for k in range(2):
						var pos: Vector3 = _roadside(rng, i, side, half + 6.0, 38.0)
						if _dist_to_road(pos) > half + 5.0 and not _on_cut(pos, SC_WIDTH * 0.5 + 9.0):
							trunks.append([pos, rng.randf_range(0.8, 1.7)])
			_add_multimesh(_cyl_mesh(0.35, 3.0), _mat(Color(0.3, 0.2, 0.12)), trunks, 1.5)
			_add_multimesh(_cone_mesh(2.6, 7.0), _mat(Color(0.1, 0.32, 0.14)), trunks, 6.0)
		"palms":
			var palms: Array = []
			for i in range(0, count, 2):
				for side in [-1.0, 1.0]:
					var pos: Vector3 = _roadside(rng, i, side, half + 4.0, 30.0)
					if _dist_to_road(pos) > half + 3.0 and not _on_cut(pos, SC_WIDTH * 0.5 + 9.0):
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
					if _dist_to_road(pos) > half + r + 2.0 and not _on_cut(pos, SC_WIDTH * 0.5 + 9.0 + r):
						var h: float = rng.randf_range(6.0, 30.0)
						rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r, h, r * rng.randf_range(0.7, 1.3))), pos + Vector3(0, h * 0.5, 0)))
			_add_multimesh_xf(_cyl_mesh(0.5, 1.0, 0.85), _mat(Color(0.62, 0.32, 0.2)), rocks)
		"city":
			var blocks: Array = []
			for i in range(0, count, 2):
				for side in [-1.0, 1.0]:
					var w: float = rng.randf_range(10.0, 24.0)
					var pos: Vector3 = _roadside(rng, i, side, half + 6.0 + w * 0.5, 30.0)
					if _dist_to_road(pos) > half + w * 0.75 + 2.0 and not _on_cut(pos, SC_WIDTH * 0.5 + 9.0 + w * 0.5):
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
			var pos: Vector3 = points[i] + right_at(i) * ((width * 0.5 + verge + wall_thickness + 1.5) * side)
			pos.y = 0.0
			if _on_cut(pos, SC_WIDTH * 0.5 + 4.0):
				continue   # no lamp post in the mouth of a dirt cut
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


## Many copies of `mesh`, one MultiMesh (one draw call) per CELL-sized chunk of the map. A single
## track-wide MultiMesh can never be culled; chunks behind the camera or past the fog are not drawn.
func _add_multimesh_xf(mesh: Mesh, mat: Material, xfs: Array) -> void:
	var cells: Dictionary = {}
	for xf in xfs:
		var key := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(xf)
	var reach: float = view_dist() + CELL * 0.75   # chunk centre to its far corner, plus tall objects
	for key in cells:
		var list: Array = cells[key]
		var centre := Vector3((key.x + 0.5) * CELL, 0.0, (key.y + 0.5) * CELL)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for n in range(list.size()):
			var xf: Transform3D = list[n]
			mm.set_instance_transform(n, Transform3D(xf.basis, xf.origin - centre))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.position = centre
		mi.visibility_range_end = reach
		add_child(mi)
