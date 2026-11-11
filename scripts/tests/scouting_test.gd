extends SceneTree
## Tests scouting: a discovered system is scouted when the ship has come within
## docking range of every body in it (planets, gas giants, stations, moons).
##   Godot --headless --path . --script res://scripts/tests/scouting_test.gd

const PATH := "user://scouting_test.json"

var _failures: int = 0


func _init() -> void:
	_clean()
	var main: Main = load("res://scenes/main.tscn").instantiate()
	main.get_node("Save").save_path = PATH
	root.add_child(main)
	await process_frame
	await process_frame

	var travel: TravelManager = main.get_node("Travel")
	var saves: SaveManager = main.get_save_manager()
	var ship := main.get_player_ship()
	var scouted_events: Array[StringName] = []
	travel.system_scouted.connect(func(id: StringName) -> void: scouted_events.append(id))

	# --- Properties of the new system.
	var galaxy := main.galaxy
	_check(not galaxy.is_inhabited(&"wolf_359") and galaxy.get_summary(&"wolf_359").location_ids.size() == 2, "Wolf 359 is uninhabited and has two bodies")
	_check(travel.get_scouting_progress(&"wolf_359") == Vector2i(0, 2) and not travel.is_scouted(&"wolf_359"), "nothing is scouted at the start")
	_check(travel.get_scouting_progress(&"nonsense") == Vector2i.ZERO and not travel.is_scouted(&"nonsense"), "an unknown system is never scouted")

	# --- A system that has not been discovered cannot be scouted.
	main._swap_system(galaxy.get_scene(&"wolf_359"))
	await process_frame
	var system := main.get_system()
	var medusa := _node(system, &"medusa")
	var cerberus := _node(system, &"cerberus")
	ship.global_position = medusa.global_position
	await process_frame
	await process_frame
	_check(travel.get_scouting_progress(&"wolf_359").x == 0, "an undiscovered system is not scouted, even from on top of a planet")
	travel.discover(&"wolf_359")

	# --- Docking range decides.
	_check(medusa.get_dock_range() > 0.0, "an undockable planet still has a docking range (%d px)" % medusa.get_dock_range())
	ship.global_position = medusa.global_position + Vector2(medusa.get_dock_range() + 40.0, 0)
	await process_frame
	await process_frame
	_check(travel.get_scouting_progress(&"wolf_359").x == 0, "just outside docking range does not count")
	ship.global_position = medusa.global_position + Vector2(medusa.get_dock_range() - 10.0, 0)
	await process_frame
	await process_frame
	_check(travel.get_scouting_progress(&"wolf_359") == Vector2i(1, 2) and not travel.is_scouted(&"wolf_359"), "within docking range counts: 1 of 2")
	_check(scouted_events.is_empty(), "the system is not scouted yet, so no announcement")

	# --- Warping does not scout.
	ship.begin_warp()
	ship.global_position = cerberus.global_position
	await process_frame
	await process_frame
	_check(travel.get_scouting_progress(&"wolf_359").x == 1, "flying past at warp speed does not scout")
	ship.end_warp()

	# --- Partial progress survives saving and loading, and loading announces nothing.
	_check(saves.save_game(), "save with a half-scouted system")
	travel._scouted_nodes.clear()
	_check(main.load_game()["ok"], "load it")
	_check(travel.get_scouting_progress(&"wolf_359") == Vector2i(1, 2) and scouted_events.is_empty(), "progress is restored without an announcement")

	# --- The last body completes it, exactly once.
	system = main.get_system()
	cerberus = _node(system, &"cerberus")
	ship.global_position = cerberus.global_position + Vector2(cerberus.get_dock_range() - 10.0, 0)
	await process_frame
	await process_frame
	_check(travel.is_scouted(&"wolf_359") and scouted_events == [&"wolf_359"], "reaching the last body scouts the system and announces it once")
	ship.global_position = Vector2.ZERO
	await process_frame
	ship.global_position = cerberus.global_position
	await process_frame
	await process_frame
	_check(scouted_events.size() == 1, "going back does not announce it again")

	# --- Saved and restored as scouted.
	_check(saves.save_game(), "save")
	travel._scouted_nodes.clear()
	_check(main.load_game()["ok"] and travel.is_scouted(&"wolf_359") and scouted_events.size() == 1, "a scouted system stays scouted after loading")

	# --- Old saves and bad data.
	var document := saves.build_document()
	document["galaxy"].erase("scouted_nodes")
	_write(PATH, JSON.stringify(document))
	_check(main.load_game()["ok"] and not travel.is_scouted(&"wolf_359"), "a save from before scouting loads with nothing scouted")
	document["galaxy"]["scouted_nodes"] = {"wolf_359": ["medusa", "no_such_place"]}
	_write(PATH, JSON.stringify(document))
	_check(not main.load_game()["ok"], "a body that is not in the system is refused")
	document["galaxy"]["scouted_nodes"] = {"andromeda": ["medusa"]}
	_write(PATH, JSON.stringify(document))
	_check(not main.load_game()["ok"], "an unknown system is refused")
	document["galaxy"]["scouted_nodes"] = "everything"
	_write(PATH, JSON.stringify(document))
	_check(not main.load_game()["ok"], "scouted_nodes of the wrong type is refused")

	# --- Inhabited systems are scouted the same way.
	_clean()
	main._swap_system(galaxy.get_scene(&"sol"))
	await process_frame
	var sol := main.get_system()
	for node in sol.get_inhabited_nodes():
		ship.global_position = node.global_position
		await process_frame
		await process_frame
	_check(travel.is_scouted(&"sol") and scouted_events.has(&"sol"), "Sol is scouted by visiting Earth, Mars and Victory I")

	main.queue_free()
	await process_frame
	print("")
	print("SCOUTING TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _node(system: StarSystem, id: StringName) -> InhabitedNode:
	for node in system.get_inhabited_nodes():
		if node.data.id == id:
			return node
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
