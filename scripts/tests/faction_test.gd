extends SceneTree
## Factions are data: every faction reference resolves to a Faction resource, no
## hardcoded faction text is left, and renaming a faction is one edit. Run with:
##   Godot --headless --path . --script res://scripts/tests/faction_test.gd

var _failures: int = 0


func _init() -> void:
	var registry := ContentRegistry.new()
	var federation := registry.faction(&"faction_1")
	_check(federation != null and federation.display_name == "Federation" and federation.validate().is_empty(), "faction_1 is the Federation")
	for faction in registry.factions():
		_check(faction.validate().is_empty(), "%s is valid" % faction.id)

	# Nothing refers to a faction by text any more.
	var leftovers: Array[String] = []
	for dir in ["res://resources/locations", "res://resources/ships", "res://resources/universe", "res://scenes/systems", "res://scripts"]:
		_scan(dir, leftovers)
	_check(leftovers.is_empty(), "no hardcoded TestFaction_1 text remains: %s" % [leftovers.slice(0, 3)])

	# Everything that has a faction has a real one.
	var unknown := 0
	var owned := 0
	for location in registry.locations():
		if location.faction != null:
			owned += 1
			if registry.faction(location.faction.id) == null:
				unknown += 1
	var galaxy: Galaxy = load("res://resources/universe/galaxy.tres")
	for id in galaxy.get_system_ids():
		var faction := galaxy.get_claim(id)
		if faction != null and registry.faction(faction.id) == null:
			unknown += 1
	for ship in ["federation_frigate", "federation_fighter", "federation_heavy_fighter"]:
		_check(registry.ship_stats(ship).faction == federation, "%s belongs to the Federation resource" % ship)
	_check(owned > 0 and unknown == 0, "every owned location and system uses a registered faction (%d owned)" % owned)

	# Renaming a faction is one edit and shows everywhere that reads the name.
	var earth := registry.location(&"earth")
	var before := earth.get_faction_name()
	federation.display_name = "Union"
	_check(earth.get_faction_name() == "Union" and galaxy.get_claim(&"sol").display_name == "Union" and registry.ship_stats(&"federation_frigate").get_faction_name() == "Union", "renaming the faction shows in locations, systems and ships")
	_check(earth.faction_id() == &"faction_1", "...while its id, used for comparisons, is unchanged")
	federation.display_name = before

	print("")
	print("FACTION TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _scan(dir: String, found: Array[String]) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["tres", "tscn", "gd"] and not file.ends_with("faction_test.gd"):
			if "TestFaction_1" in FileAccess.get_file_as_string(dir + "/" + file):
				found.append(dir + "/" + file)
	for sub in DirAccess.get_directories_at(dir):
		_scan(dir + "/" + sub, found)


func _check(condition: bool, label: String) -> void:
	print("PASS  " if condition else "FAIL  ", label)
	if not condition:
		_failures += 1
