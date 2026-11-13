class_name AllegianceRules
extends Resource
## The tunable numbers of who counts as an ally in combat. One file:
## resources/combat/allegiance_rules.tres. See Allegiance for how they are used.

const PATH := "res://resources/combat/allegiance_rules.tres"

static var _shared: AllegianceRules


## The project's rules (loaded once).
static func shared() -> AllegianceRules:
	if _shared == null:
		_shared = load(PATH)
	return _shared


## The player counts as an ally of a faction (and the faction's ships as the
## player's allies) while their reputation with it is at least this. 40 is the
## start of "Friendly" on the default scale (resources/reputation/standings.tres).
@export var min_reputation: int = 40


func validate() -> Array[String]:
	var problems: Array[String] = []
	var standings: ReputationStandings = load(ReputationManager.STANDINGS_PATH)
	if standings != null and (min_reputation <= standings.start or min_reputation > standings.maximum):
		problems.append("min_reputation must be above the starting reputation and within the scale")
	return problems
