extends SceneTree
## Tests the balancing maths (tools/balance_math.gd) on the real ship data, with no scene: which
## weapons can hurt which ship, the time to kill, the edge between two ships, and the matching of
## classes across factions. Run with:
##   Godot --headless --path . --script res://scripts/tests/balance_math_test.gd </dev/null

var _failures: int = 0
var _registry: ContentRegistry


func _init() -> void:
	_registry = ContentRegistry.new()
	var fighter := _registry.ship_stats(&"federation_fighter")
	var heavy := _registry.ship_stats(&"federation_heavy_fighter")
	var cruiser := _registry.ship_stats(&"federation_cruiser")
	var capital := _registry.ship_stats(&"federation_capital_ship")
	var freighter := _registry.ship_stats(&"freighter")

	# --- Which weapons can hurt what.
	var cruiser_vs_fighter := BalanceMath.weapons_that_hit(cruiser, fighter)
	_check(cruiser_vs_fighter.is_empty() and is_inf(BalanceMath.time_to_kill(cruiser, fighter)), "a cruiser's medium and heavy guns pass through a fighter: it cannot hurt it")
	var cruiser_vs_cruiser := BalanceMath.weapons_that_hit(cruiser, cruiser)
	_check(not cruiser_vs_cruiser.is_empty() and not cruiser_vs_cruiser.any(func(w: WeaponDefinition) -> bool: return w.point_defence), "against a ship that is not nimble every main gun counts, never point defence")
	_check(BalanceMath.weapons_that_hit(heavy, fighter).size() == 1 and BalanceMath.weapons_that_hit(heavy, cruiser).size() == 2, "a heavy fighter hurts a fighter with its light blaster only, a cruiser with both guns")
	_check(is_inf(BalanceMath.time_to_kill(freighter, cruiser)) and BalanceMath.landing_dps(freighter, cruiser) == 0.0, "an unarmed ship cannot hurt anything")
	_check(is_equal_approx(BalanceMath.landing_dps(fighter, cruiser), fighter.default_loadout[0].damage / fighter.default_loadout[0].fire_interval), "a fighter's landing damage per second is its light blaster's")

	# --- Time to kill.
	var seconds := BalanceMath.time_to_kill(fighter, fighter)
	_check(seconds > 0.0 and seconds < 60.0 and not is_inf(seconds), "two fighters destroy each other in a plausible time (%.1f s)" % seconds)
	_check(BalanceMath.time_to_kill(fighter, cruiser) > BalanceMath.time_to_kill(fighter, fighter), "a cruiser takes longer to destroy than a fighter")
	_check(BalanceMath.time_to_kill(capital, cruiser) < BalanceMath.time_to_kill(cruiser, capital), "a capital ship destroys a cruiser faster than the cruiser could destroy it")
	var no_shield_state := DefenceState.full(0.0, 0.0, 100.0)
	var hit := Hit.from_weapon(fighter.default_loadout[0])
	DamageModel.resolve(no_shield_state, hit, DamageRules.shared())
	_check(no_shield_state.hull < 100.0, "(setup) the damage model is the real one")
	# A defender with no shield, armour or nothing else but hull is destroyed by the number of shots the hull allows.
	var hull_only := fighter.duplicate() as ShipStats
	hull_only.shield_capacity = 0.0
	hull_only.armour = 0.0
	hull_only.hull = fighter.default_loadout[0].damage * 3.0 - 0.5
	var shots := fighter.default_loadout[0]
	_check(is_equal_approx(BalanceMath.time_to_kill(fighter, hull_only), 2.0 * shots.fire_interval), "a hull of three shots less a bit dies at the third shot (after two intervals)")

	# --- Edge.
	_check(is_equal_approx(BalanceMath.edge(fighter, fighter), 1.0), "two identical ships are even")
	_check(BalanceMath.edge(capital, cruiser) > 1.0 and BalanceMath.edge(cruiser, capital) < 1.0, "the edge says who is ahead")
	_check(is_inf(BalanceMath.edge(cruiser, fighter)) == false and BalanceMath.edge(cruiser, fighter) == 0.0, "a ship that cannot hurt the other, and is hurt by it, has no edge at all")
	_check(BalanceMath.edge(freighter, freighter) == 1.0, "two ships that cannot hurt each other are even")

	# --- Matching classes.
	var pairs := BalanceMath.matching_pairs(_registry.all_ship_stats(), &"faction_1", &"faction_2")
	var classes: Array = pairs.map(func(p: Dictionary) -> StringName: return p["class"])
	_check(classes.has(&"fighter") and classes.has(&"cruiser") and classes.has(&"capital_ship") and not classes.has(&"gunboat"), "the matching classes are the ones both factions have (no gunboat: the Federation has none): %s" % [classes])
	_check(classes.find(&"fighter") < classes.find(&"cruiser") and classes.find(&"cruiser") < classes.find(&"capital_ship"), "...smallest first")
	for pair in pairs:
		_check(pair["a"].faction.id == &"faction_1" and pair["b"].faction.id == &"faction_2" and pair["a"].ship_class == pair["b"].ship_class, "the %s pair is one ship of each faction, of one class" % pair["class"])

	print("BALANCE MATH TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
