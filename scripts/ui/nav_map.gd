class_name NavMap
extends Control
## The navicomputer's system map, in the manner of Escape Velocity Nova's
## sensor display: a small square view that is always centred on the player and
## scrolls as the ship moves (north stays up). It shows inhabited places as
## circle outlines (planets blue, uninhabited bodies such as gas giants grey,
## stations yellow) and NPC ships as blue dots. If no planet is in view, a
## flashing arrow at the edge points towards the system centre, so the player
## can find their way back; it disappears as soon as a planet comes into view.
##
## It only reads the ship and the loaded system; it owns no game state.

const KIND_PLANET := &"planet"
const KIND_UNINHABITED := &"uninhabited"
const KIND_STATION := &"station"
const KIND_SHIP := &"ship"

## Half the width of the view, in world pixels: what the map covers around the ship.
@export var view_range: float = 2500.0
## Seconds per flash of the selected ship's dot (on for one, off for the next).
@export var target_flash_period: float = 0.25
## Seconds per blink of the arrow (on for one, off for the next).
@export var blink_period: float = 0.4
## The arrow is not shown this close to the system centre (the direction is meaningless).
const ARROW_MIN_DISTANCE := 60.0

const BACKGROUND := Color(0.0, 0.0, 0.0)
const BORDER := Color(0.3, 0.65, 1.0)
const PLANET_COLOUR := Color(0.35, 0.6, 1.0)
const UNINHABITED_COLOUR := Color(0.62, 0.62, 0.66)
const STATION_COLOUR := Color(1.0, 0.9, 0.3)
const SHIP_COLOUR := Color(0.3, 0.5, 1.0)
const PLAYER_COLOUR := Color(1.0, 1.0, 1.0)
const ARROW_COLOUR := Color(1.0, 0.85, 0.3)

var _ship: Node2D
## The selected target, if any. A selected NPC ship's dot flashes.
var _target: Targetable
var _system: StarSystem
var _time: float = 0.0


func _ready() -> void:
	resized.connect(_keep_square)


## The map fills the width it is given and is as tall as it is wide.
func _keep_square() -> void:
	if absf(custom_minimum_size.y - size.x) > 0.5:
		custom_minimum_size.y = size.x


func set_ship(ship: Node2D) -> void:
	_ship = ship


## The currently selected target (null for none). Connect to the HUD's target.
func set_target(target: Targetable) -> void:
	_target = target
	queue_redraw()


## The system to show. Called whenever the loaded system changes.
func set_system(system: StarSystem) -> void:
	_system = system
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# ------------------------------------------------------------------- content

## Everything in view, as dictionaries {"kind", "world" (position), "offset"
## (world pixels from the ship), "size" (world pixels, 0 for ships),
## "targetable" (the ship's Targetable, null for places)}. Objects
## beyond the edge of the view are left out.
func get_blips() -> Array[Dictionary]:
	var blips: Array[Dictionary] = []
	if _ship == null or _system == null or not is_instance_valid(_system):
		return blips
	for node in _system.get_inhabited_nodes():
		var kind := _kind_of(node)
		_add_blip(blips, kind, node.global_position, node.data.size if node.data != null else 0.0)
	for npc in _system.get_ships_root().get_children():
		if npc is Node2D and not npc.is_queued_for_deletion():
			_add_blip(blips, KIND_SHIP, (npc as Node2D).global_position, 0.0, npc.get_node_or_null("Targetable"))
	return blips


func _add_blip(blips: Array[Dictionary], kind: StringName, world: Vector2, size: float, targetable: Targetable = null) -> void:
	var offset := world - _ship.global_position
	if absf(offset.x) <= view_range and absf(offset.y) <= view_range:
		blips.append({"kind": kind, "world": world, "offset": offset, "size": size, "targetable": targetable})


func _kind_of(node: InhabitedNode) -> StringName:
	if node.get_object_type() == SpaceObject.ObjectType.STATION:
		return KIND_STATION
	if node.data != null and not node.data.is_dockable():
		return KIND_UNINHABITED
	return KIND_PLANET


## The blip of the selected NPC ship, or an empty dictionary when the target is
## not an NPC ship in view (nothing selected, a planet, or the ship is gone).
func get_selected_blip() -> Dictionary:
	if _target == null or not is_instance_valid(_target):
		return {}
	for blip in get_blips():
		if blip["kind"] == KIND_SHIP and blip["targetable"] == _target:
			return blip
	return {}


## Whether the selected ship's dot is lit in the current phase of its flash.
func is_target_flash_on() -> bool:
	return int(_time / target_flash_period) % 2 == 0


## Number of planets (inhabited or not) in view. Stations and ships do not count.
func get_visible_planet_count() -> int:
	var count := 0
	for blip in get_blips():
		if blip["kind"] == KIND_PLANET or blip["kind"] == KIND_UNINHABITED:
			count += 1
	return count


## Direction (unit vector) the arrow points when it should be shown, otherwise
## Vector2.ZERO: no planet in view and the ship is not already at the centre.
func get_arrow_direction() -> Vector2:
	if _ship == null or _system == null or not is_instance_valid(_system) or get_visible_planet_count() > 0:
		return Vector2.ZERO
	var to_centre := _system.global_position - _ship.global_position
	if to_centre.length() < ARROW_MIN_DISTANCE:
		return Vector2.ZERO
	return to_centre.normalized()


func is_arrow_visible() -> bool:
	return get_arrow_direction() != Vector2.ZERO


# ------------------------------------------------------------------- drawing

func _draw() -> void:
	var side := minf(size.x, size.y)
	var top_left := (size - Vector2(side, side)) * 0.5
	var middle := size * 0.5
	var pixels_per_unit := side * 0.5 / view_range
	draw_rect(Rect2(top_left, Vector2(side, side)), BACKGROUND)
	if _ship != null:
		for blip in get_blips():
			_draw_blip(blip, middle, pixels_per_unit)
		_draw_player(middle)
		var arrow := get_arrow_direction()
		if arrow != Vector2.ZERO and int(_time / blink_period) % 2 == 0:
			_draw_arrow(middle, arrow, side * 0.5 - 14.0)
	draw_rect(Rect2(top_left, Vector2(side, side)), BORDER, false, 2.0)
	draw_rect(Rect2(top_left - Vector2(2, 2), Vector2(side + 4, side + 4)), Color(BORDER, 0.35), false, 2.0)


func _draw_blip(blip: Dictionary, middle: Vector2, pixels_per_unit: float) -> void:
	var at: Vector2 = middle + (blip["offset"] as Vector2) * pixels_per_unit
	match blip["kind"]:
		KIND_SHIP:
			if blip["targetable"] == _target and _target != null and is_instance_valid(_target):
				if is_target_flash_on():
					draw_circle(at, 3.0, SHIP_COLOUR.lightened(0.5))
			else:
				draw_circle(at, 2.0, SHIP_COLOUR)
		KIND_STATION:
			draw_arc(at, 4.0, 0.0, TAU, 20, STATION_COLOUR, 1.5, true)
		KIND_UNINHABITED:
			draw_arc(at, 4.0 + minf(blip["size"] / 400.0, 3.0), 0.0, TAU, 24, UNINHABITED_COLOUR, 1.5, true)
		_:
			draw_arc(at, 4.0 + minf(blip["size"] / 400.0, 3.0), 0.0, TAU, 24, PLANET_COLOUR, 1.5, true)


## A small arrow showing the ship's heading, at the middle of the view.
func _draw_player(middle: Vector2) -> void:
	var heading := Vector2.from_angle(_ship.rotation)
	var side := heading.orthogonal()
	draw_colored_polygon(PackedVector2Array([middle + heading * 5.0, middle - heading * 3.0 + side * 3.0, middle - heading * 3.0 - side * 3.0]), PLAYER_COLOUR)


func _draw_arrow(middle: Vector2, direction: Vector2, distance: float) -> void:
	var tip := middle + direction * distance
	var side := direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip, tip - direction * 12.0 + side * 7.0, tip - direction * 12.0 - side * 7.0]), ARROW_COLOUR)
