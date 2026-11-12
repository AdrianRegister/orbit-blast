class_name Market
extends RefCounted
## The live market of one location: its stock of each good, and the prices that
## follow from it. What the location makes and uses each day comes from the
## EconomyModel (population, planet type, profile); this class turns that into
## stock over time and into prices. It is the only place the stock and price
## rules live.
##
## Stock changes in whole days. Nothing runs on a timer: the market remembers the
## last day it was brought up to date, and every read first catches up to the
## calendar's day by running the daily rule once per missing day. A market the
## player never visits costs nothing. The rule has no randomness, so the result
## does not depend on when or how often the market was read.
##
## Each day, for each good (rates are units per day):
##   made     = production * (1 - stock / capacity)       slows to nothing when full
##   used     = consumption * min(1, stock / reserve)     goes short when stock is low
##   freight  = (consumption - production) * ambient_share * (1 - stock / normal)
##              background supply, only while the market is short of its normal stock
##   stock   += made + freight - used
##
## Price follows how full the warehouse is compared with normal:
##   ratio  = stock / normal
##   factor = clamp(ratio ^ -exponent, min, max)
##   price  = base_price * factor        (the market charges +spread/2, pays -spread/2)
## Buying or selling moves the stock, so a large order is priced unit by unit and
## the average price is worse than the first unit's.

signal changed

## How well supplied a good is, for display (see EconomyConfig, "Supply labels").
enum Supply { SCARCE, LOW, NORMAL, PLENTIFUL, GLUT }

const SUPPLY_NAMES := ["SCARCE", "LOW", "NORMAL", "PLENTIFUL", "GLUT"]

var location: InhabitedData

var _model: EconomyModel
var _config: EconomyConfig
var _day_source: Callable
var _production_scale: Callable
var _economy: LocationEconomy
var _goods: Array[Commodity] = []
var _stock: Dictionary = {}  # StringName -> float
var _last_day: int = 0


## `day_source` is a Callable returning the current calendar day (an int). Without
## one the market lives on day 0 for ever. `production_scale` is a Callable taking a
## day and returning what share of its normal production the location makes that
## day (1.0 undamaged, see InfrastructureManager); without one production is never
## reduced.
func _init(location_data: InhabitedData, model: EconomyModel, day_source: Callable = Callable(),
		production_scale: Callable = Callable()) -> void:
	location = location_data
	_model = model
	_config = model.config
	_day_source = day_source
	_production_scale = production_scale
	_load_economy()
	for _i in _config.warmup_days:
		_step_day(_today())
	_last_day = _today()


## Brings the stock up to the calendar's day now. Reading does this anyway; call it
## before changing something that alters the daily rates (damage), so the days up to
## now are worked out with the old rates.
func catch_up() -> void:
	_sync()


# ------------------------------------------------------------------ reading

## Commodities this market deals in (makes or uses), sorted by id.
func get_commodities() -> Array[Commodity]:
	_sync()
	return _goods


func has_commodity(commodity: Commodity) -> bool:
	if commodity == null:
		return false
	return _economy.production.has(commodity.id) or _economy.consumption.has(commodity.id)


func is_export(commodity: Commodity) -> bool:
	return _economy.is_export(commodity)


func is_import(commodity: Commodity) -> bool:
	return _economy.is_import(commodity)


## Whole units in stock.
func get_stock(commodity: Commodity) -> int:
	_sync()
	return floori(_stock.get(commodity.id, 0.0))


## Stock compared with the normal level: 1.0 is normal, below 1 is short, above 1
## is plentiful.
func get_supply_ratio(commodity: Commodity) -> float:
	_sync()
	return _stock.get(commodity.id, 0.0) / _normal_stock(commodity)


## How well supplied the good is, from the stock compared with normal.
func get_supply_level(commodity: Commodity) -> Supply:
	var ratio := get_supply_ratio(commodity)
	if ratio < _config.scarce_below:
		return Supply.SCARCE
	if ratio < _config.low_below:
		return Supply.LOW
	if ratio <= _config.plentiful_above:
		return Supply.NORMAL
	if ratio <= _config.glut_above:
		return Supply.PLENTIFUL
	return Supply.GLUT


## What the stock level does to the price: 1.0 is the base price.
func get_price_factor(commodity: Commodity) -> float:
	_sync()
	return _factor_at(commodity, _stock.get(commodity.id, 0.0))


## Units made and used per day (before the stock limits slow them down).
func get_production(commodity: Commodity) -> float:
	return _economy.production_of(commodity)


func get_consumption(commodity: Commodity) -> float:
	return _economy.consumption_of(commodity)


# ------------------------------------------------------------------- prices

## Price the player pays for the next unit.
func get_buy_price(commodity: Commodity) -> int:
	_sync()
	return maxi(roundi(_ask_at(commodity, _stock.get(commodity.id, 0.0))), 1)


## Price the market pays the player for the next unit.
func get_sell_price(commodity: Commodity) -> int:
	_sync()
	return maxi(roundi(_bid_at(commodity, _stock.get(commodity.id, 0.0))), 1)


## Total the player pays for `quantity` units, each priced at the stock left after
## the one before. Meant for quantities up to the stock on hand.
func buy_total(commodity: Commodity, quantity: int) -> int:
	_sync()
	var stock: float = _stock.get(commodity.id, 0.0)
	var total := 0.0
	for _i in maxi(quantity, 0):
		total += _ask_at(commodity, stock)
		stock = maxf(stock - 1.0, 0.0)
	return maxi(roundi(total), maxi(quantity, 0))


## Total the market pays for `quantity` units, each priced at the stock the ones
## before have raised it to.
func sell_total(commodity: Commodity, quantity: int) -> int:
	_sync()
	var stock: float = _stock.get(commodity.id, 0.0)
	var total := 0.0
	for _i in maxi(quantity, 0):
		total += _bid_at(commodity, stock)
		stock += 1.0
	return maxi(roundi(total), maxi(quantity, 0))


## The most units that can be bought with `credits`, up to `limit` and the stock.
func max_buyable(commodity: Commodity, credits: int, limit: int) -> int:
	_sync()
	var stock: float = _stock.get(commodity.id, 0.0)
	var spent := 0.0
	var count := 0
	while count < limit and count < floori(stock):
		var price := _ask_at(commodity, stock)
		if roundi(spent + price) > credits:
			break
		spent += price
		stock = maxf(stock - 1.0, 0.0)
		count += 1
	return count


## Whether the market will take this commodity from the player: any good it deals
## in. (A glut simply makes the price poor.)
func accepts(commodity: Commodity) -> bool:
	return has_commodity(commodity)


# ------------------------------------------------------------------ changing

## Returns false, changing nothing, if there are not that many units.
func remove_stock(commodity: Commodity, quantity: int) -> bool:
	_sync()
	if quantity <= 0 or quantity > get_stock(commodity):
		return false
	_stock[commodity.id] = _stock[commodity.id] - quantity
	changed.emit()
	return true


func add_stock(commodity: Commodity, quantity: int) -> bool:
	_sync()
	if quantity <= 0 or not has_commodity(commodity):
		return false
	_stock[commodity.id] = _stock.get(commodity.id, 0.0) + quantity
	changed.emit()
	return true


# ---------------------------------------------------------------- simulation

func _today() -> int:
	return int(_day_source.call()) if _day_source.is_valid() else 0


func _load_economy() -> void:
	_economy = _model.of(location)
	_goods = _economy.goods()
	for good in _goods:
		if not _stock.has(good.id):
			_stock[good.id] = 0.0


## Brings the stock up to the calendar's day.
func _sync() -> void:
	var today := _today()
	if today <= _last_day:
		_last_day = mini(_last_day, today)
		return
	_load_economy()
	var days := mini(today - _last_day, _config.max_sync_days)
	var first := today - days + 1
	for i in days:
		_step_day(first + i)
	_last_day = today


## The share of normal production the location makes on `day`.
func _scale_on(day: int) -> float:
	return float(_production_scale.call(day)) if _production_scale.is_valid() else 1.0


## One day of the rule. `day` is the calendar day it is, which decides the damage.
func _step_day(day: int) -> void:
	var scale := _scale_on(day)
	for good in _goods:
		var made := _economy.production_of(good) * scale
		var used := _economy.consumption_of(good)
		var stock: float = _stock[good.id]
		var produced := made * clampf(1.0 - stock / _capacity(good), 0.0, 1.0)
		var consumed := used
		if used > 0.0:
			consumed = used * minf(1.0, stock / (used * _config.reserve_days))
		var short_of_normal := clampf(1.0 - stock / _normal_stock(good), 0.0, 1.0)
		var freight := maxf(used - made, 0.0) * _config.ambient_share * short_of_normal
		_stock[good.id] = maxf(stock + produced + freight - consumed, 0.0)


## Units per day the market is sized for: its throughput, but never less than a
## small floor so tiny markets still hold something.
func _flow(commodity: Commodity) -> float:
	return maxf(maxf(_economy.production_of(commodity), _economy.consumption_of(commodity)), _config.min_flow)


func _capacity(commodity: Commodity) -> float:
	return _flow(commodity) * _config.cover_days


func _normal_stock(commodity: Commodity) -> float:
	return _flow(commodity) * _config.target_cover_days


func _factor_at(commodity: Commodity, stock: float) -> float:
	var ratio := maxf(stock / _normal_stock(commodity), _config.min_supply_ratio)
	return clampf(pow(ratio, -_config.price_exponent), _config.min_price_factor, _config.max_price_factor)


func _ask_at(commodity: Commodity, stock: float) -> float:
	return commodity.base_price * _factor_at(commodity, stock) * (1.0 + _config.spread / 2.0)


func _bid_at(commodity: Commodity, stock: float) -> float:
	return commodity.base_price * _factor_at(commodity, stock) * (1.0 - _config.spread / 2.0)


# -------------------------------------------------------------------- saving

## Plain data for the save file: the stock and the day it was last brought up to
## date. Prices are not saved: they are worked out from the stock.
func save_state() -> Dictionary:
	_sync()
	var stock := {}
	for id in _stock:
		stock[str(id)] = snappedf(_stock[id], 0.001)
	return {"stock": stock, "day": _last_day}


## Problems with saved market data; empty when load_state() can use it. Needs no
## Market: it checks only the shape and that the commodities exist.
static func validate_state(data: Variant, registry: ContentRegistry) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary:
		return ["market is not an object"]
	var stock = data.get("stock")
	if not stock is Dictionary:
		problems.append("market stock is not an object")
	else:
		for id in stock:
			if registry.commodity(StringName(id)) == null:
				problems.append("market stock refers to unknown commodity '%s'" % id)
			if not SaveData.is_number(stock[id]) or stock[id] < 0:
				problems.append("market stock of '%s' is not a non-negative number" % id)
	if data.has("day") and (not SaveData.is_int(data["day"]) or data["day"] < 0):
		problems.append("market day is not a non-negative whole number")
	return problems


## Applies validated saved data to a fresh market. Goods the market no longer
## deals in are ignored, and goods the data does not mention keep their starting
## stock. Saves from before stock was timed have no day: the market then starts
## from today.
func load_state(data: Dictionary) -> void:
	for id in data["stock"]:
		if _stock.has(StringName(id)):
			_stock[StringName(id)] = float(data["stock"][id])
	_last_day = mini(int(data["day"]), _today()) if data.has("day") else _today()
	changed.emit()
