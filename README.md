# Cops & Robbers Racer  v0.2  (Godot 4)

Open this folder in Godot 4.3+ (built/tested on 4.4.1, you're on 4.7.x - fine) and press F5.

**One escape, four legs:** Suburbs (afternoon) -> Coast Road (sunset) -> Red Canyon (dusk) -> Night City (midnight).
You + 3 AI robbers race 2 laps per leg while cop cars hunt the closest robber. Each leg adds cops, speed and obstacles.
Every robber has an ARREST bar that fills while a cop is within ~12 m. Full bar = busted (out for the rest of the run).
Race order and half of each arrest bar carry into the next leg. Survive all four legs to escape.

- **Nitrous** (everyone): SHIFT. ~3 s per tank, refills slowly, fast while drifting. Cops only boost when far behind.
- **Shortcuts** (Suburbs, Coast, City): narrow, loose dirt, marked by yellow signs. Shorter, harder.
- **Obstacles** (legs 2-4): spike strips (shred your tyres for a few seconds) and barrel walls, dropped ahead of the
  leader or laid by a cop that got ahead. A warning pops up when one is coming.

**Controls:** W/S gas & brake/reverse - A/D steer - SPACE handbrake drift - SHIFT nitro - R flip/reset - ENTER retry leg / new run.
**ESC or P** = pause menu: How to play, Settings (volume, fullscreen, tips, controls bar, minimap, mph, speed effects,
camera shake; saved to user://settings.cfg), Retry leg, New run. How to play opens by itself on first launch.
In-race tips (cyan) explain what to do when you are stuck, going the wrong way, about to be arrested or out of nitro.

## Files
- main.gd     legs + difficulty (LEGS), race flow, cops/robbers, obstacles, lighting per map, camera, HUD, test hooks
- car.gd      raycast-vehicle physics, handling, nitrous, sounds, lights, player input, AI driver
- track.gd    the 4 maps (MAPS), spline circuit, auto-placed shortcuts, walls, road, themed scenery
- Resources/Audio   small mono .ogg sounds;  Resources/Shaders/windows.gdshader   procedural city windows
- menu.gd     pause menu, how to play, settings
- minimap.gd, speedfx.gd   HUD minimap, speed streaks
- CHANGELOG.md

## Tuning knobs
- Handling: top of car.gd (GRIP_FRONT/REAR, HANDBRAKE_REAR_GRIP, STEER_RATE, DRIFT_SLIP, DRIFT_SLIP_EXTRA, MASS)
- Difficulty: main.gd LEGS (laps, cops, cop speed, start delay, obstacle rate, arrest rate per leg) and ROBBERS list
- Maps: track.gd MAPS (layout, width, colours, sky/sun/fog, scenery, number of shortcuts)
- Nitrous / shortcuts: top of car.gd (NITRO_*), track.gd (SC_WIDTH, SC_GRIP, SC_SPEED)
- Volume: car.gd VOL (all car sounds), main.gd _build_sfx (UI sounds)

## Performance tricks (invisible on purpose)
- Walls, road dashes, trees, rocks, buildings: one MultiMesh draw call each, not hundreds of nodes.
- Depth fog closes in before the (shortened) far plane, so the cut-off is never seen.
- Lamps, windows, flames and sirens are just bright materials + bloom; real lights only where they show:
  the player's headlight at night, and siren lights on cops within 70 m. Other cars get a fake light pool on the road.
- Car sounds stop entirely beyond 140 m; only the nearest cop's siren plays.
- City windows are a shader (no textures); synthesized sounds; shadows only within 80 m and off at night.
- AI cornering: track.gd `a_lat`

## Headless testing (optional)
godot --headless --audio-driver Dummy --path . -- autotest [noarrest] [solo] [leg=0..3] [pspeed=30] [alat=12]
godot --audio-driver Dummy --path . -- autotest leg=3 top=40 shots=5,20 shotdir=/tmp   (screenshots; top = view from above)
godot --headless --path . -- autotest ptest=turn|drift|drift_long|brake ps=30
