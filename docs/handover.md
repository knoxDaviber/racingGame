# Handover

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
- Human playtest: new drift/handbrake feel, web frame rate (Night City with cops close), difficulty ramp,
  shortcut feel, obstacle frequency, audio mix.
- If the web build still lags: robber cars keep 12 un-merged parts (paint + tiling UVs; see bake log), and day legs
  draw cars twice for shadows (main.gd sun shadow distance 80 m).
- The AI still sometimes crashes at shortcut mouths or a city corner; the watchdog respawns it.

## Open decisions
- Engine sounds come from GGBot's pack: check its itch.io licence before publishing.
- Busted = retry the leg (not the whole run). Change in main.gd _restart if a harder mode is wanted.
