class_name MissionComputerScreen
extends CanvasLayer
## Full-screen mission computer, shown over the settlement screen while docked.
## It lists the contracts on offer here and the player's active and completed
## ones, shows the selected one in detail and asks the ContractManager to accept
## it. It holds no contract state of its own and refreshes from signals.

const ERROR_COLOR := Color(1.0, 0.45, 0.4)
const INFO_ROW_SCENE := preload("res://scenes/ui/info_row.tscn")
const SECTION_TITLES := ["AVAILABLE HERE", "ACTIVE", "COMPLETED"]

enum Column { TITLE, DESTINATION, CARGO, REWARD }

var _contracts: ContractManager
var _economy: EconomyManager
var _location: InhabitedData
var _selected: Contract

@onready var _location_label: Label = %LocationLabel
@onready var _back_button: Button = %BackButton
@onready var _credits_row: InfoRow = %CreditsRow
@onready var _table: Tree = %Table
@onready var _title_label: Label = %TitleLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _detail_rows: VBoxContainer = %DetailRows
@onready var _progress_label: Label = %ProgressLabel
@onready var _accept_button: Button = %AcceptButton
@onready var _message_label: Label = %MessageLabel
@onready var _cargo_list: CargoList = %CargoList


func _ready() -> void:
	_table.columns = Column.size()
	var titles := ["CONTRACT", "DESTINATION", "CARGO", "REWARD"]
	for column in Column.size():
		_table.set_column_title(column, titles[column])
		_table.set_column_expand(column, column == Column.TITLE)
		_table.set_column_custom_minimum_width(column, 200 if column == Column.TITLE else 130)
	_table.set_column_title_alignment(Column.REWARD, HORIZONTAL_ALIGNMENT_RIGHT)
	_table.item_selected.connect(_on_item_selected)
	_back_button.pressed.connect(close)
	_accept_button.pressed.connect(_on_accept)


## Gives the screen the managers it reads from. Called once by Main.
func setup(contracts: ContractManager, economy: EconomyManager) -> void:
	_contracts = contracts
	_economy = economy
	_contracts.contracts_changed.connect(_refresh)
	_economy.credits_changed.connect(func(_credits: int) -> void: _refresh())
	_economy.cargo_changed.connect(_refresh)


## Opens the mission computer of the docked target. Does nothing without one.
func open(target: Targetable) -> void:
	var location := target.details as InhabitedData
	if location == null:
		return
	_location = location
	_selected = null
	_location_label.text = "%s MISSION COMPUTER" % target.target_name.to_upper()
	_message_label.text = ""
	visible = true
	_refresh()


func close() -> void:
	visible = false
	_location = null
	_selected = null


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Rebuilds the list and detail from the manager, keeping the selection.
func _refresh() -> void:
	if not visible or _location == null:
		return
	_credits_row.set_value("%s CR" % NumberFormat.with_commas(_economy.get_credits()))
	var cargo := _economy.get_cargo()
	_cargo_list.set_cargo(cargo.get_used(), cargo.capacity, _economy.get_cargo_lines())

	var groups: Array = [
		_contracts.get_available(_location),
		_contracts.get_active(),
		_contracts.get_completed(),
	]
	if _selected != null and not _is_listed(groups):
		_selected = null
	_table.clear()
	var root := _table.create_item()
	for section in groups.size():
		var header := _table.create_item(root)
		header.set_text(Column.TITLE, SECTION_TITLES[section])
		header.set_selectable(Column.TITLE, false)
		header.set_custom_color(Column.TITLE, Color(0.55, 0.7, 0.9))
		for contract in groups[section]:
			var item := _table.create_item(header)
			item.set_text(Column.TITLE, contract.title)
			item.set_text(Column.DESTINATION, contract.destination.display_name)
			item.set_text(Column.CARGO, contract.get_requirement_text())
			item.set_text(Column.REWARD, "%s CR" % NumberFormat.with_commas(contract.reward))
			item.set_text_alignment(Column.REWARD, HORIZONTAL_ALIGNMENT_RIGHT)
			item.set_metadata(Column.TITLE, contract)
			if contract == _selected:
				item.select(Column.TITLE)
		if groups[section].is_empty():
			var empty := _table.create_item(header)
			empty.set_text(Column.TITLE, "None")
			empty.set_selectable(Column.TITLE, false)
			empty.set_custom_color(Column.TITLE, Color(0.5, 0.55, 0.6))
	_show_detail()


func _is_listed(groups: Array) -> bool:
	for group in groups:
		if group.has(_selected):
			return true
	return false


func _on_item_selected() -> void:
	var item := _table.get_selected()
	_selected = item.get_metadata(Column.TITLE) if item != null else null
	_message_label.text = ""
	_show_detail()


func _show_detail() -> void:
	for row in _detail_rows.get_children():
		_detail_rows.remove_child(row)
		row.queue_free()
	if _selected == null:
		_title_label.text = "SELECT A CONTRACT"
		_description_label.text = ""
		_progress_label.text = ""
		_accept_button.disabled = true
		return
	_title_label.text = _selected.title.to_upper()
	_description_label.text = _selected.description
	_add_row("STATUS", _selected.get_status_text())
	_add_row("FROM", _selected.origin.display_name)
	_add_row("TO", _selected.destination.display_name)
	_add_row("CARGO", _selected.get_requirement_text())
	_add_row("REWARD", "%s CR" % NumberFormat.with_commas(_selected.reward))
	_progress_label.text = _selected.get_progress_text()
	var result := _contracts.check_accept(_selected, _location)
	_accept_button.disabled = result != ContractManager.AcceptResult.OK
	if _selected.status == Contract.Status.AVAILABLE and result != ContractManager.AcceptResult.OK:
		_show_message(ContractManager.get_result_message(result), true)


func _add_row(caption: String, value: String) -> void:
	var row: InfoRow = INFO_ROW_SCENE.instantiate()
	row.caption = caption
	_detail_rows.add_child(row)
	row.set_value(value)


func _on_accept() -> void:
	if _selected == null:
		return
	var contract := _selected
	var result := _contracts.accept(contract, _location)
	if result == ContractManager.AcceptResult.OK:
		_show_message("ACCEPTED: %s" % contract.title.to_upper(), false)
	else:
		_show_message(ContractManager.get_result_message(result), true)


func _show_message(text: String, is_error: bool) -> void:
	_message_label.text = text
	if is_error:
		_message_label.add_theme_color_override("font_color", ERROR_COLOR)
	else:
		_message_label.remove_theme_color_override("font_color")
