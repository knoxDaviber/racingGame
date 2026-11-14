# Handover

## Done (2026-11-15, v0.2)
- 4 legs (track.gd MAPS, main.gd LEGS) with rising difficulty; nitrous; auto-placed dirt shortcuts; spike strips and
  barrel walls; sounds (car.gd VOL is the master trim); per-map lighting; batched meshes + other hidden perf tricks.
- Headless autotest runs all 4 legs. The autopilot usually gets busted on leg 3 (difficulty feels right for an AI driver).

## Done (2026-11-15, v0.2.1)
- menu.gd: pause menu (ESC/P), how to play (auto on first launch), settings saved to user://settings.cfg.
- main.gd: countdown tips, contextual tips (_update_tips), wrong-way warning, comfort toggles in _update_camera.
- Checked natively (menu, settings, HUD screenshots); web build re-exported. Godot: ~/Downloads/Godot, templates installed.

## Next
- Human playtest: difficulty ramp (LEGS), shortcut feel, obstacle frequency, audio mix.
- The AI still sometimes crashes at shortcut mouths or a city corner; the watchdog respawns it.

## Open decisions
- Engine sounds come from GGBot's pack: check its itch.io licence before publishing.
- Busted = retry the leg (not the whole run). Change in main.gd _restart if a harder mode is wanted.
