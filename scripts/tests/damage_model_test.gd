extends SceneTree
## Tests the layered damage rules (DamageModel) on plain data, no scene needed.
## Run: Godot --headless --path . --script res://scripts/tests/damage_model_test.gd </dev/null

var _failures := 0


func _init() -> void:
	var rules := DamageRules.new()
	rules.armour_damage_reduction = 0.25
	rules.armour_bleed_through = 0.0

	_test_shields_absorb_first(rules)
	_test_overflow_passes_on(rules)
	_test_armour_reduction(rules)
	_test_armour_overflow_to_hull(rules)
	_test_multipliers(rules)
	_test_bypass(rules)
	_test_bleed_through()
	_test_destruction(rules)
	_test_dead_ship_ignores_hits(rules)
	_test_shipped_rules_load()

	print("DAMAGE MODEL TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _hit(damage: float, shield_mult := 1.0, armour_mult := 1.0, bypass := 0.0) -> Hit:
	var hit := Hit.new()
	hit.damage = damage
	hit.shield_multiplier = shield_mult
	hit.armour_multiplier = armour_mult
	hit.shield_bypass = bypass
	return hit


func _test_shields_absorb_first(rules: DamageRules) -> void:
	var state := DefenceState.full(50.0, 40.0, 100.0)
	var result := DamageModel.resolve(state, _hit(20.0), rules)
	_check(is_equal_approx(state.shield, 30.0), "shields take the whole hit while they last")
	_check(is_equal_approx(state.armour, 40.0) and is_equal_approx(state.hull, 100.0), "armour and hull untouched")
	_check(is_equal_approx(result.shield_damage, 20.0) and not result.penetrated(), "result reports shield damage only")
	_check(not result.destroyed, "ship survives")


func _test_overflow_passes_on(rules: DamageRules) -> void:
	var state := DefenceState.full(10.0, 40.0, 100.0)
	var result := DamageModel.resolve(state, _hit(30.0), rules)
	_check(is_equal_approx(state.shield, 0.0), "shield is stripped")
	# 20 raw damage overflows; armour reduction 25% -> 15 armour damage.
	_check(is_equal_approx(result.armour_damage, 15.0), "overflow hits armour, reduced by the armour rule")
	_check(is_equal_approx(state.armour, 25.0), "armour pool drops by that amount")
	_check(is_equal_approx(state.hull, 100.0), "hull is safe while armour holds")


func _test_armour_reduction(rules: DamageRules) -> void:
	var state := DefenceState.full(0.0, 100.0, 100.0)
	DamageModel.resolve(state, _hit(40.0), rules)
	_check(is_equal_approx(state.armour, 70.0), "armour takes 40 * 0.75 = 30")


func _test_armour_overflow_to_hull(rules: DamageRules) -> void:
	var state := DefenceState.full(0.0, 30.0, 100.0)
	# 100 raw: armour absorbs 30 of the 75 effective, leaving 45 effective = 60 raw to the hull.
	var result := DamageModel.resolve(state, _hit(100.0), rules)
	_check(is_equal_approx(state.armour, 0.0), "armour is gone")
	_check(is_equal_approx(result.hull_damage, 60.0), "the rest is converted back and reaches the hull")
	_check(is_equal_approx(state.hull, 40.0), "hull drops")


func _test_multipliers(rules: DamageRules) -> void:
	var state := DefenceState.full(100.0, 100.0, 100.0)
	DamageModel.resolve(state, _hit(20.0, 2.0), rules)
	_check(is_equal_approx(state.shield, 60.0), "a 2x shield multiplier doubles the damage to shields")

	var weak := DefenceState.full(0.0, 100.0, 100.0)
	DamageModel.resolve(weak, _hit(40.0, 1.0, 0.5), rules)
	_check(is_equal_approx(weak.armour, 85.0), "a 0.5 armour multiplier halves armour damage (40*0.75*0.5)")

	# Overflow past shields keeps its raw size even with a multiplier.
	var thin := DefenceState.full(10.0, 0.0, 100.0)
	var result := DamageModel.resolve(thin, _hit(20.0, 2.0), rules)
	# effective 40, shield absorbs 10, 30 overflow / 2 = 15 raw to hull.
	_check(is_equal_approx(result.hull_damage, 15.0), "overflow past shields is converted back to raw damage")


func _test_bypass(rules: DamageRules) -> void:
	var state := DefenceState.full(100.0, 0.0, 100.0)
	var result := DamageModel.resolve(state, _hit(50.0, 1.0, 1.0, 0.2), rules)
	_check(is_equal_approx(result.hull_damage, 10.0), "20% bypass goes straight past shields")
	_check(is_equal_approx(state.shield, 60.0), "the other 80% hits the shields")


func _test_bleed_through() -> void:
	var rules := DamageRules.new()
	rules.armour_damage_reduction = 0.0
	rules.armour_bleed_through = 0.5
	var state := DefenceState.full(0.0, 100.0, 100.0)
	DamageModel.resolve(state, _hit(40.0), rules)
	_check(is_equal_approx(state.armour, 60.0) and is_equal_approx(state.hull, 80.0), "bleed-through hurts the hull while armour holds")


func _test_destruction(rules: DamageRules) -> void:
	var state := DefenceState.full(0.0, 0.0, 30.0)
	var result := DamageModel.resolve(state, _hit(25.0), rules)
	_check(not result.destroyed and is_equal_approx(state.hull, 5.0), "hull above zero is not destroyed")
	result = DamageModel.resolve(state, _hit(25.0), rules)
	_check(result.destroyed and state.hull <= 0.0, "hull at zero destroys the ship")
	_check(is_equal_approx(result.hull_damage, 5.0), "only the remaining hull counts as damage dealt")


func _test_dead_ship_ignores_hits(rules: DamageRules) -> void:
	var state := DefenceState.full(0.0, 0.0, 10.0)
	DamageModel.resolve(state, _hit(50.0), rules)
	var result := DamageModel.resolve(state, _hit(50.0), rules)
	_check(result.destroyed and is_equal_approx(result.total(), 0.0), "a destroyed ship takes no further damage")


func _test_shipped_rules_load() -> void:
	var rules: DamageRules = load("res://resources/combat/damage_rules.tres")
	_check(rules != null, "damage_rules.tres loads")
	if rules != null:
		_check(rules.validate().is_empty(), "damage_rules.tres is valid")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
