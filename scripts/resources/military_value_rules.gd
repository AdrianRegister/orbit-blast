class_name MilitaryValueRules
extends Resource
## The numbers that turn locations into military value, and systems into an
## importance score (resources/military/military_value_rules.tres). A war needs to
## know how much a place is worth taking or defending; this says how that is
## worked out. Nothing here changes while playing, and nothing fights anything.
##
## The value of one inhabited location is
##   profile.military_value * size_factor
##     + shipyard_value (if it has a shipyard) + outfitter_value (if it has an outfitter)
##     + location.military_value_bonus
## where the profile is its economy profile (EconomyProfile.military_value: what
## kind of settlement it is) and size_factor grows with its population.
## A system's value is the sum of its locations' values times its class's
## military_value_multiplier (SystemClass).

## Added for a location with a shipyard / an outfitter (the big warship and refit
## facilities of a place).
@export var shipyard_value: float = 30.0
@export var outfitter_value: float = 20.0

@export_group("Size")
## size_factor = clamp((population / reference population) ^ size_exponent,
## size_min, size_max). A big world is worth more than a small one, with a limit
## either way, so a tiny outpost still counts and an enormous one does not swamp
## everything.
@export var size_exponent: float = 0.5
@export var size_min: float = 0.25
@export var size_max: float = 3.0

@export_group("Damage")
## How much damage lowers current military value: current = value *
## (1 - damage_weight * damage). 0 = damage does not touch military value; 1 = a
## devastated location is worth nothing. Damage never lowers the structural value.
@export_range(0.0, 1.0) var damage_weight: float = 0.5

@export_group("Importance")
## A system's importance is a score that sums its worth to a faction: military
## value, what it makes, the people in it, and how many jump links pass through it.
## Used to decide which systems are centres of power. Each term is multiplied by:
## military value (per point), production value (per credit of goods made each
## day), population (per million people) and connectivity (per jump link).
@export var weight_military: float = 1.0
@export var weight_production: float = 0.01
@export var weight_population: float = 2.0
@export var weight_connectivity: float = 3.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if shipyard_value < 0.0 or outfitter_value < 0.0:
		problems.append("shipyard_value and outfitter_value must not be negative")
	if size_exponent <= 0.0 or size_min <= 0.0 or size_max < size_min:
		problems.append("size settings are out of range")
	if weight_military < 0.0 or weight_production < 0.0 or weight_population < 0.0 or weight_connectivity < 0.0:
		problems.append("importance weights must not be negative")
	return problems
