class_name EventPopup
extends CanvasLayer
## A modal message box for things that happen to the player: a title, a piece
## of flavour text and a few "caption: value" detail rows. It only displays what
## it is given. Several events raised at once are queued and shown one after
## another, each dismissed with the button, Enter or Esc.

signal closed

const INFO_ROW_SCENE := preload("res://scenes/ui/info_row.tscn")

## Queued events: {"title": String, "flavour": String, "details": Array}.
var _queue: Array[Dictionary] = []

@onready var _title_label: Label = %TitleLabel
@onready var _flavour_label: Label = %FlavourLabel
@onready var _detail_rows: VBoxContainer = %DetailRows
@onready var _ok_button: Button = %OkButton


func _ready() -> void:
	_ok_button.pressed.connect(_dismiss)


## Shows an event. `details` is an Array of [caption, value] string pairs.
## If a popup is already open, this one waits its turn.
func show_event(title: String, flavour: String, details: Array = []) -> void:
	_queue.append({"title": title, "flavour": flavour, "details": details})
	if not visible:
		_show_next()


func _show_next() -> void:
	var event: Dictionary = _queue.pop_front()
	_title_label.text = event["title"]
	_flavour_label.text = event["flavour"]
	_flavour_label.visible = not event["flavour"].is_empty()
	for row in _detail_rows.get_children():
		_detail_rows.remove_child(row)
		row.queue_free()
	for detail in event["details"]:
		var row: InfoRow = INFO_ROW_SCENE.instantiate()
		row.caption = detail[0]
		_detail_rows.add_child(row)
		row.set_value(detail[1])
	visible = true
	_ok_button.grab_focus()


func _dismiss() -> void:
	if _queue.is_empty():
		visible = false
		closed.emit()
	else:
		_show_next()


## Runs before the other screens' Esc handling, so Esc closes the popup first.
func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept")):
		_dismiss()
		get_viewport().set_input_as_handled()
