class_name ExplorationOffer
extends Resource
## An exploration contract a location offers: scout a star system. One .tres per
## offer in resources/contracts/, listed in the issuing location's
## `exploration_offers`. The target is a system id (StarSystem.system_id).

@export var title: String = ""
@export_multiline var description: String = ""
## The star system to scout, by id, e.g. &"wolf_359".
@export var target_system: StringName = &""
## Credits paid. 0 = work it out from the distance with the reward rules.
@export var reward: int = 0
@export var reward_multiplier: float = 1.0


## Human-readable problems with this offer. With a `context` that knows the
## galaxy it checks the target exists, is not the issuer's own system and can be
## reached by jumping.
func validate(origin: InhabitedData = null, context: ContractContext = null) -> Array[String]:
	var problems: Array[String] = []
	if title.is_empty():
		problems.append("title is empty")
	if target_system == &"":
		problems.append("target_system is not set")
	if reward < 0:
		problems.append("reward is negative")
	if reward_multiplier <= 0.0:
		problems.append("reward_multiplier must be above 0")
	if context != null and context.galaxy != null and target_system != &"":
		if not context.galaxy.has_system(target_system):
			problems.append("target system '%s' does not exist" % target_system)
		elif origin != null:
			var from_system := context.system_of(origin)
			if from_system == target_system:
				problems.append("the target is the issuer's own system")
			elif from_system != &"" and context.journey(from_system, target_system) == Vector2i(-1, -1):
				problems.append("there is no jump route to the target")
		if reward == 0 and context.rewards == null:
			problems.append("reward is 0 but there are no reward rules")
	return problems
