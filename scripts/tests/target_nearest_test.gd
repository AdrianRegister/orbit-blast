extends SceneTree
## Tests the R key (select the nearest NPC ship) through the real game scene.
##   Godot --headless --path . --script res://scripts/tests/target_nearest_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var ship := main.get_player_ship()
	var targeting: TargetingManager = main.get_node("Targeting")
	var system := main.get_system()
	var npcs: Array[Node] = system.get_ships_root().get_children()
	_check(npcs.size() >= 2, "there are NPC ships to choose from (%d)" % npcs.size())

	# Put the player in several places; R must pick whichever ship is closest each time.
	for position in [Vector2.ZERO, Vector2(-1500, 300), Vector2(2500, -1200), Vector2(100, 2800)]:
		ship.global_position = position
		var expected: Node2D = null
		var best := INF
		for npc in npcs:
			var distance := (npc as Node2D).global_position.distance_to(position)
			if distance < best:
				best = distance
				expected = npc
		targeting.select(null)
		_press("target_nearest_ship")
		await process_frame
		_check(targeting.current_target != null and targeting.current_target.get_parent() == expected,
				"from %s, R selects the nearest ship (%d px away)" % [position, roundi(best)])

	# Moving makes a different ship the nearest.
	var first: Targetable = targeting.current_target
	ship.global_position = (npcs[0] as Node2D).global_position + Vector2(5, 5)
	_press("target_nearest_ship")
	await process_frame
	_check(targeting.current_target.get_parent() == npcs[0], "next to a ship, R selects that one")
	_check(first != null, "(a ship was selected before)")

	# It ignores locations and does nothing with no ships.
	for npc in npcs:
		npc.get_node("Targetable").set_enabled(false)
	targeting.select(null)
	_press("target_nearest_ship")
	await process_frame
	_check(targeting.current_target == null, "with no ship available R does nothing")

	print("")
	print("TARGET NEAREST TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
