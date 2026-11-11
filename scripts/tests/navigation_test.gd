extends SceneTree
## Tests the navicomputer and the jump sequence through the real game scene:
## choosing a destination, the HUD readout, J, the warp acceleration, the flash,
## the arrival, and saving the chosen destination. Takes about ten seconds of
## real time because the jump sequence is timed. Run with:
##   Godot --headless --path . --script res://scripts/tests/navigation_test.gd

const PATH := "user://navigation_test.json"

var _failures: int = 0


func _init() -> void:
	_clean()
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Save").save_path = PATH
	root.add_child(main)
	await process_frame
	await process_frame

	var travel: TravelManager = main.get_node("Travel")
	var hud: Hud = main.get_node("Hud")
	var flash: JumpFlash = main.get_node("JumpFlash")
	var saves: SaveManager = main.get_save_manager()
	var ship := main.get_player_ship()
	var map: GalaxyMapScreen = main.get_node("GalaxyMapScreen")

	# --- The navicomputer, with no destination.
	_check(hud.get_node("%NavDestinationLabel").text == "No destination selected", "with nothing chosen it says so")
	_check(hud.get_node("%NavCentreRow").get_node("%Value").text == "0 / 2,000", "it shows the distance from the system centre (%s)" % hud.get_node("%NavCentreRow").get_node("%Value").text)
	_check(hud.get_node("%NavStatusLabel").text == "", "and no status")
	var result := main.try_jump()
	_check(not result.ok and not ship.warping, "J without a destination does nothing")
	_check(hud.get_node("%NavMessageLabel").visible and "destination" in hud.get_node("%NavMessageLabel").text, "...and tells the player why: %s" % hud.get_node("%NavMessageLabel").text)

	# --- Choosing a destination.
	_check(not travel.set_destination(&"barnards_star"), "a system with no direct link cannot be the destination")
	_check(travel.set_destination(&"sirius") and travel.get_destination() == &"sirius", "a linked system can")
	await process_frame
	_check(hud.get_node("%NavDestinationLabel").text == "Selected destination: Sirius", "the HUD shows: %s" % hud.get_node("%NavDestinationLabel").text)
	_check(hud.get_node("%NavStatusLabel").text == "TOO CLOSE TO CENTRE", "in the middle of Sol it says too close: %s" % hud.get_node("%NavStatusLabel").text)
	_check(not main.try_jump().ok and not ship.warping, "J refuses while too close")
	_check("centre" in hud.get_node("%NavMessageLabel").text, "...with the reason: %s" % hud.get_node("%NavMessageLabel").text)

	# --- Outside the minimum range: JUMP OK, in green.
	ship.global_position = Vector2(1990, 0)
	await process_frame
	_check(hud.get_node("%NavStatusLabel").text == "TOO CLOSE TO CENTRE", "just inside 2,000 px is still too close")
	ship.global_position = Vector2(2010, 0)
	ship.velocity = Vector2.ZERO
	ship.rotation = 0.0
	await process_frame
	var status: Label = hud.get_node("%NavStatusLabel")
	_check(status.text == "JUMP OK - PRESS J" and status.get_theme_color("font_color").g > status.get_theme_color("font_color").r, "outside 2,000 px it reads JUMP OK in green")
	_check(hud.get_node("%NavCentreRow").get_node("%Value").text == "2,010 / 2,000", "with the distance: %s" % hud.get_node("%NavCentreRow").get_node("%Value").text)

	# --- J: warp, flash, arrival.
	ship.rotation = 0.0  # pointing right: the ship should come in from the left
	var old_system := main.get_system()
	var credits := main.get_player_data().credits
	_press("jump")
	await process_frame
	_check(ship.warping, "J starts the warp")
	await process_frame
	_check(status.text == "JUMPING...", "the status reads JUMPING...")
	await create_timer(0.5).timeout
	var speed_half := ship.velocity.length()
	_check(speed_half > 1500.0, "the ship is accelerating hard (%d px/s after half a second)" % speed_half)
	_press("galaxy_map")
	await process_frame
	_check(not map.visible and not paused, "the galaxy map cannot be opened mid-jump")
	await create_timer(1.0).timeout
	_check(ship.velocity.length() > speed_half and ship.velocity.length() > 5000.0, "it keeps accelerating towards warp speed (%d px/s)" % ship.velocity.length())
	_check(main.get_system() == old_system and not flash.visible, "before two seconds are up, nothing has happened yet")
	await create_timer(0.7).timeout
	_check(flash.visible or main.get_system() != old_system, "at two seconds the screen flashes")
	await create_timer(0.7).timeout
	_check(main.get_system().system_id == &"sirius", "the player has arrived in Sirius")
	_check(not ship.warping and ship.velocity.length() <= Main.ARRIVAL_SPEED + 1.0, "warp ended; the ship drifts in slowly (%d px/s)" % ship.velocity.length())
	_check(absf(ship.global_position.length() - main.get_system().jump_radius) < 150.0, "on the edge of the system")
	_check(ship.global_position.x < -1800.0 and absf(ship.global_position.y) < 300.0 and absf(ship.rotation) < 0.01, "pointing right, the ship came in from the left and still points right")
	_check(travel.get_destination() == &"", "the destination is cleared")
	_check(hud.get_node("%NavDestinationLabel").text == "No destination selected" and status.text == "", "the navicomputer resets")
	_check(main.get_player_data().credits == credits, "credits unchanged")
	await create_timer(0.6).timeout
	_check(not flash.visible, "the flash has faded away")

	# --- Docked: J gives the reason.
	travel.set_destination(&"tau_ceti")
	var aurelia_target: Targetable
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name == "Persephone":
			aurelia_target = t
	ship.global_position = aurelia_target.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	main.get_node("Targeting").select(aurelia_target)
	main.get_node("Docking").try_dock()
	await process_frame
	_check(not main.try_jump().ok and "Depart" in hud.get_node("%NavMessageLabel").text, "docked: J says to depart first")
	main.get_node("Docking").undock()

	# --- The destination is saved and restored.
	_check(saves.save_game(), "save with a destination chosen")
	travel.clear_destination()
	_check(main.load_game()["ok"] and travel.get_destination() == &"tau_ceti", "the destination is restored by loading")
	var document := saves.build_document()
	document["galaxy"]["destination"] = "procyon"  # not linked to Sirius
	_write(PATH, JSON.stringify(document))
	_check(main.load_game()["ok"] and travel.get_destination() == &"", "a saved destination that is not linked is dropped")
	document["galaxy"]["destination"] = "andromeda"
	_write(PATH, JSON.stringify(document))
	_check(not main.load_game()["ok"], "a destination that does not exist is refused")
	document["galaxy"].erase("destination")
	_write(PATH, JSON.stringify(document))
	_check(main.load_game()["ok"] and travel.get_destination() == &"", "a save from before destinations loads")

	_clean()
	main.queue_free()
	await process_frame
	print("")
	print("NAVIGATION TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


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
