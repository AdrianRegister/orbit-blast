class_name StarSystem
extends Node2D
## Reusable container for one star system. Individual systems are scenes that
## inherit star_system.tscn and add their objects under the `Objects` node.
## Nothing here needs to change to create a new system.

@export var system_name: String = ""

@onready var _objects: Node2D = $Objects


## Every SpaceObject placed in this system.
func get_space_objects() -> Array[SpaceObject]:
	var result: Array[SpaceObject] = []
	for child in _objects.get_children():
		if child is SpaceObject:
			result.append(child)
	return result
