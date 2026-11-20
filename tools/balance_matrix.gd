extends SceneTree
## The simulated duel matrix (doctrine_balancing.md, tool 3): runs the real NPC combat AI headless, at
## a raised time scale, for N random seeds, and reports win rates and time to kill. By default it
## fights every class both factions have, one ship each (Federation against Hegemony: fighter,
## heavy fighter, frigate, cruiser, capital ship). Sides are swapped on alternate seeds so that
## where a ship starts does not decide the result. Run it in the background: a full run takes many
## minutes. It prints an estimate after the first battle and writes its progress as it goes.
##
##   Godot --headless --path . --script res://tools/balance_matrix.gd -- [options] </dev/null
##
## Options (after the `--`):
##   --seeds=N     battles per pairing (default 10)
##   --limit=S     game seconds before a battle is called undecided (default 240)
##   --scale=X     time scale (default 5; higher is faster but less accurate)
##   --cross       every Federation model against every Hegemony model, not just matching classes
##   --units       also squadron against squadron and battle group against battle group
##   --fleets      also fleet against fleet (slow)
##   --only=a,b    only pairings whose names contain one of these words (for example --only=cruiser)
##
## Output: user://balance/matrix.md (the table) and user://balance/progress.txt (one line per battle,
## and DONE at the end). The path is printed. A pairing is "even" when its win rate cannot be told
## from 50% with the seeds run; with few seeds only a big imbalance shows. The aim is 45 to 55%.

const FACTION_A := &"faction_1"
const FACTION_B := &"faction_2"
const DIR := "user://balance/"

var _seeds: int = 10
var _limit: float = 240.0
var _scale: float = 5.0
var _filter: Array[String] = []
var _cross: bool = false
var _units: bool = false
var _fleets: bool = false


func _init() -> void:
	_parse_args()
	var registry := ContentRegistry.new()
	var matches := _build_matches(registry)
	if matches.is_empty():
		print("Nothing to run (check --only).")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var total := matches.size() * _seeds
	print("%d pairings x %d seeds = %d battles (time scale %.0f, limit %.0f s). An estimate follows the first battle." % [matches.size(), _seeds, total, _scale, _limit])
	print("Progress: ", ProjectSettings.globalize_path(DIR + "progress.txt"))
	var progress := FileAccess.open(DIR + "progress.txt", FileAccess.WRITE)

	var harness := BattleHarness.new()
	harness.time_scale = _scale
	await harness.start(self)
	var rows: Array[Dictionary] = []
	var done := 0
	var started := Time.get_ticks_msec()
	for entry in matches:
		var row := {"name": entry["name"], "a_wins": 0, "b_wins": 0, "other": 0, "from_a": 0, "times": [], "left": []}
		for battle_seed in range(1, _seeds + 1):
			var federation_on_a := battle_seed % 2 == 1
			var result: Dictionary
			if federation_on_a:
				result = await harness.run(entry["a"], entry["b"], battle_seed, _limit)
			else:
				result = await harness.run(entry["b"], entry["a"], battle_seed, _limit)
			var winner: StringName = result["winner"]
			var first_side := &"a" if federation_on_a else &"b"
			if winner == &"draw" or winner == &"timeout":
				row["other"] += 1
			else:
				var first_won := winner == first_side
				row["a_wins" if first_won else "b_wins"] += 1
				if winner == &"a":
					row["from_a"] += 1  # (the side that started as A, whoever it was)
				row["times"].append(result["time"])
				var winning: Dictionary = result[str(winner)]
				row["left"].append(winning["rating_left"] / maxf(winning["rating_start"], 1.0))
			done += 1
			var elapsed := (Time.get_ticks_msec() - started) / 1000.0
			var remaining := elapsed / done * (total - done)
			var line := "battle %d of %d: %s, seed %d, winner %s after %.0f game s (%.0f s real so far, about %.0f s to go)" % [
					done, total, entry["name"], battle_seed, winner, result["time"], elapsed, remaining]
			progress.store_line(line)
			progress.flush()
			if done == 1:
				print("First battle took %.0f s real: about %.0f minutes for all of it." % [elapsed, elapsed * total / 60.0])
		rows.append(row)
		print(_row_text(row))
	harness.finish()

	var report := _report(rows, total, (Time.get_ticks_msec() - started) / 1000.0)
	var out := FileAccess.open(DIR + "matrix.md", FileAccess.WRITE)
	out.store_string(report)
	out.close()
	progress.store_line("DONE")
	progress.close()
	print("")
	print(report)
	print("Written to ", ProjectSettings.globalize_path(DIR + "matrix.md"))
	quit()


func _parse_args() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seeds="):
			_seeds = maxi(int(argument.substr(8)), 1)
		elif argument.begins_with("--limit="):
			_limit = float(argument.substr(8))
		elif argument.begins_with("--scale="):
			_scale = float(argument.substr(8))
		elif argument.begins_with("--only="):
			for word in argument.substr(7).split(","):
				_filter.append(word.strip_edges().to_lower())
		elif argument == "--cross":
			_cross = true
		elif argument == "--units":
			_units = true
		elif argument == "--fleets":
			_fleets = true


## The pairings to fight: [{"name", "a": the Federation's side, "b": the Hegemony's side}].
func _build_matches(registry: ContentRegistry) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var models := registry.all_ship_stats()
	var armed_a: Array[ShipStats] = []
	var armed_b: Array[ShipStats] = []
	for model in models:
		if model.faction != null and not model.default_loadout.is_empty():
			if model.faction.id == FACTION_A:
				armed_a.append(model)
			elif model.faction.id == FACTION_B:
				armed_b.append(model)
	if _cross:
		for a in armed_a:
			for b in armed_b:
				matches.append(_one_v_one("%s v %s" % [a.id, b.id], a, b))
	else:
		for pair in BalanceMath.matching_pairs(models, FACTION_A, FACTION_B):
			matches.append(_one_v_one("1v1 %s" % pair["class"], pair["a"], pair["b"]))
	for preset in BattlePresets.PRESETS:
		var name: String = preset["name"]
		if (_units and (name.begins_with("Squadrons:") or name.begins_with("Battle groups:"))) or (_fleets and name.begins_with("Capital fleets:")):
			matches.append({"name": name.get_slice(":", 0).to_lower() + (" (hand-picked)" if not name.begins_with("Capital") else ""), "a": preset["a"], "b": preset["b"]})
	var wanted: Array[Dictionary] = []
	for entry in matches:
		var keep := _filter.is_empty()
		for word in _filter:
			keep = keep or str(entry["name"]).to_lower().contains(word)
		if keep:
			wanted.append(entry)
	return wanted


func _one_v_one(name: String, a: ShipStats, b: ShipStats) -> Dictionary:
	return {"name": name, "a": {"faction": FACTION_A, "model": a.id, "count": 1}, "b": {"faction": FACTION_B, "model": b.id, "count": 1}}


func _row_text(row: Dictionary) -> String:
	var decided: int = row["a_wins"] + row["b_wins"]
	var rate := float(row["a_wins"]) / decided if decided > 0 else 0.5
	return "%-34s Federation %2d, Hegemony %2d, undecided %2d  (%3.0f%%)" % [row["name"], row["a_wins"], row["b_wins"], row["other"], rate * 100.0]


func _report(rows: Array[Dictionary], total: int, real_seconds: float) -> String:
	var lines: Array[String] = []
	lines.append("# Duel matrix: Federation against Hegemony")
	lines.append("")
	lines.append("%d battles, %d seeds a pairing, time scale %.0f, limit %.0f game s; %.0f minutes. Sides swapped on alternate seeds." % [total, _seeds, _scale, _limit, real_seconds / 60.0])
	lines.append("")
	lines.append("| Pairing | Federation | Hegemony | Undecided | Federation win rate | Won from side A | Median time to kill | Winner's strength left | Verdict |")
	lines.append("|---|---|---|---|---|---|---|---|---|")
	for row in rows:
		var decided: int = row["a_wins"] + row["b_wins"]
		var rate := float(row["a_wins"]) / decided if decided > 0 else 0.5
		var margin := 1.96 * sqrt(0.25 / decided) if decided > 0 else 1.0
		var verdict := "even (cannot tell from 50%%, +-%d%%)" % roundi(margin * 100.0)
		if absf(rate - 0.5) > margin:
			verdict = "FEDERATION AHEAD" if rate > 0.5 else "HEGEMONY AHEAD"
		if decided == 0:
			verdict = "no result"
		lines.append("| %s | %d | %d | %d | %.0f%% | %d of %d | %s | %s | %s |" % [row["name"], row["a_wins"], row["b_wins"], row["other"], rate * 100.0,
				row["from_a"], decided, _median_text(row["times"], "%.0f s"), _percent_text(_median(row["left"])), verdict])
	lines.append("")
	lines.append("\"Won from side A\" counts wins by whichever faction started on side A: far from half of the decided battles means where a ship starts, or who acts first, decides the result.")
	lines.append("")
	lines.append("Target: matching classes 45 to 55%. Planned counters (fighters against an unescorted cruiser) should show large swings, and only those.")
	return "\n".join(lines) + "\n"


func _median(values: Array) -> float:
	if values.is_empty():
		return NAN
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _median_text(values: Array, format: String) -> String:
	var value := _median(values)
	return "-" if is_nan(value) else format % value


func _percent_text(value: float) -> String:
	return "-" if is_nan(value) else "%.0f%%" % (value * 100.0)
