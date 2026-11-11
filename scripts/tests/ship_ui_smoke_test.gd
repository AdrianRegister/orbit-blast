extends SceneTree
## Plays the shipyard and outfitters through the real game scene and its
## buttons: dock, install an upgrade, buy a ship keeping the old one, name it,
## then buy another ship trading the old one in. Run with:
##   Godot --headless --path . --script res://scripts/tests/ship_ui_smoke_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var ship: PlayerShip = main.get_node("PlayerShip")
	var targeting: TargetingManager = main.get_node("Targeting")
	var docking: DockingManager = main.get_node("Docking")
	var settlement: SettlementScreen = main.get_node("SettlementScreen")
	var outfitters: OutfittersScreen = main.get_node("OutfittersScreen")
	var shipyard: ShipyardScreen = main.get_node("ShipyardScreen")
	var prompt: NamePrompt = main.get_node("NamePrompt")
	var player: PlayerData = main.get_player_data()
	var first := player.fleet.get_active()
	_check(first.model.id == &"shuttle" and player.cargo.capacity == 20, "the game starts with the shuttle (hold 20)")

	# --- Mars: outfitters but no shipyard.
	_dock(ship, targeting, docking, _find("Mars"))
	await process_frame
	_check(settlement.get_node("%ShipyardButton").disabled, "Mars has no shipyard button")
	_check(not settlement.get_node("%OutfitterButton").disabled, "Mars has an outfitter button")
	settlement.get_node("%OutfitterButton").pressed.emit()
	await process_frame
	_check(outfitters.visible, "the outfitters open")
	var table: Tree = outfitters.get_node("%Table")
	var credits := player.credits
	var item := table.get_root().get_first_child()
	item.select(OutfittersScreen.Column.UPGRADE)
	table.item_selected.emit()
	await process_frame
	var install: Button = outfitters.get_node("%InstallButton")
	_check(not install.disabled, "install is enabled for the cargo upgrade")
	install.pressed.emit()
	await process_frame
	_check(player.cargo.capacity == 35 and player.credits == credits - 8000, "cargo upgrade installed: hold %d, credits paid once" % player.cargo.capacity)
	_check("INSTALLED" in outfitters.get_node("%MessageLabel").text, "the screen confirms: %s" % outfitters.get_node("%MessageLabel").text)
	# Engine II first is refused with a reason (rows: cargo, engine I, II, III).
	var engine_two := table.get_root().get_child(2)
	engine_two.select(OutfittersScreen.Column.UPGRADE)
	table.item_selected.emit()
	await process_frame
	_check(install.disabled, "engine II cannot be installed before engine I")
	_check("previous tier" in engine_two.get_text(OutfittersScreen.Column.STATUS), "its status says why: %s" % engine_two.get_text(OutfittersScreen.Column.STATUS))
	main.get_node("OutfittersScreen")._unhandled_input(_escape())
	_check(not outfitters.visible, "Esc closes the outfitters")

	# --- Earth: shipyard.
	docking.undock()
	await create_timer(1.7).timeout
	_dock(ship, targeting, docking, _find("Earth"))
	await process_frame
	_check(not settlement.get_node("%ShipyardButton").disabled, "Earth has a shipyard button")
	settlement.get_node("%ShipyardButton").pressed.emit()
	await process_frame
	_check(shipyard.visible, "the shipyard opens")
	var ships_table: Tree = shipyard.get_node("%Table")
	_check(ships_table.get_root().get_child_count() == 3, "Earth sells three ships")
	var freighter_row := ships_table.get_root().get_child(1)
	freighter_row.select(ShipyardScreen.Column.SHIP)
	ships_table.item_selected.emit()
	await process_frame
	_check(shipyard.get_node("%SpriteRect").texture == freighter_row.get_metadata(ShipyardScreen.Column.SHIP).texture, "the shipyard shows the selected ship's sprite")
	var choice: ChoicePopup = shipyard.get_node("%ChoicePopup")
	credits = player.credits
	shipyard.get_node("%BuyButton").pressed.emit()
	await process_frame
	_check(choice.visible, "buying asks whether to trade in or keep the old ship")
	var buttons := choice.get_node("%Buttons")
	_check(buttons.get_child_count() == 3, "trade in, keep, cancel")
	buttons.get_child(2).pressed.emit()
	await process_frame
	_check(not choice.visible and player.fleet.ships.size() == 1 and player.credits == credits, "cancel changes nothing")
	shipyard.get_node("%BuyButton").pressed.emit()
	await process_frame
	buttons.get_child(1).pressed.emit()  # keep
	await process_frame
	_check(player.fleet.get_active().model.id == &"freighter" and player.credits == credits - 250000, "the freighter was bought at full price")
	_check(first.is_previous() and player.fleet.ships.size() == 2, "the shuttle is kept and flagged PREVIOUS_SHIP")
	_check(prompt.visible, "the player is asked to name the new ship")
	prompt.get_node("%NameInput").text = ""
	prompt._on_text_changed("")
	_check(prompt.get_node("%OkButton").disabled, "an empty name cannot be confirmed")
	prompt.get_node("%NameInput").text = "x".repeat(60)
	_check(prompt.get_node("%NameInput").text.length() <= 50, "names are limited to 50 characters")
	prompt.get_node("%NameInput").text = "Big Mama"
	prompt._on_text_changed("Big Mama")
	prompt.get_node("%OkButton").pressed.emit()
	await process_frame
	_check(player.fleet.get_active().ship_name == "Big Mama" and not prompt.visible, "the ship is named")
	_check(player.cargo.capacity == 2000, "hold follows the freighter")

	# --- Trade the freighter in for a shuttle: price floor of 10,000.
	var shuttle_row := ships_table.get_root().get_child(0)
	shuttle_row.select(ShipyardScreen.Column.SHIP)
	ships_table.item_selected.emit()
	await process_frame
	credits = player.credits
	shipyard.get_node("%BuyButton").pressed.emit()
	await process_frame
	_check("10,000" in buttons.get_child(0).text, "trade-in option shows the 10,000 CR floor (%s)" % buttons.get_child(0).text)
	buttons.get_child(0).pressed.emit()
	await process_frame
	_check(player.credits == credits - 10000, "a huge trade-in still costs 10,000")
	_check(player.fleet.get_active().model.id == &"shuttle" and player.fleet.ships.size() == 2, "freighter gone, old shuttle and the new one remain")
	prompt.get_node("%OkButton").pressed.emit()
	await process_frame
	_check(not prompt.visible, "default name accepted")

	print("")
	print("SHIP UI SMOKE TEST: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _escape() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	return event


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
