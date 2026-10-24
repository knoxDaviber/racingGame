extends Control
## Tiny top-down map: the circuit outline plus a dot per car.

var track = null
var items: Array = []  # each entry: [node, colour]
var pts: PackedVector2Array = PackedVector2Array()
var scale_f: float = 1.0
var offset: Vector2 = Vector2.ZERO


func setup(t) -> void:
	track = t
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in t.points:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
	var area: Vector2 = custom_minimum_size - Vector2(28, 28)
	scale_f = minf(area.x / (hi.x - lo.x), area.y / (hi.y - lo.y))
	offset = (custom_minimum_size - (hi - lo) * scale_f) * 0.5 - lo * scale_f
	pts.clear()
	for p in t.points:
		pts.append(Vector2(p.x, p.z) * scale_f + offset)
	pts.append(pts[0])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color(0, 0, 0, 0.45))
	if pts.size() > 1:
		draw_polyline(pts, Color(0.85, 0.85, 0.9, 0.9), 3.0)
	for it in items:
		var n = it[0]
		if is_instance_valid(n):
			var q := Vector2(n.global_position.x, n.global_position.z) * scale_f + offset
			draw_circle(q, 5.5, Color(0, 0, 0, 0.8))
			draw_circle(q, 4.0, it[1])
