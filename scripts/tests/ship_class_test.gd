extends SceneTree
## Tests ship classes (the ShipClass resources and the class of every ship model)
## and the combat rating.
##   Godot --headless --path . --script res://scripts/tests/ship_class_test.gd </dev/null

var _failures: int = 0


func _init() -> void:
	var registry := ContentRegistry.new()
	_check(registry.problems.is_empty(), "the content registry builds with no problems %s" % [registry.problems])

	_test_class_files(registry)
	_test_hierarchy(registry)
	_test_ship_models(registry)
	_test_validation()
	_test_rating(registry)

	print("SHIP CLASS TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_class_files(registry: ContentRegistry) -> void:
	var classes := registry.ship_classes()
	_check(classes.size() == 14, "fourteen ship classes exist (%d)" % classes.size())
	var ids := {}
	for ship_class in classes:
		_check(ship_class.validate().is_empty(), "%s validates %s" % [ship_class.id, ship_class.validate()])
		_check(not ids.has(ship_class.id), "%s has a unique id" % ship_class.id)
		ids[ship_class.id] = true
	for id in [&"warship", &"cargo_ship", &"shuttle", &"freighter", &"bulk_freighter", &"interceptor", &"fighter",
			&"heavy_fighter", &"gunboat", &"corvette", &"light_frigate", &"frigate", &"cruiser", &"capital_ship"]:
		_check(registry.ship_class(id) != null, "the class '%s' can be looked up" % id)
	# Smallest tier first, ties by id.
	var sorted_ok := true
	for index in range(1, classes.size()):
		if classes[index - 1].tier > classes[index].tier:
			sorted_ok = false
	_check(sorted_ok, "ship_classes() lists the smallest tier first")


func _test_hierarchy(registry: ContentRegistry) -> void:
	var warship := registry.ship_class(&"warship")
	var cargo_ship := registry.ship_class(&"cargo_ship")
	for id in [&"interceptor", &"fighter", &"heavy_fighter", &"gunboat", &"corvette", &"light_frigate", &"frigate", &"cruiser", &"capital_ship"]:
		_check(registry.ship_class(id).is_a(warship), "%s is a warship" % id)
		_check(not registry.ship_class(id).is_a(cargo_ship), "%s is not a cargo ship" % id)
	for id in [&"freighter", &"bulk_freighter"]:
		_check(registry.ship_class(id).is_a(cargo_ship) and not registry.ship_class(id).is_a(warship), "%s is a cargo ship, not a warship" % id)
		_check(registry.ship_class(id).carries_cargo(), "%s carries cargo" % id)
	_check(not registry.ship_class(&"shuttle").is_a(warship) and not registry.ship_class(&"shuttle").is_a(cargo_ship), "a shuttle is neither")
	var frigate := registry.ship_class(&"frigate")
	_check(frigate.is_a(frigate), "a class is itself")
	_check(not frigate.is_a(null), "nothing is a null class")
	_check(not warship.is_a(frigate), "a parent is not a kind of its child")
	_check(not registry.ship_class(&"fighter").carries_cargo(), "a fighter carries no cargo")
	_check(registry.ship_class(&"capital_ship").is_capital() and not registry.ship_class(&"cruiser").is_capital(), "only the capital ship is a capital class")

	# A class that does not exist yet could be added with no code: a made-up one behaves.
	var corvette_line := ShipClass.new()
	corvette_line.id = &"test_picket"
	corvette_line.display_name = "Picket"
	corvette_line.parent = registry.ship_class(&"corvette")
	_check(corvette_line.is_a(warship) and corvette_line.is_a(registry.ship_class(&"corvette")), "a new subclass is a corvette and a warship through its parents")


func _test_ship_models(registry: ContentRegistry) -> void:
	var expected := {
		&"shuttle": &"shuttle", &"freighter": &"freighter", &"bulk_freighter": &"bulk_freighter",
		&"interceptor": &"interceptor", &"light_frigate": &"light_frigate",
		&"federation_fighter": &"fighter", &"federation_heavy_fighter": &"heavy_fighter",
		&"federation_frigate": &"frigate", &"federation_cruiser": &"cruiser", &"federation_capital_ship": &"capital_ship",
		&"hegemony_fighter": &"fighter", &"hegemony_heavy_fighter": &"heavy_fighter", &"hegemony_gunboat": &"gunboat",
		&"hegemony_frigate": &"frigate", &"hegemony_cruiser": &"cruiser", &"hegemony_capital_ship": &"capital_ship",
	}
	var models := registry.all_ship_stats()
	_check(models.size() == expected.size(), "every ship model is covered (%d)" % models.size())
	for model in models:
		_check(model.ship_class != null, "%s has a class" % model.id)
		_check(model.validate().is_empty(), "%s validates %s" % [model.id, model.validate()])
		if expected.has(model.id) and model.ship_class != null:
			_check(model.ship_class.id == expected[model.id], "%s is a %s" % [model.id, expected[model.id]])

	# Sizes: light < medium < large < heavy < capital, across the roster.
	var tier := func(id: StringName) -> int: return registry.ship_stats(id).ship_class.tier
	_check(tier.call(&"interceptor") == tier.call(&"federation_fighter"), "interceptors and fighters are both light")
	_check(tier.call(&"federation_fighter") < tier.call(&"federation_heavy_fighter"), "a heavy fighter outranks a fighter")
	_check(tier.call(&"federation_heavy_fighter") < tier.call(&"federation_frigate"), "a frigate outranks a heavy fighter")
	_check(tier.call(&"federation_frigate") < tier.call(&"federation_cruiser"), "a cruiser outranks a frigate")
	_check(tier.call(&"federation_cruiser") < tier.call(&"federation_capital_ship"), "a capital ship outranks a cruiser")
	_check(tier.call(&"freighter") < tier.call(&"bulk_freighter"), "a bulk freighter outranks a freighter")

	# The ship classes the formation rules rely on exist in the roster.
	var classes_in_use := {}
	for model in models:
		classes_in_use[model.ship_class.id] = true
	for id in [&"fighter", &"heavy_fighter", &"frigate", &"cruiser", &"capital_ship", &"interceptor", &"light_frigate", &"freighter"]:
		_check(classes_in_use.has(id), "a ship model of class '%s' exists" % id)
	_check(classes_in_use.has(&"gunboat") and not classes_in_use.has(&"corvette"), "the Hegemony has a gunboat; the corvette is a class with no models yet")


func _test_validation() -> void:
	var nameless := ShipClass.new()
	_check(not nameless.validate().is_empty(), "a class with no id or name is invalid")
	var looped := ShipClass.new()
	looped.id = &"looped"
	looped.display_name = "Looped"
	var other := ShipClass.new()
	other.id = &"other"
	other.display_name = "Other"
	looped.parent = other
	other.parent = looped
	_check(not looped.validate().is_empty(), "a parent chain that loops is invalid")
	_check(not looped.is_a(ShipClass.new()), "is_a stops on a loop instead of hanging")
	var classless := ShipStats.new()
	classless.id = &"x"
	classless.display_name = "X"
	_check("ship_class is not set" in classless.validate(), "a ship model without a class is invalid")


func _test_rating(registry: ContentRegistry) -> void:
	var rating := func(id: StringName) -> float: return CombatRating.of(registry.ship_stats(id))

	for model in registry.all_ship_stats():
		_check(CombatRating.of(model) > 0.0, "%s has a positive rating (%.0f)" % [model.id, CombatRating.of(model)])

	# The Federation line is strictly ordered by strength.
	var order := [&"federation_fighter", &"federation_heavy_fighter", &"federation_frigate", &"federation_cruiser", &"federation_capital_ship"]
	for index in range(1, order.size()):
		_check(rating.call(order[index]) > rating.call(order[index - 1]), "%s rates above %s (%.0f > %.0f)" % [order[index], order[index - 1], rating.call(order[index]), rating.call(order[index - 1])])
	# The Hegemony line is ordered the same way, with the gunboat between the heavy fighter and the frigate,
	# and each ship rates within 5% of its Federation counterpart (the rating budget, see doctrine_balancing.md).
	var hegemony := [&"hegemony_fighter", &"hegemony_heavy_fighter", &"hegemony_gunboat", &"hegemony_frigate", &"hegemony_cruiser", &"hegemony_capital_ship"]
	for index in range(1, hegemony.size()):
		_check(rating.call(hegemony[index]) > rating.call(hegemony[index - 1]), "%s rates above %s (%.0f > %.0f)" % [hegemony[index], hegemony[index - 1], rating.call(hegemony[index]), rating.call(hegemony[index - 1])])
	for kind in ["fighter", "heavy_fighter", "frigate", "cruiser", "capital_ship"]:
		var ours: float = rating.call(StringName("federation_" + kind))
		var theirs: float = rating.call(StringName("hegemony_" + kind))
		_check(absf(theirs - ours) <= ours * 0.05, "the Hegemony %s rates within 5%% of the Federation's (%.0f and %.0f)" % [kind, theirs, ours])
	_check(rating.call(&"bulk_freighter") > rating.call(&"freighter"), "a bulk freighter rates above a freighter by its staying power")
	_check(rating.call(&"federation_fighter") > rating.call(&"freighter"), "an armed fighter outranks an unarmed freighter")

	# Firepower and staying power both count.
	var frigate := registry.ship_stats(&"federation_frigate")
	var armed := CombatRating.of(frigate)
	var disarmed := CombatRating.of(frigate, [])
	_check(disarmed < armed and disarmed > 0.0, "the same ship with no weapons rates lower, but not zero (%.0f < %.0f)" % [disarmed, armed])
	var extra: Array = frigate.default_loadout.duplicate()
	extra.append(load("res://resources/weapons/heavy_blaster.tres"))
	_check(CombatRating.of(frigate, extra) > armed, "an extra weapon raises the rating")
	_check(CombatRating.of(frigate, [null, null, null]) == disarmed, "empty mounts count as no weapons")
	var tough: ShipStats = frigate.duplicate()
	tough.hull *= 2.0
	_check(CombatRating.of(tough) > armed, "more hull raises the rating")
	var strongest: ShipStats = null
	for model in registry.all_ship_stats():
		if strongest == null or CombatRating.of(model) > CombatRating.of(strongest):
			strongest = model
	_check(strongest.id == &"federation_capital_ship", "the capital ship is the strongest ship in the roster")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
