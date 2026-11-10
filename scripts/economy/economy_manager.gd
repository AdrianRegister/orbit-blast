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
var _markets: Dictionary = {}  # InhabitedData -> Market
## Every commodity seen so far, by id, so the manifest (which stores only
## ids) can be shown with proper names.
var _known_commodities: Dictionary = {}  # StringName -> Commodity


func setup(player: PlayerData) -> void:
	_player = player
	_player.cargo.changed.connect(cargo_changed.emit)
	credits_changed.emit(_player.credits)


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
	lines.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return lines


## The persistent market of a location, created on first use. Null if the
## location has no market configured. The same Market is returned on every
## visit, so stock changes persist.
func get_market(location: InhabitedData) -> Market:
	if location == null or location.market == null:
		return null
	if not _markets.has(location):
		var market := Market.new(location, location.market)
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
	elif quote.total > _player.credits:
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


func _new_quote(is_buy: bool, commodity: Commodity, quantity: int, unit_price: int) -> TradeQuote:
	var quote := TradeQuote.new()
	quote.is_buy = is_buy
	quote.commodity = commodity
	quote.quantity = quantity
	quote.unit_price = unit_price
	quote.total = unit_price * maxi(quantity, 0)
	return quote
