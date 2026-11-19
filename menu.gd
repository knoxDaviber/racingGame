extends CanvasLayer
## Main menu + pause menu in one: TITLE (Play, Garage, How to play, Settings, Quit), NEW GAME (side, game mode, modifiers),
## and in a race PAUSED (Resume, Garage, How to play, Settings, Retry level, Restart match, Main menu, Quit).
## ESC or P opens/closes the pause menu and pauses the game; G opens it straight on the Garage.
## Settings and your last choices are saved to user://settings.cfg.
## Main reads `cfg` every frame (shake, speed_fx, tips, controls, minimap, mph); the new-game choices ("role", "mode",
## "elim_last", "elim_busted", "ending", "cop_scale", "cop_share") when `start_requested` fires; "car_color" when the
## menu closes (`closed`).

signal retry
signal new_run              # Restart match (same settings)
signal closed
signal start_requested      # START on the New Game page
signal to_title_requested   # Main menu in the pause menu

const PATH: String = "user://settings.cfg"
const GarageScript = preload("res://garage.gd")

var cfg: Dictionary = {
	"volume": 0.8, "shake": true, "speed_fx": true, "tips": true,
	"controls": true, "minimap": true, "mph": false, "fullscreen": false, "seen_help": false,
	"role": "robber",                     # side: "robber" (the racer) or "cop"
	"car_color": Color(1.0, 0.8, 0.05),   # the getaway car's paint, set in the Garage
	"mode": "points",                     # racer side: "points" race or "story"
	"elim_last": false,                   # modifier: whoever finishes last is eliminated from the next level
	"elim_busted": false,                 # modifier: busted racers are eliminated from the next level
	"ending": "survival",                 # racer side: "survival" (play on to the last level) or "last" one standing
	"cop_scale": "scaled",                # cop side points: "scaled" by racers left, or "flat"
	"cop_share": "own",                   # cop side, one racer busted by several cops: "own", "highest", "split"
}
var can_pause: bool = false   # set by main (false at the title, during warm-up and in headless tests)
var version: String = ""      # set by main, shown on the title page
var pages: Dictionary = {}
var page: String = "title"
var origin: String = "main"   # the root page of this menu session: "title" (main menu) or "main" (pause menu)
var garage = null
var garage_return: String = "main"   # where Done in the Garage goes back to
var garage_direct: bool = false      # opened with the G key: Done goes straight back to the race
var dim: ColorRect = null
var title_note: Label = null
var side_row: HBoxContainer = null
var mode_row: HBoxContainer = null
var mods_box: VBoxContainer = null
var tog_last: CheckButton = null
var tog_busted: CheckButton = null
var cyc_ending: Button = null
var cyc_scale: Button = null
var cyc_share: Button = null
var setup_note: Label = null

const HELP: String = """[b]THE GAME[/b]
Four levels in four places. Pick a side in New Game: [b]RACER[/b] (race three AI racers while the cops hunt everybody)
or [b]COP[/b] (drive the police cruiser and bust the racers). Racers paint their car in the [b]Garage[/b]
(before the race, or press G any time).

[b]RACER: POINTS RACE[/b]
Every level pays points by place: 1st 10, 2nd 7, 3rd 4, 4th 2. [b]Busted = 0 points.[/b] Most points after the
last level wins; everybody is ranked by points.
[b]RACER: STORY[/b]
No points. Level 1: just survive. Level 2: finish in the top 3. Level 3: top 2. Level 4: win it.

[b]MODIFIERS (points race)[/b]
[b]Last place is eliminated:[/b] whoever ends a level last cannot race the next one. They keep their points, so there are
two rankings at the end: points, and elimination (who lasted longest). With four racers the last level is the
survivor against the cops.
[b]Busted racers are eliminated:[/b] get caught by the cops and you are out of the next level.
[b]Match ends:[/b] [b]survival[/b] (you always play on to the last level, even if you are the only racer left: then it is you
against the cops and you must not get caught) or [b]last one standing[/b] (the match ends as soon as one racer is left).
This choice only appears when racers can be eliminated.
If you are eliminated the match is over for you, with the standings so far.

[b]DRIVING[/b]
W or UP  =  gas          S or DOWN  =  brake, then reverse
A / D or LEFT / RIGHT  =  steer
SPACE + steer  =  drift. Keep steering into the turn with gas held and
   the drift keeps going after you let go of SPACE. Centre the wheel to straighten up.
SPACE alone (no steering)  =  handbrake: it just slows you down
SHIFT  =  nitro boost (the blue bar under your speed)
R  =  put your car back on the road (if you are flipped or stuck)
F  =  siren sound on / off (cop)
ENTER  =  skip ahead when your race is over, retry after a failed level
G  =  Garage        ESC or P  =  pause menu

[b]THE COPS (racer side)[/b]
Cops are the blue dots on the minimap (top right). When a cop is close (about 12 m), your red ARREST bar fills up.
Full red bar = BUSTED. Drive away and the bar slowly empties.

[b]PLAYING AS A COP[/b]
The racers are the coloured dots on the minimap and have a name tag over their car. Your own dot has a white ring.
Stay within about 12 m of a racer and its ARREST bar fills. Full bar = BUSTED. The green bar under your speed shows the
racer closest to you. The other cops are backup: they help, and they compete with you.
Each level the cops must bust at least 1 racer (level 1), then 2, 3 and all 4. With an elimination modifier it is always
at least 1. Let too many get away and you replay the level (ENTER).
[b]Points:[/b] a bust scores 1, 2, 3, 4 ... as long as the SAME cop keeps busting racers (a strike). A bust by another cop
breaks your strike. [b]Scaled:[/b] with fewer racers left the steps get bigger (3 racers: 2, 3, 5. 2 racers: 4, 6.
1 racer: 10), so busting everybody is always worth 10. [b]Flat:[/b] always 1, 2, 3, 4.
[b]Shared busts[/b] (two cops arrest a racer together): everybody gets their own step, or everybody gets the highest
step, or the points are split.
Two leaderboards: eliminations (busts) and points. Dispatch also drops spike strips and roadblocks ahead of the racers.

[b]NITRO[/b]
Each tank lasts about 3 seconds. It refills slowly on its own,
and [b]fast while you are really sliding sideways[/b] in a drift. Use it on straights to catch up or get away.

[b]SHORTCUTS AND DANGER[/b]
Yellow signs mark dirt shortcuts: shorter, but slippery.
From level 2: flashing spike strips pop your tyres for a few seconds,
and barrel walls block the road. A warning shows when one is coming. Steer around them."""


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
	if cfg["ending"] != "last":   # an older build called this "all": it is survival
		cfg["ending"] = "survival"


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
	if k == KEY_G and not visible:   # G = Garage (car colour), also in the middle of a race
		if can_pause:
			get_viewport().set_input_as_handled()
			garage_direct = true
			garage_return = "main"
			open("garage")
		return
	if k != KEY_ESCAPE and k != KEY_P:
		return
	get_viewport().set_input_as_handled()
	if visible:
		if page == "garage":
			_garage_done()
		elif page != origin:
			_show(origin)
		elif origin == "main":
			close()
		# the main menu itself cannot be closed
	elif can_pause:
		open("main")


## The pause menu (pauses the game).
func open(p: String) -> void:
	origin = "main"
	visible = true
	get_tree().paused = true
	_show(p)


## The main menu before a race: does not pause anything, ESC does not close it.
func open_title() -> void:
	origin = "title"
	visible = true
	get_tree().paused = false
	garage_direct = false
	_show("title")


func close() -> void:
	visible = false
	get_tree().paused = false
	garage_direct = false
	save()
	closed.emit()


func _show(p: String) -> void:
	page = p
	if p == origin:
		garage_direct = false
	for n in pages:
		pages[n].visible = n == p
	var shade: Color = dim.color
	shade.a = 0.84 if origin == "title" else 0.65
	dim.color = shade
	if p == "title":
		title_note.text = version
	if p == "setup":
		_update_setup()
	if p == "garage":
		garage.refresh()
	var first: Control = pages[p].get_meta("first")
	first.grab_focus()   # arrow keys + ENTER work too, not only the mouse


# --------------------------------------------------------------------- build
func _build() -> void:
	dim = ColorRect.new()
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

	# title page: the main menu
	var t := _page(stack, "title", "COPS & ROBBERS")
	(t.get_child(0) as Label).add_theme_font_size_override("font_size", 58)
	t.set_meta("first", _button(t, "PLAY", func(): _show("setup")))
	_button(t, "Garage", func():
		garage_direct = false
		garage_return = "title"
		_show("garage"))
	_button(t, "How to play", func(): _show("help"))
	_button(t, "Settings", func(): _show("settings"))
	if not OS.has_feature("web"):
		_button(t, "Quit game", _on_quit)
	title_note = _note(t, "")

	# new game: side, game mode, modifiers
	var n := _page(stack, "setup", "NEW GAME")
	var nscroll := ScrollContainer.new()
	nscroll.custom_minimum_size = Vector2(760, 430)
	nscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	n.add_child(nscroll)
	var nbox := VBoxContainer.new()
	nbox.add_theme_constant_override("separation", 10)
	nscroll.add_child(nbox)
	side_row = _choice_row(nbox, "PLAY AS", "role", [["robber", "RACER"], ["cop", "COP"]])
	mode_row = _choice_row(nbox, "GAME MODE", "mode", [["points", "POINTS RACE"], ["story", "STORY"]])
	setup_note = _note(nbox, "")
	setup_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	setup_note.custom_minimum_size = Vector2(720, 0)
	mods_box = VBoxContainer.new()
	mods_box.add_theme_constant_override("separation", 8)
	nbox.add_child(mods_box)
	var mh := _note(mods_box, "MODIFIERS")
	mh.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	mh.add_theme_font_size_override("font_size", 22)
	tog_last = _toggle(mods_box, "elim_last", "Last place is eliminated after every level")
	tog_busted = _toggle(mods_box, "elim_busted", "Busted racers are eliminated (cop elimination)")
	cyc_ending = _cycle(mods_box, "ending", "Match ends", [["survival", "SURVIVAL"], ["last", "LAST ONE STANDING"]])
	cyc_scale = _cycle(mods_box, "cop_scale", "Cop points", [["scaled", "SCALED BY RACERS LEFT"], ["flat", "FLAT"]])
	cyc_share = _cycle(mods_box, "cop_share", "Shared busts", [["own", "OWN STEP EACH"], ["highest", "HIGHEST STEP FOR ALL"], ["split", "SPLIT THE POINTS"]])
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 10)
	n.add_child(nrow)
	var go := _button(nrow, "START", _on_start)
	go.custom_minimum_size = Vector2(300, 54)
	var gb := _button(nrow, "Garage", func():
		garage_direct = false
		garage_return = "setup"
		_show("garage"))
	gb.custom_minimum_size = Vector2(200, 54)
	var bb := _button(nrow, "Back", func(): _show("title"))
	bb.custom_minimum_size = Vector2(140, 54)
	n.set_meta("first", go)

	# pause page
	var m := _page(stack, "main", "PAUSED")
	m.set_meta("first", _button(m, "Resume", close))
	_button(m, "Garage  (car colour)", func():
		garage_direct = false
		garage_return = "main"
		_show("garage"))
	_button(m, "How to play", func(): _show("help"))
	_button(m, "Settings", func(): _show("settings"))
	_button(m, "Retry this level", _on_retry)
	_button(m, "Restart match", _on_new_run)
	_button(m, "Main menu", _on_main_menu)
	if not OS.has_feature("web"):
		_button(m, "Quit game", _on_quit)
	_note(m, "ESC or P closes this menu")

	# how to play
	var h := _page(stack, "help", "HOW TO PLAY")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h.add_child(scroll)
	var txt := RichTextLabel.new()
	txt.bbcode_enabled = true
	txt.fit_content = true
	txt.custom_minimum_size = Vector2(740, 0)
	txt.add_theme_font_size_override("normal_font_size", 19)
	txt.add_theme_font_size_override("bold_font_size", 19)
	txt.text = HELP
	scroll.add_child(txt)
	h.set_meta("first", _button(h, "Got it!", _help_ok))
	_button(h, "Back", func(): _show(origin))

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
	_button(s, "Back", func(): _show(origin))

	# garage: car preview and the colour wheel (garage.gd)
	var g := _page(stack, "garage", "GARAGE")
	var gscroll := ScrollContainer.new()
	gscroll.custom_minimum_size = Vector2(900, 520)
	gscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	g.add_child(gscroll)
	garage = GarageScript.new()
	gscroll.add_child(garage)
	garage.setup(cfg)
	garage.done.connect(_garage_done)
	g.set_meta("first", garage.first)


func _garage_done() -> void:
	if garage_direct:   # opened with G in the middle of a race: back to it
		close()
	else:
		_show(garage_return)


func _help_ok() -> void:
	if origin == "main":
		close()
	else:
		_show("title")


func _on_retry() -> void:
	close()
	retry.emit()


func _on_new_run() -> void:
	close()
	new_run.emit()


func _on_main_menu() -> void:
	close()
	to_title_requested.emit()


func _on_start() -> void:
	if cfg["role"] == "cop":
		cfg["mode"] = "points"   # story is a racer mode
	save()
	visible = false
	start_requested.emit()


func _on_quit() -> void:
	save()
	get_tree().quit()


# ------------------------------------------------------------------ new game page
## A row of toggle buttons: options = [[value, label], ...]; the pressed one is cfg[key].
func _choice_row(parent: Node, title: String, key: String, options: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = title
	l.custom_minimum_size = Vector2(140, 0)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	row.add_child(l)
	for o in options:
		var b := Button.new()
		b.text = o[1]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(200, 46)
		b.add_theme_font_size_override("font_size", 22)
		b.set_meta("value", o[0])
		b.pressed.connect(_on_choice.bind(key, o[0]))
		row.add_child(b)
	row.set_meta("key", key)
	parent.add_child(row)
	return row


func _on_choice(key: String, value: String) -> void:
	cfg[key] = value
	_update_setup()


func _sync_row(row: HBoxContainer) -> void:
	var key: String = row.get_meta("key")
	for b in row.get_children():
		if b is Button:
			b.set_pressed_no_signal(b.get_meta("value") == cfg[key])


## A button that cycles through options ([[value, label], ...]) and keeps the choice in cfg[key].
func _cycle(parent: Node, key: String, title: String, options: Array) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(560, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.set_meta("key", key)
	b.set_meta("title", title)
	b.set_meta("options", options)
	b.pressed.connect(_on_cycle.bind(b))
	parent.add_child(b)
	return b


func _on_cycle(b: Button) -> void:
	var key: String = b.get_meta("key")
	var opts: Array = b.get_meta("options")
	var at: int = 0
	for i in range(opts.size()):
		if opts[i][0] == cfg[key]:
			at = i
	cfg[key] = opts[(at + 1) % opts.size()][0]
	_update_setup()


func _cycle_text(b: Button) -> void:
	var key: String = b.get_meta("key")
	var txt: String = ""
	for o in b.get_meta("options"):
		if o[0] == cfg[key]:
			txt = o[1]
	b.text = "%s:  %s" % [b.get_meta("title"), txt]


## Show only what applies to the chosen side and game mode, and describe the rules in a few lines.
func _update_setup() -> void:
	var cop: bool = cfg["role"] == "cop"
	if cop:
		cfg["mode"] = "points"
	var story: bool = cfg["mode"] == "story"
	_sync_row(side_row)
	_sync_row(mode_row)
	mode_row.visible = not cop
	mods_box.visible = not story
	cyc_ending.visible = (not cop) and (cfg["elim_last"] or cfg["elim_busted"])   # it only matters when racers can be eliminated
	cyc_scale.visible = cop
	cyc_share.visible = cop
	tog_last.set_pressed_no_signal(cfg["elim_last"])
	tog_busted.set_pressed_no_signal(cfg["elim_busted"])
	_cycle_text(cyc_ending)
	_cycle_text(cyc_scale)
	_cycle_text(cyc_share)
	setup_note.text = _setup_summary()


func _setup_summary() -> String:
	var cop: bool = cfg["role"] == "cop"
	var t: String = ""
	if cop:
		t = "You drive the police cruiser. Stay close to a racer to arrest it. The cops must bust at least 1 racer on level 1, then 2, 3 and all 4. Every bust scores points, and you compete with the backup cops on two leaderboards (eliminations and points)."
	elif cfg["mode"] == "story":
		t = "Four levels, no points. Level 1: just survive. Level 2: finish in the top 3. Level 3: top 2. Level 4: win it."
	else:
		t = "Race three AI racers over four levels while the cops hunt everybody. 1st place 10 points, 2nd 7, 3rd 4, 4th 2, busted 0. Most points wins."
	if cfg["mode"] == "points":
		if cfg["elim_last"]:
			t += "\nLast place is out of the next level (and keeps its points)."
		if cfg["elim_busted"]:
			t += "\nBusted racers are out of the next level."
		if cop and (cfg["elim_last"] or cfg["elim_busted"]):
			t += "\nWith eliminations the cops only need 1 bust per level."
		if not cop:
			if not cfg["elim_last"] and not cfg["elim_busted"]:
				t += "\n(Turn on an elimination modifier to choose how the match ends.)"
			elif cfg["ending"] == "last":
				t += "\nLast one standing: the match ends as soon as one racer is left."
			else:
				t += "\nSurvival: the match goes on to the last level, even if you are the only racer left. Then it is you against the cops."
	return t


# ------------------------------------------------------------------ helpers
func _page(parent: Node, name_: String, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	parent.add_child(v)
	pages[name_] = v
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


func _toggle(parent: Node, key: String, text: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = cfg[key]
	c.add_theme_font_size_override("font_size", 20)
	c.toggled.connect(_on_toggle.bind(key))
	parent.add_child(c)
	return c


func _on_toggle(on: bool, key: String) -> void:
	cfg[key] = on
	_apply()
	if page == "setup":
		_update_setup()


func _note(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	parent.add_child(l)
	return l
