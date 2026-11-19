# Changelog

## v0.4.2
- "Match ends" is now **survival** / **last one standing**. Survival is what v0.4.1 called "all levels": the match always goes on
  to the last level, even if you are the only racer left (then it is you against the cops). The choice only shows up when an
  elimination modifier is on, because without eliminations nobody is ever left alone.

## v0.4.1
- The AI backup cops now fill a racer's arrest bar exactly as fast as you do (it was half speed).
- "Survival" is gone from "Match ends": it was practically the same as playing all the levels. The choice is now all levels /
  last one standing. (The lone survivor of the last level still goes out if the cops catch them.)

## v0.4
- Main menu before the race (Play, Garage, How to play, Settings, Quit) and a New Game page: pick the side (RACER / COP), the
  game mode (POINTS RACE / STORY) and the modifiers, open the Garage, START. Your choices are remembered. The pause menu
  got Retry level, Restart match and Main menu. The Garage no longer switches side (that is the New Game page now).
- Points race (racer): 1st 10, 2nd 7, 3rd 4, 4th 2, busted 0 points per level; results screen after each level; the other
  racers get to finish after you (or ENTER skips). Final standings with two rankings (points, elimination).
- Modifiers: last place is eliminated, busted racers are eliminated, match ends = all levels / last one standing.
- Story (racer): level 1 survive, level 2 top 3, level 3 top 2, level 4 win. No points. (Busted AI racers now come back every
  level instead of sitting the run out, and arrest bars no longer carry over: each level starts clean.)
- Cop side: bust quota per level (1, 2, 3, all 4; 1 with an elimination modifier), points per bust with strikes (same cop busting
  in a row: 1/2/3/4, scaled by how many racers are left or flat), shared bust rules (own step / highest step / split), the AI backup
  cops compete with you, leaderboards for eliminations and for points. Cop levels have 3 laps.
- rules.gd holds all of that (no nodes, tested against the examples in the design notes); results_view.gd draws the screens.
- "Leg" is now called "level" everywhere. The HUD shows your points / the bust quota.

## v0.3
- Garage (key G, "Garage" in the pause menu, and it opens by itself on first launch): a turntable preview of your car,
  a colour wheel (plus quick swatches and a hex field) to paint the getaway car any colour you like, and a ROBBER / COP
  switch. The colour and the role are saved in user://settings.cfg. The colour is applied live: the racing car's red
  paint is swapped for it (car_model.gd `set_paint_color`), so you no longer start as yellow every time.
- Cop mode: drive the police cruiser (siren, nitro, drift, F = siren sound on/off) and bust the four AI racers.
  A racer's ARREST bar fills while you are within ~12 m (backup cops count half). Name tags over the racers, a nearest-racer
  readout and a green arrest bar show who you are catching. Racers that finish their laps got away; more escapes than the
  leg allows (2 on legs 1-2, 1 on legs 3-4) loses the leg. Three laps per leg, racers get faster each leg, 1-2 backup cops.
  Dispatch still drops spike strips / roadblocks ahead of the racers.
- Minimap: your own dot has a white ring; hidden cars are not drawn.
- Main flow: the field is now built by `_spawn_field()` for either role (the start-up calibration car is replaced by it).

## v0.2.2
- Performance: view distance cut from 900 m to each map's fog distance (340-450 m); scenery and road split into
  120 m chunks that can be skipped when off-screen or past the fog (was one track-wide mesh each, always drawn);
  car models baked into far fewer draw calls (tools/bake_car.gd); real siren lights on the nearest cop only.
  Measured: first leg 414k -> 184k triangles a frame, draw calls 463 -> 340; Night City draw calls 276 -> 171.
- Handbrake: SPACE without steering now brakes the rear wheels and cuts power (it used to cost nothing), and
  nitro only refills while the car is really sliding (it used to refill whenever SPACE was held).
- Drift: start it with SPACE + steering; it holds after SPACE is released while you steer into the turn on the
  gas, and ends when you centre the wheel, brake or lift off.

## v0.2.1
- Pause menu (ESC or P): Resume, How to play, Settings, Retry leg, New run, Quit (desktop only). Keyboard navigable.
- How to play page, shown automatically on first launch.
- Settings, saved to user://settings.cfg: volume, fullscreen, tips, controls bar, minimap, mph/km/h,
  speed effects (FOV + streaks) and camera shake/lean (comfort toggles).
- Tips: one per countdown, plus contextual hints (hold W, stuck -> R, cop on you, spikes, nitro empty/unused),
  a WRONG WAY warning and a tip on the BUSTED screen.

## v0.2
- Four maps played as one escape, time of day moving on each leg: Suburbs, Coast Road, Red Canyon, Night City.
  Difficulty rises per leg (more and faster cops, earlier start, obstacles, faster arrests). Busted = out for the run;
  ENTER retries the current leg. Race order and half of each arrest bar carry over.
- Nitrous for everyone (SHIFT), refilled by drifting. Exhaust flames, blue screen tint, FOV kick, wind streaks.
- Shortcuts on three maps (auto-placed through the infield): narrow loose-dirt cuts, signposted.
- Obstacles from leg 2: spike strips and barrel walls, with on-screen warnings. Cops are immune to spikes.
- Sound: engines (robber / cop), soft siren (nearest cop only, with doppler), tyre squeal, nitrous, crashes, countdown,
  busted / escaped stingers.
- Lighting: per-map sky, sun and fog, bloom, headlights and light pools at night, distance-culled siren lights.
- Fixes: road faced downwards (rendered too dark); walls/dashes batched into MultiMeshes.

## v0.1
Handling (from friend feedback: "too heavy, turns too slow, drift spins out too easily")
- Lighter car (1000 -> 800 kg), much more steering lock at speed, faster steering rate, more tyre grip.
  Measured: steady ~1.6 g cornering at 25 and 40 m/s with ~2 deg of slip (was slow and lazy).
- Yaw assist makes turn-in quick and stable.
- Drift rewritten: handbrake now holds a controllable slide angle (~30 deg), snaps back when released.
  Only holding full lock + handbrake for ~2 s pushes it far enough to actually spin.
- Brakes fixed (were ~0.35 g, now ~1 g).
Speed sensation
- FOV widens with speed, camera pulls back/lower, slight shake and lean into turns, screen-edge speed streaks,
  trees and lamp posts along the road, higher top speed (no more hidden default damping capping speed at ~100 km/h).
Gameplay
- 3 AI robbers racing you; per-racer arrest bars, busted/escaped states, live leaderboard + position.
- Cops pick the closest robber, start after a short delay, rubber-band gently. 6 s arrest grace at the start.
- Instant restart (ENTER): no scene reload, no recalibration.
- Minimap + HUD now positioned from the real window size.
