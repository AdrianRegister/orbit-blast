extends SceneTree
## Headless checks of ship models, upgrades, the fleet and the ShipManager.
##   Godot --headless --path . --script res://scripts/tests/ship_test.gd

var _failures: int = 0


func _init() -> void:
	var shuttle: ShipStats = load("res://resources/ships/shuttle_stats.tres")
	var interceptor: ShipStats = load("res://resources/ships/interceptor_stats.tres")
	var freighter: ShipStats = load("res://resources/ships/freighter_stats.tres")
	var cargo_up: UpgradeDefinition = load("res://resources/upgrades/cargo_bay.tres")
	var e1: UpgradeDefinition = load("res://resources/upgrades/engine_1.tres")
	var e2: UpgradeDefinition = load("res://resources/upgrades/engine_2.tres")
	var m1: UpgradeDefinition = load("res://resources/upgrades/manoeuvre_1.tres")
	var food: Commodity = load("res://resources/commodities/food.tres")

	for model in [shuttle, interceptor, freighter]:
		_check(model.validate().is_empty(), "%s model validates: %s" % [model.id, model.validate()])
	for upgrade in [cargo_up, e1, e2, m1]:
		_check(upgrade.validate().is_empty(), "%s validates: %s" % [upgrade.id, upgrade.validate()])

	# --- Specs ---------------------------------------------------------------
	var base := ShipSpecs.compute(shuttle)
	_check(base.max_speed == shuttle.max_speed and base.cargo_capacity == shuttle.cargo_capacity, "no upgrades = base specs")
	var tuned := ShipSpecs.compute(shuttle, [e1, m1, cargo_up, cargo_up])
	_check(is_equal_approx(tuned.max_speed, shuttle.max_speed * 1.1), "engine I gives +10%% speed (%s)" % tuned.max_speed)
	_check(is_equal_approx(tuned.thrust, shuttle.thrust * 1.1), "engine I gives +10%% acceleration")
	_check(is_equal_approx(tuned.turn_rate, shuttle.turn_rate * 1.1), "manoeuvring I gives +10%% turn rate")
	_check(tuned.cargo_capacity == shuttle.cargo_capacity + 30, "two cargo bays add 30")
	var tier2 := ShipSpecs.compute(shuttle, [e1, e2])
	_check(is_equal_approx(tier2.max_speed, shuttle.max_speed * 1.2), "engine tiers replace each other, they do not stack")

	# --- Manager ---------------------------------------------------------------
	var earth := InhabitedData.new()
	earth.shipyard_ships = [interceptor, freighter]
	earth.outfitter_upgrades = [cargo_up, e1, e2, m1]
	var nowhere := InhabitedData.new()
	var here: Array = [earth]
	var player := PlayerData.new()
	player.credits = 500000
	var economy := EconomyManager.new()
	economy.setup(player)
	var ships := ShipManager.new()
	ships.setup(economy, player, func() -> InhabitedData: return here[0])
	var changes := [0]
	ships.fleet_changed.connect(func() -> void: changes[0] += 1)
	var first := ships.start_new_game(shuttle)
	_check(player.fleet.get_active() == first and first.ship_name == "Shuttle", "new game gives one active shuttle")
	_check(player.cargo.capacity == 20, "hold capacity follows the active ship")

	# Upgrades
	var credits := player.credits
	var result := ships.install_upgrade(cargo_up)
	_check(result.ok and player.credits == credits - cargo_up.price, "cargo upgrade installed and paid once")
	_check(player.cargo.capacity == 35, "upgraded capacity reaches the cargo hold (%d)" % player.cargo.capacity)
	_check(ships.install_upgrade(cargo_up).ok and player.cargo.capacity == 50, "second cargo upgrade installs")
	credits = player.credits
	result = ships.install_upgrade(cargo_up)
	_check(not result.ok and player.credits == credits and player.cargo.capacity == 50, "third cargo upgrade refused, nothing changed: %s" % result.message)
	result = ships.install_upgrade(e2)
	_check(not result.ok and player.credits == credits, "engine II needs engine I first: %s" % result.message)
	_check(ships.install_upgrade(e1).ok and ships.install_upgrade(e2).ok, "engine I then II install")
	_check(not ships.install_upgrade(e1).ok, "an installed tier cannot be bought again")
	_check(is_equal_approx(first.get_specs().max_speed, shuttle.max_speed * 1.2), "effective speed reflects engine II")
	player.credits = 100
	_check(not ships.install_upgrade(m1).ok and player.credits == 100 and first.get_tier(UpgradeDefinition.Category.MANOEUVRE) == 0, "unaffordable upgrade changes nothing")
	player.credits = 500000
	here[0] = nowhere
	_check(not ships.install_upgrade(m1).ok, "an outfitter that does not offer it refuses")
	here[0] = null
	_check(not ships.install_upgrade(m1).ok, "cannot install in open space")

	# Buying a ship, keeping the old one
	here[0] = earth
	_check(not ships.quote_ship(shuttle, false).ok, "this shipyard does not sell the shuttle")
	player.cargo.add(food.id, 45)
	result = ships.quote_ship(interceptor, false)
	_check(not result.ok and result.message.contains("does not fit"), "cargo too big for the new ship blocks the purchase: %s" % result.message)
	_check(player.fleet.get_active() == first and ships.get_fleet().ships.size() == 1, "refused purchase changes nothing")
	player.cargo.remove(food.id, 45)
	player.cargo.add(food.id, 5)
	credits = player.credits
	result = ships.buy_ship(interceptor, false)
	_check(result.ok and result.cost == interceptor.price and player.credits == credits - interceptor.price, "interceptor bought for full price")
	_check(player.fleet.get_active() == result.ship and result.ship.ship_name == "Interceptor", "new ship is active, named after its model")
	_check(first.is_previous() and player.fleet.ships.has(first.id), "kept ship is flagged PREVIOUS_SHIP and still owned")
	_check(player.fleet.get_visible_ships().size() == 1, "previous ship is hidden from the visible list")
	_check(player.cargo.capacity == 10 and player.cargo.get_quantity(food.id) == 5, "cargo travelled with the player")
	var interceptor_ship := result.ship

	# Trade-in
	player.cargo.remove(food.id, 5)
	credits = player.credits
	result = ships.buy_ship(freighter, true)
	_check(result.ok and result.trade_in_value == interceptor.price, "trade-in value is the old ship's price")
	_check(result.cost == freighter.price - interceptor.price and player.credits == credits - result.cost, "trade-in reduces the cost (%d)" % result.cost)
	_check(not player.fleet.ships.has(interceptor_ship.id), "traded-in ship is gone")
	_check(player.fleet.ships.size() == 2, "previous shuttle and the freighter remain")
	_check(player.cargo.capacity == freighter.cargo_capacity, "capacity follows the freighter")

	# Trade-in floor
	_check(ships.get_net_price(freighter, 0) == freighter.price, "no trade-in = full price")
	_check(ships.get_net_price(shuttle, 1000000) == 10000, "a huge trade-in value still leaves 10,000")
	_check(ships.get_net_price(interceptor, 85000) == 10000, "a trade-in within 10,000 of the price leaves 10,000")
	var cheap := ShipStats.new()
	cheap.price = 5000
	_check(ships.get_net_price(cheap, 100000) == 5000, "a ship cheaper than the minimum is never priced above its own price")

	# Unaffordable ship
	earth.shipyard_ships = [shuttle, interceptor, freighter]
	player.credits = 1000
	credits = player.credits
	_check(not ships.buy_ship(shuttle, false).ok and player.credits == credits and player.fleet.ships.size() == 2, "unaffordable purchase changes nothing")

	# Switching
	player.credits = 500000
	var shuttle_ship := first
	player.cargo.add(food.id, 100)
	result = ships.switch_to(shuttle_ship.id)
	_check(not result.ok and player.fleet.get_active() != shuttle_ship, "cargo that does not fit blocks the switch: %s" % result.message)
	player.cargo.remove(food.id, 100)
	result = ships.switch_to(shuttle_ship.id)
	_check(result.ok and player.fleet.get_active() == shuttle_ship and not shuttle_ship.is_previous(), "switch works when cargo fits")
	_check(shuttle_ship.upgrades.size() == 4 and player.cargo.capacity == 50, "the shuttle kept its upgrades and capacity (%d)" % player.cargo.capacity)
	here[0] = null
	_check(not ships.switch_to(shuttle_ship.id).ok, "cannot switch in open space")
	here[0] = earth

	# Naming
	_check(ships.rename(shuttle_ship.id, "  Rusty  ") and shuttle_ship.ship_name == "Rusty", "rename trims")
	_check(not ships.rename(shuttle_ship.id, "   ") and shuttle_ship.ship_name == "Rusty", "empty name refused")
	_check(not ships.rename(shuttle_ship.id, "x".repeat(51)), "51 characters refused")
	_check(ships.rename(shuttle_ship.id, "x".repeat(50)), "50 characters accepted")
	_check(changes[0] > 0, "fleet_changed was emitted")

	var ids := {}
	for ship in player.fleet.ships.values():
		ids[ship.id] = true
	_check(ids.size() == player.fleet.ships.size(), "ship ids are unique")

	print("")
	print("SHIP TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
