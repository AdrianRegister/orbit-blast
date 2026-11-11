extends SceneTree
## A completed ferry contract shows the ferry flavour pool and its own title,
## not the cargo delivery text. Run with:
##   Godot --headless --path . --script res://scripts/tests/ferry_popup_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var registry := ContentRegistry.new()
	var contracts: ContractManager = main.get_node("Contracts")
	var popup: EventPopup = main.get_node("EventPopup")
	var earth := registry.location(&"earth")
	var mars := registry.location(&"mars")
	var ferry := FerryContract.new()
	ferry.title = "Passage to Mars"
	ferry.origin = earth
	ferry.destination = mars
	ferry.commodity = registry.commodity(&"passengers")
	ferry.quantity = 2
	ferry.reward = 900
	contracts.set_source(ContractSource.new())
	contracts.get_available(earth)  # create the location's list
	contracts._available[earth].append(ferry)
	ferry.id = &"contract_ferry"
	ferry.context = contracts.get_context()
	_check(contracts.accept(ferry, earth) == ContractManager.AcceptResult.OK, "the ferry job is accepted")
	var target: Targetable = load("res://scenes/objects/targetable.tscn").instantiate()
	target.details = mars
	contracts.on_docked(target)
	await process_frame
	_check(ferry.status == Contract.Status.COMPLETED, "it completes at Mars")
	_check(popup.visible and popup.get_node("%TitleLabel").text == "PASSENGERS DELIVERED", "the popup says passengers were delivered")
	var pool: FlavourPool = load("res://resources/flavour/ferry_complete.tres")
	var possible: Array[String] = []
	for entry in pool.entries:
		possible.append(entry.replace("{destination}", "Mars"))
	_check(pool.entries.size() == 3 and possible.has(popup.get_node("%FlavourLabel").text), "the text is one of the three ferry entries")
	_check(pool.entries[0].begins_with("Once your postflight checks are complete"), "the supplied text is included")
	print("")
	print("FERRY POPUP TEST: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print("PASS  " if condition else "FAIL  ", label)
	if not condition:
		_failures += 1
