extends SceneTree
## Tests the maths of fighting (CombatSteering): where to aim, whether the nose is
## on target, holding a fighting range, getting behind a target, circling, weaving
## and running. Pure: no scenes are run.
##   Godot --headless --path . --script res://scripts/tests/combat_steering_test.gd </dev/null

var _failures: int = 0


func _init() -> void:
	_test_lead_point()
	_test_is_aimed()
	_test_close_velocity()
	_test_arrival()
	_test_tail()
	_test_strafe_and_evade()
	_test_flee()
	_test_tether()
	_test_tuning_and_doctrines()

	print("COMBAT STEERING TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _near(a: Vector2, b: Vector2, tolerance: float = 0.01) -> bool:
	return a.distance_to(b) <= tolerance


# ----------------------------------------------------------------------- tests

func _test_lead_point() -> void:
	var shooter := Vector2.ZERO
	var still := CombatSteering.lead_point(shooter, Vector2.ZERO, Vector2(500.0, 0.0), Vector2.ZERO, 1000.0)
	_check(_near(still, Vector2(500.0, 0.0)), "a target standing still is aimed at")
	var moving := CombatSteering.lead_point(shooter, Vector2.ZERO, Vector2(500.0, 0.0), Vector2(0.0, 300.0), 1000.0)
	_check(moving.x > 499.0 and moving.y > 100.0, "a target crossing the line of fire is aimed ahead of (%s)" % moving)
	var t := (moving - shooter).length() / 1000.0
	_check(_near(moving, Vector2(500.0, 0.0) + Vector2(0.0, 300.0) * t, 1.0), "...exactly where it will be when the shot arrives")
	var away := CombatSteering.lead_point(shooter, Vector2.ZERO, Vector2(500.0, 0.0), Vector2(1500.0, 0.0), 1000.0)
	_check(_near(away, Vector2(500.0, 0.0)), "a target that cannot be caught (faster than the shot) is aimed at directly")
	_check(_near(CombatSteering.lead_point(shooter, Vector2.ZERO, Vector2(500.0, 0.0), Vector2(0.0, 300.0), 0.0), Vector2(500.0, 0.0)), "a weapon with no shot speed aims at the target")
	var from_moving := CombatSteering.lead_point(shooter, Vector2(0.0, 300.0), Vector2(500.0, 0.0), Vector2(0.0, 300.0), 1000.0)
	_check(_near(from_moving, Vector2(500.0, 150.0), 1.0), "a shooter moving with its target aims where the target will be, 0.5 s on (shots keep the shooter's velocity, so the shot flies straight at it)")


func _test_is_aimed() -> void:
	var muzzle := Vector2.ZERO
	var point := Vector2(600.0, 0.0)
	_check(CombatSteering.is_aimed(0.0, muzzle, point, 20.0, 5.0), "a nose dead on target is aimed")
	_check(CombatSteering.is_aimed(deg_to_rad(4.0), muzzle, point, 1.0, 5.0), "...and one within the tolerance")
	_check(not CombatSteering.is_aimed(deg_to_rad(12.0), muzzle, point, 1.0, 5.0), "...but not one outside it")
	_check(not CombatSteering.is_aimed(deg_to_rad(-12.0), muzzle, point, 1.0, 5.0), "...on either side")
	_check(CombatSteering.is_aimed(deg_to_rad(8.0), muzzle, point, 120.0, 5.0), "a big target is hit even outside the tolerance (it covers 11 degrees at that range)")
	_check(not CombatSteering.is_aimed(deg_to_rad(8.0), muzzle, Vector2(6000.0, 0.0), 120.0, 5.0), "...but not from far away")
	_check(CombatSteering.is_aimed(PI, muzzle, Vector2(-600.0, 0.0), 10.0, 3.0), "facing the other way at a target behind is aimed (angles wrap)")
	_check(CombatSteering.is_aimed(3.0, muzzle, Vector2.ZERO, 10.0, 3.0), "a target on top of the muzzle counts as aimed")


func _test_close_velocity() -> void:
	var position := Vector2.ZERO
	var point := Vector2(1000.0, 0.0)
	var far := CombatSteering.close_velocity(position, point, Vector2.ZERO, 300.0, 500.0, 400.0, 250.0)
	_check(far.x > 0.0 and absf(far.y) < 0.001 and far.length() <= 500.0, "far away it closes on the target, at most at top speed (%s)" % far)
	var near := CombatSteering.close_velocity(position, Vector2(320.0, 0.0), Vector2.ZERO, 300.0, 500.0, 400.0, 250.0)
	_check(near.x > 0.0 and near.length() < far.length(), "it slows as it nears its range (%d against %d)" % [near.length(), far.length()])
	var at_range := CombatSteering.close_velocity(position, Vector2(300.0, 0.0), Vector2(50.0, 20.0), 300.0, 500.0, 400.0, 250.0)
	_check(_near(at_range, Vector2(50.0, 20.0)), "at its range it just matches the target's velocity")
	var too_close := CombatSteering.close_velocity(position, Vector2(100.0, 0.0), Vector2.ZERO, 300.0, 500.0, 400.0, 250.0)
	_check(too_close.x < 0.0 and too_close.length() <= 250.0, "too close it backs away, no faster than its limit (%s)" % too_close)
	var backing := CombatSteering.close_velocity(position, Vector2(1.0, 0.0), Vector2.ZERO, 300.0, 500.0, 400.0, 250.0)
	_check(is_equal_approx(backing.length(), 250.0), "...at that limit when very close")
	var chasing := CombatSteering.close_velocity(position, point, Vector2(0.0, 200.0), 300.0, 500.0, 400.0, 250.0)
	_check(is_equal_approx(chasing.y, 200.0) and chasing.x > 0.0, "a moving target's velocity is added, so the ship keeps pace with it")
	_check(_near(CombatSteering.close_velocity(position, position, Vector2(7.0, 0.0), 300.0, 500.0, 400.0, 250.0), Vector2(7.0, 0.0)), "on top of the point it matches its velocity (no divide by zero)")


## Flies a ship that obeys close_velocity, with limited acceleration, and checks it
## arrives at its range and stays there without overshooting.
func _test_arrival() -> void:
	var position := Vector2(-2000.0, 0.0)
	var velocity := Vector2.ZERO
	var target := Vector2.ZERO
	var top := 750.0
	var accel := 480.0
	var dt := 1.0 / 60.0
	var closest := INF
	for step in 60 * 20:
		var wanted := CombatSteering.close_velocity(position, target, Vector2.ZERO, 350.0, top, accel * 0.8, top * 0.5)
		var change := (wanted - velocity).limit_length(accel * dt)
		velocity = (velocity + change).limit_length(top)
		position += velocity * dt
		closest = minf(closest, position.distance_to(target))
	_check(absf(position.distance_to(target) - 350.0) < 15.0 and velocity.length() < 20.0, "a ship following it comes to rest at its fighting range (%d px, %d px/s)" % [position.distance_to(target), velocity.length()])
	_check(closest > 350.0 - 60.0, "...without flying through it (closest %d px)" % closest)
	# A target that moves: the ship ends up keeping pace at the range.
	position = Vector2(-2000.0, 0.0)
	velocity = Vector2.ZERO
	target = Vector2.ZERO
	var target_velocity := Vector2(0.0, 200.0)
	for step in 60 * 30:
		target += target_velocity * dt
		var wanted := CombatSteering.close_velocity(position, target, target_velocity, 350.0, top, accel * 0.8, top * 0.5)
		velocity = (velocity + (wanted - velocity).limit_length(accel * dt)).limit_length(top)
		position += velocity * dt
	_check(absf(position.distance_to(target) - 350.0) < 25.0 and velocity.distance_to(target_velocity) < 30.0, "...and with a moving target it keeps pace at the range (%d px, %d px/s apart)" % [position.distance_to(target), velocity.distance_to(target_velocity)])


func _test_tail() -> void:
	var target := Vector2(100.0, 100.0)
	_check(_near(CombatSteering.trail_point(target, Vector2(300.0, 0.0), 1.0, 200.0), Vector2(-100.0, 100.0)), "the point behind a moving target is against its direction of travel")
	_check(_near(CombatSteering.trail_point(target, Vector2(5.0, 0.0), PI / 2.0, 200.0), Vector2(100.0, -100.0), 0.001), "...and behind its nose when it is nearly still (it faces down, so behind is up)")
	_check(_near(CombatSteering.forward_of(Vector2(0.0, -100.0), 0.0), Vector2.UP) and _near(CombatSteering.forward_of(Vector2.ZERO, 0.0), Vector2.RIGHT), "forward is the velocity, or the nose when nearly still")
	var forward := Vector2.RIGHT
	_check(CombatSteering.angle_off_tail(Vector2(-300.0, 0.0), Vector2.ZERO, forward) < 0.001, "a ship right behind its target is on its tail")
	_check(is_equal_approx(CombatSteering.angle_off_tail(Vector2(300.0, 0.0), Vector2.ZERO, forward), PI), "...straight ahead of it is as far off as it gets")
	_check(is_equal_approx(CombatSteering.angle_off_tail(Vector2(0.0, 300.0), Vector2.ZERO, forward), PI / 2.0), "...and beside it is a quarter turn off")
	_check(CombatSteering.rear_weight(0.8, PI, deg_to_rad(70.0), false) == 0.8, "a fighter that is not behind its target goes for its tail")
	_check(CombatSteering.rear_weight(0.8, deg_to_rad(40.0), deg_to_rad(70.0), false) == 0.0, "...one already behind it attacks directly")
	_check(CombatSteering.rear_weight(0.8, PI, deg_to_rad(70.0), true) == 0.0, "...and one that has committed attacks directly whatever its position")


func _test_strafe_and_evade() -> void:
	var position := Vector2.ZERO
	var point := Vector2(500.0, 0.0)
	var strafe := CombatSteering.strafe_velocity(position, point, 100.0, 1.0)
	_check(absf(strafe.x) < 0.001 and is_equal_approx(absf(strafe.y), 100.0), "strafing is sideways to the line to the target, at the given speed (%s)" % strafe)
	_check(_near(CombatSteering.strafe_velocity(position, point, 100.0, -1.0), -strafe), "...and the other side circles the other way")
	_check(CombatSteering.strafe_velocity(position, position, 100.0, 1.0) == Vector2.ZERO, "no strafing on top of the target")
	var weave := CombatSteering.evade_velocity(position, point, 0.5, 200.0, 1.0)
	_check(absf(weave.x) < 0.001 and is_equal_approx(absf(weave.y), 100.0), "weaving is sideways to the threat, strength times speed")
	_check(_near(CombatSteering.evade_velocity(position, point, 0.5, 200.0, -1.0), -weave), "...to the side given")
	_check(CombatSteering.evade_velocity(position, point, 0.0, 200.0, 1.0) == Vector2.ZERO, "a ship with no evasion does not weave")
	_check(CombatSteering.evade_velocity(position, position, 0.5, 200.0, 1.0) == Vector2.ZERO, "...and there is nothing to weave from at zero distance")
	_check(weave.dot(point) == 0.0 or absf(weave.normalized().dot(point.normalized())) < 0.001, "the weave never changes how close it keeps to the threat")


func _test_flee() -> void:
	var position := Vector2.ZERO
	var east: Array[Vector2] = [Vector2(500.0, 0.0)]
	var run := CombatSteering.flee_velocity(position, east, Vector2.ZERO, 400.0)
	_check(_near(run, Vector2(-400.0, 0.0), 0.5), "a ship runs directly away from a threat, at top speed (%s)" % run)
	var two: Array[Vector2] = [Vector2(500.0, 0.0), Vector2(0.0, 500.0)]
	var diagonal := CombatSteering.flee_velocity(position, two, Vector2.ZERO, 400.0)
	_check(diagonal.x < 0.0 and diagonal.y < 0.0 and is_equal_approx(diagonal.length(), 400.0), "...from two threats it runs away from both")
	var near_far: Array[Vector2] = [Vector2(200.0, 0.0), Vector2(0.0, 2000.0)]
	var weighted := CombatSteering.flee_velocity(position, near_far, Vector2.ZERO, 400.0)
	_check(absf(weighted.x) > absf(weighted.y), "...and the nearer threat counts for more")
	var north := Vector2.UP
	var lean := CombatSteering.flee_velocity(position, east, north, 400.0)
	_check(lean.x < 0.0 and lean.y < 0.0 and is_equal_approx(lean.length(), 400.0), "with a way out it leans toward it, still running from the threat")
	var empty: Array[Vector2] = []
	_check(_near(CombatSteering.flee_velocity(position, empty, north, 400.0), Vector2(0.0, -400.0)), "with no threats left it heads for the exit")
	_check(CombatSteering.flee_velocity(position, empty, Vector2.ZERO, 400.0) == Vector2.ZERO, "...or stops when there is no exit")
	var exits: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP]
	_check(CombatSteering.best_exit(position, east, exits) == Vector2.LEFT, "the exit chosen is the one away from the threat")
	var south: Array[Vector2] = [Vector2(0.0, 500.0)]
	_check(CombatSteering.best_exit(position, south, exits) == Vector2.UP, "...whichever way the threat is")
	var no_exits: Array[Vector2] = []
	_check(CombatSteering.best_exit(position, east, no_exits) == Vector2.ZERO, "with no exits there is none to choose")


func _test_tether() -> void:
	var wanted := Vector2(300.0, 0.0)
	var home := Vector2.ZERO
	_check(CombatSteering.tether_velocity(Vector2(1000.0, 0.0), wanted, home, 1600.0, 0.5, 400.0) == wanted, "inside the screen radius a ship flies as it wanted")
	var edge := CombatSteering.tether_velocity(Vector2(1900.0, 0.0), wanted, home, 1600.0, 0.5, 400.0)
	_check(edge.x < wanted.x and edge.x > -400.0, "just past the edge it is drawn back, but only part of the way (%s)" % edge)
	var far := CombatSteering.tether_velocity(Vector2(2600.0, 0.0), wanted, home, 1600.0, 0.5, 400.0)
	_check(_near(far, Vector2(-400.0, 0.0), 0.5), "well past it, it flies straight back at top speed (%s)" % far)
	_check(CombatSteering.tether_velocity(home, wanted, home, 1600.0, 0.5, 400.0) == wanted, "a ship on its point is left alone")


func _test_tuning_and_doctrines() -> void:
	var tuning := AiTuning.shared()
	_check(tuning != null and tuning.validate().is_empty(), "the AI tuning loads and validates %s" % [tuning.validate()])
	_check(tuning.evade_speed <= tuning.trim_range and tuning.strafe_speed <= tuning.trim_range, "weaving and strafing stay within the trim range, so a ship keeps its nose on target")
	var bad := AiTuning.new()
	bad.jink_period_min = 3.0
	bad.jink_period_max = 1.0
	_check(not bad.validate().is_empty(), "an inverted weave period is invalid")
	var registry := ContentRegistry.new()
	var fighter: CombatDoctrine = registry.ship_class(&"fighter").get_doctrine()
	var heavy: CombatDoctrine = registry.ship_class(&"heavy_fighter").get_doctrine()
	var frigate: CombatDoctrine = registry.ship_class(&"frigate").get_doctrine()
	var cruiser: CombatDoctrine = registry.ship_class(&"cruiser").get_doctrine()
	var capital: CombatDoctrine = registry.ship_class(&"capital_ship").get_doctrine()
	_check(fighter.style == CombatDoctrine.Style.DOGFIGHT and heavy.style == CombatDoctrine.Style.DOGFIGHT, "fighters dogfight")
	_check(frigate.style == CombatDoctrine.Style.SKIRMISH and registry.ship_class(&"gunboat").get_doctrine().style == CombatDoctrine.Style.SKIRMISH, "gunboats and frigates skirmish")
	_check(cruiser.style == CombatDoctrine.Style.STANDOFF and capital.style == CombatDoctrine.Style.STANDOFF, "cruisers and capital ships hold off at range")
	_check(fighter.evasion > frigate.evasion and frigate.evasion > cruiser.evasion and cruiser.evasion > capital.evasion, "the smaller the ship the harder it weaves, to nothing for a capital ship")
	_check(fighter.rear_attack_weight > 0.0 and cruiser.rear_attack_weight == 0.0 and frigate.rear_attack_weight == 0.0, "only fighters go for their target's tail")
	_check(frigate.strafe > 0.0 and fighter.strafe == 0.0 and cruiser.strafe == 0.0, "only the skirmishers circle their target")
	_check(fighter.preferred_range_fraction < frigate.preferred_range_fraction and frigate.preferred_range_fraction < cruiser.preferred_range_fraction, "the bigger the ship the further out it fights")
	_check(capital.retreat_hull_fraction == 0.0 and fighter.retreat_hull_fraction > 0.0, "a capital ship never runs; fighters do")
	_check(cruiser.line_role == CombatDoctrine.LineRole.ANCHOR and capital.line_role == CombatDoctrine.LineRole.ANCHOR, "cruisers and capital ships anchor the line")
	_check(fighter.line_role == CombatDoctrine.LineRole.SCREEN and heavy.line_role == CombatDoctrine.LineRole.SCREEN and frigate.line_role == CombatDoctrine.LineRole.SCREEN, "fighters and frigates screen it")
	var bad_doctrine := CombatDoctrine.new()
	bad_doctrine.id = &"x"
	bad_doctrine.display_name = "X"
	bad_doctrine.preferred_range_fraction = 0.0
	_check(not bad_doctrine.validate().is_empty(), "a doctrine that fights from no distance at all is invalid")
	bad_doctrine.preferred_range_fraction = 0.5
	bad_doctrine.evasion = 1.5
	_check(not bad_doctrine.validate().is_empty(), "...and so is an evasion above 1")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
