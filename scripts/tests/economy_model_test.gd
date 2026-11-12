extends SceneTree
## The economic model: what a settlement makes and uses follows from its
## population, planet type and profile. Run with:
##   Godot --headless --path . --script res://scripts/tests/economy_model_test.gd </dev/null

var _failures: int = 0
var _registry: ContentRegistry
var _model: EconomyModel
var _food: Commodity
var _ore: Commodity
var _machinery: Commodity


func _init() -> void:
	_registry = ContentRegistry.new()
	_model = EconomyModel.new(load(EconomyModel.DEFAULT_CONFIG), _registry.commodities())
	_food = _registry.commodity(&"food")
	_ore = _registry.commodity(&"ore")
	_machinery = _registry.commodity(&"machinery")

	_check_data()
	_check_scaling()
	_check_profiles()
	_check_specialties()
	_check_no_economy()
	_check_cache()
	_check_consumers()

	print("")
	print("ECONOMY MODEL TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _planet(type_id: String, population: int) -> PlanetData:
	var planet := PlanetData.new()
	planet.id = StringName("test_" + type_id)
	planet.display_name = type_id
	planet.population = population
	planet.planet_type = load("res://resources/planet_types/%s.tres" % type_id)
	return planet


func _check_data() -> void:
	_check(_model.config.validate().is_empty(), "the economy config is valid")
	var all_valid := true
	for file in DirAccess.get_files_at("res://resources/economy/profiles/"):
		var profile := load("res://resources/economy/profiles/" + file) as EconomyProfile
		if profile == null or not profile.validate().is_empty():
			all_valid = false
	_check(all_valid, "every profile is valid")
	for type_id in ["terrestrial", "jungle", "ocean", "desert", "rocky", "moon", "arctic", "resort"]:
		var type: PlanetType = load("res://resources/planet_types/%s.tres" % type_id)
		_check(type.economy_profile != null, "planet type %s has a profile" % type_id)
	_check(_food.civilian_demand > 0.0, "people need food")
	_check(_ore.civilian_demand == 0.0, "people do not need ore")


func _check_scaling() -> void:
	var small := _model.compute(_planet("terrestrial", 20000), false)
	var big := _model.compute(_planet("terrestrial", 5000000), false)
	_check(big.production_of(_food) > small.production_of(_food) * 10.0, "a bigger population makes much more")
	_check(big.consumption_of(_food) > small.consumption_of(_food) * 10.0, "a bigger population uses much more")
	_check(small.has_economy(), "a small settlement still has an economy")
	var tiny := _model.compute(_planet("terrestrial", 50), false)
	var floor_scale := _model.compute(_planet("terrestrial", 1), false)
	_check(is_equal_approx(tiny.production_of(_food), floor_scale.production_of(_food)),
			"below the minimum scale the rates stop shrinking")
	var ref := _planet("terrestrial", _model.config.reference_population)
	var at_ref := _model.compute(ref, false)
	_check(is_equal_approx(at_ref.production_of(_food), 120.0), "reference population gets the profile rates exactly")
	_check(is_equal_approx(at_ref.consumption_of(_food), 40.0), "reference population gets the civilian rates exactly")


func _check_profiles() -> void:
	var farm := _model.compute(_planet("terrestrial", 1000000), false)
	_check(farm.is_export(_food), "an agricultural world exports food")
	_check(farm.is_import(_machinery), "an agricultural world imports machinery")
	var mine := _model.compute(_planet("rocky", 1000000), false)
	_check(mine.is_export(_ore), "a mining world exports ore")
	_check(mine.is_import(_food), "a mining world imports food")
	var factory := _model.compute(_planet("desert", 1000000), false)
	_check(factory.is_export(_machinery), "an industrial world exports machinery")
	_check(factory.is_import(_ore), "an industrial world imports ore")
	# Changing the planet type changes the goods with no other edit.
	var planet := _planet("terrestrial", 1000000)
	var before := _model.of(planet)
	planet.planet_type = load("res://resources/planet_types/rocky.tres")
	var after := _model.of(planet)
	_check(before.is_export(_food) and after.is_import(_food), "changing the planet type changes what it trades")
	# A location's own profile overrides its planet type.
	planet.economy_profile = load("res://resources/economy/profiles/agricultural.tres")
	_check(_model.of(planet).is_export(_food), "a location's own profile overrides its planet type")
	# A station with no profile uses the default station profile.
	var station := InhabitedData.new()
	station.id = &"test_station"
	station.population = 5000
	var economy := _model.compute(station, false)
	_check(economy.profile == _model.config.station_profile, "a station gets the station profile")
	_check(economy.has_economy(), "a station has an economy")


func _check_specialties() -> void:
	var planet := _planet("terrestrial", 300000)
	var plain := _model.compute(planet, false)
	_check(not plain.is_export(_ore), "setup: no ore export without a specialty")
	planet.exported_goods = [_ore]
	var with_ore := _model.compute(planet)
	_check(with_ore.is_export(_ore), "a listed export becomes an export")
	planet.exported_goods = [_food]
	planet.imported_goods = []
	var food := _model.compute(planet)
	_check(food.production_of(_food) > plain.production_of(_food), "a listed export of a produced good makes more of it")
	planet.exported_goods = []
	planet.imported_goods = [_food]
	var no_food := _model.compute(planet)
	_check(no_food.is_import(_food), "a listed import becomes an import")
	_check(no_food.production_of(_food) == 0.0, "a listed import stops production of it")


func _check_no_economy() -> void:
	_check(not _model.compute(_planet("terrestrial", 0)).has_economy(), "an uninhabited world has no economy")
	var giant := PlanetData.new()
	giant.id = &"test_giant"
	giant.dockable = false
	giant.population = 0
	giant.planet_type = load("res://resources/planet_types/gas_giant_red.tres")
	_check(not _model.compute(giant).has_economy(), "a gas giant has no economy")
	_check(not _model.of(null).has_economy(), "no location, no economy")


func _check_cache() -> void:
	var planet := _planet("jungle", 800000)
	var first := _model.of(planet)
	_check(_model.of(planet) == first, "an unchanged location gives the cached economy")
	planet.population = 1600000
	var second := _model.of(planet)
	_check(second != first and second.production_of(_food) > first.production_of(_food),
			"changing the population recomputes the economy")


func _check_consumers() -> void:
	var earth: InhabitedData = _registry.location(&"earth")
	var rows := earth.get_rows()
	var exports_text := ""
	for row in rows:
		if row[0] == "EXPORTS":
			exports_text = row[1]
	_check(exports_text != "" and exports_text != "None", "the settlement rows list derived exports")
	var context := ContractContext.new()
	_check(context.economy != null, "contract context has an economy model")


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
