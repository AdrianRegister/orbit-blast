class_name Market
extends RefCounted
## The live market of one location: current stock plus pricing, built from the
## static MarketData and the location's imports/exports. This is the only
## place price and stock rules live, so later features (dynamic prices, stock
## regeneration, events) change this class and nothing else.

signal changed

var location: InhabitedData
var data: MarketData

var _stock: Dictionary = {}  # StringName -> int
var _commodities: Array[Commodity] = []


func _init(location_data: InhabitedData, market_data: MarketData) -> void:
	location = location_data
	data = market_data
	for listing in data.listings:
		if listing == null or listing.commodity == null:
			continue
		_commodities.append(listing.commodity)
		_stock[listing.commodity.id] = _starting_stock(listing)


## Commodities this market deals in, in listing order.
func get_commodities() -> Array[Commodity]:
	return _commodities


func has_commodity(commodity: Commodity) -> bool:
	return commodity != null and _stock.has(commodity.id)


func is_export(commodity: Commodity) -> bool:
	return _contains(location.exported_goods, commodity)


func is_import(commodity: Commodity) -> bool:
	return _contains(location.imported_goods, commodity)


func get_stock(commodity: Commodity) -> int:
	return _stock.get(commodity.id, 0)


## Price the player pays per unit.
func get_buy_price(commodity: Commodity) -> int:
	var multiplier: float = 1.0
	if is_export(commodity):
		multiplier = data.export_price_multiplier
	elif is_import(commodity):
		multiplier = data.import_price_multiplier
	return maxi(roundi(commodity.base_price * multiplier), 1)


## Price the market pays the player per unit.
func get_sell_price(commodity: Commodity) -> int:
	return maxi(roundi(get_buy_price(commodity) * data.sell_price_factor), 1)


## Whether the market will take this commodity from the player: only imports.
func accepts(commodity: Commodity) -> bool:
	return has_commodity(commodity) and is_import(commodity)


## Returns false, changing nothing, if the stock would go negative.
func remove_stock(commodity: Commodity, quantity: int) -> bool:
	if quantity <= 0 or quantity > get_stock(commodity):
		return false
	_stock[commodity.id] = get_stock(commodity) - quantity
	changed.emit()
	return true


func add_stock(commodity: Commodity, quantity: int) -> bool:
	if quantity <= 0 or not has_commodity(commodity):
		return false
	_stock[commodity.id] = get_stock(commodity) + quantity
	changed.emit()
	return true


func _starting_stock(listing: MarketListing) -> int:
	var multiplier: float = 1.0
	if _contains(location.exported_goods, listing.commodity):
		multiplier = data.export_stock_multiplier
	elif _contains(location.imported_goods, listing.commodity):
		multiplier = data.import_stock_multiplier
	return maxi(roundi(listing.base_stock * multiplier), 0)


func _contains(goods: Array[Commodity], commodity: Commodity) -> bool:
	for good in goods:
		if good != null and commodity != null and good.id == commodity.id:
			return true
	return false
