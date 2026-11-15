class_name CombatSteering
extends RefCounted
## The maths of fighting in space: where to aim, how to hold a fighting range, how to
## get behind a target, how to weave and how to run. Pure functions on positions and
## velocities (no nodes), like FormationSteering, so the behaviours can be tested
## without a scene. ShipPilot picks which to use; NpcShip flies the result.
##
## How strongly a fleeing ship leans toward an exit (1 = as much as it runs from the
## threats).
const EXIT_LEAN := 0.75

## Everything returns a VELOCITY the ship should have (px/s). The ship's own physics
## (turn, then thrust along the heading) takes it from there.


## Where to aim so a shot of `projectile_speed` meets the target, or at the target
## itself when it cannot be caught (or the weapon has no shot speed).
static func lead_point(shooter_pos: Vector2, shooter_velocity: Vector2, target_pos: Vector2,
		target_velocity: Vector2, projectile_speed: float) -> Vector2:
	if projectile_speed <= 0.0:
		return target_pos
	var aim: Variant = Intercept.solve(shooter_pos, shooter_velocity, target_pos, target_velocity, projectile_speed)
	return aim if aim != null else target_pos


## Whether a nose pointing along `heading` is on target for a shot from `muzzle`
## at `aim_point`: within `tolerance_degrees`, or the angle the target's own size
## covers at that distance if that is wider.
static func is_aimed(heading: float, muzzle: Vector2, aim_point: Vector2, target_radius: float, tolerance_degrees: float) -> bool:
	var to_target := aim_point - muzzle
	var distance := to_target.length()
	if distance < 1.0:
		return true
	var covered := atan2(target_radius, distance)
	return absf(angle_difference(heading, to_target.angle())) <= maxf(deg_to_rad(tolerance_degrees), covered)


## The velocity that takes a ship to `hold_distance` from `point` (which itself
## moves at `point_velocity`) and keeps it there: the point's own velocity plus a
## closing speed that falls to nothing at the hold distance, set so a ship that can
## brake at `brake_accel` (px/s^2) just stops in time. Too close, it backs away, at
## most `max_back_speed`. The closing speed is never more than `top_speed`.
static func close_velocity(position: Vector2, point: Vector2, point_velocity: Vector2, hold_distance: float,
		top_speed: float, brake_accel: float, max_back_speed: float) -> Vector2:
	var to_point := point - position
	var distance := to_point.length()
	if distance < 0.001:
		return point_velocity
	var direction := to_point / distance
	var excess := distance - hold_distance
	var closing: float
	if excess >= 0.0:
		closing = minf(sqrt(2.0 * brake_accel * excess), top_speed)
	else:
		closing = -minf(sqrt(2.0 * brake_accel * -excess), max_back_speed)
	return point_velocity + direction * closing


## The place `distance` behind a target: along the reverse of its direction of
## travel, or of its nose when it is nearly stopped.
static func trail_point(target_pos: Vector2, target_velocity: Vector2, target_heading: float, distance: float) -> Vector2:
	return target_pos - forward_of(target_velocity, target_heading) * distance


## The direction a ship is going: its velocity, or its nose when it is nearly stopped.
static func forward_of(velocity: Vector2, heading: float) -> Vector2:
	return velocity.normalized() if velocity.length() > 40.0 else Vector2.from_angle(heading)


## How far round from dead behind the target a position is, in radians: 0 right on
## its tail, PI straight ahead of it.
static func angle_off_tail(position: Vector2, target_pos: Vector2, target_forward: Vector2) -> float:
	return absf(angle_difference((position - target_pos).angle(), (-target_forward).angle()))


## How much of the way to its target's tail a dogfighter should manoeuvre now:
## `base` (its doctrine's rear attack weight), or 0 when it is already behind the
## target (within `tail_cone`) or has `committed` to a direct attack.
static func rear_weight(base: float, off_tail: float, tail_cone: float, committed: bool) -> float:
	if committed or off_tail <= tail_cone:
		return 0.0
	return base


## A sideways velocity that circles the target: perpendicular to the line to it,
## `speed` px/s, clockwise or anticlockwise by `side` (1 or -1).
static func strafe_velocity(position: Vector2, point: Vector2, speed: float, side: float) -> Vector2:
	var to_point := point - position
	if to_point.length() < 0.001:
		return Vector2.ZERO
	return to_point.orthogonal().normalized() * side * speed


## A weave to throw off the aim of a threat at `threat_pos`: perpendicular to the
## line between the two, `strength` (0 to 1) of `top_speed`, to the side given by
## `side` (1 or -1). The caller changes `side` now and then.
static func evade_velocity(position: Vector2, threat_pos: Vector2, strength: float, top_speed: float, side: float) -> Vector2:
	var to_threat := threat_pos - position
	if to_threat.length() < 0.001 or strength <= 0.0:
		return Vector2.ZERO
	return to_threat.orthogonal().normalized() * side * strength * top_speed


## `wanted` bent back toward `point` when the ship is further from it than `radius`: no
## change inside the radius, then more and more of the way to flying straight back at
## `top_speed`, all of it `soft_band` (a fraction of the radius) beyond the edge.
static func tether_velocity(position: Vector2, wanted: Vector2, point: Vector2, radius: float,
		soft_band: float, top_speed: float) -> Vector2:
	var to_point := point - position
	var distance := to_point.length()
	if distance <= radius or distance < 0.001:
		return wanted
	var pull := clampf((distance - radius) / maxf(radius * soft_band, 1.0), 0.0, 1.0)
	return wanted.lerp(to_point / distance * top_speed, pull)


## The velocity of a ship running from `threats` at `top_speed`: directly away from
## them (nearer ones count for more). With an `exit_direction` (a way out of the
## system, a unit vector, or ZERO for none) it leans toward the exit as far as it
## does not mean running into the threats.
static func flee_velocity(position: Vector2, threats: Array[Vector2], exit_direction: Vector2, top_speed: float) -> Vector2:
	var away := Vector2.ZERO
	for threat in threats:
		var from_threat := position - threat
		var distance := maxf(from_threat.length(), 1.0)
		away += from_threat / distance * (1.0 / distance)
	if away.length() < 0.000001:
		return exit_direction * top_speed
	var direction := away.normalized()
	if exit_direction != Vector2.ZERO:
		direction = (direction + exit_direction * EXIT_LEAN).normalized()
	return direction * top_speed


## The best of `exit_directions` (unit vectors) to run for: the one most directly
## away from the threats, or ZERO when there are none.
static func best_exit(position: Vector2, threats: Array[Vector2], exit_directions: Array[Vector2]) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -INF
	for exit in exit_directions:
		var score := 0.0
		for threat in threats:
			score += (position - threat).normalized().dot(exit)
		if score > best_score:
			best_score = score
			best = exit
	return best
