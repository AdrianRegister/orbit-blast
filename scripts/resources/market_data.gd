class_name MarketData
extends Resource
## Static configuration of one location's market. Assign it to
## InhabitedData.market. The location's exports and imports decide how each
## listing is priced and stocked:
##   export  -> plentiful and cheap       (player may buy, market won't take it)
##   import  -> scarce and expensive      (player may buy and sell)
##   neither -> base price and base stock (player may buy only)
## The multipliers live here so each market can be tuned independently.

@export var listings: Array[MarketListing] = []

@export_group("Pricing")
@export var export_price_multiplier: float = 0.75
@export var import_price_multiplier: float = 1.3
## The market pays the player this fraction of its own price when buying.
@export_range(0.0, 1.0) var sell_price_factor: float = 0.9

@export_group("Stock")
@export var export_stock_multiplier: float = 1.5
@export var import_stock_multiplier: float = 0.4


## Human-readable problems with this data; empty when it is valid.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for listing in listings:
		if listing == null or listing.commodity == null:
			problems.append("a market listing has no commodity")
			continue
		if seen.has(listing.commodity.id):
			problems.append("commodity '%s' is listed twice" % listing.commodity.id)
		seen[listing.commodity.id] = true
	return problems
