extends SceneTree
## Market stock over time and prices: the daily rule, catching up lazily, selling
## into and buying out a market, and the price curve. Run with:
##   Godot --headless --path . --script res://scripts/tests/market_sim_test.gd </dev/null

var _failures: int = 0
var _registry: ContentRegistry
var _model: EconomyModel
var _clock: GameClock
var _food: Commodity
var _machinery: Commodity
var _ore: Commodity


func _init() -> void:
	_registry = ContentRegistry.new()
	_model = EconomyModel.new(load(EconomyModel.DEFAULT_CONFIG), _registry.commodities())
	_food = _registry.commodity(&"food")
	_machinery = _registry.commodity(&"machinery")
	_ore = _registry.commodity(&"ore")
	_clock = GameClock.new()

	_check_start()
	_check_catch_up()
	_check_dump()
	_check_buy_out()
	_check_prices()
	_check_slippage()
	_check_population()

	print("")
	print("MARKET SIMULATION TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _planet(type_id: String, population: int, id: String = "") -> PlanetData:
	var planet := PlanetData.new()
	planet.id = StringName(id if id != "" else "test_" + type_id)
	planet.display_name = planet.id
	planet.population = population
	planet.planet_type = load("res://resources/planet_types/%s.tres" % type_id)
	return planet


func _market(planet: PlanetData, clock: GameClock = null) -> Market:
	var source := clock if clock != null else _clock
	return Market.new(planet, _model, func() -> int: return source.day)


func _check_start() -> void:
	var farm := _market(_planet("terrestrial", 1000000))
	_check(farm.get_stock(_food) > 0, "a new market starts with stock, not empty")
	_check(farm.get_stock(_machinery) >= 0, "stock is never negative")
	_check(farm.get_stock(_food) > farm.get_stock(_machinery), "an exporter holds more than an importer")
	_check(not farm.has_commodity(_ore), "a farm world does not deal in ore")
	_check(farm.get_supply_ratio(_food) > farm.get_supply_ratio(_machinery), "exporters are better supplied than importers")
	_check(farm.get_supply_level(_food) in [Market.Supply.PLENTIFUL, Market.Supply.GLUT], "a farm world's food is plentiful")
	_check(farm.get_supply_level(_machinery) in [Market.Supply.SCARCE, Market.Supply.LOW], "a farm world is short of machinery")
	farm.add_stock(_machinery, 100000)
	_check(farm.get_supply_level(_machinery) == Market.Supply.GLUT, "dumping far more than normal makes a glut")
	farm.remove_stock(_machinery, farm.get_stock(_machinery))
	_check(farm.get_supply_level(_machinery) == Market.Supply.SCARCE, "an emptied good is scarce")
	var again := _market(_planet("terrestrial", 1000000))
	_check(again.get_stock(_food) == farm.get_stock(_food), "two new markets from the same data start the same")


func _check_catch_up() -> void:
	var clock := GameClock.new()
	var planet := _planet("terrestrial", 1000000)
	var daily := _market(planet, clock)
	var bulk := _market(planet, clock)
	daily.remove_stock(_machinery, 0)  # no-op, syncs both on day 0
	var drained := mini(daily.get_stock(_machinery), 100)
	daily.remove_stock(_machinery, drained)
	bulk.remove_stock(_machinery, drained)
	var after_buy := daily.get_stock(_machinery)
	for _day in 60:
		clock.advance(1)
		daily.get_stock(_machinery)  # reading brings it up to date each day
	_check(daily.get_stock(_machinery) != after_buy or drained == 0, "stock moves as days pass")
	_check(bulk.save_state()["stock"] == daily.save_state()["stock"],
			"reading every day or once after 60 days gives exactly the same stock")
	var away := _market(planet, clock)
	var before: Dictionary = away.save_state()["stock"]
	clock.advance(500)
	var settled: Dictionary = away.save_state()["stock"]
	clock.advance(500)
	var later: Dictionary = away.save_state()["stock"]
	var still := true
	for id in settled:
		still = still and absf(float(later[id]) - float(settled[id])) < 1.0
	_check(still, "a market that has settled stops changing (to within a unit)")
	_check(before.size() == settled.size(), "the same goods are traded throughout")
	_check(away.save_state()["day"] == clock.day, "a saved market remembers the day it was brought up to")


## Selling far more than a market uses leaves production stopped and the surplus
## to be used up at the rate people consume it.
func _check_dump() -> void:
	var clock := GameClock.new()
	var planet := _planet("terrestrial", 1000000)
	var market := _market(planet, clock)
	var used_per_day := market.get_consumption(_machinery)
	_check(used_per_day > 0.0 and market.get_production(_machinery) == 0.0, "setup: a farm world only uses machinery")
	var glut := 3000
	market.add_stock(_machinery, glut)
	var start := market.get_stock(_machinery)
	var cheap := market.get_buy_price(_machinery)
	clock.advance(10)
	var left := market.get_stock(_machinery)
	var digested := start - left
	_check(absf(digested - used_per_day * 10.0) <= used_per_day * 0.5 + 1.0,
			"a glut is used up at the consumption rate (%d units in 10 days, %.1f a day)" % [digested, used_per_day])
	_check(left > start / 2, "a large dump takes much longer than a few days to clear")
	_check(cheap < _machinery.base_price,
			"a glut makes the good cheaper than its base price")
	clock.advance(2000)
	_check(market.get_stock(_machinery) < start / 10, "given long enough the glut is gone")


func _check_buy_out() -> void:
	var clock := GameClock.new()
	var planet := _planet("terrestrial", 1000000)
	var market := _market(planet, clock)
	var all := market.get_stock(_machinery)
	_check(market.remove_stock(_machinery, all), "the whole stock can be bought")
	_check(market.get_stock(_machinery) == 0, "stock is then empty")
	_check(not market.remove_stock(_machinery, 1), "nothing more can be taken from an empty market")
	var empty_price := market.get_buy_price(_machinery)
	_check(empty_price <= int(_machinery.base_price * 2.2), "an empty market's price is capped, not infinite")
	clock.advance(20)
	_check(market.get_stock(_machinery) > 0, "freight and local production refill an emptied market")
	_check(market.get_stock(_machinery) >= 0, "stock stays non-negative")


func _check_prices() -> void:
	var clock := GameClock.new()
	var config := _model.config
	var market := _market(_planet("terrestrial", 1000000), clock)
	var low_stock_price := market.get_buy_price(_machinery)
	market.add_stock(_machinery, 5000)
	var high_stock_price := market.get_buy_price(_machinery)
	_check(high_stock_price < low_stock_price, "plentiful stock is cheaper than scarce stock")
	_check(market.get_price_factor(_machinery) >= config.min_price_factor - 0.0001, "the price factor has a floor")
	var factor := market.get_price_factor(_food)
	_check(factor >= config.min_price_factor and factor <= config.max_price_factor, "the price factor stays within its limits")
	_check(market.get_buy_price(_food) > market.get_sell_price(_food), "a market charges more than it pays")
	var spread := 1.0 - float(market.get_sell_price(_food)) / market.get_buy_price(_food)
	_check(absf(spread - config.spread) < 0.03, "the gap between buying and selling is the configured spread")

	# Prices fall monotonically as stock rises.
	var fresh := _market(_planet("terrestrial", 1000000, "test_monotonic"), clock)
	var last := 1.0e9
	var monotonic := true
	for _i in 12:
		var price := fresh.get_buy_price(_machinery)
		monotonic = monotonic and price <= last
		last = price
		fresh.add_stock(_machinery, 100)
	_check(monotonic, "price never rises as stock is added")

	# Short supply is dear, normal is the base price.
	var scarce := _market(_planet("terrestrial", 1000000, "test_scarce"), clock)
	scarce.remove_stock(_machinery, scarce.get_stock(_machinery))
	_check(scarce.get_price_factor(_machinery) > 1.0, "scarcity raises the price above base")
	_check(scarce.get_supply_ratio(_machinery) < 0.2, "an emptied market is far below normal supply")


func _check_slippage() -> void:
	var clock := GameClock.new()
	var market := _market(_planet("terrestrial", 100000), clock)
	var first := market.get_buy_price(_food)
	var many := mini(market.get_stock(_food), 80)
	_check(many >= 20, "setup: enough stock to test a large order (%d)" % many)
	_check(market.buy_total(_food, many) >= many * first - 1, "buying many costs at least the first price each")
	_check(market.buy_total(_food, many) > many * first, "a large order costs more per unit than a single unit")
	_check(market.buy_total(_food, 1) == first, "one unit costs the quoted price")
	_check(market.sell_total(_food, 1) == market.get_sell_price(_food), "selling one unit pays the quoted price")

	# No profit from buying and selling straight back at the same market.
	var credits := 1000000
	var bought := market.buy_total(_food, many)
	market.remove_stock(_food, many)
	var received := market.sell_total(_food, many)
	market.add_stock(_food, many)
	_check(received < bought, "buying then selling back at the same market always loses money (%d paid, %d back)" % [bought, received])
	_check(credits - bought + received < credits, "so there is no round trip profit")

	var budget := market.buy_total(_food, 10)
	_check(market.max_buyable(_food, budget, 1000) >= 10, "max_buyable affords what buy_total says it costs")
	_check(market.buy_total(_food, market.max_buyable(_food, budget, 1000)) <= budget, "max_buyable never overspends")
	_check(market.max_buyable(_food, 0, 1000) == 0, "nothing is affordable with no credits")


func _check_population() -> void:
	var small := _market(_planet("terrestrial", 50000, "test_small"))
	var large := _market(_planet("terrestrial", 5000000, "test_large"))
	_check(large.get_stock(_food) > small.get_stock(_food) * 5, "a bigger settlement holds much more stock")
	var planet := _planet("terrestrial", 100000, "test_growing")
	var market := _market(planet)
	var before := market.get_production(_food)
	planet.population = 1000000
	_check(_model.of(planet).production_of(_food) > before, "a grown population produces more")


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
