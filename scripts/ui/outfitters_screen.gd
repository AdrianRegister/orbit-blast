class_name OutfittersScreen
extends CanvasLayer
## Full-screen outfitters, shown over the settlement screen while docked. It
## lists the upgrades this location offers, compares the active ship with and
## without the selected upgrade, and asks the ShipManager to install it. It
## holds no money or ship state and refreshes from the manager's and
## economy's signals.

const ERROR_COLOR := Color(1.0, 0.45, 0.4)
const CATEGORY_NAMES := ["CARGO", "ENGINE", "MANOEUVRE"]

enum Column { UPGRADE, TYPE, PRICE, STATUS }

var _ships: ShipManager
var _economy: EconomyManager
var _location: InhabitedData
var _selected: UpgradeDefinition

@onready var _title_label: Label = %TitleLabel
@onready var _back_button: Button = %BackButton
@onready var _credits_row: InfoRow = %CreditsRow
@onready var _ship_row: InfoRow = %ShipRow
@onready var _table: Tree = %Table
@onready var _name_label: Label = %NameLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _price_label: Label = %PriceLabel
@onready var _specs: SpecComparison = %SpecTable
@onready var _install_button: Button = %InstallButton
@onready var _message_label: Label = %MessageLabel

var _items: Dictionary = {}  # StringName -> TreeItem


func _ready() -> void:
	_table.columns = Column.size()
	var titles := ["UPGRADE", "TYPE", "PRICE", "STATUS"]
	for column in Column.size():
		_table.set_column_title(column, titles[column])
		_table.set_column_expand(column, column == Column.UPGRADE or column == Column.STATUS)
		_table.set_column_custom_minimum_width(column, 100 if column == Column.TYPE or column == Column.PRICE else 220)
	_table.set_column_title_alignment(Column.PRICE, HORIZONTAL_ALIGNMENT_RIGHT)
	_table.item_selected.connect(_on_item_selected)
	_back_button.pressed.connect(close)
	_install_button.pressed.connect(_on_install_pressed)


func setup(ships: ShipManager, economy: EconomyManager) -> void:
	_ships = ships
	_economy = economy
	_economy.credits_changed.connect(func(_credits: int) -> void: _refresh())
	_ships.fleet_changed.connect(_refresh)


## Opens the outfitters of the docked target. Does nothing if it offers none.
func open(target: Targetable) -> void:
	_location = target.details as InhabitedData
	if _location == null or _location.outfitter_upgrades.is_empty():
		return
	_title_label.text = "%s OUTFITTERS" % target.target_name.to_upper()
	_message_label.text = ""
	_build_table()
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_location = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build_table() -> void:
	_table.clear()
	_items.clear()
	_selected = null
	var root := _table.create_item()
	for upgrade in _location.outfitter_upgrades:
		var item := _table.create_item(root)
		item.set_text(Column.UPGRADE, upgrade.display_name)
		item.set_metadata(Column.UPGRADE, upgrade)
		item.set_text(Column.TYPE, CATEGORY_NAMES[upgrade.category])
		item.set_text(Column.PRICE, "%s CR" % NumberFormat.with_commas(upgrade.price))
		item.set_text_alignment(Column.PRICE, HORIZONTAL_ALIGNMENT_RIGHT)
		_items[upgrade.id] = item
	var first := root.get_first_child()
	if first != null:
		first.select(Column.UPGRADE)
		_selected = first.get_metadata(Column.UPGRADE)


func _on_item_selected() -> void:
	var item := _table.get_selected()
	_selected = item.get_metadata(Column.UPGRADE) if item != null else null
	_message_label.text = ""
	_refresh()


func _refresh() -> void:
	if not visible or _location == null:
		return
	var active := _ships.get_active()
	_credits_row.set_value("%s CR" % NumberFormat.with_commas(_economy.get_credits()))
	_ship_row.set_value("%s (%s)" % [active.ship_name, active.model.display_name])
	for upgrade in _location.outfitter_upgrades:
		var quote := _ships.quote_upgrade(upgrade)
		var item: TreeItem = _items[upgrade.id]
		item.set_text(Column.STATUS, "Available" if quote.ok else quote.message)
		var installed := active.count_installed(upgrade)
		if installed > 0 and upgrade.max_per_ship > 1:
			item.set_text(Column.STATUS, "Fitted %d of %d" % [installed, upgrade.max_per_ship]
					if not quote.ok else "Fitted %d of %d, more available" % [installed, upgrade.max_per_ship])
		item.set_custom_color(Column.STATUS, Color.WHITE if quote.ok else Color(0.65, 0.68, 0.75))
	if _selected == null:
		_install_button.disabled = true
		return
	var selected_quote := _ships.quote_upgrade(_selected)
	_name_label.text = _selected.display_name.to_upper()
	_description_label.text = _selected.description
	_price_label.text = "PRICE %s CR" % NumberFormat.with_commas(_selected.price)
	_specs.show_specs(active.get_specs(), _ships.preview_upgrade(active, _selected))
	_install_button.disabled = not selected_quote.ok
	if not selected_quote.ok and _message_label.text.is_empty():
		_show_error(selected_quote.message)


func _on_install_pressed() -> void:
	if _selected == null:
		return
	var upgrade_name := _selected.display_name
	var cost := _selected.price
	var result := _ships.install_upgrade(_selected)
	if result.ok:
		_message_label.remove_theme_color_override("font_color")
		_message_label.text = "INSTALLED %s FOR %s CR" % [upgrade_name.to_upper(), NumberFormat.with_commas(cost)]
		_refresh()
	else:
		_show_error(result.message)


func _show_error(text: String) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", ERROR_COLOR)
