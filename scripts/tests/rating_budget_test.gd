extends SceneTree
## Enforces the rating budget (doctrine_balancing.md, tool 1): the ships of the same class of two
## factions have a combat rating within 5% of each other, so that a doctrine trades inside a budget
## (more armour for fewer guns) instead of just adding up. Matching classes are also checked for how
## fast each would destroy the other in the best case, which the rating alone does not show. Run with:
##   Godot --headless --path . --script res://scripts/tests/rating_budget_test.gd </dev/null

const BUDGET := 0.05
## The edge between two matching ships (BalanceMath.edge) must lie within these.
const EDGE_LOW := 0.8
const EDGE_HIGH := 1.25

var _failures: int = 0


func _init() -> void:
	var registry := ContentRegistry.new()
	var factions := registry.factions().filter(func(f: Faction) -> bool: return not f.hostile_to_all)
	var checked := 0
	for first_index in factions.size():
		for second_index in range(first_index + 1, factions.size()):
			var pairs := BalanceMath.matching_pairs(registry.all_ship_stats(), factions[first_index].id, factions[second_index].id)
			for pair in pairs:
				var a: ShipStats = pair["a"]
				var b: ShipStats = pair["b"]
				var gap := BalanceMath.rating_gap(a, b)
				var edge := BalanceMath.edge(a, b)
				_check(gap <= BUDGET, "%s and %s are within %d%% of each other in rating (%.1f%%)" % [a.id, b.id, int(BUDGET * 100.0), gap * 100.0])
				_check(edge >= EDGE_LOW and edge <= EDGE_HIGH, "...and neither would destroy the other more than %.2f times faster (edge %.2f)" % [EDGE_HIGH, edge])
				checked += 1
	_check(checked >= 5, "(setup) the budget was checked for every matching class (%d pairs)" % checked)

	print("RATING BUDGET TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
