extends SceneTree
## Headless checks of cargo delivery contracts. Run with:
##   Godot --headless --path . --script res://scripts/tests/contract_test.gd
## Exits with code 1 if any check fails.

var _failures: int = 0


func _init() -> void:
	var earth_data: InhabitedData = load("res://resources/locations/earth.tres")
	var mars_data: InhabitedData = load("res://resources/locations/mars.tres")
	var victory_data: InhabitedData = load("res://resources/locations/victory_i.tres")
	var food: Commodity = load("res://resources/commodities/food.tres")

	for data in [earth_data, mars_data, victory_data]:
		_check(data.validate().is_empty(), "%s validates: %s" % [data.display_name, data.validate()])

	var player := PlayerData.new()
	player.credits = 1000
	player.cargo.capacity = 500
	var economy := EconomyManager.new()
	economy.setup(player)
	var contracts := ContractManager.new()
	contracts.setup(economy)
	contracts.set_system_lookup(func(_location: InhabitedData) -> String: return "Sol")

	# Availability: per location, one-time, unique ids.
	var at_earth := contracts.get_available(earth_data)
	var at_mars := contracts.get_available(mars_data)
	_check(at_earth.size() == 7 and at_mars.size() == 4, "offers are available per location (%d at Earth, %d at Mars)" % [at_earth.size(), at_mars.size()])
	_check(contracts.get_available(earth_data).size() == 7, "same contracts on every visit")
	var ids := {}
	for contract in at_earth + at_mars + contracts.get_available(victory_data):
		ids[contract.id] = true
		_check(contract.status == Contract.Status.AVAILABLE, "%s starts AVAILABLE" % contract.title)
	_check(ids.size() == 14, "contract ids are unique (%d)" % ids.size())

	var food_job: CargoDeliveryContract = at_earth[0]
	var bulk_job: CargoDeliveryContract = at_earth[2]
	_check(food_job.destination == mars_data and food_job.origin == earth_data, "origin and destination set")

	# Accepting at the wrong location is refused.
	_check(contracts.accept(food_job, mars_data) == ContractManager.AcceptResult.NOT_AVAILABLE,
			"a contract is not offered at another location")
	_check(food_job.status == Contract.Status.AVAILABLE and player.cargo.get_used() == 0, "refusal changes nothing")

	# Accepting loads contract cargo into the one hold.
	var changes := [0]
	player.cargo.changed.connect(func() -> void: changes[0] += 1)
	_check(contracts.accept(food_job, earth_data) == ContractManager.AcceptResult.OK, "accept succeeds at the origin")
	_check(food_job.status == Contract.Status.ACCEPTED, "status ACCEPTED")
	_check(player.cargo.get_used() == 40 and player.cargo.get_free() == 460, "contract cargo uses hold capacity")
	_check(changes[0] == 1, "cargo change is announced")
	_check(player.cargo.get_quantity(&"food") == 0 and player.cargo.get_manifest().is_empty(),
			"contract cargo is not ordinary cargo")
	_check(contracts.get_available(earth_data).size() == 6 and contracts.get_active() == [food_job],
			"accepted contract leaves the offers and becomes active")
	_check(contracts.accept(food_job, earth_data) == ContractManager.AcceptResult.NOT_AVAILABLE, "cannot accept twice")

	# Contract cargo cannot be sold, even where it is wanted.
	var mars := economy.get_market(mars_data)
	var quote := economy.quote_sell(mars, food, 10)
	_check(quote.reason == TradeQuote.Reason.INSUFFICIENT_CARGO, "contract cargo cannot be sold")
	var lines := economy.get_cargo_lines()
	_check(lines == [["Food (contract, Mars in the Sol system)", 40]], "cargo list marks contract cargo: %s" % [lines])

	# Capacity is shared with ordinary cargo and other contracts.
	_check(contracts.accept(bulk_job, earth_data) == ContractManager.AcceptResult.INSUFFICIENT_CARGO_SPACE,
			"contract larger than free space is refused")
	_check(bulk_job.status == Contract.Status.AVAILABLE and player.cargo.get_used() == 40, "refusal changes nothing")
	var second: CargoDeliveryContract = at_earth[1]
	_check(contracts.accept(second, earth_data) == ContractManager.AcceptResult.OK, "second contract accepted")
	_check(contracts.get_active().size() == 2 and player.cargo.get_used() == 70, "two active contracts share the hold")
	player.cargo.capacity = 80
	_check(not economy.buy(economy.get_market(earth_data), food, 11).is_ok(),
			"trading purchases respect contract cargo (10 free)")
	player.cargo.capacity = 500

	# Wrong destination does not complete anything.
	var credits_before := player.credits
	contracts.on_docked(_target_for(earth_data))
	_check(contracts.get_active().size() == 2 and player.cargo.get_used() == 70,
			"docking at the origin completes nothing")
	_check(player.credits == credits_before, "no reward at the wrong location")

	# Right destination completes only the contracts for it.
	var done: Array[Contract] = []
	contracts.contract_completed.connect(func(c: Contract) -> void: done.append(c))
	var seen_credits := [0]
	economy.credits_changed.connect(func(c: int) -> void: seen_credits[0] = c)
	contracts.on_docked(_target_for(mars_data))
	_check(food_job.status == Contract.Status.COMPLETED, "delivery at Mars completes the Mars contract")
	_check(second.status == Contract.Status.ACCEPTED, "the Victory I contract stays active")
	_check(player.credits == credits_before + food_job.reward and seen_credits[0] == player.credits,
			"reward paid through the economy")
	_check(player.cargo.get_used() == 30 and player.cargo.get_lot_quantity(food_job.id) == 0, "delivered cargo removed")
	_check(done == [food_job] and contracts.get_completed() == [food_job], "completion announced and recorded")
	contracts.on_docked(_target_for(mars_data))
	_check(player.credits == credits_before + food_job.reward, "no second payment")
	contracts.on_docked(_target_for(victory_data))
	_check(second.status == Contract.Status.COMPLETED and player.cargo.get_used() == 0, "second contract delivered")
	_check(not contracts.get_available(earth_data).has(food_job), "completed contracts are not offered again")

	# Missing cargo is not paid.
	var ore_job: CargoDeliveryContract = contracts.get_available(mars_data)[0]
	contracts.accept(ore_job, mars_data)
	player.cargo.remove_lot(ore_job.id)
	credits_before = player.credits
	contracts.on_docked(_target_for(earth_data))
	_check(ore_job.status == Contract.Status.ACCEPTED and player.credits == credits_before,
			"delivery without the cargo is not paid")

	economy.free()
	contracts.free()
	print("")
	if _failures == 0:
		print("CONTRACT TESTS: all passed")
	else:
		print("CONTRACT TESTS: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


## A stand-in for the docked Targetable: only `details` is read.
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
