extends Node3D
## Procedural circuit: a closed Catmull-Rom spline with walls, a road ribbon,
## a start/finish gantry, and helper data (tangents, arc length, safe corner
## speeds) used by the lap counter and the cop AI.

const SUBDIV: int = 12
const LAYOUT_SCALE: float = 1.5  # blow the layout up for longer straights and wider sweepers

var width: float = 18.0
var wall_height: float = 1.6
var wall_thickness: float = 1.2
var a_lat: float = 12.0  # lateral acceleration (m/s^2) the AI assumes it can corner at

var points: PackedVector3Array = PackedVector3Array()
var tangents: PackedVector3Array = PackedVector3Array()
var corner_speed: PackedFloat32Array = PackedFloat32Array()  # max sensible speed at each sample
var length: float = 0.0
var count: int = 0
var spacing: float = 1.0  # average distance between samples (metres)


func build() -> void:
	_make_centerline()
	_make_ground()
	_make_road()
	_make_walls()
	_make_start_gantry()
	_make_scenery()


# ---------------------------------------------------------------- centerline
func _make_centerline() -> void:
	# Control points (x, z). Index 0 sits mid-straight: that's the start/finish line.
	# The loop runs counter-clockwise (left-hand corners) when seen from above.
	var ctrl: Array = [
		Vector2(-40, 0), Vector2(70, 0), Vector2(150, -10), Vector2(210, -70),
		Vector2(200, -150), Vector2(130, -190), Vector2(60, -170), Vector2(20, -120),
		Vector2(-30, -140), Vector2(-100, -190), Vector2(-170, -150), Vector2(-190, -80),
		Vector2(-150, -20), Vector2(-95, 2),
	]
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
	mi.material_override = _mat(Color(0.16, 0.30, 0.14))
	body.add_child(mi)


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
		for v in [l0, r0, l1, r0, r1, l1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _mat(Color(0.18, 0.18, 0.2), 0.8)
	add_child(mi)

	# Dashed centre line + solid edge lines, as thin boxes.
	var line_mat: StandardMaterial3D = _mat(Color(0.9, 0.9, 0.9))
	for i in range(0, count, 2):
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.02, spacing * 0.9)
		seg.mesh = bm
		seg.material_override = line_mat
		seg.transform = Transform3D(Basis.looking_at(tangents[i], Vector3.UP), points[i] + Vector3(0, 0.07, 0))
		add_child(seg)

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
	var mat_a: StandardMaterial3D = _mat(Color(0.85, 0.12, 0.12), 0.7)
	var mat_b: StandardMaterial3D = _mat(Color(0.92, 0.92, 0.92), 0.7)
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

			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = size
			cs.shape = bs
			cs.transform = xf
			body.add_child(cs)

			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size
			mi.mesh = bm
			mi.material_override = mat_a if (i / 2) % 2 == 0 else mat_b
			mi.transform = xf
			body.add_child(mi)


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
	var trunks: Array = []
	var crowns: Array = []
	for i in range(count):
		for side in [-1.0, 1.0]:
			for k in range(2):
				var off: float = half + 6.0 + rng.randf() * 38.0
				var along: float = rng.randf_range(-0.5, 0.5) * spacing
				var pos: Vector3 = points[i] + right_at(i) * (off * side) + tangents[i] * along
				pos.y = 0.0
				if _dist_to_road(pos) < half + 5.0:
					continue
				trunks.append([pos, rng.randf_range(0.8, 1.7)])
				crowns.append([pos, rng.randf_range(0.8, 1.7)])
	_add_multimesh(_cyl_mesh(0.35, 3.0), _mat(Color(0.3, 0.2, 0.12)), trunks, 1.5, 0.0)
	_add_multimesh(_cone_mesh(2.6, 7.0), _mat(Color(0.1, 0.32, 0.14)), crowns, 6.0, 0.0)

	# lamp posts just outside the wall, every 3rd sample, alternating sides
	var posts: Array = []
	var heads: Array = []
	for i in range(0, count, 3):
		for side in [-1.0, 1.0]:
			var pos: Vector3 = points[i] + right_at(i) * ((width * 0.5 + wall_thickness + 1.5) * side)
			pos.y = 0.0
			posts.append([pos, 1.0])
			heads.append([pos, 1.0])
	_add_multimesh(_box_mesh(Vector3(0.25, 6.0, 0.25)), _mat(Color(0.25, 0.25, 0.3)), posts, 3.0, 0.0)
	var glow := _mat(Color(1.0, 0.85, 0.5))
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.8, 0.4)
	glow.emission_energy_multiplier = 2.0
	_add_multimesh(_box_mesh(Vector3(0.9, 0.25, 0.9)), glow, heads, 6.1, 0.0)


func _dist_to_road(pos: Vector3) -> float:
	var best: float = INF
	for p in points:
		var dx: float = p.x - pos.x
		var dz: float = p.z - pos.z
		best = minf(best, dx * dx + dz * dz)
	return sqrt(best)


func _cyl_mesh(r: float, h: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = r * 0.7
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
func _add_multimesh(mesh: Mesh, mat: Material, items: Array, y_lift: float, _unused: float) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = items.size()
	for n in range(items.size()):
		var pos: Vector3 = items[n][0]
		var sc: float = items[n][1]
		var b := Basis.IDENTITY.scaled(Vector3(sc, sc, sc))
		mm.set_instance_transform(n, Transform3D(b, pos + Vector3(0, y_lift * sc, 0)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)
