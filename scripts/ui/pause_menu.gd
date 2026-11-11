class_name PauseMenu
extends CanvasLayer
## The menu opened with Esc: resume, save, load, or return to the main menu.
## It only shows buttons and a status line and reports presses; Main decides
## what each one does. It keeps running while the game tree is paused.

signal resume_requested
signal save_requested
signal load_requested
signal quit_to_menu_requested

const ERROR_COLOR := Color(1.0, 0.45, 0.4)

@onready var _resume_button: Button = %ResumeButton
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _quit_button: Button = %QuitButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_resume_button.pressed.connect(resume_requested.emit)
	_save_button.pressed.connect(save_requested.emit)
	_load_button.pressed.connect(load_requested.emit)
	_quit_button.pressed.connect(quit_to_menu_requested.emit)


## Shows the menu. `can_load` is false when there is no saved game.
func open(can_load: bool) -> void:
	_load_button.disabled = not can_load
	_status_label.text = ""
	visible = true
	_resume_button.grab_focus()


func close() -> void:
	visible = false


## One line under the buttons, such as "GAME SAVED" or why saving failed.
func show_status(text: String, is_error: bool = false) -> void:
	_status_label.text = text
	if is_error:
		_status_label.add_theme_color_override("font_color", ERROR_COLOR)
	else:
		_status_label.remove_theme_color_override("font_color")


func set_load_enabled(enabled: bool) -> void:
	_load_button.disabled = not enabled


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		resume_requested.emit()
		get_viewport().set_input_as_handled()
