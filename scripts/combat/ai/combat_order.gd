class_name CombatOrder
extends RefCounted
## What a unit commander tells one ship's pilot to do, as plain data (Phase 3.3, step 4).
## An order never says HOW to fly: the pilot does that from its doctrine. Commanders
## reissue orders about once a second, and clear them when the unit stands down.
##
##   FIRE_AT_WILL  keep your place and shoot what comes in range (the pilot does not fly)
##   ENGAGE        fight: go for `target` (the commander's choice; the pilot picks its own
##                 if it is null or gone), staying in the unit's slot to return to
##   GUARD         as ENGAGE, but stay within `radius` of `protectee` and only take
##                 targets inside that radius (an escort)
##   MOVE          fly to `point` at the formation's own speed and turn limits (the leader of
##                 a unit closing on an enemy), shooting what is in range on the way
##   WITHDRAW      run from `point` (where the enemy is) for the way out of the system and
##                 jump, at the formation's limits (the leader of a unit that is losing)

enum Kind { FIRE_AT_WILL, ENGAGE, GUARD, MOVE, WITHDRAW }

var kind: Kind = Kind.FIRE_AT_WILL
## ENGAGE and GUARD: the Combatant to attack (may be null).
var target: Combatant
## GUARD: the ship to stay near, and how far from it the escort may go (pixels).
var protectee: NpcShip
var radius: float = 0.0
## MOVE: where to fly. WITHDRAW: where the enemy is, to run from.
var point: Vector2 = Vector2.ZERO


func _init(order_kind: Kind = Kind.FIRE_AT_WILL) -> void:
	kind = order_kind


## Whether the order puts the pilot in charge of flying the ship (so it leaves its slot).
func takes_control() -> bool:
	return kind != Kind.FIRE_AT_WILL


## Whether the ship keeps the formation's speed and turn limits while it obeys.
func keeps_formation_limits() -> bool:
	return kind == Kind.MOVE or kind == Kind.WITHDRAW
