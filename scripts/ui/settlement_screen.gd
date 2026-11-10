class_name SettlementScreen
extends CanvasLayer
## Full-screen interface shown while docked. It draws over (and in Main's wiring
## replaces) the flight HUD. It shows what it is given and reports button
## presses; it does not decide anything about docking itself.

## The player pressed Depart.
signal depart_requested
## The player pressed Trading Floor.
signal trading_requested

const INFO_ROW_SCENE := preload("res://scenes/ui/info_row.tscn")

## Shown when the settlement has no picture of its own.
@export var default_picture: Texture2D

@onready var _picture: TextureRect = %Picture
@onready var _name_label: Label = %NameLabel
@onready var _detail_rows: VBoxContainer = %DetailRows
@onready var _trading_button: Button = %TradingButton
@onready var _depart_button: Button = %DepartButton


func _ready() -> void:
	_depart_button.pressed.connect(depart_requested.emit)
	_trading_button.pressed.connect(trading_requested.emit)


## Fills the screen from a dockable target and shows it.
func open(target: Targetable) -> void:
	_name_label.text = target.target_name
	var inhabited := target.details as InhabitedData
	var picture: Texture2D = inhabited.get_picture() if inhabited != null else null
	_picture.texture = picture if picture != null else default_picture
	_trading_button.disabled = inhabited == null or inhabited.market == null

	for row in _detail_rows.get_children():
		_detail_rows.remove_child(row)
		row.queue_free()
	for row_data in target.get_detail_rows():
		var row: InfoRow = INFO_ROW_SCENE.instantiate()
		row.caption = row_data[0]
		_detail_rows.add_child(row)
		row.set_value(row_data[1])
	visible = true


func close() -> void:
	visible = false
