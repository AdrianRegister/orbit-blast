class_name TradeQuote
extends RefCounted
## The outcome of checking a proposed trade: either it is allowed, with its
## total, or it is refused with a reason for the player. Creating a quote never
## changes any state.

enum Reason {
	NONE,
	INVALID_QUANTITY,
	NOT_SOLD_HERE,
	NOT_ACCEPTED,
	INSUFFICIENT_STOCK,
	INSUFFICIENT_CREDITS,
	INSUFFICIENT_CARGO_SPACE,
	INSUFFICIENT_CARGO,
}

const MESSAGES := {
	Reason.NONE: "",
	Reason.INVALID_QUANTITY: "ENTER A QUANTITY OF AT LEAST 1",
	Reason.NOT_SOLD_HERE: "NOT TRADED AT THIS LOCATION",
	Reason.NOT_ACCEPTED: "THIS MARKET DOES NOT ACCEPT THAT COMMODITY",
	Reason.INSUFFICIENT_STOCK: "INSUFFICIENT MARKET STOCK",
	Reason.INSUFFICIENT_CREDITS: "INSUFFICIENT CREDITS",
	Reason.INSUFFICIENT_CARGO_SPACE: "INSUFFICIENT CARGO SPACE",
	Reason.INSUFFICIENT_CARGO: "YOU DO NOT HAVE THAT MUCH CARGO",
}

var is_buy: bool = true
var commodity: Commodity
var quantity: int = 0
## The price of one unit. For a valid trade this is the average over all the
## units, since each unit is priced after the ones before it moved the stock.
## For a refused trade it is the price of the next single unit.
var unit_price: int = 0
## Credits spent (buy) or earned (sell). For a refused trade it is only an
## estimate (the first unit's price times the quantity) unless the refusal is for
## credits or cargo space, when it is the real cost.
var total: int = 0
var reason: Reason = Reason.NONE


func is_ok() -> bool:
	return reason == Reason.NONE


func get_message() -> String:
	return MESSAGES[reason]
