extends SceneTree
## Headless test of inter-system travel through the real game scene: jump
## rules, discovery, the transition itself, what is preserved, and saving.
##   Godot --headless --path . --script res://scripts/tests/travel_test.gd

const PATH := "user://travel_test.json"

var _failures: int = 0


func _init() -> void:
	_clean()
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var big_hold: ShipStats = load("res://resources/ships/shuttle_stats.tres").duplicate()
	big_hold.cargo_capacity = 500
	main.starting_ship_stats = big_hold
	main.get_node("Save").save_path = PATH
	root.add_child(main)
	await process_frame
	await process_frame

	var travel: TravelManager = main.get_node("Travel")
	var economy: EconomyManager = main.get_node("Economy")
	var contracts: ContractManager = main.get_node("Contracts")
	var ships: ShipManager = main.get_node("Ships")
	var saves: SaveManager = main.get_save_manager()
	var ship := main.get_player_ship()
	var player := main.get_player_data()
	var earth: InhabitedData = load("res://resources/locations/earth.tres")
	var food: Commodity = load("res://resources/commodities/food.tres")

	# --- Discovery to begin with.
	_check(travel.is_discovered(&"sol") and travel.get_discovered().size() == 1, "a new game knows only Sol")

	# --- The rules.
	var far := 3300.0
	var check := travel.check_jump(&"nowhere", far, false)
	_check(not check.ok and not check.reachable, "unknown system refused: %s" % check.reason)
	check = travel.check_jump(&"sol", far, false)
	_check(not check.ok and "already" in check.reason, "the current system is refused: %s" % check.reason)
	check = travel.check_jump(&"barnards_star", far, false)
	_check(not check.ok and not check.reachable, "a disconnected system is refused: %s" % check.reason)
	check = travel.check_jump(&"sirius", far, true)
	_check(not check.ok and check.reachable and "Depart" in check.reason, "docked: %s" % check.reason)
	check = travel.check_jump(&"sirius", 1000.0, false)
	_check(not check.ok and check.reachable and "centre" in check.reason, "too close to the centre: %s" % check.reason)
	check = travel.check_jump(&"sirius", far, false)
	_check(check.ok and check.cost > 0 and check.required_distance == 2000.0, "a linked system far enough out is allowed (cost %d)" % check.cost)
	_check(not main.jump_to(&"sirius").ok and main.get_system().system_id == &"sol", "Main.jump_to refuses from the middle of Sol and stays put")

	# --- State that must survive the jump.
	economy.buy(economy.get_market(earth), food, 25)
	contracts.accept(contracts.get_available(earth)[0], earth)
	ships.rename(player.fleet.get_active().id, "Wanderer")
	player.fleet.get_active().upgrades.append(load("res://resources/upgrades/engine_1.tres"))
	var credits := player.credits
	var cargo_used := player.cargo.get_used()
	var contract_count := contracts.get_active().size()
	var old_system := main.get_system()
	var old_ships := old_system.get_ships_root().get_child_count()
	_check(old_ships > 0, "Sol has NPC traffic before the jump (%d)" % old_ships)

	# --- The jump.
	ship.global_position = Vector2(3300, 100)
	ship.velocity = Vector2.ZERO
	ship.rotation = -PI / 2.0  # pointing up
	var departure_heading := ship.rotation
	var result := main.jump_to(&"sirius")
	await process_frame
	await process_frame
	_check(result.ok, "the jump to Sirius is made")
	var system := main.get_system()
	_check(system.system_id == &"sirius" and system != old_system, "Sirius is now loaded")
	_check(not is_instance_valid(old_system) or old_system.is_queued_for_deletion(), "Sol was unloaded")
	var system_count := 0
	for child in main.get_children():
		if child is StarSystem:
			system_count += 1
	_check(system_count == 1, "only one star system exists")
	_check(absf(ship.global_position.length() - system.jump_radius) < 40.0, "the ship arrives on the edge of the system (%d px out)" % ship.global_position.length())
	_check(absf(angle_difference(ship.rotation, departure_heading)) < 0.001, "the ship keeps its heading")
	var heading := Vector2.from_angle(departure_heading)
	_check(ship.global_position.normalized().dot(-heading) > 0.999, "it enters from the opposite side to the way it was pointing (pointing up, in from the bottom)")
	_check(ship.velocity.normalized().dot(heading) > 0.999 and ship.velocity.length() > 0.0, "...flying the same way")
	_check(travel.is_discovered(&"sirius") and travel.get_discovered().size() == 2, "Sirius is discovered on arrival")
	_check(player.credits == credits and player.cargo.get_used() == cargo_used, "credits and cargo are unchanged")
	_check(contracts.get_active().size() == contract_count, "contracts are unchanged")
	_check(player.fleet.get_active().ship_name == "Wanderer" and player.fleet.get_active().upgrades.size() == 1, "the ship and its upgrades are unchanged")
	_check(system.get_ships_root().get_child_count() > 0, "Sirius has fresh NPC traffic (%d)" % system.get_ships_root().get_child_count())
	_check(main.get_node("Targeting").get_node_or_null(".") != null, "targeting still works")
	_check(main._get_system_name_of(load("res://resources/locations/mars.tres")) == "Sol", "contract destinations in other systems still name their system")

	# --- Along the network, and no shortcuts.
	_check(not travel.check_jump(&"procyon", 3300.0, false).reachable, "Sirius does not connect to Procyon")
	ship.global_position = Vector2(0, 3400)
	_check(main.jump_to(&"tau_ceti").ok, "Sirius to Tau Ceti")
	await process_frame
	_check(main.get_system().system_id == &"tau_ceti" and travel.get_discovered().size() == 3, "arrived at Tau Ceti; three systems discovered")
	_check(main.get_system().get_ships_root().get_child_count() == 0, "Tau Ceti has only one place to dock, so no traffic")

	# --- Saving and loading with discovery.
	_check(saves.save_game(), "save in Tau Ceti")
	travel._discovered.clear()
	travel._discovered[&"tau_ceti"] = true
	_check(main.load_game()["ok"], "load it again")
	_check(travel.get_discovered().size() == 3 and travel.is_discovered(&"sirius") and travel.is_discovered(&"sol"), "discovery was saved and restored")
	_check(main.get_system().system_id == &"tau_ceti", "and the player is back in Tau Ceti")
	_check(player.credits == credits and player.fleet.get_active().ship_name == "Wanderer", "credits and ship also restored")

	# --- Docked in another system.
	var aurelia := _find("Aurelia")
	ship.global_position = aurelia.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	main.get_node("Targeting").select(aurelia)
	main.get_node("Docking").try_dock()
	await process_frame
	_check(not main.jump_to(&"sirius").ok, "cannot jump while docked")
	_check(saves.save_game(), "save while docked at Aurelia")
	_check(main.load_game()["ok"], "load it")
	await process_frame
	_check(main.get_docked_target() != null and main.get_docked_target().target_name == "Aurelia", "restored docked at Aurelia")
	main.get_node("Docking").undock()

	# --- Old saves (no galaxy section) and bad data.
	var document := saves.build_document()
	document.erase("galaxy")
	_write(PATH, JSON.stringify(document))
	_check(main.load_game()["ok"], "a save without a galaxy section loads")
	_check(travel.is_discovered(&"sol") and travel.is_discovered(&"tau_ceti"), "it defaults to Sol plus the current system")
	_check(travel.get_discovered().size() == 2, "...and nothing else")
	document["galaxy"] = {"discovered": ["sol", "andromeda"]}
	_write(PATH, JSON.stringify(document))
	_check(not main.load_game()["ok"], "a discovered system that does not exist is refused")
	document["galaxy"] = {"discovered": "all"}
	_write(PATH, JSON.stringify(document))
	_check(not main.load_game()["ok"], "a discovered list of the wrong type is refused")

	_clean()
	main.queue_free()
	await process_frame
	print("")
	print("TRAVEL TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _find(target_name: String) -> Targetable:
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name == target_name:
			return t
	return null


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
