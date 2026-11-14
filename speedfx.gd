extends Control
## Screen-space speed FX, all 2D draws (no post-process pass): edge streaks, a vignette that
## closes in with speed, and a blue boost tint. Main drives `intensity` (0..1 speed) and `boost` (0..1).

var intensity: float = 0.0
var boost: float = 0.0
var fade: float = 0.0          # black fade between legs (0..1)
var streaks: Array = []        # each: [angle, phase, speed, length, width]
var vignette: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(96):
		streaks.append([rng.randf() * TAU, rng.randf(), rng.randf_range(1.4, 2.8), rng.randf_range(0.08, 0.26), rng.randf_range(1.0, 3.0)])
	# radial gradient texture, stretched over the screen: a vignette for the price of one quad
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 128
	tex.height = 128
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 1)])
	tex.gradient = g
	vignette = TextureRect.new()
	vignette.texture = tex
	vignette.stretch_mode = TextureRect.STRETCH_SCALE
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


func _process(delta: float) -> void:
	var k: float = intensity + boost * 0.8
	vignette.modulate = Color(0.2 * boost, 0.35 * boost, 0.9 * boost, clampf(0.25 * intensity + 0.55 * boost, 0.0, 0.8))
	if k > 0.03 or fade > 0.0:
		for st in streaks:
			st[1] = fmod(st[1] + delta * st[2] * (0.6 + k), 1.0)
		queue_redraw()


func _draw() -> void:
	var k: float = clampf(intensity + boost * 0.8, 0.0, 1.6)
	if k >= 0.05:
		var c: Vector2 = size * 0.5
		var maxr: float = c.length()
		var col: Color = Color(1, 1, 1).lerp(Color(0.5, 0.8, 1.0), boost)
		var n: int = int(streaks.size() * clampf(0.4 + k * 0.6, 0.0, 1.0))   # more streaks the faster you go
		for i in range(n):
			var st: Array = streaks[i]
			var d := Vector2(cos(st[0]), sin(st[0]))
			var r0: float = maxr * (0.5 - 0.2 * boost + 0.5 * st[1])
			var r1: float = r0 + maxr * st[3] * (0.4 + k)
			col.a = 0.4 * minf(k, 1.0) * (1.0 - 0.5 * st[1])
			draw_line(c + d * r0, c + d * r1, col, st[4] * (1.0 + boost))
	if fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, fade))
