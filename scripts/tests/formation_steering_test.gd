extends SceneTree
## Tests the formation steering maths (speed and turn limits, following velocity,
## separation and obstacle avoidance) as pure functions.
##   Godot --headless --path . --script res://scripts/tests/formation_steering_test.gd </dev/null

var _failures: int = 0
var _tuning: FormationTuning


func _init() -> void:
	_tuning = FormationTuning.shared()
	_test_speed_cap()
	_test_turn_cap()
	_test_follow_velocity()
	_test_separation()
	_test_obstacles()

	print("FORMATION STEERING TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _test_speed_cap() -> void:
	_check(is_equal_approx(FormationSteering.speed_cap([750.0, 650.0, 750.0], 0.9), 585.0), "the leader cruises at 90%% of the slowest member (585)")
	_check(FormationSteering.speed_cap([], 0.9) == INF, "no members, no cap")
	_check(is_equal_approx(FormationSteering.speed_cap([240.0, 700.0], 0.5), 120.0), "the margin is a plain multiplier")


## The sideways-acceleration limit on w for a member `distance` out, at lead speed v:
## (v + w x distance) x w = accel.
func _accel_limit(speed: float, distance: float, thrust: float) -> float:
	var accel := _tuning.turn_accel_fraction * thrust
	return (-speed + sqrt(speed * speed + 4.0 * distance * accel)) / (2.0 * distance)


func _test_turn_cap() -> void:
	# Fighters 110 and 220 px out; leader at 585, top speed 750: the outer ship has 165 px/s in hand.
	var members := [
		{"max_speed": 750.0, "turn_rate": 4.8, "thrust": 480.0, "distance": 110.0},
		{"max_speed": 750.0, "turn_rate": 4.8, "thrust": 480.0, "distance": 220.0}]
	var speed_limit := _tuning.turn_safety * 165.0 / 220.0
	var cap := FormationSteering.turn_cap(4.0, members, 585.0, _tuning)
	_check(is_equal_approx(cap, minf(speed_limit, _accel_limit(585.0, 220.0, 480.0))), "the outer member speed and acceleration limit the turn (%.2f rad/s)" % cap)
	_check(cap <= speed_limit + 0.0001, "never more than its spare speed allows")
	# A slower leader may turn more tightly: the sideways acceleration needed falls with its speed.
	var slow_cap := FormationSteering.turn_cap(4.0, members, 100.0, _tuning)
	_check(slow_cap > cap, "a slower leader can turn faster (%.2f > %.2f)" % [slow_cap, cap])
	_check(is_equal_approx(slow_cap, minf(_tuning.turn_safety * 650.0 / 220.0, _accel_limit(100.0, 220.0, 480.0))), "at low speed the engines set the limit (%.2f)" % slow_cap)
	# A stationary leader: only w^2 x distance matters.
	var still := FormationSteering.turn_cap(4.0, members, 0.0, _tuning)
	_check(is_equal_approx(still, minf(_tuning.turn_safety * 750.0 / 220.0, sqrt(_tuning.turn_accel_fraction * 480.0 / 220.0))), "a stationary leader turns as fast as the engines allow (%.2f)" % still)
	# The sideways acceleration really is within budget at the limit.
	var w := FormationSteering.turn_cap(4.0, [members[1]], 351.0, _tuning)
	_check((351.0 + w * 220.0) * w <= _tuning.turn_accel_fraction * 480.0 + 0.01, "at the limit the sideways acceleration (v + w r) x w stays within the thrust fraction")
	# A slow-turning member limits it directly.
	var clumsy := [{"max_speed": 9999.0, "turn_rate": 0.9, "thrust": 9999.0, "distance": 10.0}]
	_check(is_equal_approx(FormationSteering.turn_cap(4.0, clumsy, 100.0, _tuning), _tuning.turn_safety * 0.9), "a member that turns slowly limits the whole formation")
	# The leader own turn rate is the ceiling.
	_check(FormationSteering.turn_cap(0.5, [{"max_speed": 9999.0, "turn_rate": 9.0, "thrust": 9999.0, "distance": 10.0}], 100.0, _tuning) == 0.5, "the leader own turn rate is a ceiling")
	# Never below the minimum, even with no speed in hand.
	var stuck := [{"max_speed": 585.0, "turn_rate": 4.8, "thrust": 480.0, "distance": 300.0}]
	_check(FormationSteering.turn_cap(4.0, stuck, 585.0, _tuning) == _tuning.min_turn_cap, "the turn limit never drops below the minimum")
	_check(FormationSteering.turn_cap(3.0, [], INF, _tuning) == 3.0, "no members: the leader rate")
	# A bigger formation turns more slowly than a tight one, and weak engines slow it too.
	var tight := [{"max_speed": 750.0, "turn_rate": 4.8, "thrust": 480.0, "distance": 100.0}]
	var wide := [{"max_speed": 750.0, "turn_rate": 4.8, "thrust": 480.0, "distance": 400.0}]
	_check(FormationSteering.turn_cap(4.0, wide, 100.0, _tuning) < FormationSteering.turn_cap(4.0, tight, 100.0, _tuning), "a wider formation turns more slowly")
	var weak := [{"max_speed": 750.0, "turn_rate": 4.8, "thrust": 90.0, "distance": 100.0}]
	_check(FormationSteering.turn_cap(4.0, weak, 100.0, _tuning) < FormationSteering.turn_cap(4.0, tight, 100.0, _tuning), "weak engines slow the turn")
	# The sideways-acceleration cap on how fast the turn rate may change.
	_check(is_equal_approx(FormationSteering.turn_accel_cap(members, _tuning), _tuning.turn_accel_fraction * 480.0 / 220.0), "the turn rate may change as fast as the outermost member engines allow")
	_check(FormationSteering.turn_accel_cap([], _tuning) == INF, "no members, no limit on changing the turn rate")
	# The leader own acceleration is held below the weakest member thrust.
	_check(is_equal_approx(FormationSteering.thrust_cap([{"thrust": 480.0}, {"thrust": 380.0}], _tuning), 380.0 * _tuning.thrust_margin), "the leader accelerates no harder than a margin of the weakest member thrust")
	_check(FormationSteering.thrust_cap([], _tuning) == INF, "no members, no thrust limit")
	# Trim thrusters: a limited push toward the correction, never past it.
	var push := FormationSteering.trim_delta(Vector2(100.0, 0.0), 240.0, 1.0 / 60.0)
	_check(is_equal_approx(push.x, 4.0) and is_equal_approx(push.y, 0.0), "a trim thruster adds at most its acceleration for the frame (4 px/s)")
	_check(FormationSteering.trim_delta(Vector2(1.0, 0.0), 240.0, 1.0 / 60.0) == Vector2(1.0, 0.0), "and never more than the correction itself")
	_check(FormationSteering.trim_delta(Vector2.ZERO, 240.0, 1.0 / 60.0) == Vector2.ZERO, "no correction, no push")
	_check(FormationSteering.trim_delta(Vector2(0.0, -50.0), 240.0, 1.0 / 60.0).y < 0.0, "trim thrusters push in any direction, not only along the nose")
	_check(is_equal_approx(FormationSteering.slot_velocity(Vector2(300.0, 0.0), Vector2(0.0, 100.0), 0.5).x, 250.0), "a slot to the right swings backward when the formation turns right (300 - 0.5 x 100)")
	_check(is_equal_approx(FormationSteering.slot_velocity(Vector2(300.0, 0.0), Vector2(100.0, 0.0), 0.5).y, 50.0), "a slot ahead swings to the right when the formation turns right")


func _test_follow_velocity() -> void:
	var lead := Vector2(300.0, 0.0)
	# On its slot a member simply matches the leader.
	_check(FormationSteering.follow_velocity(Vector2.ZERO, lead, 750.0, false, _tuning) == lead, "on its slot a member matches the leader's velocity")
	# Behind its slot (the slot is ahead): faster than the leader.
	var behind := FormationSteering.follow_velocity(Vector2(50.0, 0.0), lead, 750.0, false, _tuning)
	_check(behind.x > lead.x and is_equal_approx(behind.x, lead.x + 50.0 * _tuning.slot_gain), "a member behind its slot speeds up in proportion to the error")
	# Ahead of its slot: slower.
	_check(FormationSteering.follow_velocity(Vector2(-50.0, 0.0), lead, 750.0, false, _tuning).x < lead.x, "a member ahead of its slot slows down")
	# Never above its top speed.
	_check(FormationSteering.follow_velocity(Vector2(5000.0, 0.0), lead, 750.0, false, _tuning).length() <= 750.0 + 0.001, "never faster than the member's top speed")
	# Catching up: full speed straight at the slot.
	var chase := FormationSteering.follow_velocity(Vector2(0.0, 600.0), lead, 750.0, true, _tuning)
	_check(chase.length() <= 750.0 + 0.001 and chase.y > 0.0, "a member that has fallen behind flies at its slot")
	_check(chase.length() > FormationSteering.follow_velocity(Vector2(0.0, 600.0), lead, 750.0, false, _tuning).length() * 0.9, "catching up uses speed in hand")


func _bodies(positions: Array, radius: float = 30.0) -> Array:
	var result: Array = []
	for index in positions.size():
		result.append({"node": index, "position": positions[index], "radius": radius})
	return result


func _test_separation() -> void:
	var bodies := _bodies([Vector2(0, 0), Vector2(40, 0), Vector2(1000, 0)])
	var push := FormationSteering.separation(0, Vector2(0, 0), 30.0, bodies, 0.6, 700.0, 0.8)
	_check(push.x < 0.0 and absf(push.y) < 0.001, "a ship pushes away from one that is too close")
	_check(push.length() <= 700.0 * 0.8 + 0.001, "the push never exceeds strength x top speed")
	var far := FormationSteering.separation(2, Vector2(1000, 0), 30.0, bodies, 0.6, 700.0, 0.8)
	_check(far == Vector2.ZERO, "ships that are far apart do not push each other")
	var edge := FormationSteering.separation(0, Vector2(0, 0), 30.0, _bodies([Vector2(0, 0), Vector2(96, 0)]), 0.6, 700.0, 0.8)
	_check(edge == Vector2.ZERO, "no push at the edge of the avoidance range ((30+30) x 1.6 = 96)")
	var closer := FormationSteering.separation(0, Vector2(0, 0), 30.0, _bodies([Vector2(0, 0), Vector2(30, 0)]), 0.6, 700.0, 0.8)
	var farther := FormationSteering.separation(0, Vector2(0, 0), 30.0, _bodies([Vector2(0, 0), Vector2(80, 0)]), 0.6, 700.0, 0.8)
	_check(closer.length() > farther.length(), "the closer the ship, the harder the push")
	# Ships either side cancel out; ships on one side add up.
	var both_sides := FormationSteering.separation(0, Vector2(0, 0), 30.0, _bodies([Vector2(0, 0), Vector2(50, 0), Vector2(-50, 0)]), 0.6, 700.0, 0.8)
	_check(both_sides.length() < 1.0, "pushes from opposite sides cancel")
	var one_side := FormationSteering.separation(0, Vector2(0, 0), 30.0, _bodies([Vector2(0, 0), Vector2(50, 0), Vector2(50, 20)]), 0.6, 700.0, 0.8)
	_check(one_side.length() > FormationSteering.separation(0, Vector2(0, 0), 30.0, _bodies([Vector2(0, 0), Vector2(50, 0)]), 0.6, 700.0, 0.8).length(), "two close ships push harder than one")
	# Exactly on top of another ship still pushes somewhere (no division by zero).
	var stacked := FormationSteering.separation(0, Vector2(5, 5), 30.0, _bodies([Vector2(5, 5), Vector2(5, 5)]), 0.6, 700.0, 0.8)
	_check(stacked.length() > 0.0 and is_finite(stacked.x) and is_finite(stacked.y), "a ship exactly on top of another is still pushed")
	# Bigger ships keep more distance.
	var big_body := [{"node": 1, "position": Vector2(100, 0), "radius": 160.0}]
	_check(FormationSteering.separation(0, Vector2(0, 0), 30.0, big_body, 0.6, 700.0, 0.8).length() > 0.0, "a big ship is avoided from farther away")


func _test_obstacles() -> void:
	var planet := [{"position": Vector2(500, 0), "radius": 200.0}]
	var near := FormationSteering.obstacle_push(Vector2(250, 0), 30.0, planet, 80.0, 600.0, 0.8)
	_check(near.x < 0.0, "a ship near a planet is pushed away from it")
	_check(FormationSteering.obstacle_push(Vector2(-500, 0), 30.0, planet, 80.0, 600.0, 0.8) == Vector2.ZERO, "a ship far from a planet is not pushed")
	var inside := FormationSteering.obstacle_push(Vector2(500, 0), 30.0, planet, 80.0, 600.0, 0.8)
	_check(inside.length() > 0.0 and is_finite(inside.x), "a ship at a planet's centre is still pushed out")
	_check(near.length() <= 600.0 * 0.8 + 0.001, "the obstacle push is capped")
	var margin_edge := FormationSteering.obstacle_push(Vector2(500 - 310, 0), 30.0, planet, 80.0, 600.0, 0.8)
	_check(margin_edge == Vector2.ZERO, "no push at the edge (radius + ship + margin = 310)")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
