class_name InhabitedNode
extends SpaceObject
## Common behaviour of every inhabited location (planets, stations, ...).
## Everything individual about a location (name, faction, population, goods,
## pictures, size, docking range) comes from its InhabitedData resource, so the
## same scene can be instanced many times with different data. Subclasses only
## provide the visual and their object type.

@export var data: InhabitedData


func _ready() -> void:
	if data == null:
		push_error("%s has no InhabitedData assigned." % name)
	else:
		for problem in data.validate():
			push_error("%s: %s" % [name, problem])
	super()


func _get_object_name() -> String:
	return data.display_name if data != null and not data.display_name.is_empty() else str(name)


func _get_target_details() -> TargetDetails:
	return data


func _get_dock_range() -> float:
	return data.docking_range if data != null else 0.0
