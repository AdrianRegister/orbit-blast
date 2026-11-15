class_name AiTuning
extends Resource
## The shared numbers of how NPC pilots behave: how often they think, how long
## they stay calm before they stand down, how they weave and strafe. One file:
## resources/combat/ai/ai_tuning.tres. What differs between kinds of ship (how close
## they fight, how hard they dodge) is in the CombatDoctrine instead. All numbers
## are first guesses.

const PATH := "res://resources/combat/ai/ai_tuning.tres"

static var _shared: AiTuning


## The project's tuning (loaded once).
static func shared() -> AiTuning:
	if _shared == null:
		_shared = load(PATH)
	return _shared


@export_group("Thinking")
## Seconds between a pilot's decisions (who to shoot, whether to run). Flying and
## firing happen every frame.
@export_range(0.05, 2.0) var decision_interval: float = 0.25
## A pilot that has seen no enemy for this long (seconds) stands down and goes back
## to what it was doing.
@export_range(0.0, 30.0) var calm_time: float = 3.0
## An unarmed ship runs from an armed enemy within this distance (pixels).
@export_range(100.0, 10000.0) var flee_alarm_range: float = 1800.0
## A ship that was hit this recently (seconds) counts as under attack and dodges.
@export_range(0.0, 10.0) var damage_alarm_seconds: float = 2.0

@export_group("Pursuit")
## A pilot gives up chasing when it has gone this far (pixels) from where it began the
## fight, so a ship that runs from an equally fast one is not chased across the galaxy.
@export_range(500.0, 50000.0) var pursuit_leash: float = 3000.0
## It then ignores that target for this long (seconds), and goes back to what it was doing.
@export_range(1.0, 300.0) var give_up_seconds: float = 30.0

@export_group("Battle line")
## A ship counts as being in a battle line when an armed friend is within this distance
## (pixels); on its own it fights as a free agent.
@export_range(500.0, 20000.0) var line_join_range: float = 3500.0
## How far (pixels) a screen ship (fighters, frigates) may stray from its anchor or, with
## no anchor, from the centre of its friends: it picks no target further than this
## from that point and is drawn back as it nears the edge.
@export_range(300.0, 10000.0) var screen_radius: float = 1600.0
## The edge of the screen is soft: the pull back builds up over this fraction of the
## radius beyond it.
@export_range(0.1, 2.0) var screen_soft_band: float = 0.5
## An anchor shoots what is within its longest weapon reach times this of the point it holds.
@export_range(1.0, 2.0) var anchor_reach_margin: float = 1.1
## An anchor that has had nothing in reach for this long (seconds), even if it is under
## fire from ships it cannot hit, creeps up on the enemy.
@export_range(1.0, 60.0) var anchor_advance_delay: float = 4.0
## How fast its place moves while it creeps (a fraction of its top speed), so that the
## screen keeps up.
@export_range(0.05, 1.0) var anchor_advance_speed: float = 0.3
## It creeps no further than this (pixels) from where the line first formed.
@export_range(100.0, 10000.0) var anchor_advance_limit: float = 1500.0

@export_group("Flying")
## The velocity a pilot wants to match the target's at its fighting range: how
## sharply it brakes for the range is set by the ship's own thrust times this fraction.
@export_range(0.1, 1.0) var brake_fraction: float = 0.8
## How fast a ship may back away to keep its range, as a fraction of its top speed.
@export_range(0.0, 1.0) var max_back_speed_fraction: float = 0.5
## Small corrections to a ship's velocity (up to this many px/s) are made with
## station-keeping trim thrusters in any direction, which is what lets a ship strafe
## while it keeps its nose on the target (formation members use them too). Each
## trims with this fraction of the ship's thrust.
@export_range(0.0, 1000.0) var trim_range: float = 220.0
@export_range(0.0, 1.0) var trim_thrust_fraction: float = 0.3

@export_group("Evasion and strafing")
## The sideways speed (px/s) a ship with evasion 1 weaves at; a doctrine's evasion is
## a fraction of it. Keep it near the trim range, so a weaving ship can still hold its
## nose on its target.
@export_range(0.0, 1000.0) var evade_speed: float = 180.0
## A dodging ship changes the side it weaves to every so many seconds (a random
## time between the two).
@export_range(0.1, 5.0) var jink_period_min: float = 0.5
@export_range(0.1, 5.0) var jink_period_max: float = 1.3
## The speed (px/s) a ship with strafe 1 circles its target at; a doctrine's strafe is
## a fraction of it. Like evade_speed, it must stay within the trim range for the ship
## to keep its nose on the target while it circles.
@export_range(0.0, 1000.0) var strafe_speed: float = 140.0
## A strafing ship (see CombatDoctrine.strafe) circles the other way after this long.
@export_range(0.5, 20.0) var strafe_period: float = 3.0

@export_group("Dogfighting")
## A fighter that is within this angle (degrees) of dead behind its target attacks it
## directly instead of manoeuvring for its tail.
@export_range(5.0, 180.0) var tail_cone_degrees: float = 70.0
## A fighter that has gone this long (seconds) without firing stops manoeuvring for
## its target's tail and attacks directly for `commit_time`, so it never spends a
## whole fight repositioning.
@export_range(0.5, 20.0) var reposition_limit: float = 3.0
@export_range(0.5, 20.0) var commit_time: float = 2.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if jink_period_min > jink_period_max:
		problems.append("jink_period_min is above jink_period_max")
	if decision_interval <= 0.0:
		problems.append("decision_interval must be above zero")
	if pursuit_leash <= 0.0 or give_up_seconds <= 0.0:
		problems.append("pursuit_leash and give_up_seconds must be above zero")
	if anchor_advance_speed <= 0.0 or anchor_advance_limit <= 0.0:
		problems.append("anchor_advance_speed and anchor_advance_limit must be above zero")
	if line_join_range <= 0.0 or screen_radius <= 0.0 or anchor_reach_margin < 1.0:
		problems.append("line_join_range and screen_radius must be above zero, anchor_reach_margin at least 1")
	return problems
