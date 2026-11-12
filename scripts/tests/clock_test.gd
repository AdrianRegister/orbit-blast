extends SceneTree
## The game clock: advancing, signals, jump length to days, and saving. Run with:
##   Godot --headless --path . --script res://scripts/tests/clock_test.gd </dev/null

const MAX_JUMP_DAYS := 10

var _failures: int = 0
var _signals: Array = []


func _init() -> void:
	var registry := ContentRegistry.new()
	var clock := GameClock.new()
	clock.day_advanced.connect(func(day: int, elapsed: int) -> void: _signals.append([day, elapsed]))

	_check(clock.day == 0, "starts at day 0")
	clock.advance(3, &"jump")
	_check(clock.day == 3, "advance moves the day")
	_check(_signals == [[3, 3]], "advance emits day and elapsed")
	clock.advance(0)
	clock.advance(-2)
	_check(clock.day == 3 and _signals.size() == 1, "zero and negative advances are ignored")

	_check(clock.jump_days(0) == 1, "a jump always takes at least a day")
	clock.days_per_fuel_unit = 2.0
	_check(clock.jump_days(4) == 8, "jump days follow fuel cost")

	_check_galaxy_travel_times()

	var saved := clock.save_state()
	_check(clock.validate_state(saved, registry).is_empty(), "saved state validates")
	_check(not clock.validate_state({"day": -1}, registry).is_empty(), "negative day rejected")
	_check(not clock.validate_state({"day": 1.5}, registry).is_empty(), "fractional day rejected")
	_check(not clock.validate_state({}, registry).is_empty(), "missing day rejected")
	var other := GameClock.new()
	other.load_state(saved, registry)
	_check(other.day == 3, "load restores the day")
	other.reset_state()
	_check(other.day == 0, "reset returns to day 0")

	print("")
	print("CLOCK TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


## With the clock's default settings no link in the galaxy takes more than
## MAX_JUMP_DAYS, and short links still take at least a day.
func _check_galaxy_travel_times() -> void:
	var galaxy: Galaxy = load("res://resources/universe/galaxy.tres")
	var clock := GameClock.new()
	var longest := 0
	var shortest := 1000
	for id in galaxy.get_system_ids():
		for other in galaxy.get_neighbours(id):
			var days := clock.jump_days(galaxy.get_jump_cost(id, other))
			longest = maxi(longest, days)
			shortest = mini(shortest, days)
	print("      galaxy jump times: %d to %d days" % [shortest, longest])
	_check(longest <= MAX_JUMP_DAYS, "the longest jump in the galaxy takes at most %d days" % MAX_JUMP_DAYS)
	_check(shortest >= 1, "the shortest jump takes at least a day")
	_check(longest >= 5, "the longest jump is still a real journey")


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
