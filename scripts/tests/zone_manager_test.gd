extends SceneTree
## Zones on the real galaxy: the Federation's capital and centres, zones around them,
## and what happens when a second faction takes systems: a conquered critical system
## becomes a regional centre after the establishment time, losing it ends that at
## once, a lost capital is replaced, contested systems, saving, and the economy never
## changing. Run with:
##   Godot --headless --path . --script res://scripts/tests/zone_manager_test.gd </dev/null

const Z := ZoneMap.Zone

var _failures: int = 0
var _registry: ContentRegistry
var _galaxy: Galaxy
var _model: EconomyModel
var _military: MilitaryValueRules
var _federation: Faction
var _rival: Faction


class World:
	var territory: TerritoryManager
	var clock: GameClock
	var zones: ZoneManager
	var assessor: SystemAssessor


func _init() -> void:
	_registry = ContentRegistry.new()
	_galaxy = load("res://resources/universe/galaxy.tres")
	_model = EconomyModel.new(load(EconomyModel.DEFAULT_CONFIG), _registry.commodities())
	_military = load("res://resources/military/military_value_rules.tres")
	_federation = _registry.faction(&"faction_1")
	_rival = Faction.new()
	_rival.id = &"faction_test"
	_rival.display_name = "Rival"
	_registry._factions[_rival.id] = _rival  # a second faction, which the game does not have yet

	_check_start()
	_check_properties()
	_check_conquest()
	_check_capital()
	_check_contested()
	_check_front()
	_check_saving()
	_check_economy_unchanged()
	_check_signals()

	print("")
	print("ZONE MANAGER TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _world(rules: ZoneRules = null) -> World:
	var world := World.new()
	world.clock = GameClock.new()
	world.territory = TerritoryManager.new()
	world.territory.setup(_galaxy, _registry)
	world.assessor = SystemAssessor.new(_galaxy, _registry, _model, _military)
	world.zones = ZoneManager.new()
	world.zones.setup(_galaxy, world.territory, world.assessor, _registry, world.clock, rules)
	return world


func _free(world: World) -> void:
	world.zones.free()
	world.territory.free()


func _settlements(system_id: StringName) -> Array[InhabitedData]:
	var result: Array[InhabitedData] = []
	for location_id in _galaxy.get_summary(system_id).location_ids:
		var location := _registry.location(location_id)
		if location.is_dockable() and location.population > 0:
			result.append(location)
	return result


func _take(world: World, system_id: StringName, faction: Faction) -> void:
	for location in _settlements(system_id):
		world.territory.transfer_settlement(location, faction)


## The Federation's critical systems other than the capital, farthest from it first.
func _far_centres(world: World) -> Array[StringName]:
	var hops := _galaxy.get_reachable(_federation.capital_system, 1000)
	var result: Array[StringName] = []
	for id in world.zones.centres_of(_federation.id):
		if id != _federation.capital_system:
			result.append(id)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return hops[a] > hops[b])
	return result


func _check_start() -> void:
	var world := _world()
	var capital := _federation.capital_system
	_check(capital != &"", "setup: the Federation has a capital")
	_check(world.zones.capital_of(_federation.id) == capital, "the capital is the capital")
	_check(world.zones.zone_of(capital) == Z.CAPITAL and world.zones.zone_name_of(capital) == "CAPITAL", "its zone is CAPITAL")
	_check(world.zones.is_centre(capital), "and it is a centre of power")

	# The centres are the critical systems the Federation holds, important enough, plus the capital.
	var expected: Array = []
	var rules := world.zones.rules
	for id in _galaxy.get_system_ids():
		var system_class := _galaxy.get_system_class(id)
		if system_class != null and system_class.can_be_centre() and world.assessor.assess(id).importance >= rules.centre_min_importance:
			expected.append(id)
	if not expected.has(capital):
		expected.append(capital)
	expected.sort_custom(func(a, b) -> bool: return str(a) < str(b))
	var found: Array = world.zones.centres_of(_federation.id).duplicate()
	found.sort_custom(func(a, b) -> bool: return str(a) < str(b))
	_check(found == expected, "the Federation's centres are its capital and its important critical systems (%d)" % found.size())
	_check(found.size() >= 3, "there are several centres: the capital and others")
	_check(world.zones.centres_of(_rival.id).is_empty() and world.zones.zone_of(capital, _rival.id) == Z.NONE, "a faction with nothing has no centres and no zones")
	_free(world)


## Every system the Federation holds has a zone that agrees with the rules.
func _check_properties() -> void:
	var world := _world()
	var rules := world.zones.rules
	var graph := GalaxyGraph.from_galaxy(_galaxy)
	var consistent := true
	var centres := world.zones.centres_of(_federation.id)
	var counts := {}
	for id in _galaxy.get_system_ids():
		var control := world.territory.get_control(id)
		var zone := world.zones.zone_of(id, _federation.id)
		if not control.involves(_federation):
			consistent = consistent and zone == Z.NONE
			continue
		counts[zone] = counts.get(zone, 0) + 1
		var centre := world.zones.region_centre_of(id, _federation.id)
		var hops := world.zones.hops_from_centre(id, _federation.id)
		if centre == &"":
			consistent = consistent and zone == Z.FRONTIER and hops == -1
			continue
		consistent = consistent and centres.has(centre) and hops >= 0
		if hops == 0:
			consistent = consistent and (zone == Z.CAPITAL or zone == Z.CORE)
		elif hops <= rules.core_max_hops and graph.degree(centre) >= rules.core_requires_links:
			consistent = consistent and zone == Z.CORE
		elif hops > rules.inner_max_hops and graph.degree(id) < rules.hub_promotion_links:
			consistent = consistent and zone == Z.FRONTIER
	_check(consistent, "every system's zone and region follow from its distance to a centre")
	print("      zones: %d capital, %d core, %d inner, %d frontier" % [counts.get(Z.CAPITAL, 0), counts.get(Z.CORE, 0), counts.get(Z.INNER, 0), counts.get(Z.FRONTIER, 0)])
	_check(counts.get(Z.CAPITAL, 0) == 1 and counts.get(Z.CORE, 0) > 1 and counts.get(Z.INNER, 0) > 0, "there is one capital, a core, and inner territory")
	_check(counts.get(Z.FRONTIER, 0) > 0, "and some frontier")
	_free(world)


func _check_conquest() -> void:
	var world := _world()
	var far := _far_centres(world)
	_check(not far.is_empty(), "setup: the Federation has a centre other than the capital")
	var victim: StringName = far[0]
	var rules := world.zones.rules
	_check(world.zones.is_centre(victim, _federation.id), "the farthest centre (%s) is a centre of the Federation" % victim)

	# The rival takes every settlement there.
	_take(world, victim, _rival)
	_check(world.territory.get_control(victim).is_controlled_by(_rival), "the rival now controls the system")
	_check(not world.zones.is_centre(victim, _federation.id) and world.zones.zone_of(victim, _federation.id) == Z.NONE,
			"the Federation loses the centre at once, and holds nothing there")
	_check(world.zones.zone_of(victim) == Z.FRONTIER, "for the rival, the conquered system is frontier at first")
	_check(world.zones.centres_of(_rival.id).is_empty(), "it is not yet a centre: it has not been held long enough")
	world.clock.advance(rules.establish_days - 1)
	_check(world.zones.centres_of(_rival.id).is_empty(), "still not, a day short")
	world.clock.advance(1)
	_check(world.zones.is_centre(victim), "after the establishment time it is a centre of power for the rival")
	_check(world.zones.hops_from_centre(victim) == 0 and world.zones.region_centre_of(victim) == victim, "a mini-core: its own region")
	_check(world.zones.zone_of(victim) in [Z.CAPITAL, Z.CORE], "and its zone is no longer frontier (%s)" % world.zones.zone_name_of(victim))

	# A neighbour taken too becomes part of the mini-core.
	var neighbour: StringName = &""
	for other in _galaxy.get_neighbours(victim):
		if not _settlements(other).is_empty():
			neighbour = other
			break
	if neighbour != &"":
		_take(world, neighbour, _rival)
		_check(world.zones.region_centre_of(neighbour) == victim and world.zones.hops_from_centre(neighbour) == 1,
				"a neighbour the rival takes joins the new region")
		_check(world.zones.zone_of(neighbour) == Z.CORE, "as core, around the new centre (%s)" % world.zones.zone_name_of(neighbour))
		_check(world.zones.zone_of(neighbour, _federation.id) == Z.NONE, "and is no longer the Federation's")

	# Retaking it ends the rival's centre at once and restores the Federation's at once.
	_take(world, victim, _federation)
	_check(not world.zones.is_centre(victim, _rival.id) and world.zones.is_centre(victim, _federation.id),
			"retaken by its starting owner it is a centre again immediately")
	_check(world.zones.save_state()["claims"].is_empty() or not world.zones.save_state()["claims"].has(str(victim)), "and it is no longer recorded as claimed")
	_free(world)


func _check_capital() -> void:
	var world := _world()
	var capital := _federation.capital_system
	_take(world, capital, _rival)
	var acting := world.zones.capital_of(_federation.id)
	_check(acting != &"" and acting != capital, "a faction that loses its capital gets an acting one (%s)" % acting)
	_check(acting == world.zones.centres_of(_federation.id)[0], "the most important remaining centre")
	_check(world.zones.zone_of(acting, _federation.id) == Z.CAPITAL, "it takes the capital zone")
	_check(world.zones.zone_of(capital, _federation.id) == Z.NONE, "and the old capital is no longer the Federation's")
	world.clock.advance(world.zones.rules.establish_days)
	_check(world.zones.is_centre(capital, _rival.id), "the rival's new conquest, a critical system, becomes its centre")
	_check(world.zones.capital_of(_rival.id) == capital, "and with no capital of its own it acts as the rival's capital")
	_take(world, capital, _federation)
	_check(world.zones.capital_of(_federation.id) == capital and world.zones.zone_of(capital) == Z.CAPITAL, "retaking the capital restores it")
	_free(world)

	var strict := ZoneRules.new()
	strict.relocate_capital = false
	var fixed := _world(strict)
	_take(fixed, capital, _rival)
	_check(fixed.zones.capital_of(_federation.id) == &"", "with relocation off a lost capital leaves no capital")
	var any_capital_zone := false
	for id in _galaxy.get_system_ids():
		any_capital_zone = any_capital_zone or fixed.zones.zone_of(id, _federation.id) == Z.CAPITAL
	_check(not any_capital_zone, "and no system is in the capital zone")
	_free(fixed)


func _check_contested() -> void:
	var world := _world()
	var contested: StringName = &""
	for id in _galaxy.get_system_ids():
		if _settlements(id).size() >= 2 and not (_galaxy.get_system_class(id) == null):
			contested = id
			break
	if contested == &"":
		_check(false, "setup: found a classed system with two settlements")
		_free(world)
		return
	var was_centre := world.zones.is_centre(contested, _federation.id)
	_take_one(world, contested)
	_check(world.territory.is_contested(contested), "%s is contested" % contested)
	_check(world.zones.zone_of(contested) == Z.NONE, "a contested system has no single zone")
	_check(world.zones.zone_of(contested, _federation.id) != Z.NONE and world.zones.zone_of(contested, _rival.id) != Z.NONE,
			"but both sides are present in it and have a zone")
	_check(not world.zones.is_centre(contested, _federation.id) and not world.zones.is_centre(contested, _rival.id),
			"neither holds it outright, so it is a centre of neither (it was %s)" % ("a centre" if was_centre else "not one"))
	_free(world)


func _take_one(world: World, system_id: StringName) -> void:
	world.territory.transfer_settlement(_settlements(system_id)[0], _rival)


func _check_front() -> void:
	var world := _world()
	var graph := GalaxyGraph.from_galaxy(_galaxy)
	var capital := _federation.capital_system
	var far := _far_centres(world)
	var victim: StringName = far[0]
	_check(world.zones.hops_to_enemy(capital, _federation.id) == -1 and not world.zones.is_border(capital), "with no enemy there is no front line")
	_take(world, victim, _rival)
	var next_to: StringName = &""
	for other in _galaxy.get_neighbours(victim):
		if world.zones.zone_of(other, _federation.id) != Z.NONE:
			next_to = other
			break
	if next_to != &"":
		_check(world.zones.is_border(next_to, _federation.id), "a system next to the rival's is a border system")
		_check(world.zones.hops_to_enemy(next_to, _federation.id) == 1, "one jump from the front")
	var expected: int = _galaxy.get_reachable(capital, 1000)[victim]
	_check(world.zones.hops_to_enemy(capital, _federation.id) <= expected, "the capital is at most %d jumps from the front line" % expected)
	_check(not world.zones.is_border(capital, _federation.id), "the capital is not on the border")
	var points := graph.articulation_points()
	var agrees := true
	for id in _galaxy.get_system_ids():
		agrees = agrees and world.zones.is_chokepoint(id) == points.has(id)
	_check(agrees, "chokepoints are the systems whose loss would split the network")
	_free(world)


func _check_saving() -> void:
	var world := _world()
	var victim: StringName = _far_centres(world)[0]
	_take(world, victim, _rival)
	world.clock.advance(3)
	var state: Dictionary = JSON.parse_string(JSON.stringify(world.zones.save_state()))
	_check(world.zones.validate_state(state, _registry).is_empty(), "saved zones validate: %s" % [world.zones.validate_state(state, _registry)])
	_check(state["claims"].has(str(victim)) and state["claims"][str(victim)]["faction"] == str(_rival.id), "a system that changed hands is saved with its new owner")

	# Load into a fresh world with the same territory and clock.
	var other := _world()
	other.territory.load_state(JSON.parse_string(JSON.stringify(world.territory.save_state())), _registry)
	other.clock.day = world.clock.day
	other.zones.load_state(state, _registry)
	_check(not other.zones.is_centre(victim), "a loaded game still waits for the establishment time")
	world.clock.advance(world.zones.rules.establish_days)
	other.clock.advance(world.zones.rules.establish_days)
	_check(world.zones.is_centre(victim) and other.zones.is_centre(victim), "and the system becomes a centre on the same day")
	_check(world.zones.centres_of(_rival.id) == other.zones.centres_of(_rival.id), "with the same centres")
	other.zones.reset_state()
	_check(other.zones.save_state()["claims"].is_empty(), "reset forgets all claims (an old save with no section)")

	var cases := {
		"no claims object": func(s: Dictionary) -> void: s["claims"] = [],
		"unknown system": func(s: Dictionary) -> void: s["claims"]["nowhere"] = {"faction": "faction_1", "day": 1},
		"unknown faction": func(s: Dictionary) -> void: s["claims"][str(victim)]["faction"] = "nobody",
		"negative day": func(s: Dictionary) -> void: s["claims"][str(victim)]["day"] = -1,
		"fractional day": func(s: Dictionary) -> void: s["claims"][str(victim)]["day"] = 1.5,
		"claim not an object": func(s: Dictionary) -> void: s["claims"][str(victim)] = 7,
	}
	for label in cases:
		var damaged: Dictionary = JSON.parse_string(JSON.stringify(state))
		cases[label].call(damaged)
		# The rival is not in the registry on disk, so give the check the test's registry.
		_check(not world.zones.validate_state(damaged, _registry).is_empty(), "damaged save rejected: %s" % label)
	_free(world)
	_free(other)


## Zones and who holds what never change what a place makes or uses.
func _check_economy_unchanged() -> void:
	var world := _world()
	var before := {}
	for location in _registry.locations():
		var economy := _model.compute(location)
		before[location.id] = [economy.production.duplicate(), economy.consumption.duplicate(), location.population]
	_take(world, _far_centres(world)[0], _rival)
	world.clock.advance(50)
	_take(world, _federation.capital_system, _rival)
	world.zones.centres_of(_federation.id)
	var same := true
	for location in _registry.locations():
		var economy := _model.compute(location)
		same = same and before[location.id] == [economy.production, economy.consumption, location.population]
	_check(same, "conquest and zone changes alter no location's production, consumption or population")
	_free(world)


func _check_signals() -> void:
	var world := _world()
	var heard: Array = []
	world.zones.zones_changed.connect(func(id: StringName) -> void: heard.append(id))
	world.clock.advance(5)
	_check(heard.is_empty(), "time passing with nothing changing announces nothing")
	_take(world, _far_centres(world)[0], _rival)
	_check(heard.has(_federation.id), "taking a centre announces that the Federation's zones changed")
	heard.clear()
	world.clock.advance(world.zones.rules.establish_days)
	_check(heard.has(_rival.id), "and the rival's zones change when the conquest becomes a centre")
	_free(world)


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
