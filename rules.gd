extends RefCounted
## Match rules: points, eliminations, cop strikes, level requirements and rankings. No nodes in here: main.gd feeds it
## names and events (a bust, a finishing order) and shows what it returns. Used by the two points modes (racer / cop).
## Story mode is only the placing requirement per level (STORY_MAX_PLACE).
##
## Racers: 1st 10, 2nd 7, 3rd 4, 4th 2 points, busted 0. "Last place is eliminated" and "busted racers are
## eliminated" remove racers from the following levels; eliminated racers keep their points.
## Cops: every bust scores along a ladder (1, 2, 3, 4 ...) that climbs while the SAME cop keeps busting racers
## (a strike); a bust by another cop breaks it. The ladder is scaled so that busting everybody is always worth 10.

const LEVELS: int = 4
const RACE_POINTS: Array = [10, 7, 4, 2]
const LADDERS: Dictionary = {4: [1, 2, 3, 4], 3: [2, 3, 5], 2: [4, 6], 1: [10]}   # by racers at the start of the level
const FLAT_LADDER: Array = [1, 2, 3, 4]       # "scaled" off: the same ladder whatever is left
const STORY_MAX_PLACE: Array = [4, 3, 2, 1]   # story mode: worst allowed place per level (1 = you must win)
const ORD: Array = ["", "1st", "2nd", "3rd", "4th", "5th", "6th"]

var active: bool = false
var cfg: Dictionary = {}
var level: int = 0
var racers: Dictionary = {}      # name -> {name, human, points, out, out_level, hist}
var racer_names: Array = []
var cops: Dictionary = {}        # name -> {name, human, points, elims, lvl_points, lvl_elims, strike}
var cop_names: Array = []
var cop_now: Array = []          # the cops on the road this level
var present: Array = []          # racers that start this level
var busts: Array = []            # [{racer, cops}] in the order they happened
var last_rank: Array = []        # racers of the last finished level, best first
var last_fin: Array = []
var last_run: Array = []
var over: bool = false
var over_reason: String = ""


func reset() -> void:
	active = false
	cfg = {}
	level = 0
	racers = {}
	racer_names = []
	cops = {}
	cop_names = []
	cop_now = []
	present = []
	busts = []
	last_rank = []
	last_fin = []
	last_run = []
	over = false
	over_reason = ""


# ------------------------------------------------------------------ match / level set-up
## p_cfg: side ("racer" / "cop"), elim_last, elim_busted, ending ("survival" = always play on to the last level / "last" = last one standing), scaled, share
## ("own" / "highest" / "split").  specs: [{name, human}] for every racer, in grid order.
func start_match(p_cfg: Dictionary, specs: Array) -> void:
	reset()
	active = true
	cfg = {
		"side": String(p_cfg.get("side", "racer")),
		"elim_last": bool(p_cfg.get("elim_last", false)),
		"elim_busted": bool(p_cfg.get("elim_busted", false)),
		"ending": String(p_cfg.get("ending", "survival")),
		"scaled": bool(p_cfg.get("scaled", true)),
		"share": String(p_cfg.get("share", "own")),
	}
	for s in specs:
		racers[s["name"]] = {"name": s["name"], "human": bool(s["human"]), "points": 0, "out": false, "out_level": -1, "hist": []}
		racer_names.append(s["name"])


## Call at the start of every level. cop_list = the cops that score this level (cop side), e.g. ["YOU", "COP 1"].
func begin_level(p_level: int, cop_list: Array) -> void:
	level = p_level
	present = active_racers()
	busts = []
	last_fin = []
	last_run = []
	cop_now = cop_list.duplicate()
	for c in cop_list:
		if not cops.has(c):
			cops[c] = {"name": c, "human": c == "YOU", "points": 0.0, "elims": 0, "lvl_points": 0.0, "lvl_elims": 0, "strike": 0}
			cop_names.append(c)
	for c in cop_names:
		cops[c]["lvl_points"] = 0.0
		cops[c]["lvl_elims"] = 0
		cops[c]["strike"] = 0


func active_racers() -> Array:
	var out: Array = []
	for n in racer_names:
		if not racers[n]["out"]:
			out.append(n)
	return out


func is_out(name: String) -> bool:
	return racers.has(name) and bool(racers[name]["out"])


func racer_points(name: String) -> int:
	return int(racers[name]["points"]) if racers.has(name) else 0


func cop_points(name: String) -> float:
	return float(cops[name]["points"]) if cops.has(name) else 0.0


func cop_elims(name: String) -> int:
	return int(cops[name]["elims"]) if cops.has(name) else 0


# ------------------------------------------------------------------ cop side
func ladder() -> Array:
	if not cfg["scaled"]:
		return FLAT_LADDER
	var k: int = clampi(present.size(), 1, 4)
	return LADDERS[k]


## Busts the cops must make this level: 1, 2, 3, then all 4. With an elimination modifier the field shrinks, so it is
## always 1.
func cop_required() -> int:
	var n: int = present.size()
	if cfg["elim_last"] or cfg["elim_busted"]:
		return mini(1, n)
	return mini(level + 1, n)


## Can the cops still make the quota if `escaped_n` racers have already got away?
func cop_can_pass(escaped_n: int) -> bool:
	return escaped_n <= present.size() - cop_required()


## A racer was busted by `capturers` (every cop within arrest range at that moment). Returns {cop: points} (cop side).
func record_bust(racer: String, capturers: Array) -> Dictionary:
	busts.append({"racer": racer, "cops": capturers.duplicate()})
	var awarded: Dictionary = {}
	if cfg["side"] != "cop":
		return awarded
	var caps: Array = []
	for c in capturers:
		if cop_now.has(c):
			caps.append(c)
	if caps.is_empty():
		return awarded
	var lad: Array = ladder()
	for c in cop_now:
		if caps.has(c):
			cops[c]["strike"] = int(cops[c]["strike"]) + 1
		else:
			cops[c]["strike"] = 0   # somebody else made this bust: the strike is broken
	var vals: Dictionary = {}
	var top: float = 0.0
	for c in caps:
		var idx: int = mini(int(cops[c]["strike"]), lad.size()) - 1
		var v: float = float(lad[idx])
		vals[c] = v
		top = maxf(top, v)
	for c in caps:
		var pts: float = float(vals[c])
		if cfg["share"] == "highest":
			pts = top
		elif cfg["share"] == "split":
			pts = top / float(caps.size())
		awarded[c] = pts
		cops[c]["points"] = float(cops[c]["points"]) + pts
		cops[c]["lvl_points"] = float(cops[c]["lvl_points"]) + pts
		cops[c]["elims"] = int(cops[c]["elims"]) + 1
		cops[c]["lvl_elims"] = int(cops[c]["lvl_elims"]) + 1
	return awarded


# ------------------------------------------------------------------ racers: end of a level
## finished = racers in the order they crossed the line, running = racers still on the road (best progress first).
## Busted racers (record_bust) rank below everybody; the last one busted ranks best of them. Hands out the points,
## eliminates, and decides whether the match is over. Returns {rows, out_now, over, reason}.
func finish_level(finished: Array, running: Array) -> Dictionary:
	var busted_names: Array = []
	for b in busts:
		busted_names.append(b["racer"])
	var ranked: Array = []
	for n in finished + running:
		if present.has(n) and not ranked.has(n) and not busted_names.has(n):
			ranked.append(n)
	for n in present:
		if not ranked.has(n) and not busted_names.has(n):
			ranked.append(n)
	var n_ok: int = ranked.size()
	for i in range(busted_names.size() - 1, -1, -1):
		var bn: String = busted_names[i]
		if present.has(bn) and not ranked.has(bn):
			ranked.append(bn)
	var rows: Array = []
	for i in range(ranked.size()):
		var n: String = ranked[i]
		var is_busted: bool = busted_names.has(n)
		var pts: int = 0
		if not is_busted and i < RACE_POINTS.size():
			pts = int(RACE_POINTS[i])
		var kind: String = "bust" if is_busted else ("fin" if finished.has(n) else "dnf")
		rows.append({"name": n, "human": racers[n]["human"], "pts": pts, "kind": kind, "place": i + 1})
		racers[n]["points"] = int(racers[n]["points"]) + pts
		racers[n]["hist"].append({"level": level, "place": i + 1, "pts": pts, "kind": kind})
	var out_now: Array = []
	if cfg["elim_busted"]:
		for n in busted_names:
			if not out_now.has(n):
				out_now.append(n)
	if cfg["elim_last"] and present.size() >= 2:
		var worst: String = ranked[ranked.size() - 1]
		if not out_now.has(worst):
			out_now.append(worst)
	var is_final: bool = level == LEVELS - 1
	if is_final and cfg["side"] == "racer" and present.size() == 1:   # the lone survivor against the cops: caught = out
		for n in busted_names:
			if not out_now.has(n):
				out_now.append(n)
	for n in out_now:
		racers[n]["out"] = true
		racers[n]["out_level"] = level
	last_rank = ranked.duplicate()
	last_fin = []
	for n in finished:
		if present.has(n):
			last_fin.append(n)
	last_run = []
	for n in running:
		if present.has(n):
			last_run.append(n)
	var active_now: Array = active_racers()
	var human_out: bool = false
	for n in racer_names:
		if racers[n]["human"] and racers[n]["out"]:
			human_out = true
	var reason: String = ""
	if cfg["side"] == "racer":
		if human_out:
			reason = "human_out"
		elif is_final:
			reason = "final"
		elif active_now.is_empty():
			reason = "all_out"
		elif cfg["ending"] == "last" and active_now.size() <= 1:
			reason = "last_standing"
	else:
		if is_final:
			reason = "final"
		elif active_now.is_empty():
			reason = "all_out"
	if reason != "":
		over = true
		over_reason = reason
	return {"rows": rows, "out_now": out_now, "over": over, "reason": reason, "ranked_ok": n_ok}


# ------------------------------------------------------------------ rankings
func points_ranking() -> Array:
	var names: Array = racer_names.duplicate()
	names.sort_custom(_cmp_points)
	return names


## Survivors first (best points first), then the eliminated: the later you went out, the better.
func elimination_ranking() -> Array:
	var alive: Array = []
	var gone: Array = []
	for n in racer_names:
		if racers[n]["out"]:
			gone.append(n)
		else:
			alive.append(n)
	alive.sort_custom(_cmp_alive)
	gone.sort_custom(_cmp_gone)
	return alive + gone


func cop_board_elims() -> Array:
	var names: Array = cop_names.duplicate()
	names.sort_custom(_cmp_cop_elims)
	return names


func cop_board_points() -> Array:
	var names: Array = cop_names.duplicate()
	names.sort_custom(_cmp_cop_points)
	return names


# sort_custom comparators: true when `a` ranks before `b`. Every one ends with the original order, so there are no ties.
func _cmp_points(a, b) -> bool:
	var ra: Dictionary = racers[a]
	var rb: Dictionary = racers[b]
	if ra["points"] != rb["points"]:
		return ra["points"] > rb["points"]
	if ra["out"] != rb["out"]:
		return not ra["out"]
	if ra["out"] and ra["out_level"] != rb["out_level"]:
		return ra["out_level"] > rb["out_level"]
	return racer_names.find(a) < racer_names.find(b)


func _cmp_alive(a, b) -> bool:
	if racers[a]["points"] != racers[b]["points"]:
		return racers[a]["points"] > racers[b]["points"]
	return racer_names.find(a) < racer_names.find(b)


func _cmp_gone(a, b) -> bool:
	if racers[a]["out_level"] != racers[b]["out_level"]:
		return racers[a]["out_level"] > racers[b]["out_level"]
	if racers[a]["points"] != racers[b]["points"]:
		return racers[a]["points"] > racers[b]["points"]
	return racer_names.find(a) < racer_names.find(b)


func _cmp_cop_elims(a, b) -> bool:
	if cops[a]["elims"] != cops[b]["elims"]:
		return cops[a]["elims"] > cops[b]["elims"]
	if cops[a]["points"] != cops[b]["points"]:
		return cops[a]["points"] > cops[b]["points"]
	return cop_names.find(a) < cop_names.find(b)


func _cmp_cop_points(a, b) -> bool:
	if cops[a]["points"] != cops[b]["points"]:
		return cops[a]["points"] > cops[b]["points"]
	if cops[a]["elims"] != cops[b]["elims"]:
		return cops[a]["elims"] > cops[b]["elims"]
	return cop_names.find(a) < cop_names.find(b)


# ------------------------------------------------------------------ snapshots (retrying a level)
func snapshot() -> Dictionary:
	return {
		"racers": racers.duplicate(true), "cops": cops.duplicate(true), "cop_names": cop_names.duplicate(),
		"cop_now": cop_now.duplicate(), "present": present.duplicate(), "busts": busts.duplicate(true),
		"last_rank": last_rank.duplicate(), "over": over, "over_reason": over_reason, "level": level,
	}


func restore(s: Dictionary) -> void:
	racers = s["racers"].duplicate(true)
	cops = s["cops"].duplicate(true)
	cop_names = s["cop_names"].duplicate()
	cop_now = s["cop_now"].duplicate()
	present = s["present"].duplicate()
	busts = s["busts"].duplicate(true)
	last_rank = s["last_rank"].duplicate()
	over = s["over"]
	over_reason = s["over_reason"]
	level = s["level"]


# ------------------------------------------------------------------ text
static func fmt(x: float) -> String:
	if absf(x - roundf(x)) < 0.001:
		return str(int(roundf(x)))
	return "%.1f" % x


static func ordinal(n: int) -> String:
	if n >= 0 and n < ORD.size():
		return ORD[n]
	return "%dth" % n


static func story_ok(lv: int, place: int) -> bool:
	return place <= int(STORY_MAX_PLACE[clampi(lv, 0, LEVELS - 1)])


## One line about this level's rules, shown during the countdown.
func rules_line() -> String:
	var parts: Array = []
	if cfg["side"] == "cop":
		parts.append("Bust at least %d of the %d racers." % [cop_required(), present.size()])
		if cfg["elim_busted"]:
			parts.append("Busted racers are out for good.")
		if cfg["elim_last"]:
			parts.append("The last racer is eliminated.")
	else:
		parts.append("1st 10 points, 2nd 7, 3rd 4, 4th 2. Busted = 0.")
		if cfg["elim_last"]:
			parts.append("Last place is eliminated.")
		if cfg["elim_busted"]:
			parts.append("Busted = eliminated.")
	return " ".join(parts)


func _table(title: String, cols: Array, rows: Array, styles: Array) -> Dictionary:
	return {"title": title, "cols": cols, "rows": rows, "styles": styles}


func _style(human: bool, bad: bool = false, good: bool = false, dim: bool = false) -> String:
	if human:
		return "you"
	if bad:
		return "bad"
	if good:
		return "good"
	if dim:
		return "dim"
	return ""


## Subtitle and tables for the screen shown after a level. `res` = what finish_level returned.
func level_screen(res: Dictionary) -> Dictionary:
	var tables: Array = []
	var sub: String = ""
	if cfg["side"] == "racer":
		var rows: Array = []
		var styles: Array = []
		var res_rows: Array = res["rows"]
		for i in range(res_rows.size()):
			var r: Dictionary = res_rows[i]
			var result: String = "FINISHED"
			if r["kind"] == "bust":
				result = "BUSTED"
			elif r["kind"] == "dnf":
				result = "DNF"
			rows.append([str(i + 1), r["name"], result, "+" + fmt(float(r["pts"]))])
			styles.append(_style(r["human"], r["kind"] == "bust"))
			if r["human"]:
				if r["kind"] == "bust":
					sub = "BUSTED: 0 points this level"
				else:
					sub = "%s place: +%s points" % [ordinal(i + 1), fmt(float(r["pts"]))]
				if res["out_now"].has(r["name"]):
					sub += "   -   ELIMINATED"
		tables.append(_table("THIS LEVEL", ["#", "RACER", "RESULT", "PTS"], rows, styles))
		rows = []
		styles = []
		var pr: Array = points_ranking()
		for i in range(pr.size()):
			var rr: Dictionary = racers[pr[i]]
			var status: String = ""
			if rr["out"]:
				status = "ELIMINATED" if rr["out_level"] == level else "OUT (L%d)" % (int(rr["out_level"]) + 1)
			rows.append([str(i + 1), pr[i], fmt(float(rr["points"])), status])
			styles.append(_style(rr["human"], false, false, rr["out"]))
		tables.append(_table("POINTS", ["#", "RACER", "TOTAL", "STATUS"], rows, styles))
	else:
		var rows2: Array = []
		var styles2: Array = []
		for b in busts:
			if present.has(b["racer"]):
				var tail: String = "  (out)" if res["out_now"].has(b["racer"]) else ""
				rows2.append([b["racer"], "BUSTED by " + ", ".join(b["cops"]) + tail])
				styles2.append("good")
		for n in last_fin:
			rows2.append([n, "GOT AWAY"])
			styles2.append("bad")
		for n in last_run:
			rows2.append([n, "STILL RACING"])
			styles2.append("")
		tables.append(_table("THE RACERS", ["RACER", "RESULT"], rows2, styles2))
		for pass_i in range(2):
			var order: Array = cop_board_elims() if pass_i == 0 else cop_board_points()
			var rows3: Array = []
			var styles3: Array = []
			for i in range(order.size()):
				var c: Dictionary = cops[order[i]]
				if pass_i == 0:
					rows3.append([str(i + 1), order[i], str(c["lvl_elims"]), str(c["elims"])])
				else:
					rows3.append([str(i + 1), order[i], "+" + fmt(float(c["lvl_points"])), fmt(float(c["points"]))])
				styles3.append("you" if c["human"] else "")
			tables.append(_table("ELIMINATIONS" if pass_i == 0 else "POINTS", ["#", "COP", "LEVEL", "TOTAL"], rows3, styles3))
		var busted_n: int = 0
		for b in busts:
			if present.has(b["racer"]):
				busted_n += 1
		sub = "Busted %d of %d (needed %d): LEVEL CLEARED" % [busted_n, present.size(), cop_required()]
		if cops.has("YOU"):
			var me: Dictionary = cops["YOU"]
			sub += "   -   you: +%s points, %d eliminations" % [fmt(float(me["lvl_points"])), int(me["lvl_elims"])]
	return {"sub": sub, "tables": tables}


## Title, two headline lines and tables for the end-of-match screen.
func final_screen() -> Dictionary:
	var tables: Array = []
	var line1: String = ""
	var line2: String = ""
	var elim_on: bool = cfg["elim_last"] or cfg["elim_busted"]
	if cfg["side"] == "racer":
		var human: String = ""
		for n in racer_names:
			if racers[n]["human"]:
				human = n
		var pr: Array = points_ranking()
		var champ: String = pr[0]
		var champ_pts: String = fmt(float(racers[champ]["points"]))
		if over_reason == "human_out":
			line1 = "ELIMINATED IN LEVEL %d" % (int(racers[human]["out_level"]) + 1)
			line2 = "You scored %s points. The others race on without you: standings so far." % fmt(float(racers[human]["points"]))
		elif over_reason == "all_out":
			line1 = "ALL RACERS ELIMINATED"
			line2 = "The cops win.   Points champion: %s (%s)" % [champ, champ_pts]
		elif elim_on:
			line1 = "YOU ARE THE LAST ONE STANDING!" if over_reason == "last_standing" else "YOU SURVIVED!"
			if champ == human:
				line2 = "You are also the points champion (%s points)." % champ_pts
			else:
				line2 = "Points champion: %s (%s points)   -   you: %s" % [champ, champ_pts, fmt(float(racers[human]["points"]))]
		elif champ == human:
			line1 = "YOU WIN!"
			line2 = "%s points" % champ_pts
		else:
			line1 = "%s WINS" % champ
			line2 = "You finished %s with %s points" % [ordinal(pr.find(human) + 1), fmt(float(racers[human]["points"]))]
		var rows: Array = []
		var styles: Array = []
		for i in range(pr.size()):
			var r: Dictionary = racers[pr[i]]
			var status: String = ""
			if r["out"]:
				status = "OUT (L%d)" % (int(r["out_level"]) + 1)
			elif elim_on:
				status = "SURVIVED"
			rows.append([str(i + 1), pr[i], fmt(float(r["points"])), status])
			styles.append(_style(r["human"], false, false, r["out"]))
		tables.append(_table("POINTS RANKING", ["#", "RACER", "POINTS", "STATUS"], rows, styles))
		if elim_on:
			var er: Array = elimination_ranking()
			rows = []
			styles = []
			for i in range(er.size()):
				var r2: Dictionary = racers[er[i]]
				var after: String = "SURVIVED"
				if r2["out"]:
					after = "LEVEL %d" % (int(r2["out_level"]) + 1)
				rows.append([str(i + 1), er[i], after, fmt(float(r2["points"]))])
				styles.append(_style(r2["human"], false, false, r2["out"]))
			tables.append(_table("ELIMINATION RANKING", ["#", "RACER", "OUT AFTER", "POINTS"], rows, styles))
	else:
		var be: Array = cop_board_elims()
		var bp: Array = cop_board_points()
		line1 = "ALL RACERS ARRESTED!" if over_reason == "all_out" else "CASE CLOSED!"
		if not be.is_empty():
			var e: String = be[0]
			var p: String = bp[0]
			line2 = "Best eliminator: %s (%d)   -   Best scored: %s (%s points)" % [e, int(cops[e]["elims"]), p, fmt(float(cops[p]["points"]))]
		for pass_i in range(2):
			var order: Array = be if pass_i == 0 else bp
			var rows2: Array = []
			var styles2: Array = []
			for i in range(order.size()):
				var c: Dictionary = cops[order[i]]
				if pass_i == 0:
					rows2.append([str(i + 1), order[i], str(c["elims"]), fmt(float(c["points"]))])
				else:
					rows2.append([str(i + 1), order[i], fmt(float(c["points"])), str(c["elims"])])
				styles2.append("you" if c["human"] else "")
			var cols: Array = ["#", "COP", "ELIMS", "POINTS"] if pass_i == 0 else ["#", "COP", "POINTS", "ELIMS"]
			tables.append(_table("ELIMINATIONS LEADERBOARD" if pass_i == 0 else "POINTS LEADERBOARD", cols, rows2, styles2))
	return {"title": "MATCH OVER", "line1": line1, "line2": line2, "tables": tables}
