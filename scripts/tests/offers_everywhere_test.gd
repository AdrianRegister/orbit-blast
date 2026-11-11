extends SceneTree
## Every location that lists contract offers must have its mission computer
## enabled in the real game scene, including when the save being loaded was
## made before those offers existed. Run with:
##   Godot --headless --path . --script res://scripts/tests/offers_everywhere_test.gd

var _failures: int = 0


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var contracts: ContractManager = main.get_node("Contracts")
	var datas: Array[InhabitedData] = []
	for file in DirAccess.get_files_at("res://resources/locations"):
		var data := load("res://resources/locations/" + file) as InhabitedData
		if data != null and not (data.contract_offers.is_empty() and data.exploration_offers.is_empty()):
			datas.append(data)
	for data in datas:
		var expected := data.contract_offers.size() + data.exploration_offers.size()
		_check(contracts.get_available(data).size() == expected and contracts.has_contracts_for(data),
				"%s: all %d offers available, mission computer enabled" % [data.display_name, expected])

	# A save from before the offers existed: the locations were already visited
	# and generated, but with nothing in them.
	var state := contracts.save_state()
	state["available"] = []
	contracts.load_state(state, ContentRegistry.new())
	for data in datas:
		var expected := data.contract_offers.size() + data.exploration_offers.size()
		_check(contracts.get_available(data).size() == expected and contracts.has_contracts_for(data),
				"%s: offers added since an old save are picked up on load (%d)" % [data.display_name, expected])
	var ids := {}
	for data in datas:
		for contract in contracts.get_available(data):
			ids[contract.id] = true
	var total := 0
	for data in datas:
		total += contracts.get_available(data).size()
	_check(ids.size() == total, "every picked-up contract has its own id")

	# Loading again changes nothing.
	contracts.load_state(contracts.save_state(), ContentRegistry.new())
	var again := 0
	for data in datas:
		again += contracts.get_available(data).size()
	_check(again == total, "loading a current save adds nothing")

	print("")
	print("OFFERS EVERYWHERE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	print("PASS  " if condition else "FAIL  ", label)
	if not condition:
		_failures += 1
