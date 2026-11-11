extends SceneTree
## Headless smoke test of the real game scene: dock at Earth, open the mission
## computer, accept a contract through the UI, fly to Mars and see it delivered.
## Run with:
##   Godot --headless --path . --script res://scripts/tests/mission_ui_smoke_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	var big_hold: ShipStats = load("res://resources/ships/shuttle_stats.tres").duplicate()
	big_hold.cargo_capacity = 500  # big enough for the test cargo, too small for the bulk contract (480 + 40)
	main.starting_ship_stats = big_hold
	root.add_child(main)
	await process_frame
	await process_frame

	var ship: PlayerShip = main.get_node("PlayerShip")
	var targeting: TargetingManager = main.get_node("Targeting")
	var docking: DockingManager = main.get_node("Docking")
	var settlement: SettlementScreen = main.get_node("SettlementScreen")
	var missions: MissionComputerScreen = main.get_node("MissionComputerScreen")
	var economy: EconomyManager = main.get_node("Economy")
	var hud: Hud = main.get_node("Hud")

	var earth := _find("Earth")
	var mars := _find("Mars")
	_check(earth != null and mars != null, "found Earth and Mars")

	_dock(ship, targeting, docking, earth)
	await process_frame
	var button: Button = settlement.get_node("%MissionButton")
	_check(not button.disabled, "Mission computer enabled at Earth")
	_check(not missions.visible, "mission computer starts closed")
	button.pressed.emit()
	await process_frame
	_check(missions.visible, "button opens the mission computer")

	# Lay out at the design resolution before measuring.
	missions.get_node("Panel").size = Vector2(1920, 1080)
	await process_frame
	var table: Tree = missions.get_node("%Table")
	var side: Control = missions.get_node("%CargoPanel").get_parent()
	var total: float = table.size.x + side.size.x
	_check(table.size.x > 0.0 and side.size.x > 0.0, "list and detail panel both visible")
	_check(absf(table.size.x / total - 0.75) < 0.01, "list is 75%% of the row (%.1f%%)" % [100.0 * table.size.x / total])

	var root_item := table.get_root()
	_check(root_item.get_child_count() == 3, "three sections: available, active, completed")
	var available := root_item.get_first_child()
	_check(available.get_child_count() == 7, "seven contracts offered at Earth (three cargo runs in Sol, four new ones, none of them exploration)")

	# Select the first contract and accept it with the button.
	var accept: Button = missions.get_node("%AcceptButton")
	_check(accept.disabled, "accept is disabled with nothing selected")
	var first := available.get_first_child()
	first.select(MissionComputerScreen.Column.TITLE)
	table.item_selected.emit()
	await process_frame
	_check(not accept.disabled, "accept enabled for an available contract")
	accept.pressed.emit()
	await process_frame
	_check(economy.get_cargo().get_used() == 40, "accepting loads 40 units of contract cargo")
	var active_section: TreeItem = table.get_root().get_first_child().get_next()
	_check(active_section.get_child_count() == 1, "the contract is listed as active")
	_check(accept.disabled, "accept is disabled for an active contract")
	var lines := hud.get_node("%CargoList").get_node("%Lines")
	var shown := ""
	for row in lines.get_children():
		for label in row.get_children():
			shown += (label as Label).text + " "
	_check(shown.to_lower().contains("food (contract, mars in the sol system)"), "HUD cargo list shows contract cargo and destination (%s)" % shown)

	# The oversized contract is refused with a message.
	var bulk: TreeItem = table.get_root().get_first_child().get_child(1)
	bulk.select(MissionComputerScreen.Column.TITLE)
	table.item_selected.emit()
	await process_frame
	_check(accept.disabled, "accept disabled when the cargo does not fit")
	var message: Label = missions.get_node("%MessageLabel")
	_check(message.text == "NOT ENOUGH FREE CARGO SPACE", "reason shown: '%s'" % message.text)

	# Undocking closes the screen. Then deliver at Mars.
	docking.undock()
	await process_frame
	_check(not missions.visible, "undocking closes the mission computer")
	var credits_before := economy.get_credits()
	await create_timer(1.7).timeout  # redock cooldown after departing
	_dock(ship, targeting, docking, mars)
	await process_frame
	_check(economy.get_credits() == credits_before + 12000, "delivery at Mars paid 12,000 CR")
	_check(economy.get_cargo().get_used() == 0, "contract cargo removed")
	var popup: EventPopup = main.get_node("EventPopup")
	_check(popup.visible, "a popup announces the delivery")
	_check(popup.get_node("%TitleLabel").text == "DELIVERY COMPLETE", "popup title")
	var flavour: String = popup.get_node("%FlavourLabel").text
	var pool: FlavourPool = load("res://resources/flavour/contract_delivery.tres")
	var possible: Array[String] = []
	for entry in pool.entries:
		possible.append(entry.replace("{destination}", "Mars"))
	_check(possible.has(flavour), "popup shows one of the flavour entries")
	_check(popup.get_node("%DetailRows").get_child_count() == 4, "popup lists contract, cargo, destination and reward")
	popup.get_node("%OkButton").pressed.emit()
	await process_frame
	_check(not popup.visible, "OK closes the popup")
	button = settlement.get_node("%MissionButton")
	_check(not button.disabled, "Mission computer enabled at Mars")
	button.pressed.emit()
	await process_frame
	var completed: TreeItem = table.get_root().get_first_child().get_next().get_next()
	_check(completed.get_child_count() == 1, "the contract is listed as completed")

	print("")
	if _failures == 0:
		print("MISSION UI SMOKE TEST: all passed")
	else:
		print("MISSION UI SMOKE TEST: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _find(target_name: String) -> Targetable:
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name == target_name:
			return t
	return null


func _dock(ship: PlayerShip, targeting: TargetingManager, docking: DockingManager, place: Targetable) -> void:
	ship.global_position = place.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	targeting.select(place)
	docking.try_dock()


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS  ", description)
	else:
		print("FAIL  ", description)
		_failures += 1
