class_name ShipyardScreen
extends CanvasLayer
## Full-screen shipyard, shown over the settlement screen while docked. It lists
## the ships this location sells, compares the selected one with the player's
## ship, and asks the ShipManager to buy it. It holds no money or ships of its
## own and refreshes from the manager's and economy's signals.
##
## Buying asks first what to do with the current ship (trade it in, or keep it
## stored). The player is then asked to name the new ship by whoever listens to
## `ship_purchased`.

signal ship_purchased(ship: OwnedShip)

const ERROR_COLOR := Color(1.0, 0.45, 0.4)

enum Column { SHIP, PRICE, SPEED, ACCELERATION, TURN, CARGO }

var _ships: ShipManager
var _economy: EconomyManager
var _location: InhabitedData
var _selected: ShipStats

@onready var _title_label: Label = %TitleLabel
@onready var _back_button: Button = %BackButton
@onready var _credits_row: InfoRow = %CreditsRow
@onready var _ship_row: InfoRow = %ShipRow
@onready var _table: Tree = %Table
@onready var _sprite: TextureRect = %SpriteRect
@onready var _name_label: Label = %NameLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _price_label: Label = %PriceLabel
@onready var _specs: SpecComparison = %SpecTable
@onready var _buy_button: Button = %BuyButton
@onready var _message_label: Label = %MessageLabel
@onready var _choice: ChoicePopup = %ChoicePopup


func _ready() -> void:
	_table.columns = Column.size()
	var titles := ["SHIP", "PRICE", "SPEED", "ACCEL.", "TURN", "CARGO"]
	for column in Column.size():
		_table.set_column_title(column, titles[column])
		_table.set_column_expand(column, column == Column.SHIP)
		_table.set_column_custom_minimum_width(column, 200 if column == Column.SHIP else 90)
		if column != Column.SHIP:
			_table.set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_RIGHT)
	_table.item_selected.connect(_on_item_selected)
	_back_button.pressed.connect(close)
	_buy_button.pressed.connect(_on_buy_pressed)
	_choice.chosen.connect(_on_choice)


func setup(ships: ShipManager, economy: EconomyManager) -> void:
	_ships = ships
	_economy = economy
	_economy.credits_changed.connect(func(_credits: int) -> void: _refresh())
	_ships.fleet_changed.connect(_refresh)


## Opens the shipyard of the docked target. Does nothing if it sells no ships.
func open(target: Targetable) -> void:
	_location = target.details as InhabitedData
	if _location == null or _location.shipyard_ships.is_empty():
		return
	_title_label.text = "%s SHIPYARD" % target.target_name.to_upper()
	_message_label.text = ""
	_build_table()
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_choice.visible = false
	_location = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_table() -> void:
	_table.clear()
	_selected = null
	var root := _table.create_item()
	for model in _location.shipyard_ships:
		var item := _table.create_item(root)
		var specs := ShipSpecs.compute(model)
		item.set_text(Column.SHIP, model.display_name)
		item.set_metadata(Column.SHIP, model)
		item.set_text(Column.PRICE, "%s CR" % NumberFormat.with_commas(model.price))
		item.set_text(Column.SPEED, "%d" % specs.max_speed)
		item.set_text(Column.ACCELERATION, "%d" % specs.thrust)
		item.set_text(Column.TURN, "%.1f" % specs.turn_rate)
		item.set_text(Column.CARGO, "%d" % specs.cargo_capacity)
		for column in range(1, Column.size()):
			item.set_text_alignment(column, HORIZONTAL_ALIGNMENT_RIGHT)
	var first := root.get_first_child()
	if first != null:
		first.select(Column.SHIP)
		_selected = first.get_metadata(Column.SHIP)


func _on_item_selected() -> void:
	var item := _table.get_selected()
	_selected = item.get_metadata(Column.SHIP) if item != null else null
	_message_label.text = ""
	_refresh()


## Re-reads everything shown from the economy and the fleet.
func _refresh() -> void:
	if not visible or _location == null:
		return
	var active := _ships.get_active()
	_credits_row.set_value("%s CR" % NumberFormat.with_commas(_economy.get_credits()))
	_ship_row.set_value("%s (%s)" % [active.ship_name, active.model.display_name])
	if _selected == null:
		_buy_button.disabled = true
		return
	_sprite.texture = _selected.texture
	_name_label.text = _selected.display_name.to_upper()
	_description_label.text = _selected.description
	_price_label.text = "PRICE %s CR" % NumberFormat.with_commas(_selected.price)
	_specs.show_specs(active.get_specs(), ShipSpecs.compute(_selected))
	# The button works if buying is possible either way; the choice popup then
	# shows which options are open.
	var keep := _ships.quote_ship(_selected, false)
	var trade := _ships.quote_ship(_selected, true)
	_buy_button.disabled = not (keep.ok or trade.ok)
	if _buy_button.disabled and _message_label.text.is_empty():
		_show_error(keep.message)


func _on_buy_pressed() -> void:
	if _selected == null:
		return
	var active := _ships.get_active()
	var keep := _ships.quote_ship(_selected, false)
	var trade := _ships.quote_ship(_selected, true)
	var value := active.model.price
	var text := "What should happen to your current ship, %s (%s)?\n\n" % [active.ship_name, active.model.display_name]
	text += "TRADE IN: it is worth %s CR, so the %s costs %s CR.\n" % [
			NumberFormat.with_commas(value), _selected.display_name,
			NumberFormat.with_commas(_ships.get_net_price(_selected, value))]
	text += "KEEP IT: you pay the full %s CR and the %s is stored for later." % [
			NumberFormat.with_commas(_selected.price), active.model.display_name]
	var options: Array[String] = [
		"TRADE IN  (%s CR)" % NumberFormat.with_commas(trade.cost),
		"KEEP IT  (%s CR)" % NumberFormat.with_commas(keep.cost),
	]
	_choice.ask("BUY THE %s" % _selected.display_name.to_upper(), text, options, [not trade.ok, not keep.ok])


func _on_choice(index: int) -> void:
	if index < 0 or _selected == null:
		return
	var result := _ships.buy_ship(_selected, index == 0)
	if not result.ok:
		_show_error(result.message)
		return
	_message_label.remove_theme_color_override("font_color")
	_message_label.text = "BOUGHT THE %s FOR %s CR" % [_selected.display_name.to_upper(), NumberFormat.with_commas(result.cost)]
	ship_purchased.emit(result.ship)


func _show_error(text: String) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", ERROR_COLOR)
