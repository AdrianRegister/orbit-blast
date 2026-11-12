class_name TradingScreen
extends CanvasLayer
## Full-screen trading floor, shown over the settlement screen while docked.
## It only displays the market and asks the EconomyManager to quote and
## execute trades; it holds no money, cargo or stock of its own. It refreshes
## itself from the economy's signals.

const NOT_AVAILABLE := "--"
const ERROR_COLOR := Color(1.0, 0.45, 0.4)

enum Column { COMMODITY, STOCK, SUPPLY, BUY, SELL, VS_BASE, OWNED }

## Colour of the supply wording, by Market.Supply. Normal uses the default text colour.
const SUPPLY_COLORS := {
	Market.Supply.SCARCE: Color(1.0, 0.45, 0.4),
	Market.Supply.LOW: Color(1.0, 0.75, 0.35),
	Market.Supply.PLENTIFUL: Color(0.55, 0.9, 0.55),
	Market.Supply.GLUT: Color(0.45, 0.85, 1.0),
}
const CHEAP_COLOR := Color(0.55, 0.9, 0.55)
const DEAR_COLOR := Color(1.0, 0.75, 0.35)
## The price must be at least this far (as a fraction) from the base price to be coloured.
const PRICE_NOTICE := 0.05

var _economy: EconomyManager
var _market: Market
var _selected: Commodity
var _items: Dictionary = {}  # StringName -> TreeItem

@onready var _location_label: Label = %LocationLabel
@onready var _back_button: Button = %BackButton
@onready var _credits_row: InfoRow = %CreditsRow
@onready var _cargo_list: CargoList = %CargoList
@onready var _table: Tree = %Table
@onready var _selected_label: Label = %SelectedLabel
@onready var _quantity: SpinBox = %QuantityBox
@onready var _max_buy_button: Button = %MaxBuyButton
@onready var _max_sell_button: Button = %MaxSellButton
@onready var _buy_button: Button = %BuyButton
@onready var _buy_label: Label = %BuyLabel
@onready var _sell_button: Button = %SellButton
@onready var _sell_label: Label = %SellLabel
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_table.columns = Column.size()
	var titles := ["COMMODITY", "IN STOCK", "SUPPLY", "BUY PRICE", "SELL PRICE", "VS BASE PRICE", "YOU OWN"]
	for column in Column.size():
		_table.set_column_title(column, titles[column])
		_table.set_column_expand(column, column == Column.COMMODITY)
		_table.set_column_custom_minimum_width(column, 110 if column != Column.COMMODITY else 200)
		if column != Column.COMMODITY:
			_table.set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_RIGHT)
	_table.item_selected.connect(_on_item_selected)
	_back_button.pressed.connect(close)
	_quantity.value_changed.connect(func(_value: float) -> void: _update_trade_panel())
	_max_buy_button.pressed.connect(_on_max_buy)
	_max_sell_button.pressed.connect(_on_max_sell)
	_buy_button.pressed.connect(_on_buy)
	_sell_button.pressed.connect(_on_sell)


## Gives the screen the economy it trades through. Called once by Main.
func setup(economy: EconomyManager) -> void:
	_economy = economy
	_economy.credits_changed.connect(func(_credits: int) -> void: _refresh())
	_economy.cargo_changed.connect(_refresh)
	_economy.market_changed.connect(func(_market_changed: Market) -> void: _refresh())


## Opens the market of the docked target. Does nothing if it has none.
func open(target: Targetable) -> void:
	var location := target.details as InhabitedData
	_market = _economy.get_market(location)
	if _market == null:
		return
	_location_label.text = target.target_name
	_status_label.text = ""
	_build_table()
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_market = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_table() -> void:
	_table.clear()
	_items.clear()
	_selected = null
	var root := _table.create_item()
	for commodity in _market.get_commodities():
		var item := _table.create_item(root)
		item.set_text(Column.COMMODITY, commodity.display_name)
		item.set_tooltip_text(Column.COMMODITY, commodity.description)
		item.set_metadata(Column.COMMODITY, commodity)
		item.set_tooltip_text(Column.SUPPLY, "How much is in stock compared with what this place normally holds. Scarce goods are dear, plentiful goods cheap.")
		item.set_tooltip_text(Column.VS_BASE, "How far today's price is from the commodity's base price. Green is cheap to buy here, orange is dear.")
		for column in [Column.STOCK, Column.SUPPLY, Column.BUY, Column.SELL, Column.VS_BASE, Column.OWNED]:
			item.set_text_alignment(column, HORIZONTAL_ALIGNMENT_RIGHT)
		_items[commodity.id] = item
	var first := root.get_first_child()
	if first != null:
		first.select(Column.COMMODITY)
		_selected = first.get_metadata(Column.COMMODITY)


func _on_item_selected() -> void:
	var item := _table.get_selected()
	_selected = item.get_metadata(Column.COMMODITY) if item != null else null
	_status_label.text = ""
	_update_trade_panel()


## Re-reads everything shown from the economy.
func _refresh() -> void:
	if not visible or _market == null:
		return
	_credits_row.set_value("%s CR" % NumberFormat.with_commas(_economy.get_credits()))
	var cargo := _economy.get_cargo()
	_cargo_list.set_cargo(cargo.get_used(), cargo.capacity, _economy.get_cargo_lines())
	for commodity in _market.get_commodities():
		var item: TreeItem = _items[commodity.id]
		item.set_text(Column.STOCK, NumberFormat.with_commas(_market.get_stock(commodity)))
		var supply := _market.get_supply_level(commodity)
		item.set_text(Column.SUPPLY, Market.SUPPLY_NAMES[supply])
		_set_color(item, Column.SUPPLY, SUPPLY_COLORS.get(supply))
		var percent := roundi((_market.get_price_factor(commodity) - 1.0) * 100.0)
		item.set_text(Column.VS_BASE, "%s%d%%" % ["+" if percent > 0 else "", percent])
		_set_color(item, Column.VS_BASE, _price_color(percent / 100.0))
		item.set_text(Column.BUY, NumberFormat.with_commas(_market.get_buy_price(commodity)))
		item.set_text(Column.SELL, NumberFormat.with_commas(_market.get_sell_price(commodity))
				if _market.accepts(commodity) else NOT_AVAILABLE)
		item.set_text(Column.OWNED, NumberFormat.with_commas(cargo.get_quantity(commodity.id)))
	_update_trade_panel()


## Sets a cell's text colour, or puts it back to the default when `color` is null.
func _set_color(item: TreeItem, column: int, color: Variant) -> void:
	if color == null:
		item.clear_custom_color(column)
	else:
		item.set_custom_color(column, color)


## Green for a price well below the base price (good to buy), orange for well above.
func _price_color(offset: float) -> Variant:
	if offset <= -PRICE_NOTICE:
		return CHEAP_COLOR
	if offset >= PRICE_NOTICE:
		return DEAR_COLOR
	return null


## Shows the cost or revenue of the entered quantity, or why it is not allowed.
func _update_trade_panel() -> void:
	if _market == null or _selected == null:
		_selected_label.text = ""
		_set_row(_buy_button, _buy_label, null, "COST")
		_set_row(_sell_button, _sell_label, null, "REVENUE")
		return
	_selected_label.text = "%s     SUPPLY: %s" % [_selected.display_name.to_upper(), Market.SUPPLY_NAMES[_market.get_supply_level(_selected)]]
	var quantity := _entered_quantity()
	_set_row(_buy_button, _buy_label, _economy.quote_buy(_market, _selected, quantity), "COST", _market.get_buy_price(_selected))
	_set_row(_sell_button, _sell_label, _economy.quote_sell(_market, _selected, quantity), "REVENUE", _market.get_sell_price(_selected))


## `first_price` is what the next single unit would cost or pay; a larger order
## is priced unit by unit, so its average differs, and the difference is shown.
func _set_row(button: Button, label: Label, quote: TradeQuote, total_caption: String, first_price: int = 0) -> void:
	if quote == null:
		button.disabled = true
		label.text = ""
		return
	button.disabled = not quote.is_ok()
	if quote.is_ok():
		label.text = "TOTAL %s: %s CR" % [total_caption, NumberFormat.with_commas(quote.total)]
		if quote.quantity > 1 and first_price > 0:
			var shift := roundi((float(quote.unit_price) / first_price - 1.0) * 100.0)
			label.text += "     AVERAGE %s CR PER UNIT" % NumberFormat.with_commas(quote.unit_price)
			if shift != 0:
				label.text += " (%s%d%% FROM THE FIRST UNIT)" % ["+" if shift > 0 else "", shift]
		label.remove_theme_color_override("font_color")
	else:
		label.text = quote.get_message()
		label.add_theme_color_override("font_color", ERROR_COLOR)


func _entered_quantity() -> int:
	return int(_quantity.value)


func _on_buy() -> void:
	if _selected == null:
		return
	var quote := _economy.buy(_market, _selected, _entered_quantity())
	_show_result(quote, "BOUGHT", "FOR")


func _on_sell() -> void:
	if _selected == null:
		return
	var quote := _economy.sell(_market, _selected, _entered_quantity())
	_show_result(quote, "SOLD", "FOR")


func _show_result(quote: TradeQuote, verb: String, preposition: String) -> void:
	if quote.is_ok():
		_status_label.text = "%s %d %s %s %s CR" % [verb, quote.quantity,
				quote.commodity.display_name.to_upper(), preposition,
				NumberFormat.with_commas(quote.total)]
		_status_label.remove_theme_color_override("font_color")
	else:
		_status_label.text = quote.get_message()
		_status_label.add_theme_color_override("font_color", ERROR_COLOR)


## Sets the quantity to the most the player could buy right now (at least 1,
## so the refusal reason still shows when nothing can be bought).
func _on_max_buy() -> void:
	if _selected == null:
		return
	var cargo := _economy.get_cargo()
	# Each unit costs more than the one before, so ask the market what the credits buy.
	_quantity.value = maxi(_market.max_buyable(_selected, _economy.get_credits(), cargo.get_free()), 1)


func _on_max_sell() -> void:
	if _selected == null:
		return
	_quantity.value = maxi(_economy.get_cargo().get_quantity(_selected.id), 1)
