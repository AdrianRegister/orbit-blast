extends SceneTree
## Tests the procedural contract generator and what hangs off it: every
## inhabited location always has a mission to take, the faction, distance and
## size rules for each contract type, reward ceilings, the issuing authority and
## its saving, topping up on docking, and the real game scene's Mission Computer
## buttons. Run with:
##   Godot --headless --path . --script res://scripts/tests/procedural_contract_test.gd

var _failures: int = 0
var _registry: ContentRegistry
var _galaxy: Galaxy
var _rules: ContractRewards


func _init() -> void:
	_registry = ContentRegistry.new()
	_galaxy = load("res://resources/universe/galaxy.tres")
	_rules = load("res://resources/contracts/reward_rules.tres")

	_check_no_hand_written_contracts()
	_check_generation_rules()
	_check_generator()
	_check_faction_rule()
	_check_reward_ceilings()
	_check_authority_and_saving()
	_check_manager()
	await _check_real_game()

	print("")
	print("PROCEDURAL CONTRACT TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _context(galaxy: Galaxy = null) -> ContractContext:
	var context := ContractContext.new()
	context.galaxy = galaxy if galaxy != null else _galaxy
	context.registry = _registry
	context.rewards = _rules
	context.max_cargo = _registry.max_cargo_capacity()
	var travel := TravelManager.new()
	travel.setup(context.galaxy, func() -> StringName: return &"sol")
	context.travel = travel
	return context


func _inhabited() -> Array[InhabitedData]:
	var result: Array[InhabitedData] = []
	for location in _registry.locations():
		if ProceduralContractSource.is_inhabited(location):
			result.append(location)
	return result


# ------------------------------------------------------------------ content

func _check_no_hand_written_contracts() -> void:
	var files := DirAccess.get_files_at("res://resources/contracts")
	files.sort()
	_check(files == PackedStringArray(["generation_rules.tres", "reward_rules.tres"]), "no hand-written contract files remain: %s" % [files])
	for location in _registry.locations():
		_check(not "contract_offers" in location and not "exploration_offers" in location, "%s no longer lists fixed offers" % location.display_name)


func _check_generation_rules() -> void:
	var rules: ContractGenerationRules = load("res://resources/contracts/generation_rules.tres")
	_check(rules.validate().is_empty(), "the generation rules are valid: %s" % [rules.validate()])
	_check(rules.ferry_max_passengers <= 3 and rules.ferry_max_jumps <= 3, "ferry limits are at most 3 passengers and 3 jumps")
	var passengers := _registry.commodity(&"passengers")
	_check(passengers != null and passengers.base_price == 0, "the passengers commodity exists and is not for sale")
	for location in _registry.locations():
		if location.market != null:
			for listing in location.market.listings:
				_check(listing.commodity.id != &"passengers", "%s does not trade passengers" % location.display_name)


# ---------------------------------------------------------------- generator

func _check_generator() -> void:
	var context := _context()
	var inhabited := _inhabited()
	_check(inhabited.size() >= 13, "there are inhabited locations to serve (%d)" % inhabited.size())
	var seen := {&"cargo": 0, &"ferry": 0, &"exploration": 0, &"bulk": 0}
	var emptiest := 99
	var bad: Array[String] = []
	for seed_value in 40:
		for location in inhabited:
			var source := ProceduralContractSource.new()
			source.seed_rng(seed_value * 1000 + location.id.hash() % 997)
			var contracts := source.generate(location, context, source.get_target_offers(), [])
			emptiest = mini(emptiest, contracts.size())
			var keys := {}
			for contract in contracts:
				var problem := _problem_with(contract, location, context)
				if not problem.is_empty():
					bad.append("%s: %s (%s)" % [location.display_name, problem, contract.title])
				if contract is FerryContract:
					seen[&"ferry"] += 1
				elif contract is CargoDeliveryContract:
					seen[&"cargo"] += 1
					if (contract as CargoDeliveryContract).quantity >= _rules.bulk_quantity:
						seen[&"bulk"] += 1
				elif contract is ExplorationContract:
					seen[&"exploration"] += 1
				var key := "%s|%s|%s" % [contract.get_type_id(), contract.destination.id if contract.destination != null else contract.get_target_system(),
						(contract as CargoDeliveryContract).commodity.id if contract is CargoDeliveryContract else ""]
				if keys.has(key):
					bad.append("%s offers %s twice" % [location.display_name, key])
				keys[key] = true
	_check(bad.is_empty(), "every generated contract obeys its rules (%d problems: %s)" % [bad.size(), bad.slice(0, 3)])
	_check(emptiest >= 1, "every inhabited location always gets at least one contract (fewest: %d)" % emptiest)
	_check(seen[&"cargo"] > 0 and seen[&"ferry"] > 0 and seen[&"exploration"] > 0 and seen[&"bulk"] > 0,
			"all kinds appear: %s" % [seen])

	# Places nobody lives are given nothing.
	var source := ProceduralContractSource.new()
	for id in [&"medusa", &"cerberus", &"atlas", &"oberon"]:
		var uninhabited := _registry.location(id)
		if uninhabited != null:
			_check(source.generate(uninhabited, context, 4, []).is_empty(), "%s (uninhabited) is offered nothing" % id)

	# The same seed gives the same offers; existing offers are not duplicated.
	var earth := _registry.location(&"earth")
	var first := ProceduralContractSource.new()
	first.seed_rng(99)
	var second := ProceduralContractSource.new()
	second.seed_rng(99)
	var a := first.generate(earth, context, 4, [])
	var b := second.generate(earth, context, 4, [])
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		same = same and a[i].title == b[i].title and a[i].reward == b[i].reward
	_check(same, "a seeded generator is reproducible")
	var more := first.generate(earth, context, 8, a)
	var clash := false
	for contract in more:
		for old in a:
			if contract.get_type_id() == old.get_type_id() and contract.destination == old.destination and contract.get_target_system() == old.get_target_system():
				if not (contract is CargoDeliveryContract) or (contract as CargoDeliveryContract).commodity == (old as CargoDeliveryContract).commodity:
					clash = true
	_check(not clash, "new contracts do not repeat the ones a location already has")


## What is wrong with a generated contract, or "" if nothing.
func _problem_with(contract: Contract, origin: InhabitedData, context: ContractContext) -> String:
	if contract.origin != origin:
		return "wrong origin"
	if contract.authority != Contract.Authority.CIVILIAN:
		return "not civilian"
	if contract.title.is_empty() or "{" in contract.title or "{" in contract.description:
		return "unfinished wording"
	if contract.reward <= 0:
		return "no reward"
	if contract.status != Contract.Status.AVAILABLE:
		return "not available"
	var origin_system := context.system_of(origin)
	if contract is ExplorationContract:
		var target := (contract as ExplorationContract).target_system
		if _galaxy.is_inhabited(target) or context.travel.is_scouted(target):
			return "exploration target is inhabited or scouted"
		var distance := context.journey(origin_system, target)
		if distance.x < 0 or distance.x > 3:
			return "exploration target too far"
		return ""
	var delivery := contract as CargoDeliveryContract
	var destination := contract.destination
	if destination == null or destination == origin or not ProceduralContractSource.is_inhabited(destination):
		return "bad destination"
	var destination_system := context.system_of(destination)
	var jumps := 0 if destination_system == origin_system else context.journey(origin_system, destination_system).x
	if jumps < 0:
		return "no route"
	if contract is FerryContract:
		if delivery.quantity < 1 or delivery.quantity > 3:
			return "ferry carries %d passengers" % delivery.quantity
		if jumps > 3:
			return "ferry is %d jumps" % jumps
		if delivery.commodity.id != &"passengers":
			return "ferry cargo is not passengers"
		if delivery.reward < 300 or delivery.reward > 3000:
			return "ferry reward %d out of range" % delivery.reward
		return ""
	if delivery.quantity < 1 or delivery.quantity > context.max_cargo:
		return "quantity %d does not fit any ship" % delivery.quantity
	if jumps > 4:
		return "cargo run is %d jumps" % jumps
	if _galaxy.get_faction(destination_system) != _galaxy.get_faction(origin_system) or destination.faction_name != origin.faction_name:
		return "delivery into another faction's territory"
	if delivery.commodity.base_price <= 0:
		return "cargo is not a trade good"
	var cap := 45000 if delivery.quantity >= 200 else 20000
	if delivery.reward > cap:
		return "reward %d above the %d ceiling" % [delivery.reward, cap]
	return ""


# -------------------------------------------------------------- faction rule

func _check_faction_rule() -> void:
	# Everything in the real galaxy is one faction, so make a second one: Procyon
	# changes hands.
	var galaxy: Galaxy = _galaxy.duplicate(true)
	for system in galaxy.systems:
		if system.scene.resource_path.ends_with("procyon_system.tscn"):
			system.faction_name = "Rival Federation"
	var context := _context(galaxy)
	_check(galaxy.get_faction(&"procyon") == "Rival Federation" and galaxy.get_faction(&"sol") == "TestFaction_1", "(setup) Procyon belongs to someone else")
	var procyon_locations: Array[StringName] = []
	for id in galaxy.get_summary(&"procyon").location_ids:
		procyon_locations.append(id)
	var wrong := 0
	var cargo_runs := 0
	var ferries_there := 0
	for seed_value in 60:
		for location in _inhabited():
			var source := ProceduralContractSource.new()
			source.seed_rng(seed_value * 31 + location.id.hash() % 101)
			for contract in source.generate(location, context, 6, []):
				var from_procyon := procyon_locations.has(location.id)
				if contract is FerryContract:
					if contract.destination != null and procyon_locations.has(contract.destination.id):
						ferries_there += 1
				elif contract is CargoDeliveryContract:
					cargo_runs += 1
					if from_procyon or procyon_locations.has(contract.destination.id):
						wrong += 1
	_check(cargo_runs > 100, "(setup) plenty of cargo contracts were generated (%d)" % cargo_runs)
	_check(wrong == 0, "no cargo is ever sent into or out of another faction's system (%d wrong)" % wrong)
	_check(ferries_there > 0, "passengers, unlike cargo, may still travel there (%d)" % ferries_there)


# ------------------------------------------------------------------ rewards

func _check_reward_ceilings() -> void:
	# The dearest cargo, the furthest reasonable journey (4 jumps, the most fuel any 4 jump route costs).
	var most_fuel := 0
	var ids := _galaxy.get_system_ids()
	for a in ids:
		for b in ids:
			var route := _galaxy.find_route(a, b)
			if not route.is_empty() and route.size() - 1 <= 4:
				most_fuel = maxi(most_fuel, _galaxy.get_route_cost(route))
	_check(most_fuel > 0, "(setup) the longest 4 jump route costs %d fuel" % most_fuel)
	var worst := 0
	for good in _registry.commodities():
		if good.base_price <= 0:
			continue
		var uncapped := _rules.cargo_value_factor * 50 * good.base_price + 4 * _rules.cargo_per_jump + most_fuel * _rules.cargo_per_fuel
		worst = maxi(worst, int(uncapped))
	_check(worst <= 20000, "50 units of the dearest cargo over 4 jumps pays %d before any cap, within 20,000" % worst)
	var isotopes := _registry.commodity(&"rare_isotopes")
	_check(_rules.cargo_reward(isotopes, 50, 4, most_fuel) <= 20000, "a typical 50 unit, 4 jump delivery pays at most 20,000")
	_check(_rules.cargo_reward(isotopes, 199, 4, most_fuel) <= 20000, "anything under 200 units is held to 20,000")
	_check(_rules.cargo_reward(isotopes, 600, 4, most_fuel) <= 45000, "a bulk delivery is held to 45,000")
	_check(_rules.cargo_reward(isotopes, 5000, 4, most_fuel) <= 45000, "...whatever its size")
	var food := _registry.commodity(&"food")
	_check(_rules.cargo_reward(food, 600, 4, most_fuel) <= 45000 and _rules.cargo_reward(food, 600, 4, most_fuel) > _rules.cargo_reward(food, 50, 4, most_fuel), "a bulk delivery of food pays more than a normal one")
	_check(_rules.cargo_reward(food, 50, 4, most_fuel) > _rules.cargo_reward(food, 50, 1, 20), "longer journeys pay more")
	_check(_rules.ferry_reward(1, 0, 0) >= 300 and _rules.ferry_reward(3, 3, 80) <= 3000, "ferry work pays small amounts (%d to %d)" % [_rules.ferry_reward(1, 0, 0), _rules.ferry_reward(3, 3, 80)])
	_check(_rules.exploration_reward(3, 100) <= 20000, "exploration is held below the old rates (%d)" % _rules.exploration_reward(3, 100))


# ---------------------------------------------------------------- authority

func _check_authority_and_saving() -> void:
	var context := _context()
	var earth := _registry.location(&"earth")
	var source := ProceduralContractSource.new()
	source.seed_rng(5)
	var kinds := {}
	for seed_value in 30:
		source.seed_rng(seed_value)
		for contract in source.generate(earth, context, 4, []):
			kinds[contract.get_type_id()] = contract
	_check(kinds.has(&"cargo_delivery") and kinds.has(&"ferry") and kinds.has(&"exploration"), "(setup) one of each kind to save: %s" % [kinds.keys()])
	for type in kinds:
		var contract: Contract = kinds[type]
		contract.id = &"contract_1"
		var data := contract.to_dict()
		_check(data["issuing_authority"] == "CIVILIAN" and contract.get_authority_text() == "Civilian", "%s is saved as civilian" % type)
		_check(ContractFactory.validate(data, _registry).is_empty(), "%s validates: %s" % [type, ContractFactory.validate(data, _registry)])
		contract.authority = Contract.Authority.MILITARY
		var military := contract.to_dict()
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(military))
		var loaded := ContractFactory.from_dict(parsed, _registry)
		_check(loaded.get_type_id() == type and loaded.authority == Contract.Authority.MILITARY, "%s keeps a military authority through saving" % type)
		_check(loaded.get_issuing_faction() == "TestFaction_1", "the issuing faction is the issuer's")
		var old_save := data.duplicate()
		old_save.erase("issuing_authority")
		_check(ContractFactory.validate(old_save, _registry).is_empty() and ContractFactory.from_dict(old_save, _registry).authority == Contract.Authority.CIVILIAN,
				"%s from a save without an authority is civilian" % type)
		var damaged := data.duplicate()
		damaged["issuing_authority"] = "PIRATE"
		_check(not ContractFactory.validate(damaged, _registry).is_empty(), "%s with an unknown authority is rejected" % type)
	var ferry: Dictionary = (kinds[&"ferry"] as Contract).to_dict()
	ferry["quantity"] = 4
	ferry["quantity_in_hold"] = 0
	_check(not ContractFactory.validate(ferry, _registry).is_empty(), "a saved ferry with more than 3 passengers is rejected")


# ------------------------------------------------------------------ manager

func _check_manager() -> void:
	var player := PlayerData.new()
	player.credits = 1000
	player.cargo.capacity = 5000
	var economy := EconomyManager.new()
	economy.setup(player)
	var context := _context()
	var contracts := ContractManager.new()
	root.add_child(contracts)
	contracts.setup(economy, context)
	var source := ProceduralContractSource.new()
	source.seed_rng(2024)
	contracts.set_source(source)
	var inhabited := _inhabited()
	var empty := 0
	for location in inhabited:
		if contracts.get_available(location).is_empty() or not contracts.has_contracts_for(location):
			empty += 1
	_check(empty == 0, "every inhabited location has an active mission computer (%d without)" % empty)
	var earth := _registry.location(&"earth")
	_check(contracts.get_available(earth).size() == 4, "a location offers its target number of contracts (%d)" % contracts.get_available(earth).size())

	# Take everything, then land: the list is filled up again.
	var taken := 0
	for contract in contracts.get_available(earth).duplicate():
		if contracts.accept(contract, earth) == ContractManager.AcceptResult.OK:
			taken += 1
	_check(taken > 0 and contracts.get_available(earth).size() == 4 - taken, "accepted contracts leave the list (%d taken)" % taken)
	if contracts.get_available(earth).is_empty():
		_check(not contracts.has_contracts_for(earth) or contracts.get_active().size() > 0, "an emptied list is only refilled on landing")
	var changes := [0]
	contracts.contracts_changed.connect(func() -> void: changes[0] += 1)
	contracts.on_docked(_target_for(earth))
	_check(contracts.get_available(earth).size() == 4 and changes[0] > 0, "landing tops the mission computer back up to 4")
	_check(contracts.has_contracts_for(earth), "...so it is enabled")
	var ids := {}
	var titles_ok := true
	for contract in contracts.get_available(earth) + contracts.get_active():
		titles_ok = titles_ok and not ids.has(contract.id)
		ids[contract.id] = true
	_check(titles_ok, "all ids stay unique after topping up")
	var before := contracts.get_available(earth).size()
	contracts.on_docked(_target_for(earth))
	_check(contracts.get_available(earth).size() == before, "landing again with a full list adds nothing")

	# An old save with empty mission computers recovers on the next landing.
	var state := contracts.save_state()
	state["available"] = []
	var other := ContractManager.new()
	root.add_child(other)
	other.setup(economy, context)
	var source2 := ProceduralContractSource.new()
	source2.seed_rng(1)
	other.set_source(source2)
	other.load_state(state, _registry)
	_check(other.get_available(earth).is_empty(), "(setup) the old save has no offers")
	other.on_docked(_target_for(earth))
	_check(other.get_available(earth).size() == 4 and other.has_contracts_for(earth), "...and landing there fills it")

	contracts.queue_free()
	other.queue_free()
	economy.free()


## A stand-in for the docked Targetable: only `details` is read.
func _target_for(location: InhabitedData) -> Targetable:
	var target: Targetable = load("res://scenes/objects/targetable.tscn").instantiate()
	target.details = location
	return target


# ---------------------------------------------------------------- real game

func _check_real_game() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var settlement: SettlementScreen = main.get_node("SettlementScreen")
	var button: Button = settlement.get_node("%MissionButton")
	var docking: DockingManager = main.get_node("Docking")
	var ship := main.get_player_ship()
	var contracts: ContractManager = main.get_node("Contracts")
	var travel: TravelManager = main.get_node("Travel")
	var disabled: Array[String] = []
	var visited := 0
	for system_id in main.galaxy.get_system_ids():
		if not main.galaxy.is_inhabited(system_id):
			continue
		if is_instance_valid(docking.docked_target):
			docking.undock()
			await create_timer(1.7).timeout
		travel.discover(system_id)
		main._swap_system(main.galaxy.get_scene(system_id))
		await process_frame
		for node in main.get_system().get_inhabited_nodes():
			if not ProceduralContractSource.is_inhabited(node.data):
				continue
			if is_instance_valid(docking.docked_target):
				docking.undock()
				await create_timer(1.7).timeout
			ship.global_position = node.global_position + Vector2(0, 40)
			ship.velocity = Vector2.ZERO
			main.get_node("Targeting").select(node.get_node("Targetable"))
			docking.try_dock()
			await process_frame
			visited += 1
			if not is_instance_valid(docking.docked_target) or button.disabled or contracts.get_available(node.data).is_empty():
				disabled.append(node.data.display_name)
	_check(visited >= 13, "(setup) visited %d inhabited locations in the real game" % visited)
	_check(disabled.is_empty(), "the Mission Computer is enabled at every inhabited location: %s" % [disabled])
	main.queue_free()
	await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
