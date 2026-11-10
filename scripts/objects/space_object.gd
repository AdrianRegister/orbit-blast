class_name SpaceObject
extends Node2D
## Generic base for anything that sits at a fixed place in a star system and
## can be selected by the player. It owns the wiring to the Targetable child;
## subclasses answer the small virtual getters below to say what they are.
## World position is simply the node's `position`: set it in the system scene.

enum ObjectType { PLANET, STATION }

@onready var _targetable: Targetable = $Targetable


func _ready() -> void:
	_refresh_targetable()


func get_object_name() -> String:
	return _get_object_name()


## How close (world pixels) a ship must be to dock here. Valid once ready.
func get_dock_range() -> float:
	return _targetable.dock_range


func get_object_type() -> ObjectType:
	return _get_object_type()


## Pushes this object's current name, size and data into its Targetable.
func _refresh_targetable() -> void:
	if not is_node_ready():
		return
	_targetable.configure(_get_object_name(), _type_label(), _get_target_bounds(),
			_is_target_round(), _get_target_details(), _get_dock_range())


func _type_label() -> String:
	return ObjectType.keys()[_get_object_type()].capitalize()


# --- Virtual getters: override in subclasses -------------------------------

func _get_object_name() -> String:
	return str(name)


func _get_object_type() -> ObjectType:
	return ObjectType.PLANET


## Visual size in world pixels, used for the click area and selection box.
func _get_target_bounds() -> Vector2:
	return Vector2(64, 64)


func _is_target_round() -> bool:
	return false


## Extra HUD information; null means name, type and distance only.
func _get_target_details() -> TargetDetails:
	return null


## Docking range override; 0 = automatic (edge of the selection box).
func _get_dock_range() -> float:
	return 0.0
