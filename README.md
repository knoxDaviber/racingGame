# Cops & Robbers Racer  v0.4.2  (Godot 4)

Open this folder in Godot 4.3+ (built/tested on 4.4.1, you're on 4.7.x - fine) and press F5.

**Flow:** boot (calibration + shader warm-up) -> **main menu** (Play / Garage / How to play / Settings / Quit) -> **New Game**
(pick a side, a game mode and the modifiers; the Garage button opens the car colour wheel) -> START -> four levels with a
results screen after each one -> final standings -> main menu. ESC / P pauses (Garage, Retry level, Restart match, Main menu).

**Four levels:** Suburbs (afternoon) -> Coast Road (sunset) -> Red Canyon (dusk) -> Night City (midnight). Each adds cops,
speed and obstacles. Every racer has an ARREST bar that fills while a cop is within ~12 m. Full bar = busted.

## Sides and game modes
**RACER**: you + 3 AI racers (BLAZE, GHOST, VIPER) race 2 laps per level while the cops hunt everybody. Colour wheel in the Garage.
- *Points race*: every level pays by place: **1st 10, 2nd 7, 3rd 4, 4th 2, busted 0** (rules.gd RACE_POINTS). A level ends when
  everybody has finished or been busted, or 15 s after your own race is over (ENTER skips ahead; unfinished racers rank by
  progress). Most points after the last level wins.
- *Story*: no points. Level 1 just survive, level 2 finish in the top 3, level 3 top 2, level 4 win. Fail = ENTER retries.

**COP**: you drive the police cruiser (siren, nitro, drift; F = siren sound on/off) after four AI racers (BLAZE, GHOST, VIPER,
RAVEN), 3 laps per level, with 1-2 AI backup cops who compete with you (they fill an arrest bar exactly as fast as you do).
Racers that finish their laps got away. Name tags float over the racers; the green bar at the bottom shows the closest one.
- The cops must bust **at least 1, then 2, 3 and all 4** racers on levels 1-4 (always 1 with an elimination modifier). Miss the
  quota = the level is lost, ENTER retries it.
- **Points**: a bust scores 1, 2, 3, 4 ... while the SAME cop keeps busting racers (a *strike*). A bust by another cop breaks it.
  *Scaled* (default): the fewer racers start the level the bigger the steps (3 racers 2/3/5, 2 racers 4/6, 1 racer 10), so
  busting everybody is always worth 10. *Flat*: always 1/2/3/4.
- **Shared busts** (several cops in arrest range when the bar fills): each gets their own step / everybody gets the highest
  step / the points are split.
- Two leaderboards: **eliminations** (busts) and **points**.

## Modifiers (points race and cop side)
- **Last place is eliminated**: whoever ranks last in a level (busted racers rank below finishers, the earliest bust is last)
  cannot race the next level. They keep their points, so there are two rankings: points, and elimination (survivors first,
  then the later you went out the better). With 4 racers the last level is the survivor alone against the cops.
- **Busted racers are eliminated** (cop elimination): get busted and you are out of the next level. Combine both freely.
- **Match ends** (racer side, only offered when racers can be eliminated): *survival* (you always play on to the last level;
  if you are the only racer left it is you against the cops and being caught puts you out) / *last one standing* (the match
  ends as soon as one racer is left). If YOU are eliminated the match is over for you, with the standings so far.
- Cop side: **cop points** scaled / flat, and **shared busts** own / highest / split (see above).

- **Nitrous** (everyone): SHIFT. ~3 s per tank, refills slowly, fast while drifting. Cops only boost when far behind.
- **Shortcuts** (Suburbs, Coast, City): narrow, loose dirt, marked by yellow signs. Shorter, harder.
- **Obstacles** (levels 2-4): spike strips (shred your tyres for a few seconds; cops are immune) and barrel walls, dropped
  ahead of the leader or laid by a cop that got ahead. A warning pops up when one is coming.

**Controls:** W/S gas & brake/reverse - A/D steer - SPACE handbrake drift - SHIFT nitro - R flip/reset - F siren sound (cop)
- G Garage - ENTER skip ahead / retry a failed level / continue on the results screens.
**ESC or P** = pause menu: Garage, How to play, Settings (volume, fullscreen, tips, controls bar, minimap, mph, speed effects,
camera shake; saved to user://settings.cfg together with your last New Game choices and car colour), Retry level,
Restart match, Main menu. In-race tips (cyan) explain what to do when you are stuck, going the wrong way, about to be
arrested or out of nitro.

## Files
- main.gd     levels + difficulty (LEGS), match flow (title, levels, results), cops/racers, obstacles, lighting per map, camera, HUD, test hooks
- rules.gd    the match rules, no nodes: points, eliminations, cop strikes and ladders, level quota, rankings, results text
- car.gd      raycast-vehicle physics, handling, nitrous, sounds, lights, player input, AI driver
- track.gd    the 4 maps (MAPS), spline circuit, auto-placed shortcuts, walls, road, themed scenery
- Resources/Audio   small mono .ogg sounds;  Resources/Shaders/windows.gdshader   procedural city windows
- menu.gd     main menu, New Game page (side, mode, modifiers), pause menu, how to play, settings
- results_view.gd   the results screen after each level and the final standings
- garage.gd   the Garage page: turntable preview + colour wheel + swatches (the side is chosen on the New Game page)
- markers.gd  cop side: name tags and arrest bars floating over the racers
- minimap.gd, speedfx.gd   HUD minimap, speed streaks
- CHANGELOG.md

## Tuning knobs
- Handling: top of car.gd (GRIP_FRONT/REAR, HANDBRAKE_REAR_GRIP, STEER_RATE, DRIFT_SLIP, DRIFT_SLIP_EXTRA, MASS)
- Handbrake / drift: HANDBRAKE_FORCE + HANDBRAKE_ENGINE (SPACE without steering = slow down), DRIFT_HOLD_GRIP
- Difficulty: main.gd LEGS (laps, cops, cop speed, start delay, obstacle rate, arrest rate per leg) and ROBBERS list
- Points and scoring: rules.gd RACE_POINTS (10/7/4/2), LADDERS and FLAT_LADDER (cop points per bust in a strike),
  STORY_MAX_PLACE (story requirement per level); main.gd WAIT_AFTER_YOU (seconds the others get after your race is over)
- Cop side: main.gd COP_LEGS (laps, backup cops, racer speed bonus per level), COP_ROBBERS (the four racers),
  COP_PLAYER_SLOT (where your cruiser starts)
- Colour swatches in the Garage: garage.gd SWATCHES;  paint look: car_model.gd PAINT_METALLIC / PAINT_ROUGHNESS
- Maps: track.gd MAPS (layout, width, colours, sky/sun/fog, scenery, number of shortcuts)
- Nitrous / shortcuts: top of car.gd (NITRO_*), track.gd (SC_WIDTH, SC_GRIP, SC_SPEED)
- Volume: car.gd VOL (all car sounds), main.gd _build_sfx (UI sounds)

## Performance tricks (invisible on purpose)
- Nothing past the fog is drawn: the camera's far plane and the fog's end are the same per-map view distance
  (track.gd `view_dist()`: fog_begin + 230 m, so 340-450 m instead of the old 900 m).
- Scenery (walls, dashes, trees, rocks, buildings, lamps) and the road are split into 120 m chunks (track.gd `CELL`),
  one MultiMesh per kind per chunk, so chunks behind the camera or past the fog are skipped.
- Car models are pre-baked (tools/bake_car.gd -> *_baked.tscn): static parts merged per material with their textures
  in an atlas, wheel parts merged per wheel. ~15-23 draw calls per car instead of 51-82; looks pixel-identical.
  Re-run the tool after changing a car .gltf (usage at the top of the file).
- Lamps, windows, flames and sirens are just bright materials + bloom; real lights only where they show:
  the player's headlight at night, and siren lights on the nearest cop only, within 70 m (each real light re-draws
  everything it touches). Other cars get a fake light pool on the road.
- Car sounds stop entirely beyond 140 m; only the nearest cop's siren plays.
- City windows are a shader (no textures); synthesized sounds; shadows only within 80 m and off at night.
- AI cornering: track.gd `a_lat`

## Headless testing (optional)
godot --headless --audio-driver Dummy --path . -- autotest [noarrest] [solo] [leg=0..3] [pspeed=30] [alat=12]
godot --audio-driver Dummy --path . -- autotest leg=3 top=40 shots=5,20 shotdir=/tmp   (screenshots; top = view from above)
godot --headless --path . -- autotest ptest=turn|drift|drift_long|brake|hb_straight ps=30
godot --headless --audio-driver Dummy --path . -- autotest role=cop mode=points elim_last=1 elim_busted=0 ending=survival scale=scaled share=own
	(a whole points match played by the AI; tests ignore the saved menu choices and print the rankings at the end.
	 Without role/mode a test plays the story rules like before: role=robber mode=points tests the racer points race)
godot --audio-driver Dummy --path . -- autotest perf noarrest leg=3    (real-time, uncapped: fps, draw calls, triangles; HITCH = any frame over 50 ms)
