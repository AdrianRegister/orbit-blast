class_name ExplorationContract
extends Contract
## Scout a star system: enter it and come within docking range of every body in
## it (planets, moons, gas giants, stations). The ContractManager completes it
## when the TravelManager announces the system scouted; merely selecting or
## viewing the system on the galaxy map does nothing.

## Id of the system to scout.
var target_system: StringName = &""
## The system has been scouted, with this contract accepted. The job is done but
## the reward is only paid on returning to the issuer, like a delivery.
var explored: bool = false


func get_type_label() -> String:
	return "EXPLORATION"


func requires_destination() -> bool:
	return false


func get_destination_text() -> String:
	return _target_name()


## Nothing left to point at on the map once the system has been scouted.
func get_target_system() -> StringName:
	return &"" if explored else target_system


func get_requirement_text() -> String:
	return "Scout %s" % _target_name()


func get_journey_text() -> String:
	if context == null:
		return ""
	return context.journey_text(_journey_start(), target_system)


func get_progress_text() -> String:
	if context == null or context.travel == null:
		return ""
	match status:
		Status.AVAILABLE:
			return "Scout every body in %s" % _target_name()
		Status.ACCEPTED:
			if explored:
				return "Scouted %s. Return to %s to collect your reward" % [_target_name(), origin.display_name]
			var progress := context.travel.get_scouting_progress(target_system)
			if context.travel.is_discovered(target_system):
				return "Scouted %d of %d bodies in %s" % [progress.x, progress.y, _target_name()]
			return "Travel to %s and fly close to everything in it" % _target_name()
		Status.COMPLETED:
			return "Scouted %s" % _target_name()
	return ""


func _target_name() -> String:
	return context.system_name(target_system) if context != null else str(target_system)


func get_type_id() -> StringName:
	return &"exploration"


func to_dict() -> Dictionary:
	var data := super()
	data["target_system"] = str(target_system)
	data["explored"] = explored
	return data


func validate_dict(data: Dictionary, registry: ContentRegistry) -> Array[String]:
	var problems := super(data, registry)
	if not SaveData.is_id(data.get("target_system")) or not registry.has_system(StringName(data["target_system"])):
		problems.append("exploration target is not a known star system")
	if data.has("explored") and not data["explored"] is bool:
		problems.append("exploration 'explored' flag is not true or false")
	return problems


func load_dict(data: Dictionary, registry: ContentRegistry) -> void:
	super(data, registry)
	target_system = StringName(data["target_system"])
	explored = data.get("explored", false)
