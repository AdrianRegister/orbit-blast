class_name Intercept
extends RefCounted
## Aim-ahead maths: where to fire so a shot meets a moving target.
## Used by turrets and the HUD lead marker, and later by NPC combat AI.


## Time until a shot of `projectile_speed` fired now from a shooter moving at
## `shooter_vel` meets a target at `target_pos` moving at `target_vel`.
## Returns -1.0 when no meeting is possible.
static func time_to_hit(shooter_pos: Vector2, shooter_vel: Vector2, target_pos: Vector2, target_vel: Vector2, projectile_speed: float) -> float:
	# Work in the shooter's frame: the shot leaves at projectile_speed relative
	# to the shooter (a shot keeps the shooter's velocity), the target moves at
	# its relative velocity.
	var rel_pos := target_pos - shooter_pos
	var rel_vel := target_vel - shooter_vel
	# Solve |rel_pos + rel_vel * t| = projectile_speed * t for the smallest t > 0.
	var a := rel_vel.length_squared() - projectile_speed * projectile_speed
	var b := 2.0 * rel_pos.dot(rel_vel)
	var c := rel_pos.length_squared()
	if absf(a) < 0.0001:
		if absf(b) < 0.0001:
			return -1.0
		var t_linear := -c / b
		return t_linear if t_linear > 0.0 else -1.0
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return -1.0
	var root := sqrt(discriminant)
	var t1 := (-b - root) / (2.0 * a)
	var t2 := (-b + root) / (2.0 * a)
	var best := -1.0
	for t in [t1, t2]:
		if t > 0.0 and (best < 0.0 or t < best):
			best = t
	return best


## The world position to aim at, or null if the target cannot be hit.
static func solve(shooter_pos: Vector2, shooter_vel: Vector2, target_pos: Vector2, target_vel: Vector2, projectile_speed: float) -> Variant:
	var t := time_to_hit(shooter_pos, shooter_vel, target_pos, target_vel, projectile_speed)
	if t < 0.0:
		return null
	return target_pos + target_vel * t
