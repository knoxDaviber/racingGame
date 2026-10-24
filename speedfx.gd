extends Control
## Screen-edge speed streaks. `intensity` (0..1) is driven by Main from the car's speed.

var intensity: float = 0.0
var streaks: Array = []  # each: [angle, phase, speed, length]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(48):
		streaks.append([rng.randf() * TAU, rng.randf(), rng.randf_range(1.4, 2.8), rng.randf_range(0.08, 0.22)])


func _process(delta: float) -> void:
	if intensity > 0.03:
		for st in streaks:
			st[1] = fmod(st[1] + delta * st[2] * (0.6 + intensity), 1.0)
		queue_redraw()


func _draw() -> void:
	if intensity < 0.05:
		return
	var c: Vector2 = size * 0.5
	var maxr: float = c.length()
	for st in streaks:
		var d := Vector2(cos(st[0]), sin(st[0]))
		var r0: float = maxr * (0.5 + 0.5 * st[1])
		var r1: float = r0 + maxr * st[3] * (0.4 + intensity)
		var a: float = 0.4 * intensity * (1.0 - 0.5 * st[1])
		draw_line(c + d * r0, c + d * r1, Color(1, 1, 1, a), 2.0)
