class_name MainMenu
extends Control
## The first screen: New Game, Continue and Quit. It starts a game by putting a
## fresh Main (the game itself) into the scene tree and removing itself. For
## Continue it asks that Main to load the save and, if the save turns out to
## be unusable, throws that Main away and says why, so a bad save can never
## leave the player stuck.

const MAIN_SCENE := preload("res://scenes/main.tscn")

## Where the save is. Only tests change this.
var save_path: String = SaveManager.SAVE_PATH

@onready var _new_button: Button = %NewButton
@onready var _continue_button: Button = %ContinueButton
@onready var _quit_button: Button = %QuitButton
@onready var _message_label: Label = %MessageLabel
@onready var _confirm: Control = %ConfirmNew
@onready var _cancel_button: Button = %CancelButton
@onready var _confirm_button: Button = %ConfirmButton


func _ready() -> void:
	_new_button.pressed.connect(_on_new_pressed)
	_cancel_button.pressed.connect(_close_confirm)
	_confirm_button.pressed.connect(func() -> void: _start(false))
	_continue_button.pressed.connect(_start.bind(true))
	_quit_button.pressed.connect(get_tree().quit)
	_refresh_continue()
	(_continue_button if not _continue_button.disabled else _new_button).grab_focus()


## Enables Continue when a readable save exists and says when it was made.
func _refresh_continue() -> void:
	var read := SaveFile.read_with_backup(save_path)
	_continue_button.disabled = not read["ok"]
	if read["ok"]:
		var saved_at = read["data"].get("saved_at")
		if SaveData.is_int(saved_at):
			_message_label.text = "Last saved %s" % Time.get_datetime_string_from_unix_time(
					int(saved_at), true).replace("T", " ")
		else:
			_message_label.text = ""
	elif read["error"] == SaveFile.NO_SAVE:
		_message_label.text = ""
	else:
		_message_label.text = read["error"]


func _start(continue_game: bool) -> void:
	var main: Main = MAIN_SCENE.instantiate()
	main.get_node("Save").save_path = save_path
	get_tree().root.add_child(main)
	if continue_game:
		var result := main.load_game()
		if not result["ok"]:
			main.free()
			_message_label.text = result["error"]
			_continue_button.disabled = true
			_new_button.grab_focus()
			return
	if continue_game:
		main.start_session()
	else:
		main.start_new_session()  # asks for the ship's name first
	queue_free()


## A new game replaces the saved game, so ask first if there is one.
func _on_new_pressed() -> void:
	if SaveFile.exists(save_path):
		_confirm.visible = true
		_cancel_button.grab_focus()  # the safe choice is the default
	else:
		_start(false)


func _close_confirm() -> void:
	_confirm.visible = false
	_new_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _confirm.visible and event.is_action_pressed("ui_cancel"):
		_close_confirm()
		get_viewport().set_input_as_handled()

