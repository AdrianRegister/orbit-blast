class_name CargoDeliveryContract
extends Contract
## Carry a quantity of a commodity, supplied by the issuer, from the origin to
## the destination. While accepted, the cargo sits in the player's CargoHold as
## a contract lot (see CargoHold), separate from ordinary trading cargo.

var commodity: Commodity
var quantity: int = 0
## How much of the contract cargo is in the hold; set by the ContractManager.
var quantity_in_hold: int = 0


func get_requirement_text() -> String:
	return "%s %s" % [NumberFormat.with_commas(quantity), commodity.display_name]


func get_progress_text() -> String:
	match status:
		Status.AVAILABLE:
			return "Pick up at %s" % origin.display_name
		Status.ACCEPTED:
			return "In hold: %d / %d. Deliver to %s" % [quantity_in_hold, quantity, destination.display_name]
		Status.COMPLETED:
			return "Delivered to %s" % destination.display_name
	return ""


func get_type_id() -> StringName:
	return &"cargo_delivery"


func to_dict() -> Dictionary:
	var data := super()
	data["commodity"] = str(commodity.id)
	data["quantity"] = quantity
	data["quantity_in_hold"] = quantity_in_hold
	return data


func validate_dict(data: Dictionary, registry: ContentRegistry) -> Array[String]:
	var problems := super(data, registry)
	if not SaveData.is_id(data.get("commodity")) or registry.commodity(StringName(data["commodity"])) == null:
		problems.append("contract commodity is not a known commodity")
	if not SaveData.is_int(data.get("quantity")) or data["quantity"] <= 0:
		problems.append("contract quantity is not a positive whole number")
	elif not SaveData.is_int(data.get("quantity_in_hold")) \
			or data["quantity_in_hold"] < 0 or data["quantity_in_hold"] > data["quantity"]:
		problems.append("contract quantity_in_hold is out of range")
	return problems


func load_dict(data: Dictionary, registry: ContentRegistry) -> void:
	super(data, registry)
	commodity = registry.commodity(StringName(data["commodity"]))
	quantity = int(data["quantity"])
	quantity_in_hold = int(data["quantity_in_hold"])
