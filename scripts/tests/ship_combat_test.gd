extends SceneTree
## Headless checks of weapons and damage on owned ships: loadouts, fitting and
## selling weapons at an outfitter, repairs at a shipyard, and how all of it is
## saved (including saves from before combat existed).
##   Godot --headless --path . --script res://scripts/tests/ship_combat_test.gd </dev/null

var _failures: int = 0


func _init() -> void:
	var shuttle: ShipStats = load("res://resources/ships/shuttle_stats.tres")
	var interceptor: ShipStats = load("res://resources/ships/interceptor_stats.tres")
	var light: WeaponDefinition = load("res://resources/weapons/light_blaster.tres")
	var ion: WeaponDefinition = load("res://resources/weapons/ion_repeater.tres")
	var pulse: WeaponDefinition = load("res://resources/weapons/pulse_cannon.tres")
	var heavy: WeaponDefinition = load("res://resources/weapons/heavy_blaster.tres")
	var rules := DamageRules.shared()

	var outfitter := InhabitedData.new()
	outfitter.outfitter_weapons = [light, ion, pulse, heavy]
	var yard := InhabitedData.new()
	yard.shipyard_ships = [interceptor]
	var plain := InhabitedData.new()
	var here: Array = [outfitter]

	var player := PlayerData.new()
	player.credits = 1000000
	var economy := EconomyManager.new()
	economy.setup(player)
	var ships := ShipManager.new()
	ships.setup(economy, player, func() -> InhabitedData: return here[0])

	# --- A new ship comes armed with its model's default weapons, undamaged.
	var first := ships.start_new_game(shuttle)
	_check(first.weapons.size() == shuttle.weapon_mounts.size() and first.weapons[0] == light, "a new shuttle carries the default light blaster")
	_check(first.condition.is_full(), "a new ship is undamaged")
	_check(outfitter.has_outfitter() and not yard.has_outfitter() and yard.has_shipyard(), "has_outfitter() counts weapons; has_shipyard() counts ships")

	# --- Fitting and selling.
	var result := ships.quote_weapon(light)
	_check(not result.ok and "mounts are in use" in result.message, "a full ship refuses another weapon: %s" % result.message)
	var credits := player.credits
	result = ships.sell_weapon(light)
	_check(result.ok and player.credits == credits + ships.get_weapon_sell_value(light), "selling pays the sell fraction of the price")
	_check(ships.get_weapon_sell_value(light) == roundi(light.price * rules.weapon_sell_fraction), "the sell value follows the damage rules")
	_check(first.weapons[0] == null and first.mounts_used() == 0, "the mount is empty after selling")
	_check(not ships.sell_weapon(light).ok, "you cannot sell what is not fitted")
	result = ships.quote_weapon(pulse)
	_check(not result.ok and "mount fits" in result.message, "a medium weapon does not fit a small mount: %s" % result.message)
	credits = player.credits
	result = ships.install_weapon(ion)
	_check(result.ok and player.credits == credits - ion.price and first.weapons[0] == ion, "installing pays once and fills the mount")
	_check(first.count_weapon(ion) == 1 and first.find_fitted_mount(ion) == 0, "the ship counts and finds the fitted weapon")
	here[0] = plain
	_check(not ships.install_weapon(light).ok and not ships.sell_weapon(ion).ok, "a place without an outfitter neither sells nor buys weapons")
	here[0] = null
	_check(not ships.install_weapon(light).ok, "cannot fit weapons in open space")
	here[0] = outfitter

	# --- A limit per ship.
	var limited: WeaponDefinition = light.duplicate()
	limited.max_per_ship = 1
	outfitter.outfitter_weapons.append(limited)
	var wide := ShipStats.new()
	wide.id = &"wide"
	wide.display_name = "Wide"
	wide.weapon_mounts = [WeaponMount.new(), WeaponMount.new()]
	wide.default_loadout = []
	var wide_ship := player.fleet.create_ship(wide, "Wide")
	_check(wide_ship.weapons.size() == 2 and wide_ship.weapons[0] == null, "a ship with no default loadout starts with empty mounts")
	player.fleet.active_id = wide_ship.id
	_check(ships.install_weapon(limited).ok, "the first copy installs")
	result = ships.quote_weapon(limited)
	_check(not result.ok and "maximum" in result.message, "max_per_ship is enforced: %s" % result.message)
	player.fleet.active_id = first.id
	player.fleet.remove(wide_ship.id)  # (a made-up model: it is not in the registry, so it cannot be saved)

	# --- Buying a ship gives it its default loadout.
	here[0] = _combined(outfitter, yard)
	_check(ships.buy_ship(interceptor, false).ok, "buying an interceptor works")
	var second := ships.get_active()
	_check(second != first and second.weapons.size() == 2 and second.weapons[0] == light and second.weapons[1] == light, "the interceptor comes with two light blasters")
	_check(second.condition.is_full(), "the new ship is undamaged")

	# --- Repairs.
	var specs := second.get_specs()
	_check(ships.get_repair_cost(second) == 0 and not ships.quote_repair().ok, "an undamaged ship has nothing to repair")
	second.condition.armour = specs.armour - 10.0
	second.condition.hull = specs.hull - 20.0
	var expected := ceili(10.0 * rules.repair_cost_per_armour + 20.0 * rules.repair_cost_per_hull)
	_check(ships.get_repair_cost(second) == expected, "repair cost is the missing armour and hull at the rule's prices (%d)" % expected)
	here[0] = outfitter
	result = ships.quote_repair()
	_check(not result.ok and "shipyard" in result.message, "only a shipyard repairs: %s" % result.message)
	here[0] = yard
	player.credits = expected - 1
	_check(not ships.repair().ok and not second.condition.is_full(), "repair refused without the credits, nothing changes")
	player.credits = expected + 100
	result = ships.repair()
	_check(result.ok and player.credits == 100 and second.condition.is_full(), "repair costs exactly the quoted price and restores the ship")
	player.credits = 1000000

	# --- Saving: weapons and damage survive a round trip.
	second.weapons[1] = ion
	second.condition.armour = 12.5
	second.condition.hull = 33.0
	var registry := ContentRegistry.new()
	var saved := ships.save_state()
	_check(Fleet.validate_state(saved, registry).is_empty(), "a saved fleet validates: %s" % [Fleet.validate_state(saved, registry)])
	var player_two := PlayerData.new()
	var economy_two := EconomyManager.new()
	economy_two.setup(player_two)
	var ships_two := ShipManager.new()
	ships_two.setup(economy_two, player_two, func() -> InhabitedData: return null)
	ships_two.load_state(JSON.parse_string(JSON.stringify(saved)), registry)
	var loaded := player_two.fleet.get_ship(second.id)
	_check(loaded.weapons.size() == 2 and loaded.weapons[0] == light and loaded.weapons[1] == ion, "fitted weapons load back")
	_check(is_equal_approx(loaded.condition.armour, 12.5) and is_equal_approx(loaded.condition.hull, 33.0), "armour and hull load back")
	_check(player_two.fleet.get_ship(first.id).condition.is_full(), "an undamaged ship loads undamaged")
	_check(player_two.fleet.get_ship(first.id).weapons[0] == ion, "another ship's weapons load back")

	# --- Saves from before combat have none of it: defaults.
	var old_style: Dictionary = JSON.parse_string(JSON.stringify(saved))
	for entry in old_style["ships"]:
		entry.erase("weapons")
		entry.erase("armour")
		entry.erase("hull")
	_check(Fleet.validate_state(old_style, registry).is_empty(), "a save without combat fields is valid")
	var player_three := PlayerData.new()
	var economy_three := EconomyManager.new()
	economy_three.setup(player_three)
	var ships_three := ShipManager.new()
	ships_three.setup(economy_three, player_three, func() -> InhabitedData: return null)
	ships_three.load_state(old_style, registry)
	var old_ship := player_three.fleet.get_ship(second.id)
	_check(old_ship.weapons[0] == light and old_ship.weapons[1] == light and old_ship.condition.is_full(), "an old save gives the default loadout and an undamaged ship")

	# --- Bad data is refused before anything changes.
	_expect_invalid(saved, registry, "weapons", func(entry: Dictionary) -> void: entry["weapons"] = ["light_blaster"], "too few weapon entries")
	_expect_invalid(saved, registry, "weapons", func(entry: Dictionary) -> void: entry["weapons"] = ["nonsense", ""], "an unknown weapon")
	_expect_invalid(saved, registry, "weapons", func(entry: Dictionary) -> void: entry["weapons"] = ["pulse_cannon", ""], "a medium weapon in a small mount")
	_expect_invalid(saved, registry, "weapons", func(entry: Dictionary) -> void: entry["weapons"] = "light_blaster", "weapons that are not a list")
	_expect_invalid(saved, registry, "armour", func(entry: Dictionary) -> void: entry["armour"] = 99999.0, "armour above the ship's maximum")
	_expect_invalid(saved, registry, "armour", func(entry: Dictionary) -> void: entry["armour"] = "lots", "armour that is not a number")
	_expect_invalid(saved, registry, "hull", func(entry: Dictionary) -> void: entry["hull"] = 0.0, "a hull of zero")
	_expect_invalid(saved, registry, "hull", func(entry: Dictionary) -> void: entry["hull"] = 99999.0, "hull above the ship's maximum")

	print("SHIP COMBAT TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


## A place that is both an outfitter and a shipyard.
func _combined(outfitter: InhabitedData, yard: InhabitedData) -> InhabitedData:
	var both := InhabitedData.new()
	both.outfitter_weapons = outfitter.outfitter_weapons
	both.shipyard_ships = yard.shipyard_ships
	return both


## Damages the first ship entry of a copy of `saved` with `damage` and checks the
## validator names the problem.
func _expect_invalid(saved: Dictionary, registry: ContentRegistry, _field: String, damage: Callable, label: String) -> void:
	var copy: Dictionary = JSON.parse_string(JSON.stringify(saved))
	for entry in copy["ships"]:
		if entry["model"] == "interceptor":
			damage.call(entry)
	var problems := Fleet.validate_state(copy, registry)
	_check(not problems.is_empty(), "the validator refuses %s" % label)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
