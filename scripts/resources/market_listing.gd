class_name MarketListing
extends Resource
## One line of a market: a commodity the location deals in and how much of it
## is normally in stock. Whether the location exports or imports it is not
## stored here; that comes from the location's InhabitedData, so the two
## can never disagree.

@export var commodity: Commodity
## Stock before the location's role is applied (see MarketData multipliers).
@export var base_stock: int = 100
