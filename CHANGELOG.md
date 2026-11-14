# Changelog

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
