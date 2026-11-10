extends SceneTree
## Headless checks of the trading rules. Run with:
##   Godot --headless --path . --script res://scripts/tests/economy_test.gd
## Exits with code 1 if any check fails.

var _failures: int = 0


func _init() -> void:
	var earth_data: InhabitedData = load("res://resources/locations/earth.tres")
	var mars_data: InhabitedData = load("res://resources/locations/mars.tres")
	var victory_data: InhabitedData = load("res://resources/locations/victory_i.tres")
	var food: Commodity = load("res://resources/commodities/food.tres")
	var electronics: Commodity = load("res://resources/commodities/electronics.tres")
	var ore: Commodity = load("res://resources/commodities/ore.tres")
	var machinery: Commodity = load("res://resources/commodities/machinery.tres")
	var fuel: Commodity = load("res://resources/commodities/fuel.tres")

	for data in [earth_data, mars_data, victory_data]:
		_check(data.validate().is_empty(), "%s data validates: %s" % [data.display_name, data.validate()])

	var player := PlayerData.new()
	player.credits = 500000
	player.cargo.capacity = 500
	var economy := EconomyManager.new()
	economy.setup(player)

	# 1. Independent markets.
	var earth := economy.get_market(earth_data)
	var mars := economy.get_market(mars_data)
	var victory := economy.get_market(victory_data)
	_check(earth != mars and earth != victory and mars != victory, "markets are separate objects")
	_check(economy.get_market(earth_data) == earth, "same market returned on every visit")

	# 2. Stock and prices differ by role.
	_check(earth.get_buy_price(food) < mars.get_buy_price(food), "Food is cheaper at exporting Earth than importing Mars")
	_check(earth.get_stock(food) > mars.get_stock(food), "Food stock is larger at Earth than Mars")
	_check(earth.get_buy_price(ore) > mars.get_buy_price(ore), "Ore costs more at importing Earth than exporting Mars")
	_check(earth.get_sell_price(ore) > mars.get_buy_price(ore), "Ore Mars->Earth is profitable")
	_check(not victory.has_commodity(food), "Victory I does not list Food")

	# 3. Buying.
	var credits_before := player.credits
	var stock_before := earth.get_stock(food)
	var quote := economy.buy(earth, food, 10)
	_check(quote.is_ok(), "buy 10 Food succeeds")
	_check(player.credits == credits_before - 10 * earth.get_buy_price(food), "credits reduced by cost")
	_check(earth.get_stock(food) == stock_before - 10, "market stock reduced")
	_check(player.cargo.get_quantity(&"food") == 10 and player.cargo.get_used() == 10, "cargo increased")

	# 10. Persistence between locations: carry the Food to Mars (an import) and sell it.
	# 4. Selling.
	credits_before = player.credits
	stock_before = mars.get_stock(food)
	quote = economy.sell(mars, food, 4)
	_check(quote.is_ok(), "sell 4 Food at Mars succeeds")
	_check(player.credits == credits_before + 4 * mars.get_sell_price(food), "credits increased by revenue")
	_check(mars.get_stock(food) == stock_before + 4, "market stock increased")
	_check(player.cargo.get_quantity(&"food") == 6, "cargo reduced; the rest was carried between locations")

	# 9. Markets reject goods they do not import.
	quote = economy.sell(earth, food, 1)
	_check(quote.reason == TradeQuote.Reason.NOT_ACCEPTED, "Earth rejects its own export")
	quote = economy.sell(mars, machinery, 1)
	_check(quote.reason == TradeQuote.Reason.NOT_ACCEPTED, "Mars rejects a listed but not imported good")
	quote = economy.sell(victory, food, 1)
	_check(quote.reason == TradeQuote.Reason.NOT_ACCEPTED, "Victory I rejects an unlisted good")

	# 8. Cannot sell more than owned. Nothing may change on a refused trade.
	credits_before = player.credits
	stock_before = mars.get_stock(food)
	quote = economy.sell(mars, food, 7)
	_check(quote.reason == TradeQuote.Reason.INSUFFICIENT_CARGO, "selling more than owned is refused")
	_check(player.credits == credits_before and mars.get_stock(food) == stock_before
			and player.cargo.get_quantity(&"food") == 6, "refused sale changed nothing")

	# 5. Insufficient credits.
	player.credits = 100
	credits_before = player.credits
	stock_before = earth.get_stock(electronics)
	quote = economy.buy(earth, electronics, 5)
	_check(quote.reason == TradeQuote.Reason.INSUFFICIENT_CREDITS, "insufficient credits refused")
	_check(player.credits == credits_before and earth.get_stock(electronics) == stock_before,
			"refused purchase changed nothing")
	player.credits = 500000

	# 6. Insufficient cargo capacity.
	player.cargo.capacity = 8
	quote = economy.buy(earth, food, 5)
	_check(quote.reason == TradeQuote.Reason.INSUFFICIENT_CARGO_SPACE, "insufficient cargo space refused")
	player.cargo.capacity = 500

	# 7. Insufficient market stock.
	quote = economy.buy(victory, electronics, victory.get_stock(electronics) + 1)
	_check(quote.reason == TradeQuote.Reason.INSUFFICIENT_STOCK, "insufficient market stock refused")

	# Invalid quantities and the exact-limit cases.
	_check(economy.buy(earth, food, 0).reason == TradeQuote.Reason.INVALID_QUANTITY, "zero quantity refused")
	_check(economy.buy(earth, food, -3).reason == TradeQuote.Reason.INVALID_QUANTITY, "negative quantity refused")
	var all_stock := victory.get_stock(fuel)
	player.cargo.capacity = 500
	_check(economy.buy(victory, fuel, mini(all_stock, player.cargo.get_free())).is_ok(), "buying up to the limit works")
	_check(victory.get_stock(fuel) >= 0 and player.credits >= 0, "stock and credits never negative")

	economy.free()
	print("")
	if _failures == 0:
		print("ECONOMY TESTS: all passed")
	else:
		print("ECONOMY TESTS: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS  ", description)
	else:
		print("FAIL  ", description)
		_failures += 1
