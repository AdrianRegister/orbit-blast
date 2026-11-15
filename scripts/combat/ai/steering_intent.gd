class_name SteeringIntent
extends RefCounted
## What a pilot wants its ship to do this frame, as plain data: the velocity it
## wants and where it wants to point. NpcShip flies it with the ship's own physics
## (turn at the ship's turn rate, thrust along the heading), so a pilot can only ask
## for what the ship can do.

## The velocity the pilot wants (px/s). The ship turns and thrusts to get there.
var velocity: Vector2 = Vector2.ZERO
## The heading (radians, 0 = facing right) to hold while the velocity needs no
## correcting, so the nose stays on the target. NAN: face along the velocity.
var aim: float = NAN


func _init(wanted_velocity: Vector2 = Vector2.ZERO, wanted_aim: float = NAN) -> void:
	velocity = wanted_velocity
	aim = wanted_aim
