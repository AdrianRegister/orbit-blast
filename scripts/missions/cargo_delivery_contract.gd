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
