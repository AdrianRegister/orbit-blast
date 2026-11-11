extends SceneTree
## The player's reputation with each faction: the scale and its standings, how it
## changes (military contracts and hostile acts, never civilian contracts), the
## checks other systems use, and saving. Run with:
##   Godot --headless --path . --script res://scripts/tests/reputation_test.gd

const PATH := "user://reputation_test.json"

var _failures: int = 0
var _registry: ContentRegistry
var _federation: Faction
var _rival: Faction


func _init() -> void:
	_registry = ContentRegistry.new()
	_federation = _registry.faction(&"faction_1")
	_rival = Faction.new()
	_rival.id = &"faction_2"
	_rival.display_name = "Rival"

	_check_standings()
	_check_manager()
	_check_contracts()
	_check_hostile_actions()
	_check_relations()
	_check_eligibility()
	_check_saving()
	await _check_game()

	print("")
	print("REPUTATION TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _new_manager(territory: TerritoryManager = null) -> ReputationManager:
	var manager := ReputationManager.new()
	manager.setup(territory)
	return manager


func _new_territory() -> TerritoryManager:
	var territory := TerritoryManager.new()
	territory.setup(load("res://resources/universe/galaxy.tres"), _registry)
	return territory


# ------------------------------------------------------------------- standings

func _check_standings() -> void:
	var standings: ReputationStandings = load("res://resources/reputation/standings.tres")
	_check(standings.validate().is_empty(), "the standings are valid: %s" % [standings.validate()])
	_check(standings.minimum == -100 and standings.maximum == 100 and standings.start == 0, "the scale is -100 to +100 and players start at 0")
	var expected := [
		[-100, "Hated"], [-81, "Hated"], [-80, "Hostile"], [-61, "Hostile"], [-60, "Unfriendly"], [-41, "Unfriendly"],
		[-40, "Wary"], [-21, "Wary"], [-20, "Neutral"], [0, "Neutral"], [19, "Neutral"], [20, "Favourable"], [39, "Favourable"],
		[40, "Friendly"], [59, "Friendly"], [60, "Trusted"], [79, "Trusted"], [80, "Honoured"], [100, "Honoured"]]
	var wrong: Array = []
	for pair in expected:
		if standings.get_standing_name(pair[0]) != pair[1]:
			wrong.append("%d is %s, not %s" % [pair[0], standings.get_standing_name(pair[0]), pair[1]])
	_check(wrong.is_empty(), "every standing begins and ends where the table says (%s)" % [wrong])
	_check(standings.clamp_value(150) == 100 and standings.clamp_value(-150) == -100 and standings.clamp_value(7) == 7, "values are clamped to the scale")
	var broken := standings.duplicate(true) as ReputationStandings
	broken.levels.reverse()
	_check(not broken.validate().is_empty(), "levels out of order are reported")


# --------------------------------------------------------------------- manager

func _check_manager() -> void:
	var manager := _new_manager()
	_check(manager.get_reputation(_federation) == 0 and manager.get_standing(_federation) == "Neutral", "a new player is neutral towards the Federation")
	_check(manager.get_reputation(_rival) == 0 and manager.get_reputation(null) == 0, "a faction nobody has met is neutral too")
	var changes: Array = []
	var standings: Array = []
	manager.reputation_changed.connect(func(id: StringName, old: int, new: int) -> void: changes.append([id, old, new]))
	manager.standing_changed.connect(func(id: StringName, old: String, new: String) -> void: standings.append([id, old, new]))
	_check(manager.change(_federation, 10) == 10 and changes == [[&"faction_1", 0, 10]] and standings.is_empty(), "a change is announced; the standing is still Neutral")
	manager.change(_federation, 15)
	_check(manager.get_standing(_federation) == "Favourable" and standings == [[&"faction_1", "Neutral", "Favourable"]], "crossing a threshold announces the new standing")
	_check(manager.change(_federation, 500) == 100 and manager.get_standing(_federation) == "Honoured", "reputation stops at +100")
	_check(manager.change(_federation, 5) == 100 and changes.size() == 3, "...and a change that does nothing announces nothing")
	manager.change(_federation, -1000)
	_check(manager.get_reputation(_federation) == -100 and manager.get_standing(_federation) == "Hated", "and at -100")
	_check(manager.get_reputation(_rival) == 0, "other factions are unaffected: reputation is tracked per faction")
	manager.change(_rival, 30)
	_check(manager.get_reputation(_rival) == 30 and manager.get_reputation(_federation) == -100, "...independently")
	manager.reset_state()
	_check(manager.get_reputation(_federation) == 0 and manager.get_reputation(_rival) == 0, "resetting makes everyone neutral again")


# ------------------------------------------------------------------- contracts

func _contract_game(manager: ReputationManager, territory: TerritoryManager) -> Dictionary:
	var player := PlayerData.new()
	player.credits = 1000
	player.cargo.capacity = 5000
	var economy := EconomyManager.new()
	economy.setup(player)
	var context := ContractContext.new()
	context.galaxy = load("res://resources/universe/galaxy.tres")
	context.registry = _registry
	context.territory = territory
	context.reputation = manager
	var contracts := ContractManager.new()
	contracts.setup(economy, context)
	contracts.set_source(FixedContractSource.new())
	contracts.contract_completed.connect(manager.apply_contract)
	return {"contracts": contracts, "economy": economy, "player": player}


func _check_contracts() -> void:
	var territory := _new_territory()
	var manager := _new_manager(territory)
	var game := _contract_game(manager, territory)
	var contracts: ContractManager = game["contracts"]
	var earth := _registry.location(&"earth")
	var mars := _registry.location(&"mars")
	var victory := _registry.location(&"victory_i")
	var offers := contracts.get_available(earth)
	var food: Contract = offers[0]  # to Mars
	var electronics: Contract = offers[1]  # to Victory I

	# Civilian contracts never change reputation, whatever number they carry.
	_check(food.authority == Contract.Authority.CIVILIAN and food.reputation_change == 0, "(setup) generated and listed contracts are civilian and carry no reputation")
	electronics.reputation_change = 50
	contracts.accept(electronics, earth)
	contracts.on_docked(_target_for(victory))
	_check(electronics.status == Contract.Status.COMPLETED and manager.get_reputation(_federation) == 0, "completing a civilian contract changes no reputation, even one carrying a number")
	_check(not manager.apply_contract(electronics) and not electronics.reputation_applied, "...and it is never marked as applied")

	# A military contract awards its own amount, once.
	food.authority = Contract.Authority.MILITARY
	food.reputation_change = 12
	contracts.accept(food, earth)
	_check(manager.get_reputation(_federation) == 0, "accepting a military contract changes nothing yet")
	contracts.on_docked(_target_for(mars))
	_check(food.status == Contract.Status.COMPLETED and manager.get_reputation(_federation) == 12 and food.reputation_applied, "completing it awards the Federation reputation")
	_check(not manager.apply_contract(food) and manager.get_reputation(_federation) == 12, "applying it again does nothing")
	contracts.on_docked(_target_for(mars))
	_check(manager.get_reputation(_federation) == 12, "docking again does not repeat it")
	var saved := food.to_dict()
	_check(saved["reputation_change"] == 12 and saved["reputation_applied"] == true, "the contract saves what it awarded and that it was applied")
	var restored := ContractFactory.from_dict(saved, _registry)
	_check(restored.reputation_applied and not manager.apply_contract(restored) and manager.get_reputation(_federation) == 12, "a restored contract cannot award it again")

	# Negative values (a contract that costs standing), and only the issuer's faction.
	var other := _contract_game(_new_manager(territory), territory)
	var second_manager: ReputationManager = _new_manager(territory)
	var third := _contract_game(second_manager, territory)
	var bulk: Contract = third["contracts"].get_available(mars)[0]  # ore to Earth
	bulk.authority = Contract.Authority.MILITARY
	bulk.reputation_change = -7
	third["contracts"].accept(bulk, mars)
	third["contracts"].on_docked(_target_for(earth))
	_check(second_manager.get_reputation(_federation) == -7 and second_manager.get_reputation(_rival) == 0, "a negative amount lowers it, only with the issuing faction")
	var empty := _new_manager()
	var no_territory := ContractContext.new()
	var contract := CargoDeliveryContract.new()
	contract.origin = earth
	contract.authority = Contract.Authority.MILITARY
	contract.reputation_change = 3
	contract.context = no_territory
	_check(empty.apply_contract(contract) and empty.get_reputation(_federation) == 3, "the issuer's own faction counts when no territory is known")
	_check(not empty.apply_contract(null), "nothing to apply is fine")
	other["contracts"].free()
	game["contracts"].free()
	third["contracts"].free()


## A stand-in for the docked Targetable: only `details` is read.
func _target_for(location: InhabitedData) -> Targetable:
	var target: Targetable = load("res://scenes/objects/targetable.tscn").instantiate()
	target.details = location
	return target


# -------------------------------------------------------------- hostile actions

func _check_hostile_actions() -> void:
	var territory := _new_territory()
	var manager := _new_manager(territory)
	var attack: HostileActionType = load("res://resources/reputation/hostile_actions/attack_ship.tres")
	var destroy: HostileActionType = load("res://resources/reputation/hostile_actions/destroy_ship.tres")
	var piracy: HostileActionType = load("res://resources/reputation/hostile_actions/piracy.tres")
	_check(attack.penalty > 0 and destroy.penalty > attack.penalty and piracy.penalty > 0, "each kind of hostile act has its own penalty (%d, %d, %d)" % [attack.penalty, destroy.penalty, piracy.penalty])
	_check(manager.report_hostile_action(attack, _federation, &"ship_7_attack") and manager.get_reputation(_federation) == -attack.penalty, "attacking a faction ship costs reputation with the faction")
	_check(not manager.report_hostile_action(attack, _federation, &"ship_7_attack") and manager.get_reputation(_federation) == -attack.penalty, "the same act is only counted once")
	_check(manager.report_hostile_action(destroy, _federation, &"ship_7_destroy") and manager.get_reputation(_federation) == -attack.penalty - destroy.penalty, "a different act against it counts")
	_check(not manager.report_hostile_action(attack, null, &"ship_8") and not manager.report_hostile_action(null, _federation, &"ship_9"), "an act with no victim or no kind is ignored")
	_check(manager.get_reputation(_rival) == 0, "the faction that was not hurt is unaffected")

	# An unaffiliated civilian in a faction's space: the faction that controls the system is charged.
	var before := manager.get_reputation(_federation)
	_check(manager.report_hostile_action_in_system(piracy, &"sol", &"civilian_1") and manager.get_reputation(_federation) == before - piracy.penalty, "piracy in a system charges the faction that controls it")
	_check(not manager.report_hostile_action_in_system(piracy, &"sol", &"civilian_1"), "...once")
	territory.transfer_settlement(_registry.location(&"mars"), _rival)
	var contested_before := manager.get_reputation(_federation)
	_check(territory.is_contested(&"sol") and not manager.report_hostile_action_in_system(piracy, &"sol", &"civilian_2") and manager.get_reputation(_federation) == contested_before, "a contested system has no single faction to blame")
	_check(not manager.report_hostile_action_in_system(piracy, &"nowhere", &"civilian_3"), "an unknown system charges nobody")
	var no_territory := _new_manager()
	_check(not no_territory.report_hostile_action_in_system(piracy, &"sol", &"civilian_4"), "without territory there is nobody to charge")


# -------------------------------------------------------------------- relations

func _check_relations() -> void:
	var manager := _new_manager()
	var other := Faction.new()
	other.id = &"faction_x"
	other.display_name = "X"
	var relation := FactionRelation.new()
	relation.other_faction_id = &"faction_1"
	relation.attitude = -90
	relation.at_war = true
	other.relations = [relation]
	manager.change(other, 40)
	_check(other.get_relation(&"faction_1").at_war and manager.get_reputation(_federation) == 0 and manager.get_reputation(other) == 40, "a faction being at war with another says nothing about the player's reputation")
	relation.attitude = 10
	_check(manager.get_reputation(other) == 40, "...and changing their relation does not move it")


# ------------------------------------------------------------------ eligibility

func _check_eligibility() -> void:
	var territory := _new_territory()
	var manager := _new_manager(territory)
	_check(manager.meets(_federation, 0) and manager.meets(_federation, -100) and not manager.meets(_federation, 20), "meets() compares reputation with a minimum")
	manager.change(_federation, 25)
	_check(manager.meets(_federation, 20) and not manager.meets(_federation, 40), "...as reputation changes")

	var game := _contract_game(manager, territory)
	var contracts: ContractManager = game["contracts"]
	var earth := _registry.location(&"earth")
	var offers := contracts.get_available(earth)
	var open_job: Contract = offers[0]
	var picky: Contract = offers[1]
	picky.required_reputation = 40
	manager.reset_state()
	_check(contracts.check_accept(open_job, earth) == ContractManager.AcceptResult.OK, "a contract that asks for nothing is open to everyone, however hated the player is")
	manager.change(_federation, -100)
	_check(contracts.check_accept(open_job, earth) == ContractManager.AcceptResult.OK, "...even at the bottom of the scale")
	manager.reset_state()
	_check(contracts.check_accept(picky, earth) == ContractManager.AcceptResult.REPUTATION_TOO_LOW, "a contract that needs Friendly (40) is refused at 0")
	_check(ContractManager.get_result_message(ContractManager.AcceptResult.REPUTATION_TOO_LOW) != "", "...with a message")
	_check(contracts.accept(picky, earth) == ContractManager.AcceptResult.REPUTATION_TOO_LOW and picky.status == Contract.Status.AVAILABLE, "accepting it changes nothing")
	manager.change(_federation, 45)
	_check(contracts.check_accept(picky, earth) == ContractManager.AcceptResult.OK, "...and is allowed once the reputation is there")
	_check(picky.to_dict()["required_reputation"] == 40, "the requirement is saved with the contract")
	game["contracts"].free()


# ---------------------------------------------------------------------- saving

func _check_saving() -> void:
	var manager := _new_manager()
	_check(manager.save_state() == {"values": {}} and manager.validate_state(manager.save_state(), _registry).is_empty(), "a new player saves an empty reputation, which validates")
	manager.change(_federation, 37)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(manager.save_state()))
	_check(parsed["values"].keys() == ["faction_1"] and int(parsed["values"]["faction_1"]) == 37 and manager.validate_state(parsed, _registry).is_empty(), "reputation is saved per faction by id and validates")
	var other := _new_manager()
	other.load_state(parsed, _registry)
	_check(other.get_reputation(_federation) == 37 and other.get_standing(_federation) == "Favourable", "it loads back")
	_check(not manager.validate_state({"values": {"faction_99": 5}}, _registry).is_empty(), "an unknown faction is rejected")
	_check(not manager.validate_state({"values": {"faction_1": 500}}, _registry).is_empty(), "a value off the scale is rejected")
	_check(not manager.validate_state({"values": {"faction_1": 1.5}}, _registry).is_empty() and not manager.validate_state({"values": {"faction_1": "high"}}, _registry).is_empty(), "a value that is not a whole number is rejected")
	_check(not manager.validate_state({"values": []}, _registry).is_empty() and not manager.validate_state(null, _registry).is_empty(), "values must be an object")
	var fresh := _new_manager()
	fresh.load_state({"values": {"faction_1": 0}}, _registry)
	_check(fresh.save_state() == {"values": {}}, "a neutral value is not stored")


func _check_game() -> void:
	_clean()
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Save").save_path = PATH
	root.add_child(main)
	await process_frame
	await process_frame
	var reputation: ReputationManager = main.get_node("Reputation")
	var saves: SaveManager = main.get_save_manager()
	_check(reputation.get_reputation(_federation) == 0 and reputation.get_standing(_federation) == "Neutral", "a new game starts neutral with the Federation")
	reputation.change(_federation, 25)
	_check(saves.save_game(), "save with reputation 25")
	var document := saves.build_document()
	_check(document.has("reputation") and document["reputation"]["values"] == {"faction_1": 25}, "the save has a reputation section")
	reputation.change(_federation, -60)
	_check(main.load_game()["ok"] and reputation.get_reputation(_federation) == 25, "loading restores it")
	document.erase("reputation")
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	reputation.change(_federation, 10)
	_check(main.load_game()["ok"] and reputation.get_reputation(_federation) == 0, "a save from before reputation existed loads as neutral")
	document["reputation"] = {"values": {"faction_77": 5}}
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	reputation.change(_federation, 12)
	_check(not main.load_game()["ok"] and reputation.get_reputation(_federation) == 12, "a damaged reputation section is refused and changes nothing")
	main.queue_free()
	await process_frame
	_clean()


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _check(condition: bool, label: String) -> void:
	print("PASS  " if condition else "FAIL  ", label)
	if not condition:
		_failures += 1
