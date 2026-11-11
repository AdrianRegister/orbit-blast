class_name SystemCatalog
extends Resource
## Maps star system ids to their scenes. A saved game says which system the
## player is in by id; this is how that id becomes a scene again, including for
## systems that are not currently loaded. One catalog:
## resources/universe/system_catalog.tres.

@export var systems: Dictionary[StringName, PackedScene] = {}


func has_system(id: StringName) -> bool:
	return systems.has(id)


func get_scene(id: StringName) -> PackedScene:
	return systems.get(id)


func validate() -> Array[String]:
	var problems: Array[String] = []
	for id in systems:
		if id == &"":
			problems.append("catalog has an empty system id")
		if systems[id] == null:
			problems.append("system '%s' has no scene" % id)
	return problems
