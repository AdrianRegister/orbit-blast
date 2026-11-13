extends SceneTree
## Tests weapon data, mounts and the intercept maths.
## Run: Godot --headless --path . --script res://scripts/tests/weapon_test.gd </dev/null

var _failures := 0


func _init() -> void:
	_test_weapon_files()
	_test_ship_files()
	_test_fits()
	_test_intercept()
	_test_specs()

	print("WEAPON TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _load_all(folder: String) -> Array:
	var found: Array = []
	var dir := DirAccess.open(folder)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".tres"):
			found.append(load(folder + file))
	return found


func _test_weapon_files() -> void:
	var weapons := _load_all("res://resources/weapons/")
	_check(weapons.size() >= 4, "at least four weapons exist (%d)" % weapons.size())
	var ids := {}
	for weapon: WeaponDefinition in weapons:
		var problems := weapon.validate()
		_check(problems.is_empty(), "%s is valid %s" % [weapon.id, str(problems)])
		_check(not ids.has(weapon.id), "%s has a unique id" % weapon.id)
		ids[weapon.id] = true


func _test_ship_files() -> void:
	var ships := _load_all("res://resources/ships/")
	_check(ships.size() == 16, "sixteen ship models (%d)" % ships.size())
	for model: ShipStats in ships:
		var problems := model.validate()
		_check(problems.is_empty(), "%s is valid %s" % [model.id, str(problems)])
		_check(model.hull > 0.0, "%s has hull" % model.id)
		_check(model.get_hit_radius() > 0.0, "%s has a hit radius" % model.id)
	var shuttle: ShipStats = load("res://resources/ships/shuttle_stats.tres")
	_check(not shuttle.weapon_mounts.is_empty() and shuttle.default_loadout.size() == 1 and shuttle.default_loadout[0] != null, "the starting shuttle comes armed")


func _test_fits() -> void:
	var small_fixed := WeaponMount.new()
	var medium_turret := WeaponMount.new()
	medium_turret.type = WeaponMount.Type.TURRET
	medium_turret.size = WeaponMount.Size.MEDIUM
	var light: WeaponDefinition = load("res://resources/weapons/light_blaster.tres")
	var pulse: WeaponDefinition = load("res://resources/weapons/pulse_cannon.tres")
	_check(light.fits(small_fixed), "a small weapon fits a small fixed mount")
	_check(light.fits(medium_turret), "a small weapon fits a larger turret mount")
	_check(not pulse.fits(small_fixed), "a medium weapon does not fit a small mount")
	_check(pulse.fits(medium_turret), "a medium weapon fits a medium turret")
	var fixed_only := WeaponDefinition.new()
	fixed_only.turret_capable = false
	_check(not fixed_only.fits(medium_turret), "a fixed-only weapon refuses a turret mount")
	_check(not light.fits(null), "no mount, no fit")


func _test_intercept() -> void:
	# A stationary target is hit where it is.
	var aim: Variant = Intercept.solve(Vector2.ZERO, Vector2.ZERO, Vector2(1000, 0), Vector2.ZERO, 500.0)
	_check(aim != null and (aim as Vector2).distance_to(Vector2(1000, 0)) < 0.01, "stationary target: aim at it")

	# A target crossing at right angles is led ahead of its position.
	aim = Intercept.solve(Vector2.ZERO, Vector2.ZERO, Vector2(1000, 0), Vector2(0, 200), 500.0)
	_check(aim != null and (aim as Vector2).y > 0.0, "crossing target: aim ahead of it")
	if aim != null:
		var t := time_for(aim, 500.0)
		var target_then := Vector2(1000, 0) + Vector2(0, 200) * t
		_check((aim as Vector2).distance_to(target_then) < 0.5, "the shot and the target arrive together")

	# Shooter motion matters: shots keep the shooter's velocity.
	aim = Intercept.solve(Vector2.ZERO, Vector2(0, 100), Vector2(1000, 0), Vector2(0, 100), 500.0)
	_check(aim != null and absf((aim as Vector2).y - (Vector2(1000, 0) + Vector2(0, 100) * (1000.0 / 500.0)).y) < 1.0, "moving together: no sideways lead needed beyond drift")

	# A target faster than the shot, running away, cannot be caught.
	aim = Intercept.solve(Vector2.ZERO, Vector2.ZERO, Vector2(1000, 0), Vector2(800, 0), 500.0)
	_check(aim == null, "an outrunning target has no solution")


func time_for(aim: Vector2, speed: float) -> float:
	return aim.length() / speed


func _test_specs() -> void:
	var model: ShipStats = load("res://resources/ships/federation_frigate_stats.tres")
	var specs := ShipSpecs.compute(model, [])
	_check(is_equal_approx(specs.hull, model.hull) and is_equal_approx(specs.shield_capacity, model.shield_capacity), "specs carry defences from the model")
	_check(specs.hit_radius > 0.0, "specs carry a hit radius")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
