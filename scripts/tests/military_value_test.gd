extends SceneTree
## Military goods and profiles, and military value: what a location and a system is
## worth to a war, and how damage and class change it. Run with:
##   Godot --headless --path . --script res://scripts/tests/military_value_test.gd </dev/null

var _failures: int = 0
var _registry: ContentRegistry
var _galaxy: Galaxy
var _model: EconomyModel
var _rules: MilitaryValueRules


func _init() -> void:
	_registry = ContentRegistry.new()
	_galaxy = load("res://resources/universe/galaxy.tres")
	_model = EconomyModel.new(load(EconomyModel.DEFAULT_CONFIG), _registry.commodities())
	_rules = load("res://resources/military/military_value_rules.tres")

	_check_goods()
	_check_profiles()
	_check_contracts()
	_check_independence()
	_check_location_values()
	_check_system_values()
	_check_damage()
	_check_one_way()

	print("")
	print("MILITARY VALUE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _assessor(damage: Callable = Callable(), scale: Callable = Callable()) -> SystemAssessor:
	return SystemAssessor.new(_galaxy, _registry, _model, _rules, damage, scale)


func _location(type_id: String, population: int, id: String = "test_place") -> PlanetData:
	var planet := PlanetData.new()
	planet.id = StringName(id)
	planet.display_name = id
	planet.population = population
	planet.planet_type = load("res://resources/planet_types/%s.tres" % type_id)
	return planet


func _profile(id: String) -> EconomyProfile:
	return load("res://resources/economy/profiles/%s.tres" % id)


# -------------------------------------------------------------------- goods

func _check_goods() -> void:
	var military_ids := [&"munitions", &"armour_plating", &"field_rations", &"combat_medkits", &"reactor_cores"]
	for id in military_ids:
		var good := _registry.commodity(id)
		_check(good != null and good.military, "%s is a military good" % id)
		_check(good != null and good.base_price > 0 and good.civilian_demand == 0.0, "%s is traded, and civilians do not need it" % id)
	for good in _registry.commodities():
		if not military_ids.has(good.id):
			_check(not good.military, "%s is not flagged military" % good.id)
	_check(_registry.problems.is_empty(), "the registry accepts the new goods: %s" % [_registry.problems])


func _check_profiles() -> void:
	_check(_rules != null and _rules.validate().is_empty(), "the military value rules are valid")
	var most_civilian := 0.0
	for file in DirAccess.get_files_at("res://resources/economy/profiles/"):
		var profile := load("res://resources/economy/profiles/" + file) as EconomyProfile
		_check(profile.validate().is_empty(), "%s is a valid profile" % profile.id)
		_check(profile.military_value >= 0.0, "%s has a military value (%s)" % [profile.id, profile.military_value])
		if profile.id != &"military" and profile.id != &"arsenal":
			most_civilian = maxf(most_civilian, profile.military_value)
	_check(_profile("military").military_value > most_civilian and _profile("arsenal").military_value > most_civilian,
			"military settlements are worth more than any civilian kind")
	_check(_profile("resort").military_value < _profile("agricultural").military_value
			and _profile("agricultural").military_value < _profile("industrial").military_value,
			"a resort is worth least and an industrial settlement more than a farming one")

	var consumes_all := true
	var makes_none := true
	for line in _profile("military").goods:
		if line.commodity.military:
			consumes_all = consumes_all and line.industrial_demand > 0.0
			makes_none = makes_none and line.production == 0.0
	_check(consumes_all and makes_none, "a military settlement uses military goods and makes none")
	var arsenal_makes := []
	for line in _profile("arsenal").goods:
		if line.production > 0.0:
			arsenal_makes.append(line.commodity.id)
	_check(arsenal_makes.has(&"munitions") and arsenal_makes.has(&"armour_plating") and arsenal_makes.has(&"reactor_cores"),
			"an arsenal makes munitions, armour plating and reactor cores")

	# Every military good is made by some profile, so the galaxy can supply it.
	for id in [&"munitions", &"armour_plating", &"field_rations", &"combat_medkits", &"reactor_cores"]:
		var made := false
		var used := false
		for file in DirAccess.get_files_at("res://resources/economy/profiles/"):
			for line in (load("res://resources/economy/profiles/" + file) as EconomyProfile).goods:
				if line.commodity.id == id:
					made = made or line.production > 0.0
					used = used or line.industrial_demand > 0.0
		_check(made and used, "%s is both made and used by some profile" % id)


# ------------------------------------------------------------ contracts, rep

## Civilian contracts never carry goods of war.
func _check_contracts() -> void:
	var context := ContractContext.new()
	context.galaxy = _galaxy
	context.registry = _registry
	context.rewards = load("res://resources/contracts/reward_rules.tres")
	context.max_cargo = _registry.max_cargo_capacity()
	var travel := TravelManager.new()
	travel.setup(context.galaxy, func() -> StringName: return &"sol")
	context.travel = travel
	var territory := TerritoryManager.new()
	territory.setup(context.galaxy, _registry)
	context.territory = territory
	var checked := 0
	var offenders := 0
	var exporters_of_military := 0
	for location in _registry.locations():
		if not ProceduralContractSource.is_inhabited(location):
			continue
		for good in _model.of(location).exports():
			if good.military:
				exporters_of_military += 1
		var source := ProceduralContractSource.new()
		source.seed_rng(location.id.hash() % 9973)
		for contract in source.generate(location, context, 12, []):
			if contract is CargoDeliveryContract:
				checked += 1
				if contract.commodity.military:
					offenders += 1
	_check(exporters_of_military > 0, "setup: some places export military goods (%d)" % exporters_of_military)
	_check(checked > 50 and offenders == 0, "no civilian contract carries a military good (%d cargo contracts checked)" % checked)


## Availability and price come from the simulation alone: the economy code does not
## read reputation or faction standing.
func _check_independence() -> void:
	for path in ["res://scripts/economy/market.gd", "res://scripts/economy/economy_manager.gd",
			"res://scripts/economy/economy_model.gd", "res://scripts/economy/location_economy.gd"]:
		var source := FileAccess.get_file_as_string(path).to_lower()
		_check(not source.contains("reputation") and not source.contains("standing"), "%s does not read reputation" % path)


# -------------------------------------------------------------- location value

func _check_location_values() -> void:
	var assessor := _assessor()
	var mining := _profile("mining")
	var base := assessor.location_value(_location("rocky", 1000000))
	_check(is_equal_approx(base, mining.military_value), "a mining world of the reference size is worth its profile's value (%s)" % base)
	_check(assessor.location_value(_location("rocky", 4000000)) > base, "a bigger settlement is worth more")
	_check(is_equal_approx(assessor.location_value(_location("rocky", 4000000)), mining.military_value * pow(4.0, _rules.size_exponent)),
			"in proportion to its size factor")
	_check(is_equal_approx(assessor.location_value(_location("rocky", 100000000000)), mining.military_value * _rules.size_max), "the size factor has a ceiling")
	_check(is_equal_approx(assessor.location_value(_location("rocky", 10)), mining.military_value * _rules.size_min), "and a floor")
	_check(assessor.location_value(_location("rocky", 0)) == 0.0, "an uninhabited place is worth nothing")
	var giant := _location("gas_giant_red", 0)
	giant.dockable = false
	_check(assessor.location_value(giant) == 0.0, "so is a place that cannot be landed on")
	_check(assessor.location_value(null) == 0.0, "and no location at all")

	var with_yard := _location("rocky", 1000000)
	with_yard.shipyard_ships = [ShipStats.new()]
	_check(is_equal_approx(assessor.location_value(with_yard), base + _rules.shipyard_value), "a shipyard adds its value")
	var with_both := _location("rocky", 1000000)
	with_both.shipyard_ships = [ShipStats.new()]
	with_both.outfitter_upgrades = [UpgradeDefinition.new()]
	_check(is_equal_approx(assessor.location_value(with_both), base + _rules.shipyard_value + _rules.outfitter_value), "and an outfitter adds its value too")
	var fortress := _location("rocky", 1000000)
	fortress.military_value_bonus = 40.0
	_check(is_equal_approx(assessor.location_value(fortress), base + 40.0), "a designed bonus is added")
	var station := InhabitedData.new()
	station.id = &"test_station"
	station.population = 1000000
	_check(is_equal_approx(assessor.location_value(station), _model.config.station_profile.military_value), "a station with no profile uses the station profile")
	station.economy_profile = _profile("military")
	_check(assessor.location_value(station) > assessor.location_value(_location("rocky", 1000000)), "a military station is worth more than a mining world of the same size")


# ---------------------------------------------------------------- system value

func _check_system_values() -> void:
	var assessor := _assessor()
	var all := assessor.assess_all()
	_check(all.size() == _galaxy.get_system_ids().size(), "every system is assessed (%d)" % all.size())
	var sums_match := true
	var connectivity_matches := true
	var population_matches := true
	var empty_is_zero := true
	var classed_total := {}
	var classed_count := {}
	for id in all:
		var a: SystemAssessment = all[id]
		var expected := 0.0
		var people := 0
		for location_id in _galaxy.get_summary(id).location_ids:
			var location := _registry.location(location_id)
			expected += assessor.location_value(location)
			if location.is_dockable() and location.population > 0:
				people += location.population
		var system_class := _galaxy.get_system_class(id)
		expected *= system_class.military_value_multiplier if system_class != null else 1.0
		sums_match = sums_match and is_equal_approx(a.military_value, expected)
		connectivity_matches = connectivity_matches and a.connectivity == _galaxy.get_neighbours(id).size()
		population_matches = population_matches and a.population == people
		if not a.is_inhabited():
			empty_is_zero = empty_is_zero and a.military_value == 0.0 and a.importance == 0.0 and a.production_value == 0.0
		elif system_class != null:
			classed_total[system_class.id] = classed_total.get(system_class.id, 0.0) + a.military_value
			classed_count[system_class.id] = classed_count.get(system_class.id, 0) + 1
	_check(sums_match, "a system's military value is its locations' values times its class multiplier")
	_check(connectivity_matches, "connectivity is the number of jump links")
	_check(population_matches, "population is the people in its inhabited locations")
	_check(empty_is_zero, "a system nobody lives in is worth nothing")
	if classed_count.has(&"economic_centre") and classed_count.has(&"rural"):
		var economic: float = classed_total[&"economic_centre"] / classed_count[&"economic_centre"]
		var rural: float = classed_total[&"rural"] / classed_count[&"rural"]
		_check(economic > rural * 2.0, "economic centres are worth far more than rural systems on average (%.0f against %.0f)" % [economic, rural])

	var sol := assessor.assess(&"sol")
	_check(sol.class_id != &"" and sol.production_value > 0.0 and sol.consumption_value > 0.0, "Sol makes and uses goods")
	_check(sol.importance > assessor.assess(&"nowhere").importance, "an inhabited system is more important than an unknown one")
	_check(assessor.assess(&"nowhere").military_value == 0.0, "an unknown system is worth nothing")
	_check(all[&"sol"].military_value == sol.military_value and sol.location_values.size() == sol.location_ids.size(), "the assessment lists each location's value")
	var expected_importance := (sol.military_value * _rules.weight_military + sol.production_value * _rules.weight_production
			+ float(sol.population) / 1000000.0 * _rules.weight_population + sol.connectivity * _rules.weight_connectivity)
	_check(is_equal_approx(sol.importance, expected_importance), "importance is military value, production, population and links, each weighted")
	_check(sol.importance > 0.0 and all[&"sol"].connectivity == _galaxy.get_neighbours(&"sol").size(),
			"Sol's importance counts its %d jump links" % sol.connectivity)


func _check_damage() -> void:
	var damaged := _assessor(func(_id: StringName) -> float: return 0.6, func(_id: StringName) -> float: return 0.5)
	var whole := _assessor()
	var a := damaged.assess(&"sol")
	var b := whole.assess(&"sol")
	_check(is_equal_approx(a.military_value, b.military_value), "damage does not change the structural military value")
	_check(a.current_military_value < a.military_value, "but it lowers the current value")
	_check(is_equal_approx(a.current_military_value, a.military_value * (1.0 - _rules.damage_weight * 0.6)), "by the configured weight")
	_check(is_equal_approx(b.current_military_value, b.military_value), "an undamaged system is worth its full value")
	_check(is_equal_approx(a.importance, b.importance), "importance is structural, so damage cannot move a centre of power")
	_check(is_equal_approx(a.infrastructure, 0.5) and is_equal_approx(b.infrastructure, 1.0), "the system's infrastructure is the share of production it makes")
	_check(is_equal_approx(a.production_value, b.production_value), "and its production value is the undamaged figure")


## Assessing changes nothing: production and consumption are the same before and after,
## however damaged the places are.
func _check_one_way() -> void:
	var earth := _registry.location(&"earth")
	var before := _model.compute(earth)
	var food := _registry.commodity(&"food")
	var made := before.production_of(food)
	var used := before.consumption_of(food)
	var population := earth.population
	_assessor(func(_id: StringName) -> float: return 1.0, func(_id: StringName) -> float: return 0.0).assess_all()
	var after := _model.compute(earth)
	_check(after.production_of(food) == made and after.consumption_of(food) == used and earth.population == population,
			"assessing systems changes no production, consumption or population")


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
