extends SceneTree
## Headless checks that credits, cargo (with contract cargo), markets and
## contracts save, survive a JSON round trip, load back identically, and that
## damaged data is rejected. Run with:
##   Godot --headless --path . --script res://scripts/tests/save_state_test.gd

var _failures: int = 0
var _registry: ContentRegistry


func _init() -> void:
	_registry = ContentRegistry.new()
	var food: Commodity = _registry.commodity(&"food")
	var earth: InhabitedData = _registry.location(&"earth")
	var mars: InhabitedData = _registry.location(&"mars")
	var victory: InhabitedData = _registry.location(&"victory_i")

	# --- A game with some history.
	var game := _new_game()
	var economy: EconomyManager = game["economy"]
	var contracts: ContractManager = game["contracts"]
	var player: PlayerData = game["player"]
	economy.buy(economy.get_market(earth), food, 25)
	economy.buy(economy.get_market(victory), _registry.commodity(&"fuel"), 10)
	var offers_at_earth := contracts.get_available(earth)
	contracts.accept(offers_at_earth[0], earth)  # Food to Mars (40)
	contracts.accept(offers_at_earth[1], earth)  # Electronics to Victory I (30)
	contracts.on_docked(_target_for(victory))  # completes the electronics contract
	contracts.get_available(mars)  # Mars offers generated but not taken

	var saved := _snapshot(game)
	_check(saved["economy"]["credits"] == player.credits, "credits are in the save")
	_check(saved["economy"]["cargo"]["manifest"].has("food"), "ordinary cargo is in the save")
	_check(saved["economy"]["cargo"]["lots"].size() == 1, "contract cargo is in the save as a lot")
	_check(saved["contracts"]["active"].size() == 1 and saved["contracts"]["completed"].size() == 1,
			"active and completed contracts are in the save")
	_check(saved["economy"]["markets"].has("earth") and saved["economy"]["markets"].has("victory_i"),
			"visited markets are in the save")

	# --- JSON round trip, then validation.
	var text := JSON.stringify(saved)
	var parsed: Dictionary = JSON.parse_string(text)
	_check(_validate(game, parsed).is_empty(), "round-tripped save validates: %s" % [_validate(game, parsed)])

	# --- Load into a different game and compare.
	var other := _new_game()
	var other_player: PlayerData = other["player"]
	other_player.credits = 7
	other["economy"].buy(other["economy"].get_market(mars), _registry.commodity(&"ore"), 5)
	_load(other, parsed)
	_check(JSON.stringify(_snapshot(other)) == text, "loaded game saves identically")
	_check(other_player.credits == player.credits, "credits restored")
	_check(other_player.cargo.get_used() == player.cargo.get_used(), "cargo used restored")
	_check(other_player.cargo.get_quantity(&"ore") == 0, "cargo from before the load is gone (replaced, not added)")
	_check(other["economy"].get_market(earth).get_stock(food) == economy.get_market(earth).get_stock(food),
			"market stock restored")
	_check(other["economy"].get_market(mars).get_stock(_registry.commodity(&"ore"))
			== other["economy"].get_market(mars).get_stock(_registry.commodity(&"ore")), "unvisited market is fresh")
	_check(other["economy"].get_cargo_lines() == economy.get_cargo_lines(), "cargo list (with destinations) restored")
	var active: Array[Contract] = other["contracts"].get_active()
	_check(active.size() == 1 and active[0].status == Contract.Status.ACCEPTED, "active contract restored")
	_check(other["contracts"].get_completed().size() == 1, "completed contract restored")
	_check(other["contracts"].get_available(earth).size() == 2, "taken offers do not reappear")

	# --- Loading twice changes nothing, delivery pays once.
	_load(other, parsed)
	_check(JSON.stringify(_snapshot(other)) == text, "loading twice gives the same state")
	var credits_before := other_player.credits
	other["contracts"].on_docked(_target_for(victory))
	_check(other_player.credits == credits_before, "a completed contract is not paid again after loading")
	other["contracts"].on_docked(_target_for(mars))
	_check(other_player.credits == credits_before + active[0].reward, "an active contract still completes after loading")
	_check(other_player.cargo.get_used() == player.cargo.get_used() - 40, "its cargo is removed once")

	# New contract ids continue after the loaded ones.
	var fresh_ids := {}
	for contract in other["contracts"].get_available(victory):
		fresh_ids[contract.id] = true
	_check(not fresh_ids.has(&"contract_1") and not fresh_ids.has(&"contract_2"), "ids do not collide with loaded contracts")

	# --- Damaged data is rejected, and rejection changes nothing.
	_expect_rejected(game, parsed, "negative credits", func(d: Dictionary) -> void: d["economy"]["credits"] = -5)
	_expect_rejected(game, parsed, "credits as text", func(d: Dictionary) -> void: d["economy"]["credits"] = "lots")
	_expect_rejected(game, parsed, "fractional credits", func(d: Dictionary) -> void: d["economy"]["credits"] = 1.5)
	_expect_rejected(game, parsed, "unknown commodity in cargo",
			func(d: Dictionary) -> void: d["economy"]["cargo"]["manifest"]["unobtainium"] = 3)
	_expect_rejected(game, parsed, "negative cargo quantity",
			func(d: Dictionary) -> void: d["economy"]["cargo"]["manifest"]["food"] = -2)
	_expect_rejected(game, parsed, "negative cargo capacity",
			func(d: Dictionary) -> void: d["economy"]["cargo"]["capacity"] = -1)
	_expect_rejected(game, parsed, "stock for a commodity the market does not trade",
			func(d: Dictionary) -> void: d["economy"]["markets"]["victory_i"]["stock"]["food"] = 5)
	_expect_rejected(game, parsed, "negative stock",
			func(d: Dictionary) -> void: d["economy"]["markets"]["earth"]["stock"]["food"] = -1)
	_expect_rejected(game, parsed, "market of an unknown location",
			func(d: Dictionary) -> void: d["economy"]["markets"]["atlantis"] = {"stock": {}})
	_expect_rejected(game, parsed, "cargo lot without a contract",
			func(d: Dictionary) -> void: d["contracts"]["active"].clear())
	_expect_rejected(game, parsed, "active contract without its cargo",
			func(d: Dictionary) -> void: d["economy"]["cargo"]["lots"].clear())
	_expect_rejected(game, parsed, "cargo that does not match the contract",
			func(d: Dictionary) -> void: d["economy"]["cargo"]["lots"]["contract_1"]["quantity"] = 3)
	_expect_rejected(game, parsed, "duplicate contract ids",
			func(d: Dictionary) -> void: d["contracts"]["completed"][0]["id"] = "contract_1")
	_expect_rejected(game, parsed, "status that disagrees with its list",
			func(d: Dictionary) -> void: d["contracts"]["completed"][0]["status"] = "ACCEPTED")
	_expect_rejected(game, parsed, "contract id at or above next_id",
			func(d: Dictionary) -> void: d["contracts"]["next_id"] = 2)
	_expect_rejected(game, parsed, "unknown contract type",
			func(d: Dictionary) -> void: d["contracts"]["completed"][0]["type"] = "time_travel")
	_expect_rejected(game, parsed, "contract to an unknown location",
			func(d: Dictionary) -> void: d["contracts"]["completed"][0]["destination"] = "atlantis")
	_expect_rejected(game, parsed, "contracts section of the wrong type",
			func(d: Dictionary) -> void: d["contracts"] = [])

	# Missing optional parts are tolerated.
	var minimal := parsed.duplicate(true)
	minimal["contracts"].erase("failed")
	_check(_validate(game, minimal).is_empty(), "a missing failed list is fine")

	print("")
	if _failures == 0:
		print("SAVE STATE TESTS: all passed")
	else:
		print("SAVE STATE TESTS: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _new_game() -> Dictionary:
	var player := PlayerData.new()
	player.credits = 500000
	player.cargo.capacity = 500
	var economy := EconomyManager.new()
	economy.setup(player)
	var contracts := ContractManager.new()
	var context := ContractContext.new()
	context.galaxy = load("res://resources/universe/galaxy.tres")
	context.registry = _registry
	contracts.setup(economy, context)
	contracts.set_source(FixedContractSource.new())
	contracts.set_system_lookup(func(_location: InhabitedData) -> String: return "Sol")
	return {"player": player, "economy": economy, "contracts": contracts}


func _snapshot(game: Dictionary) -> Dictionary:
	return {"economy": game["economy"].save_state(), "contracts": game["contracts"].save_state()}


func _validate(game: Dictionary, document: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	problems.append_array(game["economy"].validate_state(document.get("economy"), _registry, document))
	problems.append_array(game["contracts"].validate_state(document.get("contracts"), _registry, document))
	return problems


func _load(game: Dictionary, document: Dictionary) -> void:
	game["economy"].load_state(document["economy"], _registry)
	game["contracts"].load_state(document["contracts"], _registry)


## Damages a copy of `document`, expects validation to fail.
func _expect_rejected(game: Dictionary, document: Dictionary, what: String, damage: Callable) -> void:
	var copy := document.duplicate(true)
	damage.call(copy)
	_check(not _validate(game, copy).is_empty(), "rejected: %s" % what)


func _target_for(location: InhabitedData) -> Targetable:
	var target: Targetable = load("res://scenes/objects/targetable.tscn").instantiate()
	target.details = location
	return target


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS  ", description)
	else:
		print("FAIL  ", description)
		_failures += 1
