extends CanvasLayer
## Pause menu: Resume, How to play, Settings, Retry leg, New run, Quit.
## ESC or P opens/closes it and pauses the game. Settings are saved to user://settings.cfg.
## Main reads `cfg` every frame (shake, speed_fx, tips, controls, minimap, mph).

signal retry
signal new_run

const PATH: String = "user://settings.cfg"

var cfg: Dictionary = {
	"volume": 0.8, "shake": true, "speed_fx": true, "tips": true,
	"controls": true, "minimap": true, "mph": false, "fullscreen": false, "seen_help": false,
}
var can_pause: bool = false   # set by main (false during warm-up and headless tests)
var pages: Dictionary = {}
var page: String = "main"

const HELP: String = """[b]GOAL[/b]
You are the yellow car. Finish every lap of all 4 legs without getting busted by the cops.
Your finishing place does not matter much. [b]Not getting caught is what counts.[/b]

[b]DRIVING[/b]
W or UP  =  gas          S or DOWN  =  brake, then reverse
A / D or LEFT / RIGHT  =  steer
SPACE  =  handbrake drift (hold it while turning)
SHIFT  =  nitro boost (the blue bar under your speed)
R  =  put your car back on the road (if you are flipped or stuck)
ESC or P  =  this menu        ENTER  =  retry after being busted

[b]THE COPS[/b]
Cops are the blue dots on the minimap (top right).
When a cop is close (about 12 m), your red ARREST bar fills up.
Full red bar = BUSTED. Drive away and the bar slowly empties.
Some of the bar carries over to the next leg, so stay clean.

[b]NITRO[/b]
Each tank lasts about 3 seconds. It refills slowly on its own,
and [b]fast while you drift[/b]. Use it on straights to get away.

[b]SHORTCUTS AND DANGER[/b]
Yellow signs mark dirt shortcuts: shorter, but slippery.
From leg 2: flashing spike strips pop your tyres for a few seconds,
and barrel walls block the road. A warning shows when one is coming. Steer around them.

[b]IF YOU GET BUSTED[/b]
Press ENTER (or Retry leg in this menu) to try the same leg again.
Nothing is lost, you only replay that leg."""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_load()
	_build()
	visible = false
	_apply()


# ------------------------------------------------------------------ settings
func _load() -> void:
	var f := ConfigFile.new()
	if f.load(PATH) != OK:
		return
	for k in cfg:
		var v = f.get_value("settings", k, cfg[k])
		if typeof(v) == typeof(cfg[k]):   # ignore a hand-edited file with the wrong types
			cfg[k] = v


func save() -> void:
	var f := ConfigFile.new()
	for k in cfg:
		f.set_value("settings", k, cfg[k])
	f.save(PATH)


func _apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(cfg["volume"], 0.0001)))
	AudioServer.set_bus_mute(0, cfg["volume"] <= 0.001)
	var fs: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if cfg["fullscreen"] != fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if cfg["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED)


# ---------------------------------------------------------------------- open
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var k: int = event.physical_keycode
	if k != KEY_ESCAPE and k != KEY_P:
		return
	get_viewport().set_input_as_handled()
	if visible:
		if page != "main":
			_show("main")
		else:
			close()
	elif can_pause:
		open("main")


func open(p: String) -> void:
	visible = true
	get_tree().paused = true
	_show(p)


func close() -> void:
	visible = false
	get_tree().paused = false
	save()


func _show(p: String) -> void:
	page = p
	for n in pages:
		pages[n].visible = n == p
	var first: Control = pages[p].get_meta("first")
	first.grab_focus()   # arrow keys + ENTER work too, not only the mouse


# --------------------------------------------------------------------- build
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(28)
	sb.border_color = Color(1.0, 0.8, 0.05)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)

	# main page
	var m := _page(stack, "main", "PAUSED")
	m.set_meta("first", _button(m, "Resume", close))
	_button(m, "How to play", func(): _show("help"))
	_button(m, "Settings", func(): _show("settings"))
	_button(m, "Retry this leg", _on_retry)
	_button(m, "New run (back to leg 1)", _on_new_run)
	if not OS.has_feature("web"):
		_button(m, "Quit game", _on_quit)
	_note(m, "ESC or P closes this menu")

	# how to play
	var h := _page(stack, "help", "HOW TO PLAY")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.fit_content = true
	txt.custom_minimum_size = Vector2(700, 0)
	txt.add_theme_font_size_override("normal_font_size", 19)
	txt.add_theme_font_size_override("bold_font_size", 19)
	txt.text = HELP
	scroll.add_child(txt)
	h.set_meta("first", _button(h, "Got it, let's go!", close))
	_button(h, "Back", func(): _show("main"))

	# settings
	var s := _page(stack, "settings", "SETTINGS")
	var row := HBoxContainer.new()
	var vl := _note(row, "Volume  %d%%" % int(cfg["volume"] * 100.0))
	vl.custom_minimum_size = Vector2(170, 0)
	vl.add_theme_font_size_override("font_size", 20)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = cfg["volume"]
	slider.custom_minimum_size = Vector2(300, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v):
		cfg["volume"] = v
		vl.text = "Volume  %d%%" % int(v * 100.0)
		_apply())
	row.add_child(slider)
	s.add_child(row)
	s.set_meta("first", slider)
	_toggle(s, "fullscreen", "Fullscreen")
	_toggle(s, "tips", "Show tips while driving")
	_toggle(s, "controls", "Show controls at the bottom")
	_toggle(s, "minimap", "Show minimap")
	_toggle(s, "mph", "Speed in mph (off = km/h)")
	_toggle(s, "speed_fx", "Speed effects (wide view, streaks)")
	_toggle(s, "shake", "Camera shake and lean")
	_note(s, "Feeling sick? Turn off speed effects and camera shake.")
	_button(s, "Back", func(): _show("main"))


func _on_retry() -> void:
	close()
	retry.emit()


func _on_new_run() -> void:
	close()
	new_run.emit()


func _on_quit() -> void:
	save()
	get_tree().quit()


func _page(parent: Node, n: String, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	parent.add_child(v)
	pages[n] = v
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	v.add_child(t)
	return v


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(380, 50)
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _toggle(parent: Node, key: String, text: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = cfg[key]
	c.add_theme_font_size_override("font_size", 20)
	c.toggled.connect(func(on):
		cfg[key] = on
		_apply())
	parent.add_child(c)


func _note(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	parent.add_child(l)
	return l
