class_name EconomyProfile
extends Resource
## A kind of economy (agricultural, industrial, mining, ...): which goods a
## settlement of this kind makes and which its industry consumes. Shared by every
## settlement that uses it; the settlement's population decides how much (see
## EconomyModel). One .tres per profile in resources/economy/profiles/.
##
## A planet type names its default profile (PlanetType.economy_profile); a single
## location can override it (InhabitedData.economy_profile).

## Permanent id, e.g. &"industrial".
@export var id: StringName = &""
@export var display_name: String = ""
@export var goods: Array[EconomyProfileGood] = []
## What a settlement of this kind adds to its system's military value (see
## MilitaryValueRules): a resort counts for little, a garrison or arsenal for a lot.
## Scaled by the settlement's size.
@export var military_value: float = 0.0
## How many times larger than its real population the population shown to the player
## is for settlements with this profile (0 = use the system class's scale; see
## PopulationDisplayRules). Garrisons and arsenals use it.
@export var population_display_scale: float = 0.0


## Human-readable problems with this profile; empty when it is valid.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if military_value < 0.0:
		problems.append("profile '%s' has a negative military_value" % id)
	if population_display_scale < 0.0:
		problems.append("profile '%s' has a negative population_display_scale" % id)
	var seen := {}
	for line in goods:
		if line == null or line.commodity == null:
			problems.append("profile '%s' has an empty line" % id)
			continue
		if seen.has(line.commodity.id):
			problems.append("profile '%s' lists '%s' twice" % [id, line.commodity.id])
		seen[line.commodity.id] = true
		if line.production < 0.0 or line.industrial_demand < 0.0:
			problems.append("profile '%s' has a negative rate for '%s'" % [id, line.commodity.id])
	return problems
