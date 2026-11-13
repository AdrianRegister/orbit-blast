extends SceneTree
## Tests how ships rank targets (TargetScorer, CombatDoctrine), using the real ship
## models and doctrines. Pure: no scenes are run.
##   Godot --headless --path . --script res://scripts/tests/target_scorer_test.gd </dev/null

const FAR := 100000.0

var _failures: int = 0
var _registry: ContentRegistry


func _init() -> void:
	_registry = ContentRegistry.new()
	_check(_registry.problems.is_empty(), "the content registry builds with no problems %s" % [_registry.problems])

	_test_doctrines()
	_test_effectiveness()
	_test_big_ships_pick_big_ships()
	_test_fighters_pick_fighters()
	_test_protecting()
	_test_distance_and_damage()
	_test_focus_and_overkill()
	_test_hysteresis()
	_test_bias_and_edges()

	print("TARGET SCORER TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------------- helpers

func _model(id: StringName) -> ShipStats:
	return _registry.ship_stats(id)


func _doctrine(id: StringName) -> CombatDoctrine:
	return _model(id).ship_class.get_doctrine()


## A ShooterInfo for a ship model with its default weapons.
func _shooter(id: StringName) -> ShooterInfo:
	var model := _model(id)
	var info := ShooterInfo.new()
	info.dps = CombatRating.damage_per_second(model.default_loadout)
	info.light_dps = CombatRating.damage_per_second(model.default_loadout.filter(
			func(weapon) -> bool: return weapon != null and weapon.mount_size < WeaponMount.Size.MEDIUM))
	for weapon: WeaponDefinition in model.default_loadout:
		if weapon != null:
			info.weapon_range = maxf(info.weapon_range, weapon.range)
	info.staying_power = CombatRating.staying_power(model)
	info.rating = CombatRating.of(model)
	info.nimble = model.ship_class.is_evasive()
	return info


## A TargetInfo for a ship model as seen by `shooter`, `distance` away, undamaged.
func _target(id: StringName, shooter: ShooterInfo, distance: float = 500.0) -> TargetInfo:
	var model := _model(id)
	var info := TargetInfo.new()
	info.ref = id
	info.distance = distance
	info.tier = model.ship_class.tier
	info.nimble = model.ship_class.is_evasive()
	info.rating = CombatRating.of(model)
	var weapons: Array = model.default_loadout
	if shooter.nimble:
		weapons = weapons.filter(func(weapon) -> bool: return weapon != null and weapon.mount_size < WeaponMount.Size.MEDIUM)
	info.threat_dps = CombatRating.damage_per_second(weapons)
	info.attackers_wanted = clampi(ceili(info.rating / shooter.rating), 1, 8)
	return info


func _score(shooter_id: StringName, target: TargetInfo, shooter: ShooterInfo = null) -> float:
	return TargetScorer.score(shooter if shooter != null else _shooter(shooter_id), _doctrine(shooter_id), target, FAR)


func _choose(shooter_id: StringName, candidates: Array[TargetInfo], current: Variant = null) -> Variant:
	return TargetScorer.choose(_shooter(shooter_id), _doctrine(shooter_id), candidates, FAR, current)


# ----------------------------------------------------------------------- tests

func _test_doctrines() -> void:
	var seen := {}
	for model in _registry.all_ship_stats():
		var doctrine := model.ship_class.get_doctrine()
		var armed := false
		for weapon in model.default_loadout:
			armed = armed or weapon != null
		if model.ship_class.is_a(_registry.ship_class(&"warship")):
			_check(doctrine != null, "%s (a warship) has a doctrine" % model.id)
		if doctrine != null:
			seen[doctrine.id] = doctrine
			_check(doctrine.validate().is_empty(), "the %s doctrine validates %s" % [doctrine.id, doctrine.validate()])
	_check(seen.size() == 5, "there are five doctrines in use (%d)" % seen.size())
	_check(_model(&"freighter").ship_class.get_doctrine() == null and _model(&"bulk_freighter").ship_class.get_doctrine() == null, "freighters have no doctrine")
	_check(_doctrine(&"federation_fighter") == _doctrine(&"hegemony_fighter"), "ships of one class share its doctrine, whatever their faction")
	_check(_doctrine(&"hegemony_gunboat") == _doctrine(&"federation_frigate"), "gunboats and frigates share one")
	var child := ShipClass.new()
	child.id = &"test_picket"
	child.display_name = "Picket"
	child.parent = _registry.ship_class(&"frigate")
	_check(child.get_doctrine() == _doctrine(&"federation_frigate"), "a class with no doctrine uses its parent's")

	var bad := CombatDoctrine.new()
	_check(not bad.validate().is_empty(), "a doctrine with no id or name is invalid")
	bad.id = &"x"
	bad.display_name = "X"
	bad.preferred_tier_min = 3
	bad.preferred_tier_max = 1
	_check(not bad.validate().is_empty(), "an inverted tier range is invalid")
	bad.preferred_tier_min = 0
	bad.weight_threat = -1.0
	_check(not bad.validate().is_empty(), "a negative weight is invalid")
	bad.weight_threat = 1.0
	bad.protect_bonus = 0.5
	_check(not bad.validate().is_empty(), "a protect bonus below 1 is invalid")
	bad.protect_bonus = 2.0
	_check(bad.validate().is_empty(), "...and a fixed doctrine is valid")
	_check(is_equal_approx(_doctrine(&"federation_cruiser").sensor_range(1000.0), 1000.0 * _doctrine(&"federation_cruiser").sensor_range_factor), "sensor range is a multiple of the weapon reach")
	_check(_doctrine(&"federation_cruiser").sensor_range(1000.0) > 1000.0, "a ship sees further than it can shoot")


func _test_effectiveness() -> void:
	var fighter := _shooter(&"federation_fighter")
	var cruiser := _shooter(&"federation_cruiser")
	var capital := _shooter(&"federation_capital_ship")
	var frigate := _shooter(&"federation_frigate")
	var nimble := _target(&"federation_fighter", cruiser)
	var sturdy := _target(&"federation_frigate", cruiser)
	_check(TargetScorer.effectiveness(fighter, nimble) == 1.0 and TargetScorer.effectiveness(fighter, sturdy) == 1.0, "a fighter, all light weapons, can hurt anything")
	_check(TargetScorer.effectiveness(cruiser, nimble) == 0.0 and TargetScorer.effectiveness(capital, nimble) == 0.0, "a cruiser and a capital ship, with no light weapons, cannot hurt a fighter")
	_check(TargetScorer.effectiveness(cruiser, sturdy) == 1.0, "...but can hurt a frigate")
	var partial := TargetScorer.effectiveness(frigate, nimble)
	_check(partial > 0.0 and partial < 1.0, "a frigate's light weapons can hurt a fighter, with part of its firepower (%.2f)" % partial)
	_check(TargetScorer.effectiveness(ShooterInfo.new(), sturdy) == 0.0, "an unarmed ship can hurt nothing")
	_check(_score(&"federation_cruiser", nimble) == TargetScorer.EXCLUDED, "so a cruiser never chooses a fighter")
	_check(_score(&"federation_cruiser", sturdy) > TargetScorer.EXCLUDED, "...but does choose a frigate")


func _test_big_ships_pick_big_ships() -> void:
	for shooter_id in [&"federation_cruiser", &"federation_capital_ship", &"hegemony_cruiser", &"hegemony_capital_ship"]:
		var shooter := _shooter(shooter_id)
		var candidates: Array[TargetInfo] = [
			_target(&"hegemony_fighter", shooter), _target(&"hegemony_heavy_fighter", shooter),
			_target(&"hegemony_frigate", shooter), _target(&"hegemony_cruiser", shooter), _target(&"hegemony_capital_ship", shooter)]
		for candidate in candidates:
			candidate.ref = candidate.tier  # (named by size, for the checks)
		var choice = TargetScorer.choose(shooter, _doctrine(shooter_id), candidates, FAR)
		_check(choice == 3 or choice == 4, "%s fires on a cruiser or a capital ship when they are in sight (chose tier %s)" % [shooter_id, choice])
		var ranked := TargetScorer.rank(shooter, _doctrine(shooter_id), candidates, FAR)
		var tiers: Array = ranked.map(func(entry: Dictionary): return entry["ref"])
		_check(not tiers.has(0), "%s never ranks a fighter (%s)" % [shooter_id, tiers])
	# With only a frigate and a cruiser in sight, a cruiser prefers the cruiser (a ship like itself).
	var shooter := _shooter(&"federation_cruiser")
	var frigate_target := _target(&"hegemony_frigate", shooter)
	var cruiser_target := _target(&"hegemony_cruiser", shooter)
	_check(_score(&"federation_cruiser", cruiser_target) > _score(&"federation_cruiser", frigate_target), "a cruiser rates an enemy cruiser above a frigate")
	var capital := _shooter(&"federation_capital_ship")
	_check(_score(&"federation_capital_ship", _target(&"hegemony_cruiser", capital), capital) > _score(&"federation_capital_ship", _target(&"hegemony_frigate", capital), capital),
			"a capital ship rates an enemy cruiser above a frigate")


func _test_fighters_pick_fighters() -> void:
	var shooter := _shooter(&"federation_fighter")
	var enemy_fighter := _target(&"hegemony_fighter", shooter)
	var enemy_cruiser := _target(&"hegemony_cruiser", shooter)
	_check(_score(&"federation_fighter", enemy_fighter) > _score(&"federation_fighter", enemy_cruiser), "a fighter rates an enemy fighter above an enemy cruiser, which cannot hurt it")
	_check(_score(&"federation_fighter", enemy_cruiser) > TargetScorer.EXCLUDED, "...but will still chew on the cruiser when that is all there is")
	var heavy := _shooter(&"federation_heavy_fighter")
	_check(_score(&"federation_heavy_fighter", _target(&"hegemony_fighter", heavy), heavy) > _score(&"federation_heavy_fighter", _target(&"hegemony_capital_ship", heavy), heavy), "a heavy fighter prefers fighters to a capital ship")
	var choice = _choose(&"federation_fighter", [enemy_cruiser, enemy_fighter])
	_check(choice == &"hegemony_fighter", "so given both, a fighter chooses the fighter (chose %s)" % [choice])


func _test_protecting() -> void:
	# The brief's example: enemy fighters attacking our cruiser should be hunted by our fighters.
	var shooter := _shooter(&"federation_fighter")
	var attacker := _target(&"hegemony_fighter", shooter, 900.0)
	var idle_cruiser := _target(&"hegemony_cruiser", shooter, 500.0)
	var idle_fighter := _target(&"hegemony_fighter", shooter, 500.0)
	idle_fighter.ref = &"idle"
	var plain := _score(&"federation_fighter", attacker)
	attacker.attacking_protected = true
	var protecting := _score(&"federation_fighter", attacker)
	_check(protecting > plain, "an enemy attacking a ship I protect scores higher (%.2f > %.2f)" % [protecting, plain])
	var choice = _choose(&"federation_fighter", [idle_cruiser, idle_fighter, attacker])
	_check(choice == &"hegemony_fighter" and TargetScorer.score(shooter, _doctrine(&"federation_fighter"), attacker, FAR) > TargetScorer.score(shooter, _doctrine(&"federation_fighter"), idle_fighter, FAR),
			"our fighters go for the enemy fighters attacking the cruiser, even though they are farther away than the others")
	var doctrine := _doctrine(&"federation_fighter")
	_check(is_equal_approx(TargetScorer.threat(shooter, doctrine, attacker), (1.0 - exp(-attacker.threat_dps * doctrine.threat_horizon / shooter.staying_power)) * doctrine.protect_bonus), "the threat is multiplied by the doctrine's protect bonus")
	_check(TargetScorer.threat(shooter, doctrine, _target(&"hegemony_cruiser", shooter)) == 0.0, "a cruiser is no threat to a nimble fighter")
	var threatened := _shooter(&"federation_frigate")
	_check(TargetScorer.threat(threatened, _doctrine(&"federation_frigate"), _target(&"hegemony_cruiser", threatened)) > 0.0, "...but it is to a frigate")


func _test_distance_and_damage() -> void:
	var shooter := _shooter(&"federation_fighter")
	var doctrine := _doctrine(&"federation_fighter")
	var near := _target(&"hegemony_fighter", shooter, shooter.weapon_range * 0.5)
	var edge := _target(&"hegemony_fighter", shooter, shooter.weapon_range)
	var far := _target(&"hegemony_fighter", shooter, shooter.weapon_range * 3.0)
	_check(TargetScorer.closeness(shooter, near, 3000.0) == 1.0 and TargetScorer.closeness(shooter, edge, 3000.0) == 1.0, "a target inside weapon reach is fully close")
	_check(TargetScorer.closeness(shooter, far, 3000.0) < 1.0 and TargetScorer.closeness(shooter, far, 3000.0) > 0.0, "...and one beyond it is less so")
	_check(TargetScorer.score(shooter, doctrine, near, 3000.0) > TargetScorer.score(shooter, doctrine, far, 3000.0), "a nearer target scores higher")
	var gone := _target(&"hegemony_fighter", shooter, 3001.0)
	_check(TargetScorer.score(shooter, doctrine, gone, 3000.0) == TargetScorer.EXCLUDED, "a target beyond sight is never chosen")
	_check(TargetScorer.closeness(shooter, far, shooter.weapon_range) == 0.0, "(a sight no longer than the weapon leaves nothing beyond it)")
	var healthy := _target(&"hegemony_fighter", shooter)
	var hurt := _target(&"hegemony_fighter", shooter)
	hurt.hull_fraction = 0.2
	_check(TargetScorer.score(shooter, doctrine, hurt, FAR) > TargetScorer.score(shooter, doctrine, healthy, FAR), "a damaged target scores higher, to finish it off")


func _test_focus_and_overkill() -> void:
	var shooter := _shooter(&"federation_fighter")
	var doctrine := _doctrine(&"federation_fighter")
	var a := _target(&"hegemony_fighter", shooter)
	var b := _target(&"hegemony_fighter", shooter)
	b.ref = &"other"
	var base := TargetScorer.score(shooter, doctrine, a, FAR)
	a.is_focus = true
	_check(is_equal_approx(TargetScorer.score(shooter, doctrine, a, FAR), base + doctrine.weight_focus), "the target a commander named gets the focus bonus")
	_check(TargetScorer.choose(shooter, doctrine, [a, b] as Array[TargetInfo], FAR) == a.ref, "...and is chosen over an equal one")
	a.is_focus = false
	_check(a.attackers_wanted == 1, "one fighter is enough against a fighter")
	a.targeted_by = 1
	_check(is_equal_approx(TargetScorer.score(shooter, doctrine, a, FAR), base - doctrine.weight_overkill), "a target that already has enough ships on it is marked down")
	_check(TargetScorer.choose(shooter, doctrine, [a, b] as Array[TargetInfo], FAR) == b.ref, "...so the next ship picks another")
	var big := _target(&"hegemony_cruiser", shooter)
	_check(big.attackers_wanted > 1, "it takes several fighters to deal with a cruiser (%d)" % big.attackers_wanted)
	big.targeted_by = big.attackers_wanted - 1
	var before := TargetScorer.score(shooter, doctrine, big, FAR)
	big.targeted_by = 0
	_check(is_equal_approx(before, TargetScorer.score(shooter, doctrine, big, FAR)), "...and a cruiser with fewer than that on it is not marked down")


func _test_hysteresis() -> void:
	var shooter := _shooter(&"federation_fighter")
	var doctrine := _doctrine(&"federation_fighter")
	var current := _target(&"hegemony_fighter", shooter)
	current.ref = &"current"
	var rival := _target(&"hegemony_fighter", shooter)
	rival.ref = &"rival"
	var candidates: Array[TargetInfo] = [current, rival]
	rival.bias = 0.1
	_check(TargetScorer.choose(shooter, doctrine, candidates, FAR, &"current") == &"current", "a ship keeps its target when another is only a little better")
	_check(TargetScorer.choose(shooter, doctrine, candidates, FAR) == &"rival", "...while a ship with no target takes the best")
	rival.bias = 5.0
	_check(TargetScorer.choose(shooter, doctrine, candidates, FAR, &"current") == &"rival", "...and changes when another is much better")
	_check(TargetScorer.choose(shooter, doctrine, candidates, FAR, &"gone") == &"rival", "a target that is no longer a candidate is replaced by the best")
	var hold := CombatDoctrine.new()
	hold.id = &"stubborn"
	hold.display_name = "Stubborn"
	hold.hysteresis = 0.0
	rival.bias = 0.1
	_check(TargetScorer.choose(shooter, hold, candidates, FAR, &"current") == &"rival", "with no hysteresis even a small edge changes the target")


func _test_bias_and_edges() -> void:
	var shooter := _shooter(&"federation_fighter")
	var doctrine := _doctrine(&"federation_fighter")
	var target := _target(&"hegemony_fighter", shooter)
	var base := TargetScorer.score(shooter, doctrine, target, FAR)
	target.bias = 2.5
	_check(is_equal_approx(TargetScorer.score(shooter, doctrine, target, FAR), base + 2.5), "a profile's bias is added to the score as it stands")
	var none: Array[TargetInfo] = []
	_check(TargetScorer.choose(shooter, doctrine, none, FAR) == null, "with no candidates there is no target")
	_check(TargetScorer.rank(shooter, doctrine, none, FAR).is_empty(), "...and no ranking")
	var unreachable := _target(&"hegemony_fighter", shooter, FAR * 2.0)
	_check(TargetScorer.choose(shooter, doctrine, [unreachable] as Array[TargetInfo], FAR) == null, "candidates all out of sight give no target")
	_check(TargetScorer.affinity(doctrine, 0) == 1.0 and TargetScorer.affinity(doctrine, 1) == 1.0, "a fighter's own sizes have full affinity")
	_check(TargetScorer.affinity(doctrine, 2) < 1.0 and TargetScorer.affinity(doctrine, 4) < TargetScorer.affinity(doctrine, 2), "...and it falls off as ships get bigger")
	_check(TargetScorer.affinity(doctrine, 10) == 0.0, "...to nothing")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
