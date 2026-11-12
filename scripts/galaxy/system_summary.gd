class_name SystemSummary
extends RefCounted
## A read-only description of a star system, for the galaxy map: its id, name,
## what its locations trade and what services they offer. Built from the
## system scene without putting it in the game, so any system can be described
## whether or not it is loaded. Nothing here is stored or saved.

var id: StringName = &""
var system_name: String = ""
## Jump distance from the system centre, in pixels (see StarSystem.jump_radius).
var jump_radius: float = 0.0
var location_ids: Array[StringName] = []
var location_names: Array[String] = []
## Distinct commodity names across all locations, sorted.
var imports: Array[String] = []
var exports: Array[String] = []
## True if the system has at least one place people live and can dock at. Worked
## out from the locations, not stored, so it always agrees with the content.
var inhabited: bool = false
var has_shipyard: bool = false
var has_outfitter: bool = false
## Why the scene is not a valid system, if it is not (empty when fine).
var problems: Array[String] = []


## Reads `scene` by instantiating it without adding it to the tree (so nothing
## in it starts running) and freeing it again.
## `max_objects` is how many objects the system may hold (see SystemClass).
static func from_scene(scene: PackedScene, max_objects: int = StarSystem.MAX_OBJECTS) -> SystemSummary:
	var summary := SystemSummary.new()
	var system := scene.instantiate() as StarSystem
	if system == null:
		summary.problems.append("scene is not a StarSystem")
		return summary
	summary.id = system.system_id
	summary.system_name = system.system_name
	summary.jump_radius = system.jump_radius
	var import_names := {}
	var export_names := {}
	for object in system.get_node("Objects").get_children():
		var data = object.get("data")
		if not data is InhabitedData:
			continue
		var location := data as InhabitedData
		summary.location_ids.append(location.id)
		summary.location_names.append(location.display_name)
		if not location.is_dockable():
			continue
		if location.population > 0:
			summary.inhabited = true
		var economy := EconomyModel.shared().of(location)
		for good in economy.imports():
			import_names[good.display_name] = true
		for good in economy.exports():
			export_names[good.display_name] = true
		summary.has_shipyard = summary.has_shipyard or not location.shipyard_ships.is_empty()
		summary.has_outfitter = summary.has_outfitter or location.has_outfitter()
	summary.imports.assign(import_names.keys())
	summary.exports.assign(export_names.keys())
	summary.imports.sort()
	summary.exports.sort()
	summary.problems = system.validate(max_objects)
	system.free()
	return summary
