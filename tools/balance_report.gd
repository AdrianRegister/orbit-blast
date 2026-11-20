extends SceneTree
## The analytic balance report (doctrine_balancing.md, tool 2): pure maths on the static ship data,
## run in a second. It prints, for every armed ship model, its combat rating, price and rating per
## 1,000 credits; for every pair of models how long the one would take to destroy the other with
## every shot landing (a best case: see BalanceMath); and for the matching classes of two factions
## the rating gap and how much quicker one would win. It catches a number that is out of line before
## anyone flies it. Run with:
##   Godot --headless --path . --script res://tools/balance_report.gd </dev/null
## Add `-- --out` to also write it to user://balance/report.txt.

const FACTION_A := &"faction_1"
const FACTION_B := &"faction_2"


func _init() -> void:
	var registry := ContentRegistry.new()
	var models: Array[ShipStats] = []
	for model in registry.all_ship_stats():
		if BalanceMath.landing_dps(model, model) > 0.0 or (model.ship_class != null and model.ship_class.is_evasive()) or not model.default_loadout.is_empty():
			models.append(model)
	var lines: Array[String] = []
	lines.append("BALANCE REPORT (static data: every shot lands, nothing dodges, no energy limit)")
	lines.append("")
	lines.append("Ships: combat rating, price and rating per 1,000 credits")
	lines.append("%-26s %-14s %9s %10s %12s" % ["model", "class", "rating", "price", "rating/1k cr"])
	for model in models:
		var rating := CombatRating.of(model)
		lines.append("%-26s %-14s %9.0f %10d %12s" % [model.id, model.ship_class.id if model.ship_class != null else "-", rating, model.price,
				"%.2f" % (rating / (model.price / 1000.0)) if model.price > 0 else "-"])
	lines.append("")
	lines.append("Seconds for the ship in the row to destroy the ship in the column (- = it cannot hurt it)")
	var header := "%-26s" % ""
	for defender in models:
		header += " %7s" % str(defender.id).left(7)
	lines.append(header)
	for attacker in models:
		var row := "%-26s" % attacker.id
		for defender in models:
			var seconds := BalanceMath.time_to_kill(attacker, defender)
			row += " %7s" % ("-" if is_inf(seconds) else "%.0f" % seconds)
		lines.append(row)
	lines.append("")
	lines.append("Matching classes, %s against %s (target: rating within 5%%, edge between 0.8 and 1.25)" % [FACTION_A, FACTION_B])
	lines.append("%-14s %-24s %-24s %8s %9s %9s %6s  %s" % ["class", "a", "b", "gap", "a kills b", "b kills a", "edge", "verdict"])
	for pair in BalanceMath.matching_pairs(models, FACTION_A, FACTION_B):
		var a: ShipStats = pair["a"]
		var b: ShipStats = pair["b"]
		var gap := BalanceMath.rating_gap(a, b)
		var edge := BalanceMath.edge(a, b)
		var verdict := "ok" if gap <= 0.05 and edge >= 0.8 and edge <= 1.25 else "OUT OF LINE"
		lines.append("%-14s %-24s %-24s %7.1f%% %8ss %8ss %6.2f  %s" % [pair["class"], a.id, b.id, gap * 100.0,
				_seconds(BalanceMath.time_to_kill(a, b)), _seconds(BalanceMath.time_to_kill(b, a)), edge, verdict])
	for line in lines:
		print(line)
	if "--out" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://balance"))
		var file := FileAccess.open("user://balance/report.txt", FileAccess.WRITE)
		file.store_string("\n".join(lines) + "\n")
		print("Written to ", ProjectSettings.globalize_path("user://balance/report.txt"))
	quit()


func _seconds(value: float) -> String:
	return "-" if is_inf(value) else "%.0f" % value
