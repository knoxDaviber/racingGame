# Cops & Robbers Racer  v0.1  (Godot 4)

Open this folder in Godot 4.3+ (built/tested on 4.4.1, you're on 4.7.x - fine) and press F5.

**You + 3 AI robbers race 3 laps. Two cop cars hunt the closest robber.**
Every robber has an ARREST bar that fills while a cop is within ~12 m. Full bar = busted (out of the race).
Finish the laps (ideally first) to escape. Busted robbers ghost through traffic so they don't block the road.

**Controls:** W/S gas & brake/reverse - A/D steer - SPACE handbrake drift - R flip/reset onto track - ENTER restart (instant).

## Files
- main.gd     race flow, calibration, grid, cops/robbers logic, camera, HUD, restart, headless test hooks
- car.gd      raycast-vehicle physics, handling model, player input, AI driver
- track.gd    spline circuit, walls, road, trees/lamp posts, AI corner-speed data
- minimap.gd, speedfx.gd   HUD minimap, speed streaks
- CHANGELOG.md

## Tuning knobs
- Handling: top of car.gd (GRIP_FRONT/REAR, HANDBRAKE_REAR_GRIP, STEER_RATE, DRIFT_SLIP, DRIFT_SLIP_EXTRA, MASS)
- Difficulty: main.gd constants (COP_COUNT, COP_SPEED, COP_DELAY, ARREST_GRACE, TOTAL_LAPS) and ROBBERS list
- AI cornering: track.gd `a_lat`

## Headless testing (optional)
godot --headless --path . -- autotest [noarrest] [solo] [pspeed=30] [alat=12]
godot --headless --path . -- autotest ptest=turn|drift|drift_long|brake ps=30
