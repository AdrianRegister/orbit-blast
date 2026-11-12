extends SceneTree
## Damage to locations: how it is stored and recovers, what it does to production
## and to markets over time, saving, and what the target panel shows. Run with:
##   Godot --headless --path . --script res://scripts/tests/infrastructure_test.gd </dev/null

var _failures: int = 0
var _registry: ContentRegistry
var _model: EconomyModel
var _food: Commodity
var _machinery: Commodity


func _init() -> void:
	_registry = ContentRegistry.new()
	_model = EconomyModel.new(load(EconomyModel.DEFAULT_CONFIG), _registry.commodities())
	_food = _registry.commodity(&"food")
	_machinery = _registry.commodity(&"machinery")

	_check_config()
	_check_damage()
	_check_scale()
	_check_markets()
	_check_economy_unchanged()
	_check_saving()
	await _check_target_panel()

	print("")
	print("INFRASTRUCTURE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _manager(clock: GameClock) -> InfrastructureManager:
	var manager := InfrastructureManager.new()
	manager.setup(clock)
	return manager


func _planet(population: int = 1000000) -> PlanetData:
	var planet := PlanetData.new()
	planet.id = &"test_world"
	planet.display_name = "Test World"
	planet.population = population
	planet.planet_type = load("res://resources/planet_types/terrestrial.tres")
	return planet


func _check_config() -> void:
	var config: InfrastructureConfig = load(InfrastructureManager.DEFAULT_CONFIG)
	_check(config != null and config.validate().is_empty(), "the infrastructure config is valid")
	_check(config.recovery_per_day > 0.0, "damage recovers (%.3f a day)" % config.recovery_per_day)
	var bad := InfrastructureConfig.new()
	bad.max_production_loss = 1.5
	_check(not bad.validate().is_empty(), "a production loss above 1 is rejected")


func _check_damage() -> void:
	var clock := GameClock.new()
	var manager := _manager(clock)
	var rate := manager.config.recovery_per_day
	_check(manager.get_damage(&"earth") == 0.0, "nothing is damaged to begin with")
	_check(manager.get_damage_percent(&"earth") == 0, "0% means undamaged")
	manager.apply_damage(&"earth", 0.5, &"test")
	_check(is_equal_approx(manager.get_damage(&"earth"), 0.5), "damage is applied")
	_check(manager.get_damage_percent(&"earth") == 50, "and shown as a percent")
	clock.advance(10)
	_check(is_equal_approx(manager.get_damage(&"earth"), 0.5 - 10.0 * rate), "damage recovers a fixed amount each day")
	clock.advance(1000)
	_check(manager.get_damage(&"earth") == 0.0, "and never below zero")
	_check(manager.get_damaged_locations().is_empty(), "a fully recovered location is no longer damaged")

	manager.apply_damage(&"mars", 0.4)
	manager.apply_damage(&"mars", 0.4)
	_check(is_equal_approx(manager.get_damage(&"mars"), 0.8), "more damage adds to what is there")
	manager.apply_damage(&"mars", 0.9)
	_check(manager.get_damage(&"mars") == 1.0 and manager.get_damage_percent(&"mars") == 100, "damage stops at 100% (devastated)")
	manager.apply_damage(&"mars", -0.25)
	_check(is_equal_approx(manager.get_damage(&"mars"), 0.75), "a negative amount repairs")
	manager.set_damage(&"mars", 0.0)
	_check(manager.get_damage(&"mars") == 0.0, "setting damage to zero repairs completely")

	# Recovery counts from when the damage was last changed, however long ago.
	clock.advance(0)
	manager.set_damage(&"venus", 0.6)
	var day := clock.day
	clock.advance(5)
	manager.apply_damage(&"venus", 0.2)  # settled to 0.6 - 5 rate, then +0.2
	_check(is_equal_approx(manager.get_damage(&"venus"), 0.6 - 5.0 * rate + 0.2), "new damage is added to the recovered amount")
	_check(is_equal_approx(manager.get_damage(&"venus", day), manager.get_damage(&"venus", clock.day)), "days before the last change give the damage as it was then")

	# The signals.
	var events: Array = []
	manager.damage_about_to_change.connect(func(id: StringName) -> void: events.append(["before", id]))
	manager.damage_changed.connect(func(id: StringName, damage: float) -> void: events.append(["after", id, damage]))
	manager.apply_damage(&"hera", 0.3)
	_check(events.size() == 2 and events[0][0] == "before" and events[1][0] == "after" and events[1][1] == &"hera",
			"the change is announced before and after: %s" % [events])
	manager.free()


func _check_scale() -> void:
	var clock := GameClock.new()
	var manager := _manager(clock)
	var loss := manager.config.max_production_loss
	_check(manager.production_scale(&"earth") == 1.0, "an undamaged location makes all its goods")
	manager.set_damage(&"earth", 0.5)
	_check(is_equal_approx(manager.production_scale(&"earth"), 1.0 - 0.5 * loss), "damage lowers production in proportion")
	manager.set_damage(&"earth", 1.0)
	_check(is_equal_approx(manager.production_scale(&"earth"), 1.0 - loss), "a devastated location makes only what the config leaves")
	var later := manager.production_scale(&"earth", clock.day + 10)
	_check(later > manager.production_scale(&"earth"), "production is higher on a later day, as damage wears off")
	_check(manager.production_scale(&"earth", clock.day + 10000) == 1.0, "and full again once recovered")
	manager.free()


## A market follows damage and recovery day by day, however it is read.
func _check_markets() -> void:
	# 1. Time before the damage is worked out at the old rate.
	var clock := GameClock.new()
	var manager := _manager(clock)
	var economy := EconomyManager.new()
	var player := PlayerData.new()
	economy.setup(player, clock, _model)
	economy.set_infrastructure(manager)
	var planet := _planet()
	var control := EconomyManager.new()
	var control_clock := GameClock.new()
	control.setup(PlayerData.new(), control_clock, _model)  # never damaged

	var market := economy.get_market(planet)
	var untouched := control.get_market(planet)
	market.get_stock(_food)
	clock.advance(15)
	control_clock.advance(15)
	manager.set_damage(planet.id, 1.0)  # the market was not read since day 0
	_check(market.save_state()["stock"] == untouched.save_state()["stock"],
			"the 15 days before the damage were worked out undamaged")
	clock.advance(30)
	control_clock.advance(30)
	_check(market.get_stock(_food) < untouched.get_stock(_food), "after the damage the food stock falls behind an undamaged twin")
	var drop := untouched.get_stock(_food) - market.get_stock(_food)
	_check(drop > 0, "by %d units after 30 devastated days" % drop)

	# 2. Reading every day or once gives the same stock.
	var clock_a := GameClock.new()
	var clock_b := GameClock.new()
	var manager_a := _manager(clock_a)
	var manager_b := _manager(clock_b)
	var economy_a := EconomyManager.new()
	var economy_b := EconomyManager.new()
	economy_a.setup(PlayerData.new(), clock_a, _model)
	economy_a.set_infrastructure(manager_a)
	economy_b.setup(PlayerData.new(), clock_b, _model)
	economy_b.set_infrastructure(manager_b)
	var market_a := economy_a.get_market(planet)
	var market_b := economy_b.get_market(planet)
	manager_a.set_damage(planet.id, 0.8)
	manager_b.set_damage(planet.id, 0.8)
	for _day in 60:
		clock_a.advance(1)
		market_a.get_stock(_food)
	clock_b.advance(60)
	_check(market_a.save_state()["stock"] == market_b.save_state()["stock"],
			"a market read every day while recovering matches one read once after the same 60 days")

	# 3. Recovery lets the stock come back.
	var clock_c := GameClock.new()
	var manager_c := _manager(clock_c)
	var economy_c := EconomyManager.new()
	economy_c.setup(PlayerData.new(), clock_c, _model)
	economy_c.set_infrastructure(manager_c)
	var market_c := economy_c.get_market(planet)
	manager_c.set_damage(planet.id, 1.0)
	clock_c.advance(40)
	var hurt := market_c.get_stock(_food)
	clock_c.advance(400)
	var healed := market_c.get_stock(_food)
	_check(healed > hurt, "once the damage has worn off the stock recovers (%d to %d)" % [hurt, healed])
	var normal := _market_without_damage(planet)
	_check(absf(healed - normal) <= maxf(2.0, normal * 0.02), "and returns to what an undamaged market holds (%d and %d)" % [healed, normal])

	# 4. A market made after the damage still sees it.
	var late := economy.get_market(_registry.location(&"mars"))
	manager.set_damage(&"mars", 1.0)
	_check(late != null and manager.production_scale(&"mars") < 1.0, "damage to a location whose market already exists applies")

	for node in [manager, manager_a, manager_b, manager_c, economy, economy_a, economy_b, economy_c, control]:
		node.free()


func _market_without_damage(planet: PlanetData) -> int:
	var clock := GameClock.new()
	var market := Market.new(planet, _model, func() -> int: return clock.day)
	clock.advance(440)  # the same time the damaged market ran
	return market.get_stock(_food)


## Damage changes only how much is produced: the settlement's goods stay the same.
func _check_economy_unchanged() -> void:
	var clock := GameClock.new()
	var manager := _manager(clock)
	var planet := _planet()
	var before := _model.of(planet)
	var exports_before := before.exports().map(func(g: Commodity) -> StringName: return g.id)
	var imports_before := before.imports().map(func(g: Commodity) -> StringName: return g.id)
	var made_before := before.production_of(_food)
	manager.set_damage(planet.id, 1.0)
	var after := _model.of(planet)
	_check(after.exports().map(func(g: Commodity) -> StringName: return g.id) == exports_before, "damage does not change what a settlement exports")
	_check(after.imports().map(func(g: Commodity) -> StringName: return g.id) == imports_before, "or imports")
	_check(after.production_of(_food) == made_before, "the settlement's own production figure is the undamaged one")
	_check(planet.population == 1000000, "and nobody dies: the population is untouched")
	manager.free()


func _check_saving() -> void:
	var clock := GameClock.new()
	var manager := _manager(clock)
	manager.apply_damage(&"earth", 0.6)
	manager.apply_damage(&"mars", 0.3)
	clock.advance(8)
	var state: Dictionary = JSON.parse_string(JSON.stringify(manager.save_state()))
	_check(manager.validate_state(state, _registry).is_empty(), "saved damage validates: %s" % [manager.validate_state(state, _registry)])
	_check(state["locations"].size() == 2 and state["locations"]["earth"]["day"] == clock.day, "damaged locations are saved as of today")

	var other_clock := GameClock.new()
	other_clock.day = clock.day
	var other := _manager(other_clock)
	other.load_state(state, _registry)
	_check(is_equal_approx(other.get_damage(&"earth"), manager.get_damage(&"earth")), "damage loads as it was saved")
	clock.advance(12)
	other_clock.advance(12)
	_check(is_equal_approx(other.get_damage(&"earth"), manager.get_damage(&"earth")), "and recovers just like the original afterwards")
	_check(other.save_state() == manager.save_state(), "saving again gives the same data")
	other.reset_state()
	_check(other.get_damaged_locations().is_empty(), "reset repairs everything (an old save with no section)")

	clock.advance(1000)
	_check(manager.save_state()["locations"].is_empty(), "recovered locations are not saved")

	var cases := {
		"no locations object": func(s: Dictionary) -> void: s["locations"] = [],
		"zero damage": func(s: Dictionary) -> void: s["locations"]["earth"]["damage"] = 0.0,
		"damage above 1": func(s: Dictionary) -> void: s["locations"]["earth"]["damage"] = 1.5,
		"text for damage": func(s: Dictionary) -> void: s["locations"]["earth"]["damage"] = "bad",
		"negative day": func(s: Dictionary) -> void: s["locations"]["earth"]["day"] = -3,
		"fractional day": func(s: Dictionary) -> void: s["locations"]["earth"]["day"] = 1.5,
		"unknown location": func(s: Dictionary) -> void: s["locations"]["nowhere"] = {"damage": 0.5, "day": 1},
		"uninhabited location": func(s: Dictionary) -> void: s["locations"]["atlas"] = {"damage": 0.5, "day": 1},
		"record not an object": func(s: Dictionary) -> void: s["locations"]["earth"] = 5,
	}
	for label in cases:
		var damaged: Dictionary = JSON.parse_string(JSON.stringify(state))
		cases[label].call(damaged)
		_check(not manager.validate_state(damaged, _registry).is_empty(), "damaged save rejected: %s" % label)
	manager.free()
	other.free()


func _check_target_panel() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var infrastructure: InfrastructureManager = main.get_node("Infrastructure")
	var targeting: TargetingManager = main.get_node("Targeting")
	var hud: Hud = main.get_node("Hud")

	var earth: Targetable
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name == "Earth":
			earth = t
	_check(earth != null, "found Earth")
	var rows := earth.get_detail_rows()
	var damage_row: Variant = _find_row(rows, "DAMAGE")
	_check(damage_row != null and damage_row[1] == "0%", "Earth's target rows show DAMAGE 0%% (%s)" % [damage_row])

	targeting.select(earth)
	await process_frame
	_check(_panel_value(hud, "DAMAGE") == "0%", "the target panel shows DAMAGE 0%")
	infrastructure.set_damage(&"earth", 0.35)
	await process_frame
	_check(_find_row(earth.get_detail_rows(), "DAMAGE")[1] == "35%", "damage shows as a percent on the target")
	_check(_panel_value(hud, "DAMAGE") == "35%", "and the panel updates while the target stays selected")
	main.get_node("Clock").advance(5)
	await process_frame
	var expected := infrastructure.get_damage_percent(&"earth")
	_check(expected < 35 and _panel_value(hud, "DAMAGE") == "%d%%" % expected, "and follows recovery as days pass (%s)" % _panel_value(hud, "DAMAGE"))
	for t in get_nodes_in_group(Targetable.GROUP):
		if t.target_name != "Earth" and t.details is PlanetData and not t.details.is_dockable():
			_check(_find_row(t.get_detail_rows(), "DAMAGE") == null, "a place nobody lives in shows no damage row")
			break
	main.queue_free()
	await process_frame


func _find_row(rows: Array, caption: String) -> Variant:
	for row in rows:
		if row[0] == caption:
			return row
	return null


func _panel_value(hud: Hud, caption: String) -> String:
	var rows: VBoxContainer = hud.get_node("%DetailRows")
	for row in rows.get_children():
		if row is InfoRow and row.caption == caption:
			return row.get_node("%Value").text
	return ""


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
