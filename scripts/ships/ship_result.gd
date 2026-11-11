class_name ShipResult
extends RefCounted
## The outcome (or quote) of a ship operation. `ok` is false with a `message`
## saying why when the operation is not allowed; nothing has changed then.

var ok: bool = false
var message: String = ""
## What it costs (or would cost) in credits, after any trade-in.
var cost: int = 0
## For a purchase: the trade-in value taken off the price (0 if none).
var trade_in_value: int = 0
## For a purchase: the new ship, once bought.
var ship: OwnedShip


static func refused(why: String) -> ShipResult:
	var result := ShipResult.new()
	result.message = why
	return result
