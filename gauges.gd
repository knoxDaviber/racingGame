extends Control
## An analog dial for the HUD (speedometer or tachometer), in the style of old arcade racers: a dark disc, tick marks,
## a red needle, a digital read-out at the bottom and an optional big number in the middle (the gear).

const START_DEG: float = 135.0
const END_DEG: float = 405.0

var value: float = 0.0       # needle position, in the dial's own units
var vmax: float = 220.0
var major: float = 20.0      # a numbered tick every `major` units
var minor: int = 2           # minor ticks between numbered ones
var label_div: float = 1.0   # the numbers on the dial are value / label_div (the tach shows thousands)
var red_from: float = -1.0   # the dial's red zone starts here (-1 = none)
var readout: String = ""     # digital text near the bottom
var centre: String = ""      # big text in the middle (gear)
var accent: Color = Color(1.0, 0.25, 0.2)


func _ang(v: float) -> float:
	return deg_to_rad(lerpf(START_DEG, END_DEG, clampf(v / vmax, 0.0, 1.0)))


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - 3.0
	var font: Font = ThemeDB.fallback_font
	draw_circle(c, r, Color(0.03, 0.03, 0.05, 0.62))
	draw_arc(c, r, 0.0, TAU, 64, Color(0.9, 0.9, 0.95, 0.85), 3.0, true)
	if red_from >= 0.0:
		draw_arc(c, r - 5.0, _ang(red_from), _ang(vmax), 24, Color(1.0, 0.2, 0.15, 0.9), 5.0, true)
	var n: int = int(roundf(vmax / major))
	for i in range(n + 1):
		var v: float = float(i) * major
		var a: float = _ang(v)
		var d := Vector2(cos(a), sin(a))
		draw_line(c + d * (r - 4.0), c + d * (r - 15.0), Color(1, 1, 1, 0.95), 2.5, true)
		var txt: String = str(int(roundf(v / label_div)))
		var ts: Vector2 = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, maxi(9, int(r * 0.15))))
		draw_string(font, c + d * (r - 28.0) - Vector2(ts.x * 0.5, -ts.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, int(r * 0.15)), Color(1, 1, 1, 0.95))
		if i < n:
			for k in range(1, minor + 1):
				var a2: float = _ang(v + major * float(k) / float(minor + 1))
				var d2 := Vector2(cos(a2), sin(a2))
				draw_line(c + d2 * (r - 4.0), c + d2 * (r - 9.0), Color(1, 1, 1, 0.6), 1.5, true)
	var na: float = _ang(value)
	var nd := Vector2(cos(na), sin(na))
	draw_line(c - nd * 8.0, c + nd * (r - 12.0), Color(0, 0, 0, 0.6), 5.0, true)
	draw_line(c - nd * 8.0, c + nd * (r - 12.0), accent, 3.0, true)
	draw_circle(c, 7.0, Color(0.15, 0.15, 0.18))
	draw_arc(c, 7.0, 0.0, TAU, 16, Color(0.8, 0.8, 0.85), 1.5)
	if centre != "":
		var cs: int = int(r * 0.42)
		var cz: Vector2 = font.get_string_size(centre, HORIZONTAL_ALIGNMENT_LEFT, -1, cs)
		var cp: Vector2 = c + Vector2(-cz.x * 0.5, -r * 0.18 + cz.y * 0.3)
		draw_string_outline(font, cp, centre, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, 6, Color(0, 0, 0, 0.9))
		draw_string(font, cp, centre, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color(1, 0.9, 0.4))
	if readout != "":
		var rs: int = int(r * 0.17)
		var rz: Vector2 = font.get_string_size(readout, HORIZONTAL_ALIGNMENT_LEFT, -1, rs)
		var rp: Vector2 = c + Vector2(-rz.x * 0.5, r * 0.62)
		draw_string_outline(font, rp, readout, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, 5, Color(0, 0, 0, 0.9))
		draw_string(font, rp, readout, HORIZONTAL_ALIGNMENT_LEFT, -1, rs, Color(1, 1, 1))
