class_name Targetable
extends Area2D
## The "targetable" interface, as a component. Add one as a child of anything
## the player should be able to select (planets, stations, later ships) and
## call configure() on it. It provides:
##   - a click area, found by the TargetingManager,
##   - the selection brackets,
##   - the name / type / extra rows the HUD displays.
## It is a component rather than a base class so that objects of any node
## type, such as a CharacterBody2D ship, can be targetable.

## Emitted when anything the HUD displays (other than distance) changes.
signal info_changed
## Emitted when this target can no longer be selected (disabled, e.g. an NPC
## that has docked). The TargetingManager clears the selection when it fires.
signal became_unavailable

## Physics layer used only for click detection.
const COLLISION_LAYER := 2
## Every Targetable joins this group, so the manager can list them all.
const GROUP := &"targetable"
## Cycle groups: Tab cycles locations, T cycles ships. A Targetable joins the
## one named by `cycle_group`, so adding a new cycle needs only a new group.
const LOCATION_GROUP := &"targetable_location"
const SHIP_GROUP := &"targetable_ship"
const SELECTION_MARGIN := 14.0
const SELECTION_COLOR := Color(1.0, 0.85, 0.3, 0.85)
const SELECTION_LINE_WIDTH := 2.0

## Which cycle this target belongs to (see LOCATION_GROUP / SHIP_GROUP).
@export var cycle_group: StringName = LOCATION_GROUP

var target_name: String = ""
var target_type: String = ""
## Optional extra information. Any TargetDetails subclass works.
var details: TargetDetails

## How close (centre to centre, world pixels) the player must be to dock.
var dock_range: float = 0.0

var _bounds_size: Vector2 = Vector2(64, 64)
var _is_round: bool = false
var _selected: bool = false
var _enabled: bool = true

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(cycle_group)


## Sets everything in one go. `bounds_size` is the visual size of the object
## in world pixels; `is_round` makes the click area a circle instead of a box.
## `dock_range_override` > 0 sets the docking range; otherwise it defaults to
## the edge of the selection box (half the object's size plus the margin).
func configure(name_text: String, type_text: String, bounds_size: Vector2,
		is_round: bool, target_details: TargetDetails = null,
		dock_range_override: float = 0.0) -> void:
	target_name = name_text
	target_type = type_text
	_bounds_size = bounds_size
	_is_round = is_round
	dock_range = dock_range_override if dock_range_override > 0.0 \
			else maxf(bounds_size.x, bounds_size.y) * 0.5 + SELECTION_MARGIN
	_set_details(target_details)
	_update_shape()
	queue_redraw()
	info_changed.emit()


## A disabled target cannot be clicked or cycled to, and loses any selection.
func set_enabled(enabled: bool) -> void:
	if enabled == _enabled:
		return
	_enabled = enabled
	_shape.set_deferred("disabled", not enabled)
	if not enabled:
		_selected = false
		queue_redraw()
		became_unavailable.emit()


func is_enabled() -> bool:
	return _enabled


func set_selected(selected: bool) -> void:
	_selected = selected
	queue_redraw()


## Callable(InhabitedData) -> String: who owns this location now. Optional; set by
## the star system so the "OWNED BY" row follows changes of ownership.
var owner_name_lookup: Callable


## Rows for the HUD beyond name, type and distance.
func get_detail_rows() -> Array:
	var rows: Array = details.get_rows() if details != null else []
	if owner_name_lookup.is_valid() and details is InhabitedData:
		for row in rows:
			if row[0] == "OWNED BY":
				row[1] = owner_name_lookup.call(details)
	return rows


func is_dockable() -> bool:
	return details != null and details.is_dockable()


func distance_from(point: Vector2) -> float:
	return global_position.distance_to(point)


func _set_details(new_details: TargetDetails) -> void:
	if details != null and details.changed.is_connected(_on_details_changed):
		details.changed.disconnect(_on_details_changed)
	details = new_details
	if details != null:
		details.changed.connect(_on_details_changed)


func _on_details_changed() -> void:
	info_changed.emit()


func _update_shape() -> void:
	if _is_round:
		var circle := CircleShape2D.new()
		circle.radius = _bounds_size.x * 0.5
		_shape.shape = circle
	else:
		var box := RectangleShape2D.new()
		box.size = _bounds_size
		_shape.shape = box


## Draws only the four corners of a box around the object.
func _draw() -> void:
	if not _selected:
		return
	var half: Vector2 = _bounds_size * 0.5 + Vector2(SELECTION_MARGIN, SELECTION_MARGIN)
	var arm: float = clampf(minf(_bounds_size.x, _bounds_size.y) * 0.18, 14.0, 40.0)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(sx * half.x, sy * half.y)
			draw_line(corner, corner + Vector2(-sx * arm, 0), SELECTION_COLOR, SELECTION_LINE_WIDTH)
			draw_line(corner, corner + Vector2(0, -sy * arm), SELECTION_COLOR, SELECTION_LINE_WIDTH)
