class_name FormationSteering
extends RefCounted
## The maths of keeping formation, as pure functions on plain data (vectors,
## numbers, and dictionaries describing nearby bodies), so each rule can be tested
## without a scene. Formation and NpcShip do the wiring; the numbers all come from
## FormationTuning.
##
## Nothing here moves a ship: each function returns a velocity or a limit, and
## the ship's own steering (turn, thrust along the heading, speed limit) does the
## flying, so formations obey the same physics as every other NPC.


## The speed a formation's leader cruises at: `margin` of the slowest member's top
## speed (infinite when there are no members), so everyone can keep up.
static func speed_cap(max_speeds: Array, margin: float) -> float:
	var slowest := INF
	for speed: float in max_speeds:
		slowest = minf(slowest, speed)
	return slowest * margin if slowest != INF else INF


## The fastest the leader may turn, in radians per second, with the leader flying
## at `lead_speed`. Each member is a dictionary {"max_speed", "turn_rate", "thrust",
## "distance"} (its distance from the leader). When the formation turns at rate w, a
## member `distance` out must:
##  - swing sideways at w x distance, so it needs that much speed in hand beyond the
##    leader's speed;
##  - bend its course at w, which takes sideways acceleration (lead_speed + w x
##    distance) x w, of which only a fraction of its thrust may be spent (this is
##    solved for w);
##  - turn that fast itself.
static func turn_cap(lead_turn_rate: float, members: Array, lead_speed: float, tuning: FormationTuning) -> float:
	var cap := lead_turn_rate
	for member: Dictionary in members:
		cap = minf(cap, tuning.turn_safety * member["turn_rate"])
		if member["distance"] > 1.0:
			if lead_speed != INF:
				var headroom := maxf(member["max_speed"] - lead_speed, 0.0)
				cap = minf(cap, tuning.turn_safety * headroom / member["distance"])
			var accel: float = tuning.turn_accel_fraction * member["thrust"]
			var speed: float = lead_speed if lead_speed != INF else 0.0
			var distance: float = member["distance"]
			# (speed + w x distance) x w = accel, solved for w.
			cap = minf(cap, (-speed + sqrt(speed * speed + 4.0 * distance * accel)) / (2.0 * distance))
	return maxf(cap, tuning.min_turn_cap)


## The change of velocity a member's trim thrusters make this frame to cancel
## `correction` (the velocity it still needs to gain): at most `trim_accel` (px/s^2)
## for `delta` seconds, in the direction of the correction, and never more than the
## correction itself (no overshoot).
static func trim_delta(correction: Vector2, trim_accel: float, delta: float) -> Vector2:
	var length := correction.length()
	if length < 0.0001:
		return Vector2.ZERO
	return correction / length * minf(trim_accel * delta, length)


## The hardest the leader may start or stop turning, in radians per second per
## second. A member `distance` out must accelerate sideways at (change in turn rate)
## x distance, within a fraction of its thrust. Infinite with no members.
static func turn_accel_cap(members: Array, tuning: FormationTuning) -> float:
	var cap := INF
	for member: Dictionary in members:
		if member["distance"] > 1.0:
			cap = minf(cap, tuning.turn_accel_fraction * member["thrust"] / member["distance"])
	return cap


## The hardest the leader may accelerate along its heading (pixels per second per
## second): a margin of the weakest member's thrust, so every member can keep pace.
## Infinite with no members.
static func thrust_cap(members: Array, tuning: FormationTuning) -> float:
	var weakest := INF
	for member: Dictionary in members:
		weakest = minf(weakest, member["thrust"])
	return weakest * tuning.thrust_margin if weakest != INF else INF


## The velocity a member wants. `slot_error` is the vector from the member to its
## slot, `slot_velocity` how fast the slot itself is moving (the leader's velocity
## plus the swing of the slot when the formation turns). Normally the member matches
## the slot's velocity plus a correction in proportion to the error. A member that
## has fallen far behind (`catching_up`) instead flies straight at its slot at top
## speed. Never faster than `max_speed`.
static func follow_velocity(slot_error: Vector2, slot_velocity: Vector2, max_speed: float,
		catching_up: bool, tuning: FormationTuning) -> Vector2:
	if catching_up:
		return (slot_velocity + slot_error.normalized() * max_speed).limit_length(max_speed)
	return (slot_velocity + slot_error * tuning.slot_gain).limit_length(max_speed)


## How fast a slot moves: the leader's velocity plus the slot's swing as the
## formation turns at `angular_velocity` (radians per second). `world_offset` is
## the slot's offset from the leader, already rotated into the world.
static func slot_velocity(lead_velocity: Vector2, world_offset: Vector2, angular_velocity: float) -> Vector2:
	return lead_velocity + Vector2(-world_offset.y, world_offset.x) * angular_velocity


## A push (a velocity) away from other ships that are too close. `bodies` are
## dictionaries {"node", "position", "radius"}; the ship's own node is skipped.
## A body repels inside (radius + its radius) x (1 + margin), more strongly the
## closer it is; the total is at most `strength` x `max_speed`.
static func separation(self_node: Variant, position: Vector2, radius: float, bodies: Array,
		margin: float, max_speed: float, strength: float) -> Vector2:
	var push := Vector2.ZERO
	for body: Dictionary in bodies:
		if body["node"] == self_node:
			continue
		var away: Vector2 = position - body["position"]
		var distance := away.length()
		var reach: float = (radius + body["radius"]) * (1.0 + margin)
		if distance >= reach or reach <= 0.0:
			continue
		var direction := away / distance if distance > 0.001 else Vector2.RIGHT
		push += direction * (1.0 - distance / reach)
	return push.limit_length(1.0) * max_speed * strength


## A push away from fixed obstacles (planets, stations): {"position", "radius"}
## dictionaries. They repel inside radius + the ship's radius + `margin` pixels.
static func obstacle_push(position: Vector2, radius: float, obstacles: Array, margin: float,
		max_speed: float, strength: float) -> Vector2:
	var push := Vector2.ZERO
	for obstacle: Dictionary in obstacles:
		var away: Vector2 = position - obstacle["position"]
		var distance := away.length()
		var reach: float = obstacle["radius"] + radius + margin
		if distance >= reach:
			continue
		var direction := away / distance if distance > 0.001 else Vector2.RIGHT
		push += direction * (1.0 - distance / reach)
	return push.limit_length(1.0) * max_speed * strength
