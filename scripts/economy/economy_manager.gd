class_name EconomyManager
extends Node
## Central trading authority. It owns the live markets and is the only code
## that changes credits, cargo and market stock together. Every trade is first
## checked by a quote (which changes nothing); a trade is applied only if its
## quote is valid, so a transaction either happens completely or not at all.
## The UI only reads quotes, calls buy()/sell() and listens to the signals.

signal credits_changed(credits: int)
signal cargo_changed
signal market_changed(market: Market)
signal transaction_completed(quote: TradeQuote)

var _player: PlayerData
var _clock: GameClock
var _model: EconomyModel
var _infrastructure: InfrastructureManager
var _markets: Dictionary = {}  # InhabitedData -> Market
## Every commodity seen so far, by id, so the manifest (which stores only
## ids) can be shown with proper names.
var _known_commodities: Dictionary = {}  # StringName -> Commodity


## `clock` is the calendar markets follow (without one they stay on day 0) and
## `model` works out what each settlement makes and uses (default: the game's own).
func setup(player: PlayerData, clock: GameClock = null, model: EconomyModel = null) -> void:
	_player = player
	_clock = clock
	_model = model if model != null else EconomyModel.shared()
	_player.cargo.changed.connect(cargo_changed.emit)
	credits_changed.emit(_player.credits)


## Lets damage (see InfrastructureManager) lower what markets produce. A market is
## brought up to date just before its location's damage changes, so the days that
## have passed use the old rate. Call once, before any market is made.
func set_infrastructure(infrastructure: InfrastructureManager) -> void:
	_infrastructure = infrastructure
	_infrastructure.damage_about_to_change.connect(_on_damage_about_to_change)


func _on_damage_about_to_change(location_id: StringName) -> void:
	for location in _markets:
		if location.id == location_id:
			_markets[location].catch_up()


## The share of normal production a location makes on a day (see Market).
func _production_scale(day: int, location_id: StringName) -> float:
	return _infrastructure.production_scale(location_id, day) if _infrastructure != null else 1.0


func get_model() -> EconomyModel:
	return _model


func _today() -> int:
	return _clock.day if _clock != null else 0


func get_credits() -> int:
	return _player.credits


func get_cargo() -> CargoHold:
	return _player.cargo


## The cargo as [display_name, quantity] pairs sorted by name, for display.
func get_cargo_lines() -> Array:
	var lines: Array = []
	var manifest: Dictionary = _player.cargo.get_manifest()
	for id in manifest:
		var commodity: Commodity = _known_commodities.get(id)
		lines.append([commodity.display_name if commodity != null else str(id), manifest[id]])
	var lots: Dictionary = _player.cargo.get_lots()
	for contract_id in lots:
		var commodity: Commodity = _known_commodities.get(lots[contract_id]["commodity"])
		var lot_name: String = commodity.display_name if commodity != null else str(lots[contract_id]["commodity"])
		var note: String = lots[contract_id]["note"]
		lines.append(["%s (%s)" % [lot_name, note if not note.is_empty() else "contract"], lots[contract_id]["quantity"]])
	lines.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return lines


## The persistent market of a location, created on first use. Null if nobody
## lives there (no economy). The same Market is returned on every visit, so
## stock changes persist.
func get_market(location: InhabitedData) -> Market:
	if location == null or not _model.of(location).has_economy():
		return null
	if not _markets.has(location):
		var market := Market.new(location, _model, _today, _production_scale.bind(location.id))
		for commodity in market.get_commodities():
			_known_commodities[commodity.id] = commodity
		market.changed.connect(market_changed.emit.bind(market))
		_markets[location] = market
	return _markets[location]


func quote_buy(market: Market, commodity: Commodity, quantity: int) -> TradeQuote:
	var quote := _new_quote(true, commodity, quantity, market.get_buy_price(commodity))
	if quantity <= 0:
		quote.reason = TradeQuote.Reason.INVALID_QUANTITY
	elif not market.has_commodity(commodity):
		quote.reason = TradeQuote.Reason.NOT_SOLD_HERE
	elif quantity > market.get_stock(commodity):
		quote.reason = TradeQuote.Reason.INSUFFICIENT_STOCK
	else:
		_set_total(quote, market.buy_total(commodity, quantity))
		if quote.total > _player.credits:
			quote.reason = TradeQuote.Reason.INSUFFICIENT_CREDITS
		elif quantity > _player.cargo.get_free():
			quote.reason = TradeQuote.Reason.INSUFFICIENT_CARGO_SPACE
	return quote


func quote_sell(market: Market, commodity: Commodity, quantity: int) -> TradeQuote:
	var quote := _new_quote(false, commodity, quantity, market.get_sell_price(commodity))
	if quantity <= 0:
		quote.reason = TradeQuote.Reason.INVALID_QUANTITY
	elif not market.accepts(commodity):
		quote.reason = TradeQuote.Reason.NOT_ACCEPTED
	elif quantity > _player.cargo.get_quantity(commodity.id):
		quote.reason = TradeQuote.Reason.INSUFFICIENT_CARGO
	else:
		_set_total(quote, market.sell_total(commodity, quantity))
	return quote


## Buys if allowed. Returns the quote so the caller can show why it failed.
func buy(market: Market, commodity: Commodity, quantity: int) -> TradeQuote:
	var quote := quote_buy(market, commodity, quantity)
	if not quote.is_ok():
		return quote
	# Every precondition was just verified, so none of these can fail.
	_known_commodities[commodity.id] = commodity
	_player.credits -= quote.total
	_player.cargo.add(commodity.id, quantity)
	market.remove_stock(commodity, quantity)
	credits_changed.emit(_player.credits)
	transaction_completed.emit(quote)
	return quote


## Sells if allowed. Returns the quote so the caller can show why it failed.
func sell(market: Market, commodity: Commodity, quantity: int) -> TradeQuote:
	var quote := quote_sell(market, commodity, quantity)
	if not quote.is_ok():
		return quote
	_player.credits += quote.total
	_player.cargo.remove(commodity.id, quantity)
	market.add_stock(commodity, quantity)
	credits_changed.emit(_player.credits)
	transaction_completed.emit(quote)
	return quote


## Loads cargo supplied by a contract issuer into the hold as a contract lot.
## `note` is shown after the name in cargo lists, e.g. "contract, Earth in the
## Sol system". Used by the ContractManager. False (nothing changed) if it does
## not fit.
func load_contract_cargo(contract_id: StringName, commodity: Commodity, quantity: int,
		note: String = "") -> bool:
	if not _player.cargo.add_lot(contract_id, commodity.id, quantity, note):
		return false
	_known_commodities[commodity.id] = commodity
	return true


## Removes a contract's lot from the hold (delivered). True if there was one.
func unload_contract_cargo(contract_id: StringName) -> bool:
	return _player.cargo.remove_lot(contract_id)


## Empties the hold: the ship that carried the cargo was destroyed. Contracts
## whose cargo this was must be failed too (ContractManager.fail_lost_cargo_contracts).
func clear_cargo() -> void:
	_player.cargo.clear()


## Pays credits that are not a trade, such as a contract reward.
func award_credits(amount: int) -> void:
	if amount <= 0:
		return
	_player.credits += amount
	credits_changed.emit(_player.credits)


## Takes `amount` credits for something that is not a trade (a ship, an
## upgrade). Checked first: False and nothing changed if the player cannot afford it.
func try_spend(amount: int) -> bool:
	if amount < 0 or amount > _player.credits:
		return false
	if amount > 0:
		_player.credits -= amount
		credits_changed.emit(_player.credits)
	return true


## Sets the hold size, which comes from the active ship. The ShipManager checks
## that the cargo fits before calling this.
func set_cargo_capacity(capacity: int) -> void:
	_player.cargo.capacity = capacity


## Sets the total of a trade whose units are priced one by one; the unit price
## becomes the average.
func _set_total(quote: TradeQuote, total: int) -> void:
	quote.total = total
	quote.unit_price = roundi(float(total) / quote.quantity)


func _new_quote(is_buy: bool, commodity: Commodity, quantity: int, unit_price: int) -> TradeQuote:
	var quote := TradeQuote.new()
	quote.is_buy = is_buy
	quote.commodity = commodity
	quote.quantity = quantity
	quote.unit_price = unit_price
	quote.total = unit_price * maxi(quantity, 0)
	return quote


## Plain data for the save file: credits, cargo and every market that has been
## visited (markets never visited are still at their starting values).
func save_state() -> Dictionary:
	var markets := {}
	for location in _markets:
		markets[str(location.id)] = _markets[location].save_state()
	return {"credits": _player.credits, "cargo": _player.cargo.save_state(), "markets": markets}


## Problems with saved economy data; empty when load_state() can use it.
func validate_state(data: Variant, registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary:
		return ["economy is not an object"]
	if not SaveData.is_int(data.get("credits")) or data["credits"] < 0:
		problems.append("credits is not a non-negative whole number")
	problems.append_array(_player.cargo.validate_state(data.get("cargo"), registry))
	var markets = data.get("markets")
	if not markets is Dictionary:
		problems.append("markets is not an object")
		return problems
	for id in markets:
		var location := registry.location(StringName(id))
		if location == null or not _model.of(location).has_economy():
			problems.append("'%s' is not a location with a market" % id)
			continue
		problems.append_array(Market.validate_state(markets[id], registry))
	return problems


## Replaces credits, cargo and market state with validated saved data. Markets
## not in the data start fresh again.
func load_state(data: Dictionary, registry: ContentRegistry) -> void:
	_player.credits = int(data["credits"])
	_markets.clear()
	_player.cargo.load_state(data["cargo"], registry)
	for id in data["cargo"]["manifest"]:
		_known_commodities[StringName(id)] = registry.commodity(StringName(id))
	for contract_id in data["cargo"]["lots"]:
		var commodity_id := StringName(data["cargo"]["lots"][contract_id]["commodity"])
		_known_commodities[commodity_id] = registry.commodity(commodity_id)
	for id in data["markets"]:
		get_market(registry.location(StringName(id))).load_state(data["markets"][id])
	credits_changed.emit(_player.credits)
