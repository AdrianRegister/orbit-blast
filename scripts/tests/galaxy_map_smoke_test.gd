extends SceneTree
## Plays the galaxy map through the real game scene: opening with M, layout at
## the configured coordinates, selecting, panning, zooming, the information
## panel, reachability, jumping and closing. Run with:
##   Godot --headless --path . --script res://scripts/tests/galaxy_map_smoke_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var map: GalaxyMapScreen = main.get_node("GalaxyMapScreen")
	var view := map.get_map()
	var galaxy: Galaxy = main.galaxy
	var travel: TravelManager = main.get_node("Travel")
	var ship := main.get_player_ship()
	var targeting: TargetingManager = main.get_node("Targeting")

	_check(not map.visible and not paused, "the map starts closed and the game runs")

	# --- M opens it, paused, centred on the current system.
	_press("galaxy_map")
	await process_frame
	map.get_node("Panel").size = Vector2(1920, 1080)
	await process_frame
	await process_frame
	_check(map.visible and paused, "M opens the map and pauses the game")
	_check(view.get_marker_position(&"sol").distance_to(view.size * 0.5) < 1.0, "it opens centred on the current system (Sol)")
	_check(map.get_selected_id() == &"sol", "the current system is selected")
	_check(map.get_node("%StatusLabel").text == "CURRENT SYSTEM", "the panel says it is the current system")
	_check(not map.get_node("%JumpButton").visible, "no Jump button for the system you are in")

	# --- Markers sit at the configured coordinates.
	for id in galaxy.get_system_ids():
		var expected: Vector2 = view.size * 0.5 + (galaxy.get_map_position(id) - galaxy.get_map_position(&"sol")) * view.zoom
		_check(view.get_marker_position(id).distance_to(expected) < 0.01, "%s is drawn at its configured position" % galaxy.get_summary(id).system_name)
	_check(view.get_marker_position(&"epsilon_eridani").x > view.get_marker_position(&"barnards_star").x, "the layout is the configured geography")

	# --- Selecting by clicking.
	_click(view, view.get_marker_position(&"tau_ceti"))
	_check(map.get_selected_id() == &"tau_ceti", "clicking a marker selects it")
	_check(map.get_node("%NameLabel").text == "TAU CETI" and map.get_node("%StatusLabel").text == "UNEXPLORED", "the panel names it and says unexplored")
	var rows := _row_text(map)
	_check("Unknown" in rows and "Direct jump from Sol" in rows, "unexplored details are hidden, the route is shown (%s)" % rows.replace("\n", " | "))
	_check("fuel" in rows and "LINKS TO" in rows and "Sol" in rows, "cost and destinations are shown")
	var jump: Button = map.get_node("%JumpButton")
	_check(jump.visible and not jump.disabled and jump.text == "SELECT DESTINATION", "a linked system offers SELECT DESTINATION, even from the middle of Sol")
	_check("press J" in map.get_node("%MessageLabel").text, "and says what to do next: %s" % map.get_node("%MessageLabel").text)
	_click(view, view.get_marker_position(&"barnards_star"))
	_check("No direct jump" in _row_text(map) and jump.disabled, "a system that is not linked cannot be selected")
	var before := map.get_selected_id()
	_click(view, view.size - Vector2(20, 20))
	_check(map.get_selected_id() == before, "clicking empty space keeps the selection")
	_click(view, view.get_marker_position(&"sol"))
	_check(map.get_selected_id() == &"sol" and map.get_node("%NameLabel").text == "SOL", "Sol can be selected again")

	# --- Zoom keeps the point under the cursor still; labels stay readable (fixed size).
	var anchor := view.size * 0.5 + Vector2(40, 20)
	var map_point := view.view_to_map(anchor)
	var zoom_before := view.zoom
	view.zoom_by(1.5, anchor)
	_check(is_equal_approx(view.zoom, zoom_before * 1.5) and view.view_to_map(anchor).distance_to(map_point) < 0.01, "zoom is anchored on the cursor")
	view.zoom_by(100.0, anchor)
	_check(view.zoom == GalaxyMapView.MAX_ZOOM, "zoom is limited")
	view.zoom_by(0.0001, anchor)
	_check(view.zoom == GalaxyMapView.MIN_ZOOM, "zoom out is limited")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = anchor
	view._gui_input(wheel)
	_check(view.zoom > GalaxyMapView.MIN_ZOOM, "the mouse wheel zooms")

	# --- Pan by dragging, limited to the galaxy.
	view.focus_on(&"sol")
	var start := view.center
	_drag(view, Vector2(500, 400), Vector2(400, 380))
	_check(view.center.distance_to(start + Vector2(100, 20) / view.zoom) < 0.01, "dragging pans the map")
	view.pan_by(Vector2(-1000000, -1000000))
	_check(view.center.length() < 5000.0, "panning is clamped to the galaxy")
	view.focus_on(&"sol")
	_check(view.get_marker_position(&"sol").distance_to(view.size * 0.5) < 1.0, "focus returns to the current system")
	var selected_before := map.get_selected_id()
	_drag(view, Vector2(500, 400), Vector2(560, 400))
	_check(map.get_selected_id() == selected_before, "a drag does not select anything")

	# --- Esc closes the map, not the pause menu.
	_press("ui_cancel")
	await process_frame
	_check(not map.visible and not paused and not main.get_node("PauseMenu").visible, "Esc closes the map and resumes without opening the pause menu")

	# --- A click on the map does not select targets in the game underneath.
	var earth: Targetable
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name == "Earth":
			earth = t
	_press("galaxy_map")
	await process_frame
	var screen_position: Vector2 = earth.get_global_transform_with_canvas().origin
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen_position
	click.global_position = screen_position
	Input.parse_input_event(click)
	await process_frame
	_check(targeting.current_target == null, "clicking on the map does not target things in space")
	_press("galaxy_map")
	await process_frame
	_check(not map.visible and not paused, "M closes the map again")

	# --- Other screens block M.
	var trading_open := false
	ship.global_position = earth.global_position + Vector2(0, 100)
	ship.velocity = Vector2.ZERO
	targeting.select(earth)
	main.get_node("Docking").try_dock()
	await process_frame
	main.get_node("SettlementScreen").get_node("%TradingButton").pressed.emit()
	await process_frame
	trading_open = main.get_node("TradingScreen").visible
	_press("galaxy_map")
	await process_frame
	_check(trading_open and not map.visible, "M does nothing while the trading screen is open")
	main.get_node("TradingScreen").close()
	await process_frame

	# --- Docked: the map opens and a destination can be chosen, but J will not work.
	_press("galaxy_map")
	await process_frame
	_check(map.visible, "the map opens while docked")
	_click(view, view.get_marker_position(&"tau_ceti"))
	_check(not jump.disabled, "docked: a destination can still be chosen")
	_press("galaxy_map")
	await process_frame
	_check(not main.try_jump().ok and travel.get_destination() == &"", "docked: J does nothing without a destination")
	main.get_node("Docking").undock()
	await create_timer(1.7).timeout

	# --- Choose a destination, then jump with J from space.
	ship.global_position = Vector2(2400, 0)
	ship.velocity = Vector2.ZERO
	_press("galaxy_map")
	await process_frame
	_click(view, view.get_marker_position(&"barnards_star"))
	_check(jump.disabled, "an unlinked system cannot be chosen")
	_click(view, view.get_marker_position(&"tau_ceti"))
	jump.pressed.emit()
	await process_frame
	await process_frame
	_check(not map.visible and not paused, "SELECT DESTINATION closes the map and resumes")
	_check(travel.get_destination() == &"tau_ceti" and main.get_system().system_id == &"sol", "Tau Ceti is the destination; the ship is still in Sol")
	_press("jump")
	await create_timer(2.6).timeout
	_check(main.get_system().system_id == &"tau_ceti" and travel.is_discovered(&"tau_ceti"), "J takes the player to Tau Ceti, which is discovered")
	_check(travel.get_destination() == &"", "the destination is cleared on arrival")

	# --- The map now shows Tau Ceti as current and Tau Ceti as discovered.
	_press("galaxy_map")
	await process_frame
	_check(view.get_marker_position(&"tau_ceti").distance_to(view.size * 0.5) < 1.0 and map.get_selected_id() == &"tau_ceti", "the map re-opens centred on Tau Ceti")
	_click(view, view.get_marker_position(&"sol"))
	_check("Direct jump from Tau Ceti" in _row_text(map), "reachability follows the current system")
	_click(view, view.get_marker_position(&"sol"))
	_check(map.get_node("%StatusLabel").text == "DISCOVERED" and "Federation" in _row_text(map), "Sol shows as discovered, with its faction and details")

	print("")
	print("GALAXY MAP SMOKE TEST: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _click(view: GalaxyMapView, at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	view._gui_input(release)


func _drag(view: GalaxyMapView, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	view._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	view._gui_input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = to
	view._gui_input(release)


func _row_text(map: GalaxyMapScreen) -> String:
	var text := ""
	for row in map.get_node("%DetailRows").get_children():
		for label in row.get_children():
			if label is Label:
				text += (label as Label).text + " "
		text += "\n"
	return text


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
