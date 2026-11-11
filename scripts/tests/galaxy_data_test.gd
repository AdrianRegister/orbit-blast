extends SceneTree
## The galaxy is built from data/galaxy/galaxy_map.json by tools/galaxy_generator.gd.
## Checks that the table is sound, that the committed files are exactly what the
## table produces (so regenerating changes nothing), that hand built systems are
## left alone, that every system is valid, and that the galaxy stays fast to use.
## Run with:
##   Godot --headless --path . --script res://scripts/tests/galaxy_data_test.gd

var _failures: int = 0


func _init() -> void:
	var generator := GalaxyGenerator.new()
	var problems := generator.validate()
	_check(problems.is_empty(), "the galaxy table is sound: %s" % [problems.slice(0, 3)])
	var rows := generator.get_rows()
	_check(rows.size() >= 90, "the table lists the Federation core (%d systems)" % rows.size())

	# The committed files are exactly what the table produces.
	var files := generator.build()
	var different: Array[String] = []
	for path in files:
		if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != files[path]:
			different.append(path)
	_check(different.is_empty(), "regenerating changes no file (%d of %d differ: %s)" % [different.size(), files.size(), different.slice(0, 3)])
	var again := GalaxyGenerator.new().build()
	_check(again == files, "generation is deterministic")

	# Hand built systems are only listed, never written.
	var hand_built := 0
	for row in rows:
		if row.get("hand_built", false):
			hand_built += 1
			_check(not files.has("res://scenes/systems/generated/%s_system.tscn" % row["id"]), "%s is hand built and not regenerated" % row["id"])
	_check(hand_built == 8, "the eight original systems are hand built (%d)" % hand_built)

	# The galaxy that results is valid and every system is a proper system.
	var galaxy: Galaxy = load("res://resources/universe/galaxy.tres")
	var galaxy_problems := galaxy.validate()
	_check(galaxy_problems.is_empty(), "the galaxy validates: %s" % [galaxy_problems.slice(0, 3)])
	_check(galaxy.get_system_ids().size() == rows.size(), "every table row is in the galaxy")
	_check(galaxy.get_map_position(&"sol") == Vector2.ZERO, "Sol is the origin of the map")
	var worst_link := 0.0
	var links_ok := true
	for row in rows:
		if not galaxy.has_system(StringName(row["id"])) or galaxy.get_summary(StringName(row["id"])).system_name != row["name"]:
			links_ok = false
		for other in row["links"]:
			worst_link = maxf(worst_link, galaxy.get_map_position(StringName(row["id"])).distance_to(galaxy.get_map_position(StringName(other))))
	_check(links_ok, "every system is listed with the name the table gives it")
	_check(worst_link < 1200.0, "no link is absurdly long (longest %d map units)" % int(worst_link))
	_check(galaxy.get_faction_name(&"sol") == "Federation" and galaxy.get_faction(&"koria") == null, "the Federation core is Federation territory, Koria is unclaimed")

	var registry := ContentRegistry.new()
	_check(registry.problems.is_empty(), "the content registry finds everything without problems: %s" % [registry.problems.slice(0, 3)])
	var inhabited := 0
	var broken: Array[String] = []
	for location in registry.locations():
		var location_problems := location.validate()
		if not location_problems.is_empty():
			broken.append("%s: %s" % [location.id, location_problems])
		if ProceduralContractSource.is_inhabited(location):
			inhabited += 1
	_check(broken.is_empty(), "every location validates: %s" % [broken.slice(0, 2)])
	_check(inhabited >= 60, "there are plenty of inhabited places (%d)" % inhabited)
	var no_home := 0
	for id in galaxy.get_system_ids():
		if galaxy.get_summary(id).location_ids.is_empty():
			no_home += 1
	_check(no_home == 0, "every system has at least one body")
	# The inhabited flag on the map is honoured for generated systems.
	var mismatched: Array[String] = []
	for row in rows:
		if row.get("hand_built", false):
			continue
		if galaxy.is_inhabited(StringName(row["id"])) != row["inhabited"]:
			mismatched.append(row["id"])
	_check(mismatched.is_empty(), "generated systems are inhabited exactly where the map says: %s" % [mismatched.slice(0, 3)])

	# Speed: a fresh galaxy and registry, routes and nearby-system searches.
	var started := Time.get_ticks_msec()
	var fresh: Galaxy = load("res://resources/universe/galaxy.tres").duplicate(true)
	fresh.get_summary(&"sol")
	var index_ms := Time.get_ticks_msec() - started
	_check(index_ms < 4000, "indexing the galaxy is quick (%d ms)" % index_ms)
	started = Time.get_ticks_msec()
	for i in 200:
		fresh.get_reachable(&"sol", 4)
	var reach_ms := Time.get_ticks_msec() - started
	_check(reach_ms < 500, "200 searches for systems within 4 jumps take %d ms" % reach_ms)
	var reach := fresh.get_reachable(&"sol", 1)
	_check(reach.size() == fresh.get_neighbours(&"sol").size() + 1 and reach[&"sol"] == 0, "within 1 jump of Sol are Sol and its neighbours")
	_check(fresh.get_reachable(&"sol", 0).size() == 1 and fresh.get_reachable(&"nowhere", 3).is_empty(), "0 jumps is just the system; unknown systems reach nothing")

	print("")
	print("GALAXY DATA TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print("PASS  " if condition else "FAIL  ", label)
	if not condition:
		_failures += 1
