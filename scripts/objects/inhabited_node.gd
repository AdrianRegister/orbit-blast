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
	var system := get_parent().get_parent() as StarSystem if get_parent() != null else null
	if system != null:
		set_owner_lookup(system.get_owner_lookup())
		set_extra_rows_lookup(system.get_extra_rows_lookup())


## Lets the HUD show who owns this location now rather than its starting owner.
func set_owner_lookup(lookup: Callable) -> void:
	if is_node_ready():
		_targetable.owner_name_lookup = lookup


## Lets the HUD show extra rows for this location (see Targetable.extra_rows_lookup).
func set_extra_rows_lookup(lookup: Callable) -> void:
	if is_node_ready():
		_targetable.extra_rows_lookup = lookup


func _get_object_name() -> String:
	return data.display_name if data != null and not data.display_name.is_empty() else str(name)


func _get_target_details() -> TargetDetails:
	return data


func _get_dock_range() -> float:
	return data.docking_range if data != null else 0.0
