class_name FormationTuning
extends Resource
## The tunable numbers shared by every formation, in one file:
## resources/formations/formation_tuning.tres. Nothing here is tuned in code.

const PATH := "res://resources/formations/formation_tuning.tres"

static var _shared: FormationTuning

@export_group("Slots")
## Gap kept between the two biggest members, as a multiple of their combined
## radii. Above 1 so even the biggest ships never overlap in their slots.
@export var spacing_gap_factor: float = 1.3

@export_group("Station keeping")
## A ship is "on station" when it is within this fraction of the spacing from its
## slot (never less than station_tolerance_min pixels).
@export var station_tolerance_factor: float = 0.25
@export var station_tolerance_min: float = 20.0
## How hard a member closes on its slot: the extra speed (px/s) per pixel of error.
@export var slot_gain: float = 1.2
## Station-keeping thrusters. A ship with forward-only engines can only brake by
## turning round, which a member cannot do every time the formation turns (the
## slots on the inside of a turn move slower than the leader). So small velocity
## corrections (up to trim_range, px/s) are made with trim thrusters: a fraction of
## the ship's thrust in any direction, with the nose staying with the leader.
## Bigger corrections use the main engines (turn, then thrust). Zero fraction turns
## the trim thrusters off.
@export_range(0.0, 1.0) var trim_thrust_fraction: float = 0.5
@export var trim_range: float = 260.0

@export_group("Orientation")
## The formation's slots are laid out along the leader's direction of TRAVEL once it
## is moving faster than this (px/s), and along its nose below that (a leader that is
## stopped or turning on the spot). A leader's nose swings ahead of its path, so
## following the path keeps the slots turning smoothly. The blend takes another
## travel_heading_blend px/s to complete.
@export var travel_heading_speed: float = 20.0
@export var travel_heading_blend: float = 40.0

@export_group("Leader limits")
## The leader cruises at this fraction of the slowest member's top speed, so
## every member can keep up and still has speed in hand to hold its place.
@export var speed_margin: float = 0.9
## The leader turns no faster than this fraction of what the outer members and
## the slowest-turning member can follow.
@export var turn_safety: float = 0.8
## Turning a formation needs the members to accelerate sideways (see
## FormationSteering.turn_cap); only this fraction of a ship's thrust may be spent on
## it. Keep it below trim_thrust_fraction so members have some in reserve.
@export var turn_accel_fraction: float = 0.4
## The leader accelerates no harder than this fraction of the weakest member's thrust,
## so members can keep pace when it speeds up or slows down.
@export var thrust_margin: float = 0.8
## The leader's turn rate never drops below this (radians per second).
@export var min_turn_cap: float = 0.2

@export_group("Recovery")
## A member this many spacings from its slot breaks off to fly straight at it at
## full speed, ignoring the leader's velocity (it has fallen behind).
@export var catch_up_factor: float = 3.0
## A member farther than this (pixels) for lost_time seconds has separated: it is
## released from the formation and carries on alone.
@export var lost_distance: float = 2500.0
@export var lost_time: float = 20.0
## A member below this fraction of its hull is out of the fight and falls out
## of formation (there is no engine damage yet, so "disabled" means this).
@export_range(0.0, 1.0) var disabled_hull_fraction: float = 0.25

@export_group("Collision avoidance")
## Ships start to avoid each other inside (radius + radius) x (1 + margin), pushing
## away at up to this fraction of their top speed.
@export var separation_margin: float = 0.6
@export var separation_strength: float = 0.8
## Planets and stations are avoided inside their radius plus this many pixels.
@export var obstacle_margin: float = 80.0
@export var obstacle_strength: float = 0.8


## The project's tuning (loaded once).
static func shared() -> FormationTuning:
	if _shared == null:
		_shared = load(PATH)
	return _shared


func validate() -> Array[String]:
	var problems: Array[String] = []
	if spacing_gap_factor < 1.0:
		problems.append("spacing_gap_factor must be at least 1 so big ships do not overlap")
	if station_tolerance_factor <= 0.0 or station_tolerance_min < 0.0:
		problems.append("station tolerance must be above zero")
	if slot_gain <= 0.0:
		problems.append("slot_gain must be above zero")
	if trim_thrust_fraction < 0.0 or trim_thrust_fraction > 1.0 or trim_range < 0.0:
		problems.append("trim_thrust_fraction must be between 0 and 1, and trim_range cannot be negative")
	if speed_margin <= 0.0 or speed_margin > 1.0:
		problems.append("speed_margin must be above 0 and at most 1")
	if turn_safety <= 0.0 or turn_safety > 1.0:
		problems.append("turn_safety must be above 0 and at most 1")
	if turn_accel_fraction <= 0.0 or turn_accel_fraction > 1.0:
		problems.append("turn_accel_fraction must be above 0 and at most 1")
	if thrust_margin <= 0.0 or thrust_margin > 1.0:
		problems.append("thrust_margin must be above 0 and at most 1")
	if min_turn_cap <= 0.0:
		problems.append("min_turn_cap must be above zero")
	if catch_up_factor <= 1.0:
		problems.append("catch_up_factor must be above 1")
	if lost_distance <= 0.0 or lost_time <= 0.0:
		problems.append("lost_distance and lost_time must be above zero")
	if separation_margin < 0.0 or obstacle_margin < 0.0:
		problems.append("avoidance margins cannot be negative")
	return problems
