class_name DevToolbar
extends CanvasLayer
## DEVELOPMENT ONLY. A row of buttons at the top left of the combat sandbox that
## open and close its panels, each also on a key (F2, F3). The panels share one place on
## the left, so opening one closes the other. Stays on screen when a
## panel is closed, so it can be opened again.

var _sandbox: CombatSandbox
## One per panel: {"panel": DevPanel, "key": Key, "button": Button}.
var _entries: Array[Dictionary] = []


func _init() -> void:
	# Keeps running while the game is paused, so it can hide itself behind menus.
	process_mode = Node.PROCESS_MODE_ALWAYS


## `panels` is a list of {"name": String, "key": Key, "panel": DevPanel}, or of {"name", "key",
## "toggle": Callable(bool)}: a button that switches something on and off (it needs no panel, and
## does not close the others).
## (The panels share one place on the left, so opening one closes the others.)
func setup(sandbox: CombatSandbox, panels: Array[Dictionary]) -> void:
	_sandbox = sandbox
	layer = 5
	var row := HBoxContainer.new()
	row.theme = load("res://resources/ui/hud_theme.tres")
	row.position = Vector2(12, 56)
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for info in panels:
		if info.has("toggle"):
			_add_toggle(row, info)
			continue
		var panel: DevPanel = info["panel"]
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = panel.open
		button.text = "%s (%s)" % [info["name"], OS.get_keycode_string(info["key"])]
		button.custom_minimum_size = Vector2(0, 30)
		var index := _entries.size()
		button.toggled.connect(func(pressed: bool) -> void: _entries[index]["panel"].set_open(pressed))
		button.focus_mode = Control.FOCUS_NONE  # (so Space cannot press it again after a click)
		panel.toggled.connect(func(is_open: bool) -> void: _on_panel_toggled(index, is_open))
		row.add_child(button)
		_entries.append({"panel": panel, "key": info["key"], "button": button})


## A button that calls `info["toggle"]` with its state.
func _add_toggle(row: HBoxContainer, info: Dictionary) -> void:
	var button := Button.new()
	button.toggle_mode = true
	button.text = "%s (%s)" % [info["name"], OS.get_keycode_string(info["key"])]
	button.custom_minimum_size = Vector2(0, 30)
	button.focus_mode = Control.FOCUS_NONE
	var callback: Callable = info["toggle"]
	button.toggled.connect(func(pressed: bool) -> void: callback.call(pressed))
	row.add_child(button)
	_entries.append({"toggle": callback, "key": info["key"], "button": button})


## The panels share one place on the screen, so opening one closes the others.
func _on_panel_toggled(index: int, is_open: bool) -> void:
	_entries[index]["button"].set_pressed_no_signal(is_open)
	if not is_open:
		return
	for other in _entries.size():
		if other != index and _entries[other].has("panel"):
			_entries[other]["panel"].set_open(false)


func _process(_delta: float) -> void:
	visible = _sandbox != null and _sandbox.is_flying() and not get_tree().paused


## Opens or closes the panel at `index` (the same as pressing its button).
func toggle_panel(index: int) -> void:
	if index >= 0 and index < _entries.size():
		if _entries[index].has("panel"):
			_entries[index]["panel"].toggle()
		else:
			_entries[index]["button"].button_pressed = not _entries[index]["button"].button_pressed


func get_button(index: int) -> Button:
	return _entries[index]["button"]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or get_tree().paused:
		return
	for index in _entries.size():
		if key.physical_keycode == _entries[index]["key"]:
			toggle_panel(index)
			get_viewport().set_input_as_handled()
			return
