class_name ChoicePopup
extends CanvasLayer
## A modal question with a few buttons. It is told what to ask and reports the
## answer; it knows nothing about what the answer means. Esc cancels.
## Runs while the game is paused too.

## The player chose option `index` (0-based), or -1 for cancel.
signal chosen(index: int)

@onready var _title_label: Label = %TitleLabel
@onready var _text_label: Label = %TextLabel
@onready var _buttons: VBoxContainer = %Buttons


## `options` are the button captions; `disabled` (optional, same length) marks
## options that cannot be chosen. A CANCEL button is always added.
func ask(title: String, text: String, options: Array[String], disabled: Array[bool] = []) -> void:
	_title_label.text = title
	_text_label.text = text
	for button in _buttons.get_children():
		_buttons.remove_child(button)
		button.queue_free()
	var first_enabled: Button = null
	for i in options.size():
		var button := _make_button(options[i])
		button.disabled = i < disabled.size() and disabled[i]
		button.pressed.connect(_answer.bind(i))
		if first_enabled == null and not button.disabled:
			first_enabled = button
		_buttons.add_child(button)
	var cancel := _make_button("CANCEL")
	cancel.pressed.connect(_answer.bind(-1))
	_buttons.add_child(cancel)
	visible = true
	(first_enabled if first_enabled != null else cancel).grab_focus()


func _make_button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(0, 44)
	return button


func _answer(index: int) -> void:
	visible = false
	chosen.emit(index)


## Runs before the other screens' Esc handling, so Esc cancels this first.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_answer(-1)
		get_viewport().set_input_as_handled()
