class_name NamePrompt
extends CanvasLayer
## Asks the player to name a ship (1 to 50 characters). Esc does not skip it;
## the ship keeps its model name until the player confirms a name. It reports
## the choice and changes nothing itself. Runs while the game is paused too.

signal named(ship_id: StringName, ship_name: String)

var _ship_id: StringName = &""

@onready var _title_label: Label = %TitleLabel
@onready var _model_label: Label = %ModelLabel
@onready var _name_edit: LineEdit = %NameInput
@onready var _ok_button: Button = %OkButton


func _ready() -> void:
	_name_edit.max_length = OwnedShip.MAX_NAME_LENGTH
	_name_edit.text_changed.connect(_on_text_changed)
	_name_edit.text_submitted.connect(func(_text: String) -> void: _confirm())
	_ok_button.pressed.connect(_confirm)


## Prompts for a name for `ship`, starting from its current name.
func ask(ship: OwnedShip, title: String = "NAME YOUR SHIP") -> void:
	_ship_id = ship.id
	_title_label.text = title
	_model_label.text = "%s class" % ship.model.display_name
	_name_edit.text = ship.ship_name
	_on_text_changed(_name_edit.text)
	visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_text_changed(text: String) -> void:
	_ok_button.disabled = OwnedShip.clean_name(text).is_empty()


func _confirm() -> void:
	var cleaned := OwnedShip.clean_name(_name_edit.text)
	if cleaned.is_empty():
		return
	visible = false
	named.emit(_ship_id, cleaned)


## Esc is swallowed so it cannot open the pause menu behind the prompt.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
