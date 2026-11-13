class_name HostilityRules
extends Resource
## The tunable numbers of who attacks whom on sight. One file:
## resources/combat/hostility_rules.tres. See Hostility for how they are used.

const PATH := "res://resources/combat/hostility_rules.tres"

static var _shared: HostilityRules


## The project's rules (loaded once).
static func shared() -> HostilityRules:
	if _shared == null:
		_shared = load(PATH)
	return _shared


## A faction's ships attack the player on sight while the player's reputation with
## that faction is at or below this. -80 is the start of "Hostile" on the default
## scale (resources/reputation/standings.tres).
@export var attack_player_reputation: int = -80
## After one side attacks another, the victim's side stays hostile to the attacker's
## for this long (seconds of game time), renewed by every further attack.
@export var grudge_seconds: float = 90.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	var standings: ReputationStandings = load(ReputationManager.STANDINGS_PATH)
	if standings != null and (attack_player_reputation >= standings.start or attack_player_reputation < standings.minimum):
		problems.append("attack_player_reputation must be below the starting reputation and within the scale")
	if grudge_seconds <= 0.0:
		problems.append("grudge_seconds must be above zero")
	return problems
