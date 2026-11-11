class_name ContractOffer
extends Resource
## A cargo delivery contract a location offers. One .tres per offer in
## resources/contracts/, listed in the issuing location's `contract_offers`.
## The origin is the location that lists it. The ContractManager turns an offer
## into a runtime CargoDeliveryContract the first time the location is visited.

@export var title: String = ""
@export_multiline var description: String = ""
## Where the cargo must be delivered: the destination's location file (for
## example res://resources/locations/mars.tres). A path rather than a direct
## reference, because locations offer contracts to each other and Godot cannot
## load resources that reference each other in a loop.
@export_file("*.tres") var destination_path: String = ""
## The cargo, supplied by the issuer when the contract is accepted.
@export var commodity: Commodity
@export var quantity: int = 10
## Credits paid on delivery. 0 = work it out from the cargo and the distance
## with the reward rules (ContractRewards).
@export var reward: int = 1000
## Scales a calculated reward (more or less than the standard rate).
@export var reward_multiplier: float = 1.0


## The destination location, loaded on demand. Null if the path is invalid.
func get_destination() -> InhabitedData:
	if destination_path.is_empty() or not ResourceLoader.exists(destination_path):
		return null
	return load(destination_path) as InhabitedData


## Human-readable problems with this offer; `origin` is the listing location.
## With a `context` that knows the galaxy it also checks that the destination
## can be reached by jumping and that the cargo fits in some ship.
func validate(origin: InhabitedData = null, context: ContractContext = null) -> Array[String]:
	var problems: Array[String] = []
	if title.is_empty():
		problems.append("title is empty")
	var destination := get_destination()
	if destination == null:
		problems.append("destination_path is not set or not a location")
	elif destination == origin:
		problems.append("destination is the issuing location")
	if commodity == null:
		problems.append("commodity is not set")
	if quantity <= 0:
		problems.append("quantity must be above 0")
	if reward < 0:
		problems.append("reward is negative")
	if reward_multiplier <= 0.0:
		problems.append("reward_multiplier must be above 0")
	if context != null and context.galaxy != null and destination != null and origin != null:
		var from_system := context.system_of(origin)
		var to_system := context.system_of(destination)
		if to_system == &"":
			problems.append("the destination is not in any star system")
		elif from_system != &"" and context.journey(from_system, to_system) == Vector2i(-1, -1):
			problems.append("there is no jump route to the destination")
		if context.max_cargo > 0 and quantity > context.max_cargo:
			problems.append("quantity %d is more than any ship can carry (%d)" % [quantity, context.max_cargo])
		if reward == 0 and context.rewards == null:
			problems.append("reward is 0 but there are no reward rules")
	return problems
