# Handover

## 2026-11-20: v0.5.0 (uncommitted, headless-tested only, NOT played by a human yet)
Done: Time Trial mode + map select + saved scores (scores.gd), new map HIGHLAND LOOP (track.gd MAPS[4], time trial only,
`cuts` = authored shortcuts incl. a ramp jump), open verge with solid props before the railing, boulder slalom + nitro
reward on dirt cuts, manual gearbox (Q/E, car.gd `_manual_forces`), endless-drive-style drift (SPACE+gas+steer), air-time
fix (`_stabilize`), twin-spotlight headlights. Details in CHANGELOG v0.5.0. Campaign (4 levels) and a cop-mode match still
run clean headless; ptests tilt / gears / jump (use `autotest perf` for jump) pass.
Next / needs a human: feel of the manual gearbox (GEAR_PULL, limiter, kick), whether the jump (needs ~105 km/h) is fair,
verge drag/grip (VERGE_DRAG, VERGE_GRIP), headlight brightness (energy 9 in car.gd `set_night`, compat renderer: no shadows),
HIGHLAND LOOP laps ~80 s for the AI (long for 3 laps?), tracing accuracy vs the sketch (min corner radius ~12 m).
Open decisions: HIGHLAND LOOP is not in the 4-level campaign (CAMPAIGN_LEGS = 4 in main.gd); no ghost car in time trial;
sketch's square section was read as a box-shaped corner section + dirt cut, the sawtooth was widened to be drivable.

Updated 2026-11-15 (v0.2.2, everything committed and pushed to `main`).

## State
- 4 legs (track.gd MAPS, main.gd LEGS) with rising difficulty; nitrous; dirt shortcuts; spike strips and barrel walls;
  per-map lighting. Pause menu, how to play (opens on first launch), settings (user://settings.cfg) and tips in menu.gd
  and main.gd `_update_tips`.
- Perf: view distance = fog distance per map (track.gd `view_dist()`), scenery and road in 120 m chunks (`CELL`),
  baked car models (`*_baked.tscn`), real siren lights on the nearest cop only. Details in README "Performance tricks".
- Handling: SPACE without steering = handbrake (slows you, no nitro); SPACE + steer = drift, held after release while
  steering into the turn on gas (car.gd `_update_drift`). Nitro refills only on a real slide.

## How to work on it (Linux box)
- Godot 4.7.2: `~/Downloads/Godot/Godot_v4.7.2-stable_linux.x86_64`; export templates installed.
- Web build: `--headless --path . --export-release "Web"`, then rename `browser/Cops and Robbers Racer.html` to
  `browser/index.html`. Pages serves `browser/`. The original .gltf files are excluded from the export.
- Changed a car .gltf? Re-run `tools/bake_car.gd` (run, `--import`, run again; usage at the top of the file).
  Atlas PNGs must keep `detect_3d/compress_to=0` in their .import (lossless, like the originals).
- Tests: ptests `ptest=turn|drift|drift_long|brake|hb_straight`, full run `autotest noarrest restarttest`,
  frame stats `autotest perf noarrest leg=N` (windowed, uncapped). See README "Headless testing".
- The browser pane has no WebGL2, so the web build can't be run here; test it in a real browser.

## Next
- 2026-11-15 (uncommitted): no more mid-race shader-compile freezes. New LOADING state + loading bar (main.gd
  `_begin_loading`): per new map, the camera visits the road, shortcuts and every car with a rig of obstacles, siren
  light, headlight and nitro flame, one stop per frame (~1 s native). Skipped on retries and headless.
  `autotest perf` prints `HITCH` for any frame over 50 ms; a full 4-leg run shows none outside loading.
  Cop-crash lag did not reproduce natively; if it persists on web, suspect web audio or physics.
- Human playtest: new drift/handbrake feel, web frame rate (Night City with cops close), difficulty ramp,
  shortcut feel, obstacle frequency, audio mix.
- If the web build still lags: robber cars keep 12 un-merged parts (paint + tiling UVs; see bake log), and day legs
  draw cars twice for shadows (main.gd sun shadow distance 80 m).
- The AI still sometimes crashes at shortcut mouths or a city corner; the watchdog respawns it.

## Open decisions
- Engine sounds come from GGBot's pack: check its itch.io licence before publishing.
- Busted = retry the leg (not the whole run). Change in main.gd _restart if a harder mode is wanted.

## 2026-11-20 (later): playtest fixes (uncommitted)
Fixed: normal matches no longer inherit a time-trial map (start_leg leak, caused "LEVEL 5/4"); grid is reset after the loading tour;
big centre text shrinks to fit (`_fit_label`); tyre smoke while sliding (car.gd `_build_smoke`); transmission moved from Settings to the
New Game page; jump ramp/landing narrowed to fit inside the dirt cut's walls (JUMP_HALF_W 4.6).
Needs a human: ramp blocking (cause guessed: ramp 13 m wide overlapped the 11 m cut's side walls), smoke look, "start in the middle" (guessed: cars moved during loading).

## 2026-11-20 (evening): drift redo, garage cars, gauges (uncommitted)
Drift is now Mario-Kart style (car.gd `_update_drift`, `_stop_drift`, MT_* consts): lasts while SPACE is held, keeps >= 90% of entry speed
(`drift_floor`), charges 3 mini-turbo tiers (0.9/1.9/3.2 s) fired on release (`mt_t`); smoke tints per tier. Old "held after release" removed.
Garage: car choice (tuner + 4 Kenney cars, cfg "car_model", CarModel.PLAYER_CARS); AI racers back on the tuner. Hype music needs 3 s above 150 km/h.
HUD: analog speed + rev/gear dials (gauges.gd) replace the centre speed text; top-left backing box removed.
Needs a human: drift feel/tiers, whether to add a big top-centre position readout (Redline Rumble style), Kenney cars can't be repainted.

## 2026-11-20 (final edit of the day): settings, HUD styles, car paint (uncommitted)
Settings are now tabs (SOUND / GAMEPLAY / HUD / DISPLAY). New cfg keys: drift_boost (toggle; off = drift keeps speed but no mini-turbo),
dials (dials on = speed/gear in the dials and the centre speed/gear text is hidden; off = centre text, one display at a time),
hud_scale (75/100/125/140), hud_opacity, hud_style (classic/neon/sunset/contrast, menu.gd HUD_STYLES; also themes the menu).
Mini-turbo is stronger and faster: tiers 0.55/1.2/2.0 s, boost 1.0/1.6/2.4 s, instant kick 3.5/6/9 m/s, power x2.4, top x1.3 (car.gd MT_*).
Kenney garage cars are repaintable (Resources/Shaders/kenney_paint.gdshader repaints palette block cols 3/6/7 of row 1 only).
Needs a human: the settings tabs look (never seen on screen), HUD 140% in a 720p window crowds the left board, boost strength.
Not done: menu size scaling, a Redline-Rumble style top-centre position readout.
