extends SceneTree
## The population the player reads: how it is scaled (location, profile, class, default),
## rounded and written, that the real population and the economy are untouched, that the
## numbers fit the intended tiers, and that the target panel shows it. Run with:
##   Godot --headless --path . --script res://scripts/tests/population_display_test.gd </dev/null

var _failures: int = 0
var _registry: ContentRegistry
var _galaxy: Galaxy
var _rules: PopulationDisplayRules
var _display: PopulationDisplay


func _init() -> void:
	_registry = ContentRegistry.new()
	_galaxy = load("res://resources/universe/galaxy.tres")
	_rules = load("res://resources/economy/population_display_rules.tres")
	_display = PopulationDisplay.new(_galaxy, _rules)

	_check_rules()
	_check_format()
	_check_scales()
	_check_tiers()
	_check_untouched()
	await _check_panel()

	print("")
	print("POPULATION DISPLAY TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _location(id: StringName) -> InhabitedData:
	return _registry.location(id)


func _class_of(location: InhabitedData) -> SystemClass:
	return _galaxy.get_system_class(_galaxy.system_of_location(location.id))


func _check_rules() -> void:
	_check(_rules != null and _rules.validate().is_empty(), "the display rules are valid: %s" % [_rules.validate()])
	var bad := PopulationDisplayRules.new()
	bad.default_planet_scale = 0.0
	_check(not bad.validate().is_empty(), "a zero default scale is rejected")
	var no_class := PopulationDisplayRules.new()
	no_class.entries = [PopulationScaleEntry.new()]
	_check(not no_class.validate().is_empty(), "an entry with no class is rejected")
	var critical := _registry.system_class(&"critical")
	var economic := _registry.system_class(&"economic_centre")
	_check(_rules.entry_for(economic) == _rules.entry_for(critical) and _rules.entry_for(critical) != null,
			"a subtype with no entry of its own uses its parent's")
	_check(_rules.entry_for(null) == null, "no class, no entry")
	for profile_file in DirAccess.get_files_at("res://resources/economy/profiles/"):
		var profile := load("res://resources/economy/profiles/" + profile_file) as EconomyProfile
		_check(profile.validate().is_empty(), "%s is still a valid profile" % profile.id)


func _check_format() -> void:
	_check(PopulationDisplay.format_count(2600000000) == "2.6 billion", "billions: 2.6 billion")
	_check(PopulationDisplay.format_count(1000000000) == "1 billion", "a round billion has no decimal")
	_check(PopulationDisplay.format_count(320000000) == "320 million", "hundreds of millions: 320 million")
	_check(PopulationDisplay.format_count(96000000) == "96 million", "tens of millions: 96 million")
	_check(PopulationDisplay.format_count(4800000) == "4.8 million", "millions with a decimal: 4.8 million")
	_check(PopulationDisplay.format_count(1000000) == "1 million", "a round million: 1 million")
	_check(PopulationDisplay.format_count(480000) == "480,000", "below a million: full digits with commas")
	_check(PopulationDisplay.format_count(0) == "0", "zero")
	_check(PopulationDisplay.round_significant(2550000000.0, 2) == 2600000000, "2.55 billion rounds to 2.6 billion")
	_check(PopulationDisplay.round_significant(323368000.0, 2) == 320000000, "323,368,000 rounds to 320 million")
	_check(PopulationDisplay.round_significant(999999.0, 2) == 1000000, "999,999 rounds up to a million")
	_check(PopulationDisplay.round_significant(7.0, 2) == 7 and PopulationDisplay.round_significant(0.0, 2) == 0, "small and zero values are left alone")
	_check(PopulationDisplay.round_significant(1234567.0, 3) == 1230000, "the significant figures are configurable")
	_check(PopulationDisplay.format_count(PopulationDisplay.round_significant(9950000.0, 2)) == "10 million", "9.95 million rounds to 10 million, not 10.0")


## Scales apply in order: the location, its profile, its class, the default.
func _check_scales() -> void:
	var aurelia := _location(&"aurelia").duplicate() as InhabitedData  # a planet in a critical system
	var critical_planet: float = _rules.entry_for(_class_of(aurelia)).planet_scale
	_check(_display.scale_for(aurelia) == critical_planet, "a planet in a critical system takes the class's planet scale (%s)" % critical_planet)
	_check(_display.display_population(aurelia) == PopulationDisplay.round_significant(aurelia.population * critical_planet, 2),
			"and its displayed population is the scaled, rounded one")

	aurelia.population_display_scale = 7.5
	_check(_display.scale_for(aurelia) == 7.5, "a location's own scale beats its class")
	var profile := EconomyProfile.new()
	profile.id = &"test_profile"
	profile.population_display_scale = 3.0
	var with_profile := _location(&"aurelia").duplicate() as InhabitedData
	with_profile.economy_profile = profile
	_check(_display.scale_for(with_profile) == 3.0, "an economy profile's scale beats its class")
	with_profile.population_display_scale = 11.0
	_check(_display.scale_for(with_profile) == 11.0, "and the location's own beats the profile's")
	profile.population_display_scale = 0.0
	with_profile.population_display_scale = 0.0
	_check(_display.scale_for(with_profile) == critical_planet, "a profile with no scale falls through to the class")

	# A station and a planet in the same class are scaled separately.
	var station := _location(&"victory_i")
	_check(_display.scale_for(station) == _rules.entry_for(_class_of(station)).station_scale, "a station takes the class's station scale")
	_check(_display.scale_for(station) != critical_planet, "different from a planet's")

	# No class: the defaults. Use a location copy placed in a system with no class.
	var unclassified: InhabitedData
	for location in _registry.locations():
		if location.population > 0 and _class_of(location) == null:
			unclassified = location
			break
	_check(unclassified != null, "setup: found a populated location in an unclassified system")
	if unclassified != null:
		var expected := _rules.default_station_scale if not unclassified is PlanetData else _rules.default_planet_scale
		var has_scale := unclassified.population_display_scale > 0.0 or (unclassified.get_economy_profile() != null and unclassified.get_economy_profile().population_display_scale > 0.0)
		if not has_scale:
			_check(_display.scale_for(unclassified) == expected, "an unclassified system uses the default scale")


## The tiers asked for: Earth in billions, core planets tens to hundreds of millions, rural
## millions, frontier and military stations hundreds of thousands.
func _check_tiers() -> void:
	var earth := _location(&"earth")
	_check(_display.display_population(earth) >= 1000000000, "Earth is in the billions (%s)" % _display.text_for(earth))
	var critical := _registry.system_class(&"critical")
	var counts := {"core": 0, "rural": 0, "frontier": 0, "military": 0}
	for location in _registry.locations():
		if location.population <= 0 or not location.is_dockable():
			continue
		var system_class := _class_of(location)
		var shown := _display.display_population(location)
		var overridden := location.population_display_scale > 0.0
		var profile := location.get_economy_profile()
		var is_planet := location is PlanetData
		if profile != null and (profile.id == &"military" or profile.id == &"arsenal"):
			counts["military"] += 1
			_check(shown >= 100000 and shown <= 1000000, "%s (a military station) reads hundreds of thousands: %s" % [location.display_name, _display.text_for(location)])
		elif system_class != null and system_class.is_a(critical.id) and is_planet and not overridden and location.population >= 1000000:
			counts["core"] += 1
			_check(shown >= 10000000 and shown <= 1000000000, "%s (a core planet) reads tens to hundreds of millions: %s" % [location.display_name, _display.text_for(location)])
		elif system_class != null and system_class.id == &"rural" and is_planet and location.population >= 250000:
			counts["rural"] += 1
			_check(shown >= 1000000 and shown < 100000000, "%s (a rural planet) reads in the millions: %s" % [location.display_name, _display.text_for(location)])
		elif system_class != null and system_class.id == &"frontier":
			counts["frontier"] += 1
			_check(shown >= 50000 and shown < 1000000, "%s (frontier) reads below a million: %s" % [location.display_name, _display.text_for(location)])
	print("      checked %d core planets, %d rural planets, %d frontier places, %d military stations" % [counts["core"], counts["rural"], counts["frontier"], counts["military"]])
	_check(counts["core"] >= 5 and counts["rural"] >= 5 and counts["frontier"] >= 3 and counts["military"] >= 5, "setup: every tier has places to check")


## Display only: the real population, and everything the economy works out from it, is unchanged.
func _check_untouched() -> void:
	var model := EconomyModel.new(load(EconomyModel.DEFAULT_CONFIG), _registry.commodities())
	var earth := _location(&"earth")
	var food := _registry.commodity(&"food")
	var before_population := earth.population
	var before_made := model.compute(earth).production_of(food)
	var before_used := model.compute(earth).consumption_of(food)
	for location in _registry.locations():
		_display.text_for(location)
	_check(earth.population == 8500000 and earth.population == before_population, "Earth's real population is still 8.5 million")
	_check(model.compute(earth).production_of(food) == before_made and model.compute(earth).consumption_of(food) == before_used,
			"and so is what it makes and uses")
	var assessor := SystemAssessor.new(_galaxy, _registry, model, load("res://resources/military/military_value_rules.tres"))
	var summary := _galaxy.get_summary(&"sol")
	var total := 0
	for location_id in summary.location_ids:
		var location := _location(location_id)
		if location.is_dockable() and location.population > 0:
			total += location.population
	_check(assessor.assess(&"sol").population == total, "a system's assessed population is still the sum of the real ones")


func _check_panel() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var earth: Targetable
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name == "Earth":
			earth = t
	_check(earth != null, "found Earth")
	var rows := earth.get_detail_rows()
	var population_rows := rows.filter(func(row: Array) -> bool: return row[0] == "POPULATION")
	_check(population_rows.size() == 1 and population_rows[0][1] == "2.6 billion", "Earth's target panel reads 2.6 billion (%s)" % [population_rows])
	_check(rows.filter(func(row: Array) -> bool: return row[0] == "DAMAGE").size() == 1, "and the damage row is still there")
	_check(earth.details.get_rows().filter(func(row: Array) -> bool: return row[0] == "POPULATION")[0][1] == "8,500,000",
			"the location's own row (no lookup) still shows the real number")

	var hud: Hud = main.get_node("Hud")
	main.get_node("Targeting").select(earth)
	await process_frame
	var panel_text := ""
	for row in hud.get_node("%DetailRows").get_children():
		if row is InfoRow and row.caption == "POPULATION":
			panel_text = row.get_node("%Value").text
	_check(panel_text == "2.6 billion", "the HUD shows it (%s)" % panel_text)
	var empty := PlanetData.new()
	empty.id = &"test_empty"
	empty.population = 0
	_check(main._extra_target_rows(empty).is_empty(), "a place nobody lives in gets no displayed population or damage row (its own row reads 0)")
	main.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
