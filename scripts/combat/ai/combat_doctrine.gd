class_name CombatDoctrine
extends Resource
## How a kind of ship fights, as data: what it likes to shoot at and how far it
## sees. One .tres per doctrine in resources/combat/ai/doctrines/; a ship class
## names its doctrine with `ShipClass.doctrine`. A doctrine is shared by every class
## that names it (gunboats and frigates fly the same one). Ships of a class never
## need code of their own: a new class, or a new ship of an old one, needs only data.
##
## TargetScorer reads the target-choice numbers below. (Later steps add how the
## ship flies: preferred range, evasion, retreat.) All numbers are first guesses.

@export var id: StringName = &""
@export var display_name: String = ""

## How far the ship sees, as a multiple of the reach of its longest weapon.
@export_range(1.0, 10.0) var sensor_range_factor: float = 2.5

@export_group("Target choice")
## The sizes of ship this doctrine is meant for (ShipClass.tier, inclusive): a
## fighter is meant for light craft, a cruiser for big ships. A target outside the
## range is still allowed, but is liked less the further its size is from it.
@export_range(0, 10) var preferred_tier_min: int = 0
@export_range(0, 10) var preferred_tier_max: int = 4
## How much each thing counts in a target's score (see TargetScorer).
@export var weight_effectiveness: float = 3.0
@export var weight_affinity: float = 1.0
@export var weight_threat: float = 1.5
@export var weight_distance: float = 1.0
@export var weight_finish: float = 0.5
@export var weight_focus: float = 1.0
@export var weight_overkill: float = 1.5
## A threat to a ship this ship protects counts this many times over: escorts go
## for whatever is attacking what they guard.
@export_range(1.0, 5.0) var protect_bonus: float = 2.0
## How far ahead a threat is judged: a target that could destroy this ship once in
## this many seconds is a 63% threat, twice a 86% threat (see TargetScorer.threat).
@export_range(1.0, 120.0) var threat_horizon: float = 20.0
## A new target must score this much better (a fraction) than the current one to
## replace it, so ships do not keep changing their minds.
@export_range(0.0, 2.0) var hysteresis: float = 0.25


## How far a ship with a longest weapon reach of `weapon_range` sees.
func sensor_range(weapon_range: float) -> float:
	return weapon_range * sensor_range_factor


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if preferred_tier_min > preferred_tier_max:
		problems.append("preferred_tier_min is above preferred_tier_max")
	for weight in [weight_effectiveness, weight_affinity, weight_threat, weight_distance, weight_finish, weight_focus, weight_overkill]:
		if weight < 0.0:
			problems.append("a weight is negative")
			break
	if protect_bonus < 1.0:
		problems.append("protect_bonus must be at least 1")
	return problems
