class_name DevToolbar
extends CanvasLayer
## DEVELOPMENT ONLY. A row of buttons at the top left of the combat sandbox that
## open and close its panels, each also on a key (F2, F3). Stays on screen when a
## panel is closed, so it can be opened again.

var _sandbox: CombatSandbox
## One per panel: {"panel": DevPanel, "key": Key, "button": Button}.
var _entries: Array[Dictionary] = []


func _init() -> void:
	# Keeps running while the game is paused, so it can hide itself behind menus.
	process_mode = Node.PROCESS_MODE_ALWAYS


## `panels` is a list of {"name": String, "key": Key, "panel": DevPanel}.
func setup(sandbox: CombatSandbox, panels: Array[Dictionary]) -> void:
	_sandbox = sandbox
	layer = 5
	var row := HBoxContainer.new()
	row.theme = load("res://resources/ui/hud_theme.tres")
	row.position = Vector2(12, 56)
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for info in panels:
		var panel: DevPanel = info["panel"]
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = panel.open
		button.text = "%s (%s)" % [info["name"], OS.get_keycode_string(info["key"])]
		button.custom_minimum_size = Vector2(0, 30)
		var index := _entries.size()
		button.toggled.connect(func(pressed: bool) -> void: _entries[index]["panel"].set_open(pressed))
		panel.toggled.connect(func(is_open: bool) -> void: button.set_pressed_no_signal(is_open))
		row.add_child(button)
		_entries.append({"panel": panel, "key": info["key"], "button": button})


func _process(_delta: float) -> void:
	visible = _sandbox != null and _sandbox.is_flying() and not get_tree().paused


## Opens or closes the panel at `index` (the same as pressing its button).
func toggle_panel(index: int) -> void:
	if index >= 0 and index < _entries.size():
		_entries[index]["panel"].toggle()


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
