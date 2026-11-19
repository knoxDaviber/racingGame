extends CanvasLayer
## The screens between levels and at the end of a match: a title, a headline and up to three small tables.
## main.gd calls show_screen() with what rules.gd built (tables = [{title, cols, rows, styles}]).
## styles per row: "you" (gold), "good" (green), "bad" (red), "dim" (grey), "" (normal).

var title_lbl: Label
var sub_lbl: Label
var sub2_lbl: Label
var tables_box: HBoxContainer
var foot_lbl: Label


func _ready() -> void:
	layer = 8   # above the HUD, below the pause menu
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(26)
	sb.border_color = Color(1.0, 0.8, 0.05)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	title_lbl = _label(box, 40, Color(1.0, 0.85, 0.2))
	sub_lbl = _label(box, 30, Color(1, 1, 1))
	sub2_lbl = _label(box, 22, Color(0.85, 0.85, 0.85))
	tables_box = HBoxContainer.new()
	tables_box.add_theme_constant_override("separation", 40)
	tables_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(tables_box)
	foot_lbl = _label(box, 22, Color(0.6, 0.9, 1.0))


func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## title: big gold line; sub / sub2: two lines under it ("" hides one); tables: see the top; footer: what ENTER does.
func show_screen(title: String, sub: String, sub2: String, tables: Array, footer: String) -> void:
	title_lbl.text = title
	sub_lbl.text = sub
	sub_lbl.visible = sub != ""
	sub2_lbl.text = sub2
	sub2_lbl.visible = sub2 != ""
	foot_lbl.text = footer
	for ch in tables_box.get_children():
		tables_box.remove_child(ch)
		ch.queue_free()
	for t in tables:
		tables_box.add_child(_build_table(t))
	visible = true


func hide_screen() -> void:
	visible = false


func _build_table(t: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var head := _label(v, 24, Color(1.0, 0.85, 0.2))
	head.text = t["title"]
	var cols: Array = t["cols"]
	var grid := GridContainer.new()
	grid.columns = maxi(1, cols.size())
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 5)
	v.add_child(grid)
	for c in cols:
		var h := Label.new()
		h.text = c
		h.add_theme_font_size_override("font_size", 17)
		h.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		grid.add_child(h)
	var rows: Array = t["rows"]
	var styles: Array = t["styles"]
	for i in range(rows.size()):
		var col: Color = _color(String(styles[i]))
		for cell in rows[i]:
			var l := Label.new()
			l.text = str(cell)
			l.add_theme_font_size_override("font_size", 22)
			l.add_theme_color_override("font_color", col)
			grid.add_child(l)
	return v


func _color(style: String) -> Color:
	match style:
		"you":
			return Color(1.0, 0.85, 0.2)
		"good":
			return Color(0.5, 1.0, 0.55)
		"bad":
			return Color(1.0, 0.45, 0.4)
		"dim":
			return Color(0.6, 0.6, 0.66)
	return Color(0.95, 0.95, 0.95)
