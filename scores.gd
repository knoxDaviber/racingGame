extends RefCounted
## Time-trial records, saved in user://scores.cfg: per map the best five totals (3 laps) and the best single lap.

const PATH: String = "user://scores.cfg"
const KEEP: int = 5


static func fmt(t: float) -> String:
	return "%d:%02d.%02d" % [int(t) / 60, int(t) % 60, int(fmod(t, 1.0) * 100.0)]


## {top: [totals, best first], best_lap: seconds (0 = none yet), runs: how many finished}
static func get_map(map_name: String) -> Dictionary:
	var f := ConfigFile.new()
	f.load(PATH)   # no file yet = no records
	var top: Array = f.get_value(map_name, "top", [])
	return {"top": top, "best_lap": float(f.get_value(map_name, "best_lap", 0.0)), "runs": int(f.get_value(map_name, "runs", 0))}


## Store a finished run. Returns {rank: 1..KEEP or 0 if it did not make the list, new_best_lap: bool, prev_total: previous best total or 0}.
static func record(map_name: String, total: float, best_lap: float) -> Dictionary:
	var f := ConfigFile.new()
	f.load(PATH)
	var top: Array = f.get_value(map_name, "top", [])
	var prev: float = float(top[0]) if not top.is_empty() else 0.0
	top.append(total)
	top.sort()
	var rank: int = top.find(total) + 1
	if top.size() > KEEP:
		top.resize(KEEP)
	if rank > KEEP:
		rank = 0
	var old_lap: float = float(f.get_value(map_name, "best_lap", 0.0))
	var new_lap: bool = old_lap <= 0.0 or best_lap < old_lap
	f.set_value(map_name, "top", top)
	f.set_value(map_name, "best_lap", best_lap if new_lap else old_lap)
	f.set_value(map_name, "runs", int(f.get_value(map_name, "runs", 0)) + 1)
	f.save(PATH)
	return {"rank": rank, "new_best_lap": new_lap, "prev_total": prev}
