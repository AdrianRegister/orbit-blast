extends SceneTree
## Saving and loading market stock: the round trip through JSON, markets catching
## up to the calendar after a load, saves from before stock was timed, and
## damaged data. Run with:
##   Godot --headless --path . --script res://scripts/tests/economy_save_test.gd </dev/null

var _failures: int = 0
var _registry: ContentRegistry
var _earth: InhabitedData
var _mars: InhabitedData
var _food: Commodity
var _ore: Commodity


func _init() -> void:
	_registry = ContentRegistry.new()
	_earth = _registry.location(&"earth")
	_mars = _registry.location(&"mars")
	_food = _registry.commodity(&"food")
	_ore = _registry.commodity(&"ore")

	_check_round_trip()
	_check_calendar()
	_check_legacy()
	_check_damaged()

	print("")
	print("ECONOMY SAVE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _new_economy(clock: GameClock) -> EconomyManager:
	var player := PlayerData.new()
	player.credits = 1000000
	player.cargo.capacity = 500
	var economy := EconomyManager.new()
	economy.setup(player, clock)
	return economy


func _through_json(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state))


func _check_round_trip() -> void:
	var clock := GameClock.new()
	var economy := _new_economy(clock)
	economy.buy(economy.get_market(_earth), _food, 40)
	economy.buy(economy.get_market(_mars), _ore, 15)
	clock.advance(12)
	var state := _through_json(economy.save_state())
	_check(economy.validate_state(state, _registry).is_empty(), "saved economy validates: %s" % [economy.validate_state(state, _registry)])
	_check(state["markets"].has("earth") and state["markets"].has("mars"), "visited markets are saved")
	_check(not state["markets"].has("victory_i"), "unvisited markets are not")
	_check(state["markets"]["earth"]["day"] == 12, "a market is saved at the day it was brought up to")

	var other_clock := GameClock.new()
	other_clock.day = clock.day
	var other := _new_economy(other_clock)
	other.load_state(state, _registry)
	_check(other.get_market(_earth).get_stock(_food) == economy.get_market(_earth).get_stock(_food), "Earth's food stock round-trips")
	_check(other.get_market(_mars).get_stock(_ore) == economy.get_market(_mars).get_stock(_ore), "Mars's ore stock round-trips")
	_check(other.get_market(_earth).get_buy_price(_food) == economy.get_market(_earth).get_buy_price(_food),
			"prices are the same after loading (they follow from stock)")
	_check(other.save_state()["markets"] == economy.save_state()["markets"], "saving again gives the same data")
	economy.free()
	other.free()


## A loaded market carries on from the saved day, so it ends up in the same state
## as one that was never saved.
func _check_calendar() -> void:
	var clock := GameClock.new()
	var economy := _new_economy(clock)
	var market := economy.get_market(_mars)
	market.remove_stock(_ore, market.get_stock(_ore))
	clock.advance(5)
	var state := _through_json(economy.save_state())

	var clock_b := GameClock.new()
	clock_b.day = 5
	var loaded := _new_economy(clock_b)
	loaded.load_state(state, _registry)
	clock.advance(25)
	clock_b.advance(25)
	var a: float = economy.get_market(_mars).save_state()["stock"]["ore"]
	var b: float = loaded.get_market(_mars).save_state()["stock"]["ore"]
	_check(absf(a - b) < 0.01, "a loaded market follows the calendar exactly like one that was never saved (%.3f and %.3f)" % [a, b])

	# Loading a save made on a later day than the clock shows must not run time backwards.
	var early := GameClock.new()
	var early_economy := _new_economy(early)
	var late_state := _through_json(economy.save_state())
	early_economy.load_state(late_state, _registry)
	_check(early_economy.get_market(_mars).get_stock(_ore) >= 0, "a save from after the clock's day loads safely")
	economy.free()
	loaded.free()
	early_economy.free()


## Saves from before stock was timed: whole-number stock, an "extra" object, no day,
## and goods the market no longer deals in.
func _check_legacy() -> void:
	var clock := GameClock.new()
	clock.day = 30
	var economy := _new_economy(clock)
	var player := PlayerData.new()
	var state := {
		"credits": 777,
		"cargo": player.cargo.save_state(),
		"markets": {"earth": {"stock": {"food": 123, "ore": 9, "passengers": 4}, "extra": {}}},
	}
	state = _through_json(state)
	var problems := economy.validate_state(state, _registry)
	_check(problems.is_empty(), "an older save with whole-number stock and no day validates: %s" % [problems])
	economy.load_state(state, _registry)
	_check(economy.get_credits() == 777, "credits load")
	var earth := economy.get_market(_earth)
	_check(earth.get_stock(_food) == 123, "legacy food stock loads")
	_check(earth.save_state()["day"] == 30, "a market with no saved day starts from today")
	economy.free()

	# A good the market does not deal in is ignored, not an error.
	var victory := _registry.location(&"victory_i")
	var state2 := _through_json({"credits": 5, "cargo": player.cargo.save_state(),
			"markets": {"victory_i": {"stock": {"ore": 50}}}})
	var economy2 := _new_economy(clock)
	_check(economy2.validate_state(state2, _registry).is_empty(), "stock of a good the market does not deal in validates")
	economy2.load_state(state2, _registry)
	_check(economy2.get_market(victory).get_stock(_ore) == 0, "and is ignored on loading")
	economy2.free()


func _check_damaged() -> void:
	var clock := GameClock.new()
	var economy := _new_economy(clock)
	economy.get_market(_earth)
	var good := _through_json(economy.save_state())
	_check(economy.validate_state(good, _registry).is_empty(), "setup: the undamaged state is valid")

	var cases := {
		"negative stock": func(s: Dictionary) -> void: s["markets"]["earth"]["stock"]["food"] = -5,
		"text for stock": func(s: Dictionary) -> void: s["markets"]["earth"]["stock"]["food"] = "lots",
		"unknown commodity": func(s: Dictionary) -> void: s["markets"]["earth"]["stock"]["unobtainium"] = 5,
		"negative day": func(s: Dictionary) -> void: s["markets"]["earth"]["day"] = -1,
		"fractional day": func(s: Dictionary) -> void: s["markets"]["earth"]["day"] = 2.5,
		"stock not an object": func(s: Dictionary) -> void: s["markets"]["earth"]["stock"] = [1, 2],
		"market not an object": func(s: Dictionary) -> void: s["markets"]["earth"] = 5,
		"unknown location": func(s: Dictionary) -> void: s["markets"]["nowhere"] = {"stock": {}},
		"uninhabited location": func(s: Dictionary) -> void: s["markets"]["atlas"] = {"stock": {}},
		"markets not an object": func(s: Dictionary) -> void: s["markets"] = [],
	}
	for label in cases:
		var damaged: Dictionary = _through_json(good)
		cases[label].call(damaged)
		_check(not economy.validate_state(damaged, _registry).is_empty(), "damaged save rejected: %s" % label)
	economy.free()


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
