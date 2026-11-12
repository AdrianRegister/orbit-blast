extends SceneTree
## System classes: the class files, subtypes, what a system must have to be of a
## class, per-class object limits, and the table and galaxy agreeing. Run with:
##   Godot --headless --path . --script res://scripts/tests/system_class_test.gd </dev/null

var _failures: int = 0
var _registry: ContentRegistry
var _galaxy: Galaxy


func _init() -> void:
	_registry = ContentRegistry.new()
	_galaxy = load("res://resources/universe/galaxy.tres")

	_check_files()
	_check_subtypes()
	_check_fit()
	_check_object_limits()
	_check_table_and_galaxy()
	_check_capitals()

	print("")
	print("SYSTEM CLASS TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check_files() -> void:
	var files := DirAccess.get_files_at("res://resources/system_classes/")
	var count := 0
	for file in files:
		if file.ends_with(".tres"):
			count += 1
			var system_class := load("res://resources/system_classes/" + file) as SystemClass
			_check(system_class != null and system_class.validate().is_empty(), "%s is a valid class: %s" % [file, system_class.validate() if system_class != null else "not loaded"])
	_check(count >= 6, "there are at least the six starting classes (%d)" % count)
	_check(_registry.system_classes().size() == count, "the registry lists every class file")
	_check(_registry.problems.is_empty(), "the registry accepts all content: %s" % [_registry.problems])
	for id in [&"critical", &"economic_centre", &"military_centre", &"military_output", &"rural", &"frontier"]:
		_check(_registry.system_class(id) != null, "the class '%s' exists" % id)


func _check_subtypes() -> void:
	for system_class in _registry.system_classes():
		_check(system_class.is_a(system_class.id), "%s is a kind of itself" % system_class.id)
		if system_class.parent != null:
			_check(system_class.is_a(system_class.parent.id), "%s is a kind of %s" % [system_class.id, system_class.parent.id])
			_check(not system_class.parent.is_a(system_class.id), "but %s is not a kind of %s" % [system_class.parent.id, system_class.id])
			_check(system_class.can_be_centre() == system_class.parent.can_be_centre() or system_class.centre_of_power,
					"%s can be a centre if its parent can" % system_class.id)
		_check(not system_class.is_a(&"no_such_class"), "%s is not a kind of an unknown class" % system_class.id)
	var critical := _registry.system_class(&"critical")
	var economic := _registry.system_class(&"economic_centre")
	var military := _registry.system_class(&"military_centre")
	_check(economic.is_a(critical.id) and military.is_a(critical.id), "economic and military centres are critical systems")
	_check(economic.can_be_centre() and military.can_be_centre(), "subtypes of a critical system can be centres of power")
	_check(not _registry.system_class(&"rural").can_be_centre(), "a rural system cannot be a centre of power")
	_check(not _registry.system_class(&"frontier").can_be_centre(), "a frontier system cannot be a centre of power")

	var loop_a := SystemClass.new()
	loop_a.id = &"a"
	loop_a.display_name = "A"
	var loop_b := SystemClass.new()
	loop_b.id = &"b"
	loop_b.display_name = "B"
	loop_a.parent = loop_b
	loop_b.parent = loop_a
	_check(not loop_a.validate().is_empty(), "a class that is its own ancestor is rejected")
	_check(not loop_a.is_a(&"nothing"), "a loop in the data does not hang is_a")


func _check_fit() -> void:
	var economic := _registry.system_class(&"economic_centre")
	var military := _registry.system_class(&"military_centre")
	_check(economic.min_links >= 2, "an economic centre needs several links (%d)" % economic.min_links)
	_check(military.min_links == 0, "a military centre is exempt from the link minimum")
	_check(not economic.check_system(true, economic.min_links - 1).is_empty(), "too few links is rejected for an economic centre")
	_check(economic.check_system(true, economic.min_links).is_empty(), "exactly enough links is accepted")
	_check(not economic.check_system(false, 9).is_empty(), "an uninhabited system cannot be an economic centre")
	_check(military.check_system(true, 1).is_empty(), "a military centre with a single link is accepted")
	_check(not military.check_system(false, 3).is_empty(), "an uninhabited system cannot be a military centre")


func _check_object_limits() -> void:
	var plain := GalaxySystem.new()
	_check(plain.object_limit() == StarSystem.MAX_OBJECTS, "an unclassified system holds the ordinary number of objects")
	var big := GalaxySystem.new()
	big.system_class = _registry.system_class(&"critical")
	_check(big.object_limit() > StarSystem.MAX_OBJECTS and big.object_limit() <= StarSystem.ABSOLUTE_MAX_OBJECTS,
			"a critical system may hold more, within the absolute limit (%d)" % big.object_limit())
	var too_many := SystemClass.new()
	too_many.id = &"too_many"
	too_many.display_name = "Too many"
	too_many.max_objects = StarSystem.ABSOLUTE_MAX_OBJECTS + 1
	_check(not too_many.validate().is_empty(), "a class cannot allow more than the absolute limit")

	# A real system with the most objects: it fits its limit and not one below it.
	var most := 0
	var fullest: StarSystem
	for id in _galaxy.get_system_ids():
		var system: StarSystem = _galaxy.get_scene(id).instantiate()
		var count := system.get_node("Objects").get_child_count()
		if count > most:
			most = count
			if fullest != null:
				fullest.free()
			fullest = system
		else:
			system.free()
	_check(fullest.validate(most).is_empty(), "a system validates against a limit equal to its object count")
	_check(not fullest.validate(most - 1).is_empty(), "and fails against a limit one lower")
	_check(fullest.validate(99).is_empty(), "a huge limit is capped but still fine")
	fullest.free()


func _check_table_and_galaxy() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/galaxy/galaxy_map.json"))
	var with_class := 0
	for row in table["systems"]:
		var id := StringName(row["id"])
		var in_galaxy := _galaxy.get_system_class(id)
		if row.has("class"):
			with_class += 1
			_check(_registry.system_class(StringName(row["class"])) != null, "table class '%s' of %s exists" % [row["class"], id])
			_check(in_galaxy != null and in_galaxy.id == StringName(row["class"]), "the galaxy has the table's class for %s" % id)
		else:
			_check(in_galaxy == null, "%s has no class in the table or the galaxy" % id)
	_check(_galaxy.get_system_class(&"nowhere") == null, "an unknown system has no class")
	_check(_galaxy.validate().is_empty(), "the galaxy validates with its classes: %s" % [_galaxy.validate()])
	print("      %d systems have a class" % with_class)


func _check_capitals() -> void:
	for faction in _registry.factions():
		if faction.capital_system == &"":
			continue
		_check(_galaxy.has_system(faction.capital_system), "%s's capital is a system" % faction.display_name)
		_check(_galaxy.is_inhabited(faction.capital_system), "%s's capital is inhabited" % faction.display_name)
		var system_class := _galaxy.get_system_class(faction.capital_system)
		_check(system_class != null and system_class.can_be_centre(), "%s's capital has a class that can be a centre of power" % faction.display_name)

	# A capital that is not a centre is reported by the registry.
	var faction := Faction.new()
	faction.id = &"test_faction"
	faction.display_name = "Test"
	faction.capital_system = &"nowhere"
	var found := _registry_problems_for(faction)
	_check(not found.is_empty(), "a capital that is not a system is reported")


func _registry_problems_for(faction: Faction) -> Array[String]:
	var registry := ContentRegistry.new()
	registry._factions[faction.id] = faction
	return registry._check_capitals()


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
