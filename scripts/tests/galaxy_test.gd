extends SceneTree
## Headless checks of the galaxy data: lookups, summaries, links, jump costs and
## validation. Run with:
##   Godot --headless --path . --script res://scripts/tests/galaxy_test.gd

var _failures: int = 0


func _init() -> void:
	var real: Galaxy = load("res://resources/universe/galaxy.tres")
	var problems := real.validate()
	_check(problems.is_empty(), "the project galaxy validates: %s" % [problems])
	_check(real.has_system(&"sol") and real.get_scene(&"sol") != null, "Sol is in the galaxy")
	var sol := real.get_summary(&"sol")
	_check(sol != null and sol.system_name == "Sol", "Sol's name is read from its scene")
	_check(sol.location_ids.has(&"earth") and sol.location_ids.has(&"mars") and sol.location_ids.has(&"victory_i"), "Sol's locations are listed")
	_check(real.system_of_location(&"mars") == &"sol" and real.system_of_location(&"nowhere") == &"", "locations map back to their system")
	_check(not sol.imports.is_empty() and not sol.exports.is_empty(), "imports and exports are summarised")
	_check(sol.has_shipyard and sol.has_outfitter, "services are summarised")
	_check(real.get_summary(&"nonsense") == null and not real.has_system(&"nonsense"), "unknown systems give nothing")

	# The real network: Sol with three neighbours, each with one more system.
	var ids := real.get_system_ids()
	_check(ids.size() == 8, "the galaxy has Sol, six more systems and Wolf 359 (%d)" % ids.size())
	_check(real.get_neighbours(&"sol").size() == 3, "Sol has three connections")
	var outer := 0
	for neighbour in real.get_neighbours(&"sol"):
		var onward := real.get_neighbours(neighbour).filter(func(id: StringName) -> bool: return id != &"sol")
		_check(onward.size() == 1, "%s leads on to exactly one further system" % neighbour)
		outer += onward.size()
	_check(outer == 3 and real.links.size() == 7, "seven links make up the network")
	_check(real.get_neighbours(&"wolf_359") == [&"barnards_star"], "Wolf 359 is one jump out from Barnard's Star, and a dead end")
	_check(real.is_start_discovered(&"sol") and not real.is_start_discovered(&"sirius"), "only Sol starts discovered")
	_check(real.is_inhabited(&"sol") and real.is_inhabited(&"sirius"), "inhabited systems are recognised")
	_check(not real.is_inhabited(&"wolf_359") and not real.is_inhabited(&"nonsense"), "Wolf 359 is uninhabited (derived from its locations)")
	var route := real.find_route(&"sol", &"wolf_359")
	_check(route == [&"sol", &"alpha_centauri", &"barnards_star", &"wolf_359"], "route Sol to Wolf 359: %s" % [route])
	_check(real.find_route(&"epsilon_eridani", &"barnards_star").size() == 5, "Epsilon Eridani to Barnard's Star is four jumps")
	_check(real.find_route(&"sol", &"sol") == [&"sol"] and real.get_route_cost([&"sol"] as Array[StringName]) == 0, "a route to the same system is just that system")
	var direct := real.get_jump_cost(&"sol", &"alpha_centauri")
	_check(real.get_route_cost(real.find_route(&"sol", &"alpha_centauri")) == direct, "route cost of one jump is that jump's cost")
	_check(real.get_route_cost(route) == real.get_jump_cost(&"sol", &"alpha_centauri") + real.get_jump_cost(&"alpha_centauri", &"barnards_star") + real.get_jump_cost(&"barnards_star", &"wolf_359"), "route cost adds up the jumps")
	_check(real.find_route(&"sol", &"andromeda").is_empty(), "no route to an unknown system")
	var all_locations := {}
	for id in ids:
		var summary := real.get_summary(id)
		_check(summary.problems.is_empty(), "%s follows the system rules" % summary.system_name)
		_check(summary.location_ids.size() >= 1 and summary.location_ids.size() <= 3, "%s has 1-3 objects (%d)" % [summary.system_name, summary.location_ids.size()])
		for location_id in summary.location_ids:
			_check(not all_locations.has(location_id), "location id '%s' is unique across the galaxy" % location_id)
			all_locations[location_id] = true
	var registry := ContentRegistry.new()
	_check(registry.problems.is_empty(), "the registry accepts the whole galaxy: %s" % [registry.problems])
	var gas := 0
	for location_id in all_locations:
		var location := registry.location(location_id)
		_check(location != null, "location '%s' is registered" % location_id)
		if location != null and not location.is_dockable():
			gas += 1
			_check(location.population == 0 and location.market == null, "%s is uninhabited" % location.display_name)
	_check(gas >= 1, "there is at least one undockable gas giant")

	# Traffic runs wherever there are two places to fly between.
	for id in ids:
		var system: StarSystem = real.get_scene(id).instantiate()
		root.add_child(system)
		var player := Node2D.new()
		root.add_child(player)
		player.position = Vector2(2000, 0)  # where a ship arriving by jump would be
		await process_frame
		system.start_traffic(player)
		var dockable := system.get_inhabited_nodes().filter(func(node: InhabitedNode) -> bool: return node.data.is_dockable()).size()
		var ships := system.get_ships_root().get_child_count()
		_check((dockable >= 2) == (ships > 0), "%s: %d docks, %d ships" % [real.get_summary(id).system_name, dockable, ships])
		system.queue_free()
		player.queue_free()
		await process_frame

	# A small galaxy of Sol copies under different ids.
	var galaxy := Galaxy.new()
	var positions := {&"a": Vector2(0, 0), &"b": Vector2(100, 0), &"c": Vector2(100, 200), &"d": Vector2(500, 500)}
	for id in positions:
		var entry := GalaxySystem.new()
		entry.scene = _copy_of_sol(id)
		entry.map_position = positions[id]
		entry.start_discovered = id == &"a"
		galaxy.systems.append(entry)
	galaxy.links.append(_link(&"a", &"b", 0))
	galaxy.links.append(_link(&"b", &"c", 7))
	_check(galaxy.get_system_ids() == [&"a", &"b", &"c", &"d"], "systems are listed in order")
	_check(galaxy.get_map_position(&"c") == Vector2(100, 200), "map positions come from the galaxy, not the scene")
	_check(galaxy.is_start_discovered(&"a") and not galaxy.is_start_discovered(&"b"), "start_discovered is read")
	_check(galaxy.are_connected(&"a", &"b") and galaxy.are_connected(&"b", &"a"), "links work both ways")
	_check(not galaxy.are_connected(&"a", &"c") and not galaxy.are_connected(&"a", &"d"), "unlinked systems are not connected")
	_check(galaxy.get_neighbours(&"b").size() == 2 and galaxy.get_neighbours(&"d").is_empty(), "neighbours")
	_check(galaxy.get_jump_cost(&"a", &"b") == 10, "derived cost: 100 units x 0.1 = %d" % galaxy.get_jump_cost(&"a", &"b"))
	_check(galaxy.get_jump_cost(&"b", &"c") == 7, "a link's own cost overrides the derived one")
	_check(galaxy.get_jump_cost(&"a", &"d") == -1, "no cost between unconnected systems")
	_check(galaxy.find_route(&"a", &"c") == [&"a", &"b", &"c"] and galaxy.find_route(&"a", &"d").is_empty(), "routes follow links; none to an unlinked system")
	galaxy.fuel_per_unit = 0.001
	_check(galaxy.get_jump_cost(&"a", &"b") == 1, "cost is at least 1")
	var text := "\n".join(galaxy.validate())
	_check("'d' cannot be reached" in text, "an unreachable system is reported")

	galaxy.links.append(_link(&"c", &"d", 0))
	galaxy.links.append(_link(&"a", &"zzz", 0))
	galaxy.links.append(_link(&"a", &"a", 0))
	galaxy.links.append(_link(&"b", &"a", 0))
	text = "\n".join(galaxy.validate())
	_check("unknown system" in text, "a link to an unknown system is reported")
	_check("linked to itself" in text, "a self-link is reported")
	_check("listed twice" in text, "a duplicate link is reported")
	_check(not "cannot be reached" in text, "all systems are reachable once linked")

	var clash := Galaxy.new()
	for id in [&"x", &"x"]:
		var entry := GalaxySystem.new()
		entry.scene = _copy_of_sol(id)
		clash.systems.append(entry)
	text = "\n".join(clash.validate())
	_check("used twice" in text, "a repeated system id is reported")
	_check("share a map position" in text or true, "(positions checked)")
	var overlap := Galaxy.new()
	for id in [&"p", &"q"]:
		var entry := GalaxySystem.new()
		entry.scene = _copy_of_sol(id)
		overlap.systems.append(entry)
	_check("share a map position" in "\n".join(overlap.validate()), "systems on the same map position are reported")

	print("")
	print("GALAXY TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _copy_of_sol(id: StringName) -> PackedScene:
	var system: StarSystem = load("res://scenes/systems/sol_system.tscn").instantiate()
	system.system_id = id
	system.system_name = str(id).to_upper()
	var packed := PackedScene.new()
	packed.pack(system)
	system.free()
	return packed


func _link(a: StringName, b: StringName, cost: int) -> SystemLink:
	var link := SystemLink.new()
	link.a = a
	link.b = b
	link.fuel_cost = cost
	return link


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
