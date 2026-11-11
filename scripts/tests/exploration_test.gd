extends SceneTree
## Tests exploration contracts and cross-system cargo deliveries: generation,
## accepting, the map markers, completion by scouting (and only by scouting),
## the already-discovered and multiple-contract cases, rewards exactly once and
## saving. Uses throwaway files in user://. Run with:
##   Godot --headless --path . --script res://scripts/tests/exploration_test.gd

const PATH := "user://exploration_test.json"

var _failures: int = 0


class TwoTargetSource:
	extends ContractSource
	## A test source: two exploration contracts for Wolf 359 and one for Sirius.
	func generate(location: InhabitedData, _context: ContractContext) -> Array[Contract]:
		var contracts: Array[Contract] = []
		for target in [&"wolf_359", &"wolf_359", &"sirius"]:
			var contract := ExplorationContract.new()
			contract.title = "Scout %s" % target
			contract.origin = location
			contract.target_system = target
			contract.reward = 10000
			contracts.append(contract)
		return contracts


func _init() -> void:
	_clean()
	await _scenario_real_game()
	await _scenario_manager_cases()
	_clean()
	print("")
	print("EXPLORATION TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# ----------------------------------------------------------- the real game

func _scenario_real_game() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	var big_hold: ShipStats = load("res://resources/ships/shuttle_stats.tres").duplicate()
	big_hold.cargo_capacity = 500
	main.starting_ship_stats = big_hold
	main.get_node("Save").save_path = PATH
	root.add_child(main)
	await process_frame
	await process_frame

	var contracts: ContractManager = main.get_node("Contracts")
	var travel: TravelManager = main.get_node("Travel")
	var economy: EconomyManager = main.get_node("Economy")
	var saves: SaveManager = main.get_save_manager()
	var map: GalaxyMapScreen = main.get_node("GalaxyMapScreen")
	var popup: EventPopup = main.get_node("EventPopup")
	var ship := main.get_player_ship()
	var galaxy := main.galaxy
	var registry := ContentRegistry.new()
	var daedalus := registry.location(&"daedalus")
	var player := main.get_player_data()

	# --- Generation.
	var offered := contracts.get_available(daedalus)
	var exploration: ExplorationContract = null
	for contract in offered:
		if contract is ExplorationContract:
			exploration = contract
	_check(exploration != null and exploration.target_system == &"wolf_359", "Daedalus offers one exploration contract, for Wolf 359")
	_check(offered.size() == 2, "...alongside its cargo delivery (%d offers)" % offered.size())
	var expected_reward: int = main.get_node("Contracts").get_context().rewards.exploration_reward(
			galaxy.find_route(&"barnards_star", &"wolf_359").size() - 1, galaxy.get_jump_cost(&"barnards_star", &"wolf_359"))
	_check(exploration.reward == expected_reward and exploration.reward > 0, "its reward comes from the reward rules (%d)" % exploration.reward)
	_check(exploration.get_type_label() == "EXPLORATION" and exploration.get_destination_text() == "Wolf 359", "it is labelled as exploration, targeting Wolf 359")
	_check("1 jump" in exploration.get_journey_text(), "the journey is shown: %s" % exploration.get_journey_text())
	var elsewhere := 0
	for location_id in [&"earth", &"mars", &"victory_i", &"hera", &"persephone"]:
		for contract in contracts.get_available(registry.location(location_id)):
			if contract is ExplorationContract:
				elsewhere += 1
	_check(elsewhere == 0, "no other location offers an exploration contract")

	# --- Accepting.
	var credits := player.credits
	var used := player.cargo.get_used()
	_check(contracts.accept(exploration, daedalus) == ContractManager.AcceptResult.OK and exploration.status == Contract.Status.ACCEPTED, "the contract is accepted at its issuer")
	_check(player.cargo.get_used() == used and player.credits == credits, "it uses no cargo space and costs nothing")
	_check(contracts.get_active().has(exploration), "it is active")
	_check(not contracts.get_objective_systems().is_empty() and contracts.get_objective_systems().has(&"wolf_359"), "the target is an objective system")
	_check("Travel to Wolf 359" in exploration.get_progress_text(), "progress: %s" % exploration.get_progress_text())

	# --- The map shows the target, and looking at it completes nothing.
	map.open()
	await process_frame
	_check(map.get_map().get_objectives(&"wolf_359").size() == 1, "the galaxy map marks Wolf 359 as an objective")
	map.get_map().select(&"wolf_359")
	map._show_system(&"wolf_359")
	await process_frame
	var rows := ""
	for row in map.get_node("%DetailRows").get_children():
		for label in row.get_children():
			if label is Label:
				rows += (label as Label).text + " "
	_check("Exploration" in rows and "Chart the Wolf 359 system" in rows, "its panel lists the objective")
	_check(exploration.status == Contract.Status.ACCEPTED and player.credits == credits, "selecting an unexplored system does not complete the contract")
	map.close()
	await process_frame
	_check(map.get_map().get_system_colour(&"wolf_359") == GalaxyMapView.UNEXPLORED, "an undiscovered system is drawn dim")

	# --- Entering the system without scouting it does not complete it either.
	travel.discover(&"wolf_359")
	main._swap_system(galaxy.get_scene(&"wolf_359"))
	ship.global_position = Vector2(2000, 0)
	await process_frame
	await process_frame
	_check(exploration.status == Contract.Status.ACCEPTED and player.credits == credits, "being in the system, discovered, is not enough")
	_check("Scouted 0 of 2" in exploration.get_progress_text(), "progress counts the bodies: %s" % exploration.get_progress_text())
	_check(map.get_map().get_system_colour(&"wolf_359") == GalaxyMapView.DISCOVERED, "a discovered but unscouted empty system is still drawn blue")

	# --- Scouting the bodies completes it, once.
	var system := main.get_system()
	var medusa := _node(system, &"medusa")
	var cerberus := _node(system, &"cerberus")
	ship.global_position = medusa.global_position
	await process_frame
	await process_frame
	_check(exploration.status == Contract.Status.ACCEPTED, "one of two bodies scouted: still active")
	_check("Scouted 1 of 2" in exploration.get_progress_text(), "progress: %s" % exploration.get_progress_text())
	_check(saves.save_game(), "save halfway")
	ship.global_position = cerberus.global_position
	await process_frame
	await process_frame
	_check(exploration.status == Contract.Status.ACCEPTED and exploration.explored, "scouting the last body finishes the job but the contract stays open")
	_check(player.credits == credits and not popup.visible, "no reward and no popup during flight")
	_check("Return to Daedalus" in exploration.get_progress_text(), "it says to return to the issuer: %s" % exploration.get_progress_text())
	_check(not main.get_node("Contracts").get_objective_systems().has(&"wolf_359"), "the map no longer marks the scouted system as an objective")
	_check(map.get_map().get_system_colour(&"wolf_359") == GalaxyMapView.SCOUTED_EMPTY, "the scouted empty system turns white on the map")
	_check(saves.save_game(), "save while the reward is waiting")
	# Return to Daedalus: now it is paid, once, with a popup.
	main._swap_system(galaxy.get_scene(&"barnards_star"))
	await process_frame
	var daedalus_node := _node(main.get_system(), &"daedalus")
	ship.global_position = daedalus_node.global_position + Vector2(0, 60)
	ship.velocity = Vector2.ZERO
	main.get_node("Targeting").select(daedalus_node.get_node("Targetable"))
	main.get_node("Docking").try_dock()
	await process_frame
	await process_frame
	_check(exploration.status == Contract.Status.COMPLETED, "landing at the issuer completes the contract")
	_check(player.credits == credits + exploration.reward, "the reward is paid through the economy")
	_check(contracts.get_completed().has(exploration) and not contracts.get_active().has(exploration), "it moves to completed")
	_check(popup.visible, "a completion popup is shown on landing")
	system = main.get_system()
	main._swap_system(galaxy.get_scene(&"wolf_359"))
	await process_frame
	ship.global_position = _node(main.get_system(), &"medusa").global_position
	await process_frame
	ship.global_position = _node(main.get_system(), &"cerberus").global_position
	await process_frame
	await process_frame
	_check(player.credits == credits + exploration.reward, "scouting again pays nothing more")
	_check(contracts.get_available(daedalus).size() == 1, "the offer is not made again")
	popup._dismiss()

	# --- Persistence: completed stays completed; loading the halfway save does not pay twice.
	var saved_credits := player.credits
	_check(saves.save_game(), "save after completing")
	_check(main.load_game()["ok"], "load")
	var loaded: ExplorationContract = null
	for contract in contracts.get_completed():
		if contract is ExplorationContract:
			loaded = contract
	_check(loaded != null and loaded.status == Contract.Status.COMPLETED and contracts.get_active().is_empty(), "the completed contract is still completed")
	_check(player.credits == saved_credits and travel.is_scouted(&"wolf_359"), "credits and scouting are as saved")
	system = main.get_system()
	ship.global_position = _node(system, &"medusa").global_position
	await process_frame
	await process_frame
	_check(player.credits == saved_credits, "the reward cannot be claimed again after loading")

	# --- A save with an active exploration contract whose target is scouted is refused.
	var document := saves.build_document()
	var damaged := loaded.to_dict()
	damaged["status"] = "ACCEPTED"
	damaged["explored"] = false
	document["contracts"]["completed"] = []
	document["contracts"]["active"].append(damaged)
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_check(not main.load_game()["ok"], "an active contract for an already scouted system is refused as damaged")

	# --- An active contract survives saving and loading.
	var fresh: Main = main
	document = saves.build_document()
	document["galaxy"]["scouted_nodes"] = {}
	document["contracts"]["completed"] = []
	var active := loaded.to_dict()
	active["status"] = "ACCEPTED"
	document["contracts"]["active"].append(active)
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	_check(fresh.load_game()["ok"], "a save with an active exploration contract loads")
	var restored: ExplorationContract = null
	for contract in contracts.get_active():
		if contract is ExplorationContract:
			restored = contract
	_check(restored != null and restored.target_system == &"wolf_359" and restored.reward == loaded.reward, "the active contract is restored")
	_check(not travel.is_scouted(&"wolf_359") and player.credits == saved_credits, "...unscouted, and loading paid nothing")

	# --- Cross-system cargo delivery, end to end.
	_clean()
	main._swap_system(galaxy.get_scene(&"sol"))
	var earth := registry.location(&"earth")
	var talos := registry.location(&"talos")
	var luxury: Commodity = registry.commodity(&"luxury_goods")
	var run: CargoDeliveryContract = null
	for contract in contracts.get_available(earth):
		if contract.title == "Luxury goods for Talos":
			run = contract
	_check(run != null and run.get_destination_text() == "Talos, Procyon", "Earth offers a delivery to Talos in Procyon")
	_check("Sol > Procyon: 1 jump" in run.get_journey_text(), "the journey is spelled out: %s" % run.get_journey_text())
	var jumps_cost := galaxy.get_jump_cost(&"sol", &"procyon")
	_check(run.reward == contracts.get_context().rewards.cargo_reward(luxury, 25, 1, jumps_cost), "the reward accounts for quantity and distance (%d)" % run.reward)
	var rules := contracts.get_context().rewards
	var water: Commodity = registry.commodity(&"water")
	_check(rules.cargo_reward(water, 100, 2, 50) > rules.cargo_reward(water, 100, 0, 0), "the same cargo pays more for a longer journey")
	_check(rules.cargo_reward(water, 200, 1, 20) > rules.cargo_reward(water, 100, 1, 20), "and more for a bigger load")
	_check(rules.cargo_reward(luxury, 50, 1, 20) > rules.cargo_reward(water, 50, 1, 20), "and more for a more valuable commodity")
	_check(rules.exploration_reward(3, 70) > rules.exploration_reward(1, 20), "an exploration contract pays more for a longer trip")
	economy.set_cargo_capacity(500)  # (loading restored the shuttle's small hold)
	var before := player.credits
	_check(contracts.accept(run, earth) == ContractManager.AcceptResult.OK, "the delivery is accepted at Earth")
	_check(economy.get_cargo_lines().any(func(line: Array) -> bool: return "Procyon" in line[0] and "Talos" in line[0]), "the cargo list names the destination and its system: %s" % [economy.get_cargo_lines()])
	var mars_market := economy.get_market(registry.location(&"mars"))
	_check(not economy.quote_sell(mars_market, luxury, 5).is_ok(), "contract cargo cannot be sold, even where luxury goods are wanted")
	_check(player.credits == before, "jump costs are shown but nothing is charged in credits or fuel")
	_check(run.get_journey_text() != "", "an accepted contract still describes the journey from where the player is")
	travel.discover(&"procyon")
	main._swap_system(galaxy.get_scene(&"procyon"))
	await process_frame
	var talos_node := _node(main.get_system(), &"talos")
	ship.global_position = talos_node.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	main.get_node("Targeting").select(talos_node.get_node("Targetable"))
	main.get_node("Docking").try_dock()
	await process_frame
	await process_frame
	_check(run.status == Contract.Status.COMPLETED, "docking at Talos in the other system delivers it")
	_check(player.credits == before + run.reward and player.cargo.get_lot_quantity(run.id) == 0, "the reward is paid once and the cargo is gone")
	_check(popup.visible, "a delivery popup is shown")
	_check(talos != null, "(sanity)")

	main.queue_free()
	await process_frame


# ------------------------------------------------- manager level, many cases

func _scenario_manager_cases() -> void:
	var galaxy: Galaxy = load("res://resources/universe/galaxy.tres")
	var registry := ContentRegistry.new()

	var player := PlayerData.new()
	player.credits = 1000
	player.cargo.capacity = 500
	var economy := EconomyManager.new()
	economy.setup(player)
	root.add_child(economy)
	var current: Array = [&"sol"]
	var travel := TravelManager.new()
	root.add_child(travel)
	travel.setup(galaxy, func() -> StringName: return current[0])
	var context := ContractContext.new()
	context.galaxy = galaxy
	context.travel = travel
	context.current_system = func() -> StringName: return current[0]
	var contracts := ContractManager.new()
	root.add_child(contracts)
	contracts.setup(economy, context)
	contracts.set_source(TwoTargetSource.new())
	var earth := registry.location(&"earth")
	var offers := contracts.get_available(earth)
	_check(offers.size() == 3, "the test source offers three exploration contracts")
	var wolf_a: Contract = offers[0]
	var wolf_b: Contract = offers[1]
	var sirius: Contract = offers[2]

	# The player has already discovered Sirius (but not scouted it) before accepting.
	travel.discover(&"sirius")
	_check(contracts.accept(sirius, earth) == ContractManager.AcceptResult.OK, "a target that is already discovered can still be accepted")
	_check(contracts.accept(wolf_a, earth) == ContractManager.AcceptResult.OK and contracts.accept(wolf_b, earth) == ContractManager.AcceptResult.OK, "two contracts for the same system can both be accepted")
	_check(contracts.get_active().size() == 3, "several exploration contracts can be active at once")
	var completed: Array[StringName] = []
	contracts.contract_completed.connect(func(c: Contract) -> void: completed.append(c.id))

	# Scouting Sirius (discovered while other contracts are active) completes only its own.
	travel.discover(&"wolf_359")
	_scout(travel, galaxy, &"sirius")
	var earth_target := Targetable.new()
	earth_target.details = earth
	_check(sirius.explored and not wolf_a.explored and not wolf_b.explored and player.credits == 1000, "scouting one system finishes only the contract for it, and pays nothing yet")
	contracts.on_docked(earth_target)
	_check(sirius.status == Contract.Status.COMPLETED and wolf_a.status == Contract.Status.ACCEPTED and wolf_b.status == Contract.Status.ACCEPTED, "landing at the issuer completes the finished one")
	_check(player.credits == 11000, "paid once for Sirius (%d)" % player.credits)

	# Both contracts for Wolf 359 complete together, each paid once.
	_scout(travel, galaxy, &"wolf_359")
	_check(wolf_a.explored and wolf_b.explored and player.credits == 11000, "both contracts for the same system finish together")
	contracts.on_docked(earth_target)
	contracts.on_docked(earth_target)
	_check(wolf_a.status == Contract.Status.COMPLETED and wolf_b.status == Contract.Status.COMPLETED, "both are completed on landing")
	_check(player.credits == 31000 and completed.size() == 3, "each is paid exactly once (%d credits, %d completions)" % [player.credits, completed.size()])
	travel.system_scouted.emit(&"wolf_359")
	_check(player.credits == 31000 and completed.size() == 3, "a repeated announcement pays nothing: completed contracts are ignored")

	# A target scouted before an offer was made is not offered; one scouted after listing is refused.
	var second := ContractManager.new()
	root.add_child(second)
	second.setup(economy, context)
	second.set_source(OfferContractSource.new())
	var daedalus := registry.location(&"daedalus")
	_check(second.get_available(daedalus).any(func(c: Contract) -> bool: return c is ExplorationContract) == false, "an exploration target that is already scouted is not offered")
	var third := ContractManager.new()
	root.add_child(third)
	var empty_travel := TravelManager.new()
	root.add_child(empty_travel)
	empty_travel.setup(galaxy, func() -> StringName: return &"barnards_star")
	var context2 := ContractContext.new()
	context2.galaxy = galaxy
	context2.travel = empty_travel
	context2.current_system = func() -> StringName: return &"barnards_star"
	third.setup(economy, context2)
	third.set_source(OfferContractSource.new())
	var listed: ExplorationContract = null
	for contract in third.get_available(daedalus):
		if contract is ExplorationContract:
			listed = contract
	_check(listed != null, "an unscouted target is offered")
	empty_travel.discover(&"wolf_359")
	_scout(empty_travel, galaxy, &"wolf_359")
	_check(third.accept(listed, daedalus) == ContractManager.AcceptResult.ALREADY_EXPLORED, "a stale offer whose target has since been scouted is refused")
	_check(third.get_available(daedalus).all(func(c: Contract) -> bool: return not c is ExplorationContract), "...and it disappears from the list")

	# --- Offer validation.
	var offer := ExplorationOffer.new()
	offer.title = "Chart Atlantis"
	offer.target_system = &"atlantis"
	_check(not offer.validate(earth, context).is_empty(), "an exploration offer for an unknown system is invalid")
	offer.target_system = &"sol"
	_check(not offer.validate(earth, context).is_empty(), "...and so is one targeting the issuer's own system")
	offer.target_system = &"wolf_359"
	_check(offer.validate(earth, context).is_empty(), "a valid one passes")
	var cargo_offer: ContractOffer = load("res://resources/contracts/earth_luxury_to_talos.tres").duplicate()
	cargo_offer.quantity = 999999
	context.max_cargo = registry.max_cargo_capacity()
	_check(not cargo_offer.validate(earth, context).is_empty(), "a delivery bigger than any ship can carry is invalid when a limit is known")
	context.max_cargo = registry.max_cargo_capacity()
	cargo_offer.quantity = 25
	_check(cargo_offer.validate(earth, context).is_empty() and context.max_cargo >= 5000, "a normal delivery is valid (largest hold %d)" % context.max_cargo)

	for node in [contracts, second, third, travel, empty_travel, economy]:
		node.queue_free()
	await process_frame


## Scouts a system for real: loads its scene and flies the ship to each body.
func _scout(travel: TravelManager, galaxy: Galaxy, system_id: StringName) -> void:
	var system: StarSystem = galaxy.get_scene(system_id).instantiate()
	root.add_child(system)
	for node in system.get_inhabited_nodes():
		travel.update_scouting(system, node.global_position)
	system.queue_free()


func _node(system: StarSystem, id: StringName) -> InhabitedNode:
	for node in system.get_inhabited_nodes():
		if node.data.id == id:
			return node
	return null


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
