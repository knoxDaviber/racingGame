extends HBoxContainer
## The GARAGE page (from the main menu, the New Game page or the pause menu): a turntable preview of your car and the
## colour wheel. Racers pick any colour; as a cop you only see the police cruiser (the side is chosen on the New Game page).
## It edits the menu's `cfg` dictionary in place ("car_color") and saves nothing itself: menu.gd saves when it closes,
## and main.gd repaints your car on the menu's `closed` signal (or builds it in that colour when a match starts).

signal done

const CarModel = preload("res://car_model.gd")
const CAR_LENGTH: float = 4.2          # the model is scaled to this length (car.gd HITBOX_BASE.z), same as in the race
const SPIN_SPEED: float = 0.5          # turntable speed, rad/s
const SWATCHES: Array = [
	Color(1.0, 0.8, 0.05), Color(1.0, 0.45, 0.08), Color(0.9, 0.1, 0.1), Color(1.0, 0.3, 0.65), Color(0.6, 0.2, 0.9),
	Color(0.15, 0.3, 0.95), Color(0.15, 0.8, 0.95), Color(0.2, 0.8, 0.3), Color(0.92, 0.92, 0.95), Color(0.1, 0.1, 0.12),
]

var cfg: Dictionary = {}
var first: Control = null              # what the menu focuses when this page opens
var pivot: Node3D = null               # the turntable
var car_visual: Node3D = null          # the car standing on it
var model = null                       # that car's CarModel (null = plain box stand-in)
var box_mat: StandardMaterial3D = null # the stand-in's paint
var spin: float = 0.0
var ground_y: float = 0.0              # height of the road under the tyres (see car_model.gd _place)
var picker: ColorPicker
var color_box: VBoxContainer
var cop_note: Label
var car_label: Label
var car_btn: Button
var swatch_btns: Array = []


func setup(p_cfg: Dictionary) -> void:
	cfg = p_cfg
	ground_y = -CarModel.RIDE_HEIGHT_GUESS + CarModel.ROAD_SURFACE - CarModel.TIRE_SINK
	add_theme_constant_override("separation", 26)

	# ---- left: the turntable and Done
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var view := SubViewportContainer.new()
	view.stretch = true
	view.custom_minimum_size = Vector2(440, 270)
	left.add_child(view)
	var vp := SubViewport.new()
	vp.own_world_3d = true             # its own world: the race itself is not drawn in here
	view.add_child(vp)
	_build_stage(vp)
	car_label = _label(left, 22, Color(1.0, 0.85, 0.2))
	car_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var done_btn := Button.new()
	done_btn.text = "Done"
	done_btn.custom_minimum_size = Vector2(440, 50)
	done_btn.add_theme_font_size_override("font_size", 24)
	done_btn.pressed.connect(func(): done.emit())
	left.add_child(done_btn)
	first = done_btn

	# ---- right: the colour wheel (robbers only)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	car_btn = Button.new()   # cycles the getaway car
	car_btn.custom_minimum_size = Vector2(340, 44)
	car_btn.add_theme_font_size_override("font_size", 20)
	car_btn.pressed.connect(_next_car)
	right.add_child(car_btn)
	color_box = VBoxContainer.new()
	color_box.add_theme_constant_override("separation", 8)
	right.add_child(color_box)
	var head := _label(color_box, 22, Color(1.0, 0.85, 0.2))
	head.text = "CAR COLOUR"
	picker = ColorPicker.new()
	# Set by name: if a Godot version renames one of these, it is skipped instead of breaking the whole page.
	var options: Dictionary = {
		"picker_shape": 1,              # ColorPicker.SHAPE_HSV_WHEEL: the colour wheel
		"edit_alpha": false,
		"sampler_visible": false,
		"color_modes_visible": false,
		"sliders_visible": false,
		"presets_visible": false,
		"hex_visible": true,            # the hex box stays: type ff8800 for an exact colour
	}
	for opt in options:
		picker.set(opt, options[opt])
	picker.add_theme_constant_override("sv_width", 220)    # a smaller wheel so the page fits a 720p window
	picker.add_theme_constant_override("sv_height", 220)
	picker.color = cfg["car_color"]
	picker.color_changed.connect(_on_color)
	color_box.add_child(picker)
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 6)
	color_box.add_child(swatches)
	for c in SWATCHES:
		swatches.add_child(_swatch(c))
	cop_note = _label(right, 19, Color(0.8, 0.8, 0.8))
	cop_note.text = "You are playing as a cop: the police cruiser has no colour to pick.\nYour colour is kept for when you race (choose the side on the New Game page)."
	cop_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cop_note.custom_minimum_size = Vector2(340, 0)


## Called each time the page opens: sync with cfg and put the right car on the turntable.
func refresh() -> void:
	CarModel.selected = String(cfg["car_model"])
	_mark_swatch()
	picker.color = cfg["car_color"]
	_update_role_ui()
	_rebuild_car()


func _process(delta: float) -> void:
	if pivot == null or not is_visible_in_tree():
		return
	spin += delta * SPIN_SPEED
	pivot.rotation.y = spin
	if model != null and String(cfg["role"]) == "cop":
		model.set_siren(int(spin * 14.0) % 2 == 0, true)   # the cruiser flashes its lights (7 times a second, like in the race)


# ------------------------------------------------------------------ the stage
func _build_stage(vp: SubViewport) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.1, 0.12, 0.17)
	sky_mat.sky_horizon_color = Color(0.3, 0.33, 0.4)
	sky_mat.ground_horizon_color = Color(0.3, 0.33, 0.4)
	sky_mat.ground_bottom_color = Color(0.08, 0.09, 0.11)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var cam := Camera3D.new()
	cam.environment = env
	cam.fov = 30.0
	var eye := Vector3(0.0, 2.0, 9.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0.0, 0.2, 0.0) - eye, Vector3.UP), eye)
	vp.add_child(cam)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.4
	key.set("sky_mode", 1)   # DirectionalLight3D.SKY_MODE_LIGHT_ONLY: lights the car, does not draw a sun in the sky
	key.rotation_degrees = Vector3(-35.0, -35.0, 0.0)
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.5
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.set("sky_mode", 1)
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	vp.add_child(fill)

	var disc := CylinderMesh.new()
	disc.top_radius = 3.0
	disc.bottom_radius = 3.0
	disc.height = 0.06
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color(0.16, 0.17, 0.2)
	disc_mat.metallic = 0.3
	disc_mat.roughness = 0.6
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = disc
	floor_mi.material_override = disc_mat
	floor_mi.position = Vector3(0.0, ground_y - 0.03, 0.0)
	vp.add_child(floor_mi)

	pivot = Node3D.new()
	vp.add_child(pivot)


## Put the right car on the turntable: the getaway car in your colour, or the police cruiser.
func _rebuild_car() -> void:
	if car_visual != null:
		pivot.remove_child(car_visual)
		car_visual.queue_free()
	car_visual = Node3D.new()
	pivot.add_child(car_visual)
	var cop: bool = String(cfg["role"]) == "cop"
	var col: Color = cfg["car_color"]
	box_mat = null
	model = CarModel.new()
	if not model.attach(car_visual, cop, "GARAGE", col, CAR_LENGTH):
		model = null
		_stand_in(cop, col)


## No usable 3D model (the car files are missing): a plain box, so the colour can still be tried.
func _stand_in(cop: bool, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.93, 0.93, 0.95) if cop else col
	m.metallic = 0.5
	m.roughness = 0.35
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 0.5, 4.2)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.position = Vector3(0.0, ground_y + 0.45, 0.0)
	car_visual.add_child(mi)
	if not cop:
		box_mat = m


# ------------------------------------------------------------------ the controls
func _next_car() -> void:
	var at: int = 0
	for i in range(CarModel.PLAYER_CARS.size()):
		if CarModel.PLAYER_CARS[i][0] == cfg["car_model"]:
			at = i
	cfg["car_model"] = CarModel.PLAYER_CARS[(at + 1) % CarModel.PLAYER_CARS.size()][0]
	CarModel.selected = String(cfg["car_model"])
	_rebuild_car()
	_update_role_ui()


func _update_role_ui() -> void:
	var cop: bool = String(cfg["role"]) == "cop"
	var cname: String = "TUNER"
	for c in CarModel.PLAYER_CARS:
		if c[0] == cfg["car_model"]:
			cname = c[1]
	car_btn.text = "Car:  %s   (click to change)" % cname
	car_btn.visible = not cop
	color_box.visible = not cop
	cop_note.visible = cop
	car_label.text = "POLICE CRUISER" if cop else "GETAWAY CAR"



func _on_color(c: Color) -> void:
	cfg["car_color"] = c
	_mark_swatch()
	if model != null:
		model.set_paint_color(c)
	elif box_mat != null:
		box_mat.albedo_color = c


func _pick(c: Color) -> void:
	picker.color = c
	_on_color(c)


func _swatch(c: Color) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(30, 30)
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		sb.border_color = Color(0, 0, 0, 0.6) if state == "normal" else Color(1, 1, 1, 0.95)
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(_pick.bind(c))
	swatch_btns.append([b, c])
	return b


## A white ring on the swatch that matches the current colour.
func _mark_swatch() -> void:
	var cur: Color = cfg["car_color"]
	for e in swatch_btns:
		var on: bool = (e[1] as Color).is_equal_approx(cur) or ((e[1] as Color).to_html(false) == cur.to_html(false))
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb: StyleBoxFlat = (e[0] as Button).get_theme_stylebox(state) as StyleBoxFlat
			sb.set_border_width_all(4 if on else 2)
			sb.border_color = Color(1, 1, 1, 1) if on else (Color(0, 0, 0, 0.6) if state == "normal" else Color(1, 1, 1, 0.95))


func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
