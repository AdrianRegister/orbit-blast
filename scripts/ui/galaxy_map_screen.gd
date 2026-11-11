class_name GalaxyMapScreen
extends CanvasLayer
## The galaxy map: the drawn map on the left and, on the right, details of the
## selected system with a JUMP button. It only displays what the Galaxy,
## TravelManager and the jump check say and reports what the player asks for;
## Main pauses the game while it is open and carries out the choice.
##
## It keeps working while the game is paused (process mode ALWAYS), so it
## handles the keys that close it itself: M and Esc.

## The player pressed SELECT DESTINATION for this system. Jumping itself is
## done from space with J, once the ship is far enough from the system centre.
signal destination_selected(system_id: StringName)
## The map was closed (by the player or by close()).
signal closed

const INFO_ROW_SCENE := preload("res://scenes/ui/info_row.tscn")
const ERROR_COLOR := Color(1.0, 0.45, 0.4)

var _galaxy: Galaxy
var _travel: TravelManager
## Callable(system_id) -> JumpCheck: asks Main whether a jump is possible now.
var _check_jump: Callable

@onready var _map: GalaxyMapView = %MapView
@onready var _back_button: Button = %BackButton
@onready var _name_label: Label = %NameLabel
@onready var _status_label: Label = %StatusLabel
@onready var _rows: VBoxContainer = %DetailRows
@onready var _jump_button: Button = %JumpButton
@onready var _message_label: Label = %MessageLabel


func _ready() -> void:
	_back_button.pressed.connect(close)
	_jump_button.pressed.connect(_on_jump_pressed)
	_map.system_selected.connect(_show_system)


func setup(galaxy: Galaxy, travel: TravelManager, check_jump: Callable) -> void:
	_galaxy = galaxy
	_travel = travel
	_check_jump = check_jump
	_map.setup(galaxy, travel)
	_travel.discovery_changed.connect(_refresh)
	_travel.destination_changed.connect(_refresh)


## Opens the map centred on the current system, which is selected.
func open() -> void:
	var current := _travel.get_current_id()
	visible = true
	_map.focus_on(current)
	_map.select(current)
	_show_system(current)


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func get_map() -> GalaxyMapView:
	return _map


func get_selected_id() -> StringName:
	return _map.selected_id


## Runs before gameplay input, and also while the game is paused.
func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("galaxy_map") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	if visible and _map.selected_id != &"":
		_show_system(_map.selected_id)


func _show_system(id: StringName) -> void:
	var summary := _galaxy.get_summary(id)
	if summary == null:
		return
	var current := _travel.get_current_id()
	var discovered := _travel.is_discovered(id)
	var check: JumpCheck = _check_jump.call(id)
	_name_label.text = summary.system_name.to_upper()
	if id == current:
		_status_label.text = "CURRENT SYSTEM"
	else:
		_status_label.text = "DISCOVERED" if discovered else "UNEXPLORED"
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()
	_add_row("FACTION", _galaxy.get_faction(id) if discovered else "Unknown")
	if id == current:
		_add_row("ROUTE", "You are here")
	elif check.reachable:
		_add_row("ROUTE", "Direct jump from %s" % _galaxy.get_summary(current).system_name)
		_add_row("JUMP COST", "%d fuel (not yet used)" % check.cost)
		_add_row("DISTANCE", "%d light-years" % roundi(_galaxy.get_map_position(current).distance_to(_galaxy.get_map_position(id)) / 10.0))
	else:
		_add_row("ROUTE", "No direct jump from %s" % _galaxy.get_summary(current).system_name)
	_add_row("EXPORTS", _join(summary.exports) if discovered else "Unknown")
	_add_row("IMPORTS", _join(summary.imports) if discovered else "Unknown")
	_add_row("SERVICES", _services(summary) if discovered else "Unknown")
	var destinations := PackedStringArray()
	for neighbour in _galaxy.get_neighbours(id):
		destinations.append(_galaxy.get_summary(neighbour).system_name)
	_add_row("LINKS TO", ", ".join(destinations) if not destinations.is_empty() else "None")

	_jump_button.disabled = not check.reachable
	_jump_button.visible = id != current
	_jump_button.text = "SELECT DESTINATION"
	if id == current:
		_message_label.text = ""
	elif not check.reachable:
		_message_label.text = check.reason
	elif _travel.get_destination() == id:
		_message_label.text = "This is your selected destination."
	else:
		_message_label.text = "Then fly clear of the system centre and press J."
	_message_label.add_theme_color_override("font_color",
			ERROR_COLOR if id != current and not check.reachable else Color(0.7, 0.75, 0.82))


func _add_row(caption: String, value: String) -> void:
	var row: InfoRow = INFO_ROW_SCENE.instantiate()
	row.caption = caption
	_rows.add_child(row)
	row.set_value(value)


func _join(names: Array[String]) -> String:
	return ", ".join(PackedStringArray(names)) if not names.is_empty() else "None"


func _services(summary: SystemSummary) -> String:
	var services := PackedStringArray()
	if summary.has_shipyard:
		services.append("Shipyard")
	if summary.has_outfitter:
		services.append("Outfitter")
	return ", ".join(services) if not services.is_empty() else "None"


func _on_jump_pressed() -> void:
	if not _jump_button.disabled:
		destination_selected.emit(_map.selected_id)
