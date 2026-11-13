extends SceneTree
## Tests the composition rules: the four recipes, FleetComposer (ratios, limits,
## civilian convoys, missing classes, factions with no ships) and FormationPlan.
## Pure: no scenes are run.
##   Godot --headless --path . --script res://scripts/tests/fleet_composer_test.gd </dev/null

const FEDERATION := &"faction_1"
const HEGEMONY := &"faction_2"
## A faction id no ship belongs to.
const NO_SHIPS_FACTION := &"faction_without_ships"
const SEEDS := 400

var _failures: int = 0
var _registry: ContentRegistry
var _types: Array[ShipType] = []


func _init() -> void:
	_registry = ContentRegistry.new()
	_check(_registry.problems.is_empty(), "the content registry builds with no problems %s" % [_registry.problems])
	_types = FleetComposer.all_ship_types()
	_check(_types.size() >= 10, "the composer finds the ship types (%d)" % _types.size())

	_test_recipe_files()
	_test_allocate()
	_test_squadron()
	_test_battle_group()
	_test_fleet()
	_test_convoy()
	_test_missing_classes()
	_test_new_class_needs_no_code()
	_test_hegemony()
	_test_determinism()
	_test_validation()

	print("FLEET COMPOSER TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# ---------------------------------------------------------------- helpers

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _compose(recipe_id: StringName, seed_value: int, types: Array[ShipType] = []) -> FormationPlan:
	return FleetComposer.compose(_registry.formation_recipe(recipe_id), FEDERATION,
			types if not types.is_empty() else _types, _rng(seed_value))


func _count_class(plan: FormationPlan, id: StringName) -> int:
	return plan.count_of(_registry.ship_class(id))


func _without(ids: Array) -> Array[ShipType]:
	var result: Array[ShipType] = []
	for type in _types:
		if not ids.has(type.stats.ship_class.id):
			result.append(type)
	return result


# ------------------------------------------------------------------ tests

func _test_recipe_files() -> void:
	var recipes := _registry.formation_recipes()
	_check(recipes.size() == 4, "four recipes exist (%d)" % recipes.size())
	for id in [&"squadron", &"battle_group", &"fleet", &"convoy"]:
		var recipe := _registry.formation_recipe(id)
		_check(recipe != null, "the '%s' recipe can be looked up" % id)
		if recipe != null:
			_check(recipe.validate().is_empty(), "%s validates %s" % [id, recipe.validate()])
	_check(_registry.formation_recipe(&"squadron").ship_count_range() == Vector2i(3, 6), "a squadron is 3 to 6 ships")
	_check(_registry.formation_recipe(&"fleet").unit == FormationRecipe.Unit.FLEET, "the fleet recipe is a fleet")
	_check(_registry.formation_recipe(&"fleet").default_shape() == null, "a fleet has no shape")
	_check(_registry.formation_recipe(&"convoy").civilian, "the convoy is civilian")
	var battle_group := _registry.formation_recipe(&"battle_group").ship_count_range()
	_check(battle_group.x >= 2 * 3 + 2 and battle_group.y <= 3 * 6 + 4, "a battle group's size follows from its parts (%s)" % battle_group)


func _test_allocate() -> void:
	var rng := _rng(1)
	var two_to_one: Array[float] = [2.0, 1.0]
	_check(_same(FleetComposer.allocate(3, two_to_one, 0, rng), [2, 1]), "3 ships at 2:1 are 2 and 1")
	_check(_same(FleetComposer.allocate(4, two_to_one, 0, rng), [3, 1]), "4 ships at 2:1 are 3 and 1")
	_check(_same(FleetComposer.allocate(5, two_to_one, 0, rng), [3, 2]), "5 ships at 2:1 are 3 and 2")
	_check(_same(FleetComposer.allocate(6, two_to_one, 0, rng), [4, 2]), "6 ships at 2:1 are 4 and 2")
	_check(_same(FleetComposer.allocate(0, two_to_one, 0, rng), [0, 0]), "no ships gives no shares")
	var with_zero: Array[float] = [1.0, 0.0, 1.0]
	var shares := FleetComposer.allocate(5, with_zero, 0, rng)
	_check(shares[1] == 0 and shares[0] + shares[2] == 5, "an entry with no weight gets nothing %s" % [shares])

	var always_total := true
	var never_negative := true
	var min_kept := true
	for trial in 500:
		var count := rng.randi_range(0, 12)
		var entries := rng.randi_range(1, 4)
		var weights: Array[float] = []
		for index in entries:
			weights.append(float(rng.randi_range(1, 5)))
		var result := FleetComposer.allocate(count, weights, 0, rng)
		var total := 0
		for share in result:
			total += share
			if share < 0:
				never_negative = false
		if total != count:
			always_total = false
		var kept := FleetComposer.allocate(count, weights, 1, rng)
		if count >= entries:
			for share in kept:
				if share < 1:
					min_kept = false
	_check(always_total, "the shares always add up to the number of ships")
	_check(never_negative, "no share is negative")
	_check(min_kept, "min_each keeps at least that many of every class")

	# Equal weights with one ship: the choice varies with the draw.
	var equal: Array[float] = [1.0, 1.0, 1.0]
	var picked := {}
	for trial in 60:
		picked[FleetComposer.allocate(1, equal, 0, rng).find(1)] = true
	_check(picked.size() == 3, "a single ship among equal classes is drawn at random")


func _test_squadron() -> void:
	var sizes := {}
	var with_support := 0
	var without_support := 0
	var rules_hold := true
	var ratio_holds := true
	var warships_only := true
	var own_faction := true
	var shapes_ok := true
	var recipe := _registry.formation_recipe(&"squadron")
	var kinds := {}
	for seed_value in SEEDS:
		var plan := _compose(&"squadron", seed_value)
		if plan == null:
			rules_hold = false
			continue
		sizes[plan.ship_count()] = true
		var fighters := _count_class(plan, &"fighter")
		var heavies := _count_class(plan, &"heavy_fighter")
		var support := _count_class(plan, &"gunboat") + _count_class(plan, &"corvette") + _count_class(plan, &"frigate")
		if plan.ship_count() < 3 or plan.ship_count() > 6 or fighters + heavies + support != plan.ship_count() or support > 1:
			rules_hold = false
		var core := fighters + heavies
		var expected_heavies := {3: 1, 4: 1, 5: 2, 6: 2}
		if not expected_heavies.has(core) or expected_heavies[core] != heavies:
			ratio_holds = false
		if support == 1:
			with_support += 1
		else:
			without_support += 1
		for type in plan.ships:
			if not type.stats.ship_class.is_a(_registry.ship_class(&"warship")):
				warships_only = false
			if type.stats.faction_id() != FEDERATION:
				own_faction = false
			kinds[type.stats.ship_class.id] = true
		if not recipe.shapes.has(plan.shape):
			shapes_ok = false
		_check_once(plan.children.is_empty(), "a squadron has no sub-units")
	_check(rules_hold, "every squadron has 3 to 6 ships with at most one support ship")
	_check(ratio_holds, "fighters and heavy fighters are always at 2:1 (largest remainder)")
	_check(warships_only and own_faction, "squadrons hold only the faction's warships")
	_check(shapes_ok, "a squadron's shape is one of its recipe's")
	for size in [3, 4, 5, 6]:
		_check(sizes.has(size), "squadrons of %d ships turn up" % size)
	_check(with_support > 0 and without_support > 0, "a support ship is sometimes there and sometimes not (%d / %d)" % [with_support, without_support])
	_check(kinds.has(&"frigate") and not kinds.has(&"gunboat") and not kinds.has(&"corvette"),
			"with no gunboat or corvette models, the support ship is a frigate")


func _test_battle_group() -> void:
	var rules_hold := true
	var squadrons_ok := true
	var counts := {}
	var recipe := _registry.formation_recipe(&"battle_group")
	for seed_value in SEEDS:
		var plan := _compose(&"battle_group", seed_value)
		if plan == null:
			rules_hold = false
			continue
		var large := _count_class(plan, &"frigate") + _count_class(plan, &"cruiser")
		if plan.ships.size() != large or large < 2 or large > 4:
			rules_hold = false
		if plan.children.size() < 2 or plan.children.size() > 3:
			squadrons_ok = false
		counts[plan.children.size()] = true
		for child in plan.children:
			if child.recipe.id != &"squadron" or child.ship_count() < 3 or child.ship_count() > 6:
				squadrons_ok = false
		if not recipe.shapes.has(plan.shape):
			rules_hold = false
		var range := recipe.ship_count_range()
		if plan.ship_count() < range.x or plan.ship_count() > range.y:
			rules_hold = false
	_check(rules_hold, "every battle group has 2 to 4 frigates and cruisers")
	_check(squadrons_ok, "every battle group has 2 to 3 valid squadrons")
	_check(counts.has(2) and counts.has(3), "battle groups with 2 and with 3 squadrons turn up")


func _test_fleet() -> void:
	var rules_hold := true
	var counts := {}
	var capitals := {}
	for seed_value in 150:
		var plan := _compose(&"fleet", seed_value)
		if plan == null:
			rules_hold = false
			continue
		var capital_count := _count_class(plan, &"capital_ship")
		if plan.ships.size() != capital_count or capital_count < 1 or capital_count > 2:
			rules_hold = false
		if plan.children.size() < 2 or plan.children.size() > 3:
			rules_hold = false
		for child in plan.children:
			if child.recipe.id != &"battle_group":
				rules_hold = false
		if plan.shape != null:
			rules_hold = false
		counts[plan.children.size()] = true
		capitals[capital_count] = true
	_check(rules_hold, "every fleet has 1 to 2 capital ships and 2 to 3 battle groups, and no shape")
	_check(counts.has(2) and counts.has(3), "fleets with 2 and with 3 battle groups turn up")
	_check(capitals.has(1) and capitals.has(2), "fleets with 1 and with 2 capital ships turn up")
	var plan := _compose(&"fleet", 7)
	_check(plan.ship_count() >= _registry.formation_recipe(&"fleet").ship_count_range().x, "a fleet is at least as big as its recipe's minimum")


func _test_convoy() -> void:
	var rules_hold := true
	var ratio_holds := true
	var civilian := true
	var escorts_ok := true
	var freighter_counts := {}
	var escort_counts := {}
	var cargo := _registry.ship_class(&"cargo_ship")
	var expected_light := {2: 1, 3: 1, 4: 1, 5: 2, 6: 2}
	for seed_value in SEEDS:
		var plan := _compose(&"convoy", seed_value)
		if plan == null:
			rules_hold = false
			continue
		var freighters := 0
		var interceptors := 0
		var light := 0
		for type in plan.ships:
			var ship_class := type.stats.ship_class
			if ship_class.is_a(cargo):
				freighters += 1
			elif ship_class.id == &"interceptor":
				interceptors += 1
			elif ship_class.id == &"light_frigate":
				light += 1
			else:
				escorts_ok = false
			if type.stats.faction_id() != &"":
				civilian = false
		var escorts := interceptors + light
		if freighters < 2 or freighters > 5 or escorts < 2 or escorts > 6 or interceptors > 4 or light > 2:
			rules_hold = false
		if not expected_light.has(escorts) or expected_light[escorts] != light:
			ratio_holds = false
		freighter_counts[freighters] = true
		escort_counts[escorts] = true
	_check(rules_hold, "every convoy has 2 to 5 freighters and 2 to 6 escorts (at most 4 interceptors and 2 light frigates)")
	_check(ratio_holds, "escorts are interceptors and light frigates at 2:1")
	_check(escorts_ok, "a convoy's escorts are only interceptors and light frigates")
	_check(civilian, "a convoy holds no military faction's ships")
	for count in [2, 3, 4, 5]:
		_check(freighter_counts.has(count), "convoys of %d freighters turn up" % count)
	for count in [2, 3, 4, 5, 6]:
		_check(escort_counts.has(count), "convoys of %d escorts turn up" % count)
	# A convoy is built whoever asks, and never uses the asker's warships.
	var plan := FleetComposer.compose(_registry.formation_recipe(&"convoy"), NO_SHIPS_FACTION, _types, _rng(3))
	_check(plan != null, "a convoy can be composed for a faction with no ships of its own")


func _test_missing_classes() -> void:
	# No heavy fighters: squadrons are fighters only.
	var no_heavies := _without([&"heavy_fighter"])
	var only_fighters := true
	var sizes_ok := true
	for seed_value in 100:
		var plan := _compose(&"squadron", seed_value, no_heavies)
		if plan == null or _count_class(plan, &"heavy_fighter") != 0 or _count_class(plan, &"fighter") < 3:
			only_fighters = false
		elif plan.ship_count() < 3 or plan.ship_count() > 6:
			sizes_ok = false
	_check(only_fighters, "with no heavy fighters, a squadron's fighters take their share")
	_check(sizes_ok, "... and it keeps its size range")

	# No support ships at all: just the fighters.
	var no_support := _without([&"frigate", &"gunboat", &"corvette"])
	var none := true
	for seed_value in 100:
		var plan := _compose(&"squadron", seed_value, no_support)
		if plan == null or plan.ship_count() > 6 or plan.ship_count() < 3 or _count_class(plan, &"frigate") != 0:
			none = false
	_check(none, "with no support ship models, squadrons are built without one")

	# Nothing a unit must have: it cannot be built.
	var no_fighters := _without([&"fighter", &"heavy_fighter"])
	_check(_compose(&"squadron", 1, no_fighters) == null, "a squadron cannot be built with no fighters or heavy fighters")
	_check(_compose(&"battle_group", 1, no_fighters) == null, "... nor a battle group, which needs squadrons")
	_check(_compose(&"fleet", 1, no_fighters) == null, "... nor a fleet")
	_check(_compose(&"fleet", 1, _without([&"capital_ship"])) == null, "a fleet cannot be built with no capital ship")
	_check(_compose(&"battle_group", 1, _without([&"frigate", &"cruiser"])) == null, "a battle group cannot be built with no frigates or cruisers")
	_check(_compose(&"convoy", 1, _without([&"freighter", &"bulk_freighter"])) == null, "a convoy cannot be built with no freighter")
	_check(_compose(&"convoy", 1, _without([&"interceptor", &"light_frigate"])) == null, "... nor with no escorts")

	# A faction with no ships gets no military unit.
	for id in [&"squadron", &"battle_group", &"fleet"]:
		var plan := FleetComposer.compose(_registry.formation_recipe(id), NO_SHIPS_FACTION, _types, _rng(1))
		_check(plan == null, "a faction with no warships gets no %s" % id)


func _test_new_class_needs_no_code() -> void:
	# A gunboat model (the Hegemony's, later) is just another ship type of an existing class.
	var gunboat_stats: ShipStats = _registry.ship_stats(&"federation_frigate").duplicate()
	gunboat_stats.id = &"test_gunboat"
	gunboat_stats.ship_class = _registry.ship_class(&"gunboat")
	var gunboat := ShipType.new()
	gunboat.stats = gunboat_stats
	gunboat.category = ShipType.Category.MILITARY
	var types: Array[ShipType] = []
	types.append_array(_types)
	types.append(gunboat)
	var seen_gunboat := false
	var seen_frigate := false
	for seed_value in SEEDS:
		var plan := _compose(&"squadron", seed_value, types)
		seen_gunboat = seen_gunboat or _count_class(plan, &"gunboat") > 0
		seen_frigate = seen_frigate or _count_class(plan, &"frigate") > 0
		if plan.ship_count() > 6 or _count_class(plan, &"gunboat") + _count_class(plan, &"frigate") > 1:
			_check(false, "a squadron never has more than one support ship")
			return
	_check(seen_gunboat and seen_frigate, "a new gunboat model joins squadrons as support with no code change")


func _test_hegemony() -> void:
	# The Hegemony has its own six warship models, so it composes every military unit from them alone.
	var gunboats := 0
	var own_ships_only := true
	var all_built := true
	var squads := 0
	for id in [&"squadron", &"battle_group", &"fleet"]:
		for seed_value in SEEDS:
			var plan := FleetComposer.compose(_registry.formation_recipe(id), HEGEMONY, _types, _rng(seed_value))
			if plan == null:
				all_built = false
				continue
			for type in plan.all_ship_types():
				if type.stats.faction_id() != HEGEMONY:
					own_ships_only = false
			if id == &"squadron":
				squads += 1
				gunboats += _count_class(plan, &"gunboat")
	_check(all_built, "the Hegemony can field a squadron, a battle group and a fleet")
	_check(own_ships_only, "...from Hegemony ships only (never the Federation's)")
	_check(gunboats > 0 and gunboats < squads, "its gunboat joins some squadrons as the support ship (%d of %d)" % [gunboats, squads])
	# And the Federation never draws a Hegemony ship.
	var federation_only := true
	for seed_value in SEEDS:
		for type in _compose(&"battle_group", seed_value).all_ship_types():
			if type.stats.faction_id() != FEDERATION:
				federation_only = false
	_check(federation_only, "the Federation draws no Hegemony ships")


func _test_determinism() -> void:
	var same := true
	var different := false
	for seed_value in 50:
		var first := _compose(&"battle_group", seed_value)
		var second := _compose(&"battle_group", seed_value)
		if first.describe() != second.describe():
			same = false
		if first.describe() != _compose(&"battle_group", seed_value + 1000).describe():
			different = true
	_check(same, "the same seed gives the same plan")
	_check(different, "different seeds give different plans")
	var description := _compose(&"squadron", 4).describe()
	_check(description.begins_with("Squadron (") and " x " in description, "a plan describes itself (%s)" % description)
	var empty := FormationPlan.new()
	_check(empty.ship_count() == 0 and empty.all_ship_types().is_empty(), "an empty plan has no ships")
	var battle_group := _compose(&"battle_group", 9)
	_check(battle_group.all_ship_types().size() == battle_group.ship_count(), "all_ship_types lists the sub-units' ships too")


func _test_validation() -> void:
	var recipe := FormationRecipe.new()
	_check(not recipe.validate().is_empty(), "an empty recipe is invalid")

	var group := RecipeGroup.new()
	group.label = "x"
	_check(not group.validate().is_empty(), "a group with no classes is invalid")
	group.classes = [_registry.ship_class(&"fighter")] as Array[ShipClass]
	group.min_count = 3
	group.max_count = 2
	_check(not group.validate().is_empty(), "a group whose maximum is below its minimum is invalid")
	group.max_count = 4
	group.weights = [1.0, 2.0] as Array[float]
	_check(not group.validate().is_empty(), "weights that do not match the classes are invalid")
	group.weights = [0.0] as Array[float]
	_check(not group.validate().is_empty(), "weights that add up to nothing are invalid")
	group.weights = [] as Array[float]
	_check(group.validate().is_empty(), "no weights means equal weights, and is valid %s" % [group.validate()])

	recipe.id = &"test"
	recipe.display_name = "Test"
	recipe.groups = [group] as Array[RecipeGroup]
	_check(not recipe.validate().is_empty(), "a squadron-like recipe with no shape is invalid")
	recipe.shapes = [_registry.formation_shape(&"wedge")] as Array[FormationShape]
	_check(recipe.validate().is_empty(), "... and valid with one %s" % [recipe.validate()])
	recipe.min_ships = 9
	recipe.max_ships = 10
	_check(not recipe.validate().is_empty(), "min_ships and max_ships the groups cannot meet are invalid")
	recipe.min_ships = 0
	recipe.max_ships = 0

	var child := RecipeChild.new()
	child.recipe = _registry.formation_recipe(&"fleet")
	child.min_count = 1
	child.max_count = 2
	recipe.children = [child] as Array[RecipeChild]
	_check(not recipe.validate().is_empty(), "a fleet cannot be inside another unit")
	child.recipe = null
	_check(not child.validate().is_empty(), "a child with no recipe is invalid")


## Whether two lists hold the same values in the same order.
func _same(first: Array, second: Array) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if first[index] != second[index]:
			return false
	return true


var _once: Dictionary = {}


## A check inside a loop that is reported once, when it fails (or on the first pass).
func _check_once(condition: bool, label: String) -> void:
	if not condition:
		_check(false, label)
	elif not _once.has(label):
		_once[label] = true
		_check(true, label)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
