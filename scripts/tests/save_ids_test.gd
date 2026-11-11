extends SceneTree
## Headless checks of the stable ids and the content registry. Run with:
##   Godot --headless --path . --script res://scripts/tests/save_ids_test.gd

var _failures: int = 0


func _init() -> void:
	var registry := ContentRegistry.new()
	_check(registry.problems.is_empty(), "registry builds without problems: %s" % [registry.problems])

	for id in [&"food", &"electronics", &"ore", &"machinery", &"fuel"]:
		_check(registry.commodity(id) != null and registry.commodity(id).id == id, "commodity '%s' resolves" % id)
	for id in [&"earth", &"mars", &"victory_i"]:
		_check(registry.location(id) != null and registry.location(id).id == id, "location '%s' resolves" % id)
	for id in [&"shuttle", &"freighter", &"interceptor"]:
		_check(registry.ship_stats(id) != null and registry.ship_stats(id).id == id, "ship '%s' resolves" % id)
	_check(registry.commodity(&"nonsense") == null and registry.location(&"") == null, "unknown ids give null")

	_check(registry.has_system(&"sol") and registry.system_scene(&"sol") != null, "system 'sol' is in the catalog")
	var sol: StarSystem = registry.system_scene(&"sol").instantiate()
	_check(sol.system_id == &"sol", "the Sol scene carries the id the catalog uses")
	sol.free()

	# Every location placed in Sol has a registered id.
	var packed: PackedScene = registry.system_scene(&"sol")
	var system: StarSystem = packed.instantiate()
	root.add_child(system)
	await process_frame
	for node in system.get_inhabited_nodes():
		_check(registry.location(node.data.id) == node.data, "%s is registered under its id" % node.data.display_name)
	system.queue_free()
	await process_frame

	print("")
	if _failures == 0:
		print("SAVE IDS TESTS: all passed")
	else:
		print("SAVE IDS TESTS: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS  ", description)
	else:
		print("FAIL  ", description)
		_failures += 1
