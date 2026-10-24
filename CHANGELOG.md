# Changelog

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
