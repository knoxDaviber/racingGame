extends Control
## Cop mode: a name tag and an arrest bar floating over every racer, drawn in screen space (2D, no 3D labels).
## Main feeds it `racers` (the same array object, always up to date), `me` (your police car) and `cam`.

const RANGE: float = 350.0       # no tag further away than this (metres)
const TAG_HEIGHT: float = 2.3    # metres above the racer's car origin

var active: bool = false
var cam: Camera3D = null
var racers: Array = []
var me = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if active:
		queue_redraw()


func _draw() -> void:
	if not active or cam == null or me == null or not is_instance_valid(me):
		return
	var font: Font = ThemeDB.fallback_font
	for r in racers:
		if not is_instance_valid(r) or not r.visible:
			continue
		var top: Vector3 = r.global_position + Vector3(0.0, TAG_HEIGHT, 0.0)
		if cam.is_position_behind(top):
			continue
		var dist: float = me.global_position.distance_to(r.global_position)
		if dist > RANGE:
			continue
		var p: Vector2 = cam.unproject_position(top)
		if r.busted:
			_text(font, p + Vector2(0.0, -14.0), "BUSTED", 18, Color(1.0, 0.35, 0.3))
			continue
		var col: Color = r.body_color
		_text(font, p + Vector2(0.0, -22.0), "%s  %d m" % [r.driver_name, int(dist)], 18, col)
		if r.arrest > 1.0:   # the arrest bar, green as it fills
			var w: float = 84.0
			var x: float = p.x - w * 0.5
			draw_rect(Rect2(x - 1.0, p.y - 17.0, w + 2.0, 9.0), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(x, p.y - 16.0, w * clampf(r.arrest / 100.0, 0.0, 1.0), 7.0), Color(1.0, 0.8, 0.1).lerp(Color(0.2, 1.0, 0.3), r.arrest / 100.0))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-7.0, -6.0), p + Vector2(7.0, -6.0), p + Vector2(0.0, 6.0)]), col)


## Centred text with a dark shadow so it reads on any background.
func _text(font: Font, p: Vector2, text: String, size: int, col: Color) -> void:
	var w: float = 260.0
	var at := Vector2(p.x - w * 0.5, p.y)
	draw_string(font, at + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(0, 0, 0, 0.9))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, size, col)
