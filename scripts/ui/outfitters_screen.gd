class_name OutfittersScreen
extends CanvasLayer
## Full-screen outfitters, shown over the settlement screen while docked. It
## lists the upgrades and weapons this location offers, compares the active
## ship with and without a selected upgrade (or shows a weapon's numbers), and
## asks the ShipManager to install it, or to sell a fitted weapon back. It
## holds no money or ship state and refreshes from the manager's and
## economy's signals.

const ERROR_COLOR := Color(1.0, 0.45, 0.4)
const CATEGORY_NAMES := ["CARGO", "ENGINE", "MANOEUVRE"]
const WEAPON_TYPE_NAME := "WEAPON"

enum Column { UPGRADE, TYPE, PRICE, STATUS }

var _ships: ShipManager
var _economy: EconomyManager
var _location: InhabitedData
## The selected row: an UpgradeDefinition or a WeaponDefinition.
var _selected: Resource

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
@onready var _sell_button: Button = %SellButton
@onready var _message_label: Label = %MessageLabel

var _items: Dictionary = {}  # String key -> TreeItem


func _ready() -> void:
	_table.columns = Column.size()
	var titles := ["ITEM", "TYPE", "PRICE", "STATUS"]
	for column in Column.size():
		_table.set_column_title(column, titles[column])
		_table.set_column_expand(column, column == Column.UPGRADE or column == Column.STATUS)
		_table.set_column_custom_minimum_width(column, 100 if column == Column.TYPE or column == Column.PRICE else 220)
	_table.set_column_title_alignment(Column.PRICE, HORIZONTAL_ALIGNMENT_RIGHT)
	_table.item_selected.connect(_on_item_selected)
	_back_button.pressed.connect(close)
	_install_button.pressed.connect(_on_install_pressed)
	_sell_button.pressed.connect(_on_sell_pressed)


func setup(ships: ShipManager, economy: EconomyManager) -> void:
	_ships = ships
	_economy = economy
	_economy.credits_changed.connect(func(_credits: int) -> void: _refresh())
	_ships.fleet_changed.connect(_refresh)


## Opens the outfitters of the docked target. Does nothing if it offers none.
func open(target: Targetable) -> void:
	_location = target.details as InhabitedData
	if _location == null or not _location.has_outfitter():
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
		var item := _add_row(root, upgrade, upgrade.display_name, CATEGORY_NAMES[upgrade.category], upgrade.price)
		_items[_key(upgrade)] = item
	for weapon in _location.outfitter_weapons:
		var item := _add_row(root, weapon, weapon.display_name, WEAPON_TYPE_NAME, weapon.price)
		_items[_key(weapon)] = item
	var first := root.get_first_child()
	if first != null:
		first.select(Column.UPGRADE)
		_selected = first.get_metadata(Column.UPGRADE)


func _add_row(root: TreeItem, thing: Resource, item_name: String, type_name: String, price: int) -> TreeItem:
	var item := _table.create_item(root)
	item.set_text(Column.UPGRADE, item_name)
	item.set_metadata(Column.UPGRADE, thing)
	item.set_text(Column.TYPE, type_name)
	item.set_text(Column.PRICE, "%s CR" % NumberFormat.with_commas(price))
	item.set_text_alignment(Column.PRICE, HORIZONTAL_ALIGNMENT_RIGHT)
	return item


## Upgrades and weapons have separate id spaces, so keys say which they are.
func _key(thing: Resource) -> String:
	return ("w:" if thing is WeaponDefinition else "u:") + str(thing.get("id"))


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
		var item: TreeItem = _items[_key(upgrade)]
		item.set_text(Column.STATUS, "Available" if quote.ok else quote.message)
		var installed := active.count_installed(upgrade)
		if installed > 0 and upgrade.max_per_ship > 1:
			item.set_text(Column.STATUS, "Fitted %d of %d" % [installed, upgrade.max_per_ship]
					if not quote.ok else "Fitted %d of %d, more available" % [installed, upgrade.max_per_ship])
		item.set_custom_color(Column.STATUS, Color.WHITE if quote.ok else Color(0.65, 0.68, 0.75))
	for weapon in _location.outfitter_weapons:
		var quote := _ships.quote_weapon(weapon)
		var item: TreeItem = _items[_key(weapon)]
		var fitted := active.count_weapon(weapon)
		var status := "Available" if quote.ok else quote.message
		if fitted > 0:
			status = "Fitted %d, more available" % fitted if quote.ok else "Fitted %d" % fitted
		item.set_text(Column.STATUS, status)
		item.set_custom_color(Column.STATUS, Color.WHITE if quote.ok else Color(0.65, 0.68, 0.75))
	_sell_button.visible = _selected is WeaponDefinition
	if _selected == null:
		_install_button.disabled = true
		return
	if _selected is WeaponDefinition:
		_refresh_weapon(active, _selected as WeaponDefinition)
	else:
		_refresh_upgrade(active, _selected as UpgradeDefinition)


func _refresh_upgrade(active: OwnedShip, upgrade: UpgradeDefinition) -> void:
	var quote := _ships.quote_upgrade(upgrade)
	_install_button.text = "INSTALL UPGRADE"
	_name_label.text = upgrade.display_name.to_upper()
	_description_label.text = upgrade.description
	_price_label.text = "PRICE %s CR" % NumberFormat.with_commas(upgrade.price)
	_specs.show_specs(active.get_specs(), _ships.preview_upgrade(active, upgrade))
	_install_button.disabled = not quote.ok
	if not quote.ok and _message_label.text.is_empty():
		_show_error(quote.message)


func _refresh_weapon(active: OwnedShip, weapon: WeaponDefinition) -> void:
	var quote := _ships.quote_weapon(weapon)
	_install_button.text = "INSTALL WEAPON"
	_name_label.text = weapon.display_name.to_upper()
	_description_label.text = "%s\n\n%s\n\nMounts used: %d of %d" % [
			weapon.description, weapon.get_stats_text(), active.mounts_used(), active.model.weapon_mounts.size()]
	_price_label.text = "PRICE %s CR" % NumberFormat.with_commas(weapon.price)
	_specs.show_specs(active.get_specs(), null)
	_install_button.disabled = not quote.ok
	var sale := _ships.quote_sell_weapon(weapon)
	_sell_button.text = "SELL ONE FOR %s CR" % NumberFormat.with_commas(_ships.get_weapon_sell_value(weapon))
	_sell_button.disabled = not sale.ok
	if not quote.ok and _message_label.text.is_empty():
		_show_error(quote.message)


func _on_install_pressed() -> void:
	if _selected == null:
		return
	var thing_name: String = _selected.get("display_name")
	var cost: int = _selected.get("price")
	var result: ShipResult
	if _selected is WeaponDefinition:
		result = _ships.install_weapon(_selected as WeaponDefinition)
	else:
		result = _ships.install_upgrade(_selected as UpgradeDefinition)
	if result.ok:
		_message_label.remove_theme_color_override("font_color")
		_message_label.text = "INSTALLED %s FOR %s CR" % [thing_name.to_upper(), NumberFormat.with_commas(cost)]
		_refresh()
	else:
		_show_error(result.message)


func _on_sell_pressed() -> void:
	if not _selected is WeaponDefinition:
		return
	var weapon := _selected as WeaponDefinition
	var result := _ships.sell_weapon(weapon)
	if result.ok:
		_message_label.remove_theme_color_override("font_color")
		_message_label.text = "SOLD %s FOR %s CR" % [weapon.display_name.to_upper(), NumberFormat.with_commas(result.trade_in_value)]
		_refresh()
	else:
		_show_error(result.message)


func _show_error(text: String) -> void:
	_message_label.text = text
	_message_label.add_theme_color_override("font_color", ERROR_COLOR)
