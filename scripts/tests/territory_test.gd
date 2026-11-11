extends SceneTree
## Settlements own themselves and a star system's control is derived from them,
## so a system can be contested. Checks the derivation, the signals, saving, and
## the places that read ownership (shipyards, contracts, the HUD, the galaxy
## map). Run with:
##   Godot --headless --path . --script res://scripts/tests/territory_test.gd

const PATH := "user://territory_test.json"

var _failures: int = 0
var _registry: ContentRegistry
var _galaxy: Galaxy
var _federation: Faction
var _rival: Faction


func _init() -> void:
	_registry = ContentRegistry.new()
	_galaxy = load("res://resources/universe/galaxy.tres")
	_federation = _registry.faction(&"faction_1")
	_rival = Faction.new()
	_rival.id = &"faction_2"
	_rival.display_name = "Rival"
	_rival.colour = Color(1.0, 0.4, 0.3)

	_check_derivation()
	_check_signals()
	_check_saving()
	await _check_game()

	print("")
	print("TERRITORY TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _new_territory() -> TerritoryManager:
	var territory := TerritoryManager.new()
	territory.setup(_galaxy, _registry)
	return territory


# ------------------------------------------------------------------ derivation

func _check_derivation() -> void:
	var territory := _new_territory()
	var earth := _registry.location(&"earth")
	var mars := _registry.location(&"mars")
	var victory := _registry.location(&"victory_i")

	var sol := territory.get_control(&"sol")
	_check(sol.status == SystemControl.Status.CONTROLLED and sol.is_controlled_by(_federation) and sol.get_text() == "Federation", "Sol starts controlled by the Federation")
	_check(territory.owner_of(earth) == _federation and territory.owner_id_of(mars) == &"faction_1" and territory.owner_name_of(victory) == "Federation", "its settlements start with their own owners")
	var wolf := territory.get_control(&"wolf_359")
	_check(wolf.status == SystemControl.Status.CONTROLLED and wolf.controller == _galaxy.get_claim(&"wolf_359"), "a system with no settlements goes to whoever claims it on the map")
	_check(territory.get_control(&"koria").status == SystemControl.Status.UNCLAIMED and territory.get_control(&"koria").get_text() == "None", "an unclaimed system with independent settlements is unclaimed")
	_check(territory.get_control(&"nowhere").status == SystemControl.Status.UNCLAIMED, "an unknown system is simply unclaimed")

	# One settlement of another faction: Sol is contested, with no owner.
	territory.transfer_settlement(mars, _rival)
	var contested := territory.get_control(&"sol")
	_check(contested.is_contested() and contested.controller == null and territory.is_contested(&"sol"), "Earth and Victory I Federation, Mars Rival: Sol is contested")
	_check(contested.factions.size() == 2 and contested.factions[0].id == &"faction_1" and contested.factions[1].id == &"faction_2", "...with both factions listed, sorted by id")
	_check(contested.get_text() == "Contested: Federation, Rival" and contested.involves(_rival) and not contested.is_controlled_by(_federation), "...described as contested")
	_check(territory.owner_of(earth) == _federation and territory.owner_of(mars) == _rival, "each settlement still has its own owner")
	_check(territory.get_control(&"procyon").is_controlled_by(_federation), "other systems are not affected")

	# An independent settlement does not make a system contested.
	territory.transfer_settlement(mars, null)
	var independent := territory.get_control(&"sol")
	_check(independent.is_controlled_by(_federation) and territory.owner_of(mars) == null and territory.owner_name_of(mars) == "", "an independent settlement does not contest a system")

	# All settlements to one faction, whichever it is.
	territory.transfer_settlement(mars, _rival)
	territory.transfer_settlement(earth, _rival)
	territory.transfer_settlement(victory, _rival)
	_check(territory.get_control(&"sol").is_controlled_by(_rival), "when one faction owns every settlement it controls the system")
	territory.reset_state()
	_check(territory.get_control(&"sol").is_controlled_by(_federation) and territory.owner_of(mars) == _federation, "resetting gives every settlement its starting owner back")


# --------------------------------------------------------------------- signals

func _check_signals() -> void:
	var territory := _new_territory()
	var earth := _registry.location(&"earth")
	var mars := _registry.location(&"mars")
	var victory := _registry.location(&"victory_i")
	var changed: Array = []
	var control: Array = []
	var contested: Array = []
	var any := [0]
	territory.settlement_owner_changed.connect(func(id: StringName, old: Faction, new: Faction) -> void: changed.append([id, old, new]))
	territory.system_control_changed.connect(func(id: StringName) -> void: control.append(id))
	territory.system_became_contested.connect(func(id: StringName) -> void: contested.append(id))
	territory.territory_changed.connect(func() -> void: any[0] += 1)

	territory.transfer_settlement(mars, _federation)
	_check(changed.is_empty() and any[0] == 0, "giving a settlement to its current owner announces nothing")
	territory.transfer_settlement(mars, _rival)
	_check(changed.size() == 1 and changed[0][0] == &"mars" and changed[0][1] == _federation and changed[0][2] == _rival, "a settlement changing hands is announced with the old and new owner")
	_check(control == [&"sol"] and contested == [&"sol"] and any[0] == 1, "...and the system becoming contested is announced once")
	territory.transfer_settlement(victory, _rival)
	_check(changed.size() == 2 and control == [&"sol"] and contested == [&"sol"], "another settlement changing hands inside a contested system changes nothing else")
	territory.transfer_settlement(earth, _rival)
	_check(control == [&"sol", &"sol"] and contested == [&"sol"], "the contest ending is a control change but not a new contest")
	territory.transfer_settlement(earth, _federation)
	_check(contested == [&"sol", &"sol"], "a system can become contested again")
	_check(territory.save_state()["owners"] == {"mars": "faction_2", "victory_i": "faction_2"}, "only settlements that differ from their starting owner are saved")
	territory.transfer_settlement(mars, _federation)
	territory.transfer_settlement(victory, _federation)
	_check(territory.save_state()["owners"].is_empty(), "giving a settlement back to its starting owner removes the override")


# ---------------------------------------------------------------------- saving

func _check_saving() -> void:
	var territory := _new_territory()
	var mars := _registry.location(&"mars")
	var earth := _registry.location(&"earth")
	territory.transfer_settlement(mars, _registry.faction(&"faction_1"))  # a no-op
	var state := territory.save_state()
	_check(state == {"owners": {}} and territory.validate_state(state, _registry).is_empty(), "an untouched territory saves as empty and validates")
	# Independent settlements are saved too (as "").
	territory.transfer_settlement(earth, null)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(territory.save_state()))
	_check(parsed == {"owners": {"earth": ""}} and territory.validate_state(parsed, _registry).is_empty(), "an independent settlement is saved and validates")
	var other := _new_territory()
	other.load_state(parsed, _registry)
	_check(other.owner_of(earth) == null and other.owner_of(mars) == _federation and other.save_state() == territory.save_state(), "it loads back identically")
	_check(not territory.validate_state({"owners": {"no_such_place": "faction_1"}}, _registry).is_empty(), "an unknown settlement is rejected")
	_check(not territory.validate_state({"owners": {"mars": "faction_99"}}, _registry).is_empty(), "an unknown faction is rejected")
	_check(not territory.validate_state({"owners": {"cerberus": "faction_1"}}, _registry).is_empty(), "something that cannot be landed on is rejected")
	_check(not territory.validate_state({"owners": []}, _registry).is_empty() and not territory.validate_state("x", _registry).is_empty(), "owners must be an object")


# -------------------------------------------------------------------- the game

func _check_game() -> void:
	_clean()
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Save").save_path = PATH
	root.add_child(main)
	await process_frame
	await process_frame
	var territory: TerritoryManager = main.get_node("Territory")
	var contracts: ContractManager = main.get_node("Contracts")
	var ships: ShipManager = main.get_node("Ships")
	var saves: SaveManager = main.get_save_manager()
	var map: GalaxyMapScreen = main.get_node("GalaxyMapScreen")
	var earth := _registry.location(&"earth")
	var mars := _registry.location(&"mars")

	# Shipyards judge the faction of a location by its current owner.
	var frigate: ShipStats = _registry.ship_stats(&"federation_frigate")
	var yard := InhabitedData.new()
	yard.id = &"test_yard"
	yard.faction = _federation
	yard.shipyard_ships = [frigate]
	_check(ships.get_ships_for_sale(yard) == [frigate], "a Federation shipyard sells a Federation ship")
	territory.transfer_settlement(yard, _rival)
	_check(ships.get_ships_for_sale(yard).is_empty(), "...until the shipyard changes hands")
	territory.transfer_settlement(yard, _federation)
	_check(ships.get_ships_for_sale(yard) == [frigate], "...and again once it is back")

	# The HUD's "owned by" row follows the current owner.
	var mars_node: InhabitedNode = null
	for node in main.get_system().get_inhabited_nodes():
		if node.data == mars:
			mars_node = node
	var targetable: Targetable = mars_node.get_node("Targetable")
	_check(_owned_by(targetable) == "Federation", "the HUD says Mars is owned by the Federation")

	# A contract's issuing faction follows the current owner too.
	var offer: Contract = null
	for contract in contracts.get_available(mars):
		offer = contract
	_check(offer != null and offer.get_issuing_faction() == _federation, "a Mars contract serves the Federation")

	# Mars changes hands: everything notices. (The second faction exists only in
	# this test; the game has not defined one yet.)
	var second := Faction.new()
	second.id = &"faction_2"
	second.display_name = "Rival"
	second.colour = Color(1.0, 0.4, 0.3)
	territory.transfer_settlement(mars, second)
	_check(_owned_by(targetable) == "Rival", "the HUD follows: Mars is owned by the Rival")
	_check(offer.get_issuing_faction() == second, "the contract now serves the Rival")
	map.open()
	await process_frame
	await process_frame
	var view: GalaxyMapView = map.get_map()
	_check(view.get_control(&"sol") != null and view.get_control(&"sol").is_contested(), "the galaxy map knows Sol is contested")
	map._show_system(&"sol")
	await process_frame
	_check("Contested" in _row_text(map) and "Rival" in _row_text(map), "its panel says so: %s" % _row_text(map).replace("\n", " | "))
	map.close()

	# Saved and restored with the game; an older save without the section loads.
	_check(saves.save_game(), "save with Mars held by the Rival")
	var document := saves.build_document()
	_check(document.has("territory") and document["territory"]["owners"] == {"mars": "faction_2"}, "the save has a territory section")
	territory.reset_state()
	_check(territory.owner_of(mars) == _federation, "(setup) back to the starting owners")
	document.erase("territory")
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(document))
	file.close()
	territory.transfer_settlement(earth, null)
	_check(main.load_game()["ok"], "a save from before territory was saved loads")
	_check(territory.owner_of(earth) == _federation and territory.owner_of(mars) == _federation, "...with every settlement back at its starting owner")

	main.queue_free()
	await process_frame
	_clean()


func _owned_by(targetable: Targetable) -> String:
	for row in targetable.get_detail_rows():
		if row[0] == "OWNED BY":
			return row[1]
	return ""


func _row_text(map: GalaxyMapScreen) -> String:
	var text := ""
	for row in map.get_node("%DetailRows").get_children():
		for label in row.get_children():
			if label is Label:
				text += (label as Label).text + " "
		text += "\n"
	return text


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _check(condition: bool, label: String) -> void:
	print("PASS  " if condition else "FAIL  ", label)
	if not condition:
		_failures += 1
