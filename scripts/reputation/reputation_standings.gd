class_name ReputationStandings
extends Resource
## The reputation scale and what each part of it is called, in one resource
## (resources/reputation/standings.tres) so the range, the starting value, the
## thresholds and the wording can all be changed in one place.

@export var minimum: int = -100
@export var maximum: int = 100
## Where a new player starts with every faction.
@export var start: int = 0
## Ordered from the lowest: each level begins at its lower bound.
@export var levels: Array[ReputationLevel] = []


func clamp_value(value: int) -> int:
	return clampi(value, minimum, maximum)


## The level a reputation value falls in (the one with the highest lower bound
## not above it).
func get_level(value: int) -> ReputationLevel:
	var found: ReputationLevel = null
	for level in levels:
		if value >= level.lower_bound:
			found = level
	return found if found != null else (levels[0] if not levels.is_empty() else null)


func get_standing_name(value: int) -> String:
	var level := get_level(value)
	return level.display_name if level != null else ""


## Human-readable problems with the scale; empty when it is sound.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if minimum >= maximum:
		problems.append("minimum must be below maximum")
	if start < minimum or start > maximum:
		problems.append("start is outside the scale")
	if levels.is_empty():
		problems.append("there are no levels")
		return problems
	if levels[0].lower_bound != minimum:
		problems.append("the first level must begin at the minimum")
	for i in levels.size():
		if levels[i] == null or levels[i].display_name.is_empty():
			problems.append("a level has no name")
		elif i > 0 and levels[i].lower_bound <= levels[i - 1].lower_bound:
			problems.append("levels must be in increasing order")
	return problems
