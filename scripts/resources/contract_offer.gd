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
## Credits paid on delivery.
@export var reward: int = 1000


## The destination location, loaded on demand. Null if the path is invalid.
func get_destination() -> InhabitedData:
	if destination_path.is_empty() or not ResourceLoader.exists(destination_path):
		return null
	return load(destination_path) as InhabitedData


## Human-readable problems with this offer; `origin` is the listing location.
func validate(origin: InhabitedData = null) -> Array[String]:
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
	return problems
