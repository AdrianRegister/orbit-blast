class_name Contract
extends RefCounted
## One mission offered to or accepted by the player (runtime data, not saved
## data). This is the base for every mission type: the mission computer only
## uses what is declared here, so a combat or exploration contract can be added
## later as another subclass without changing the interface.
##
## Created by a ContractSource; its id and status are managed by the
## ContractManager. Each type saves itself with to_dict() and is recreated by
## the ContractFactory.

enum Status { AVAILABLE, ACCEPTED, COMPLETED, FAILED }

## Unique within the session. Assigned by the ContractManager.
var id: StringName = &""
var title: String = ""
var description: String = ""
## The location that issues the contract.
var origin: InhabitedData
## Where it must be completed. Null for contracts that are not about a
## place to go to (exploration).
var destination: InhabitedData
## Credits paid on completion.
var reward: int = 0
var status: Status = Status.AVAILABLE
## What the contract can ask the world about (routes, scouting). Set by the
## ContractManager when the contract is created or loaded.
var context: ContractContext


## Short name of the contract type for lists, e.g. "CARGO".
func get_type_label() -> String:
	return ""


## Whether this type always has a destination location (and saves one).
func requires_destination() -> bool:
	return true


## Where the contract is issued: "Earth, Sol".
func get_origin_text() -> String:
	return _place_text(origin)


## Where to go: "Mars, Sol" (a location and its system), or the target system.
func get_destination_text() -> String:
	return _place_text(destination)


## What the journey involves from where the player stands (or, before accepting,
## from the issuer): "Sol > Sirius: 1 jump, 21 fuel".
func get_journey_text() -> String:
	return ""


## The system the player should travel to, or &"" if the contract has none.
## The galaxy map marks it.
func get_target_system() -> StringName:
	return context.system_of(destination) if context != null and destination != null else &""


## The system the journey is measured from: where the issuer is while the
## contract is on offer, where the player is once it has been accepted.
func _journey_start() -> StringName:
	if status == Status.AVAILABLE or context == null:
		return context.system_of(origin) if context != null else &""
	return context.current_system.call()


func _place_text(location: InhabitedData) -> String:
	if location == null:
		return ""
	if context == null:
		return location.display_name
	var system_name := context.system_name(context.system_of(location))
	return "%s, %s" % [location.display_name, system_name] if not system_name.is_empty() else location.display_name


## What the contract asks for, e.g. "50 Food".
func get_requirement_text() -> String:
	return ""


## Where the player stands with it, e.g. "In hold: 50 / 50".
func get_progress_text() -> String:
	return ""


func get_status_text() -> String:
	return Status.keys()[status]


## The permanent name of this contract type in save files.
func get_type_id() -> StringName:
	return &""


## Plain data for the save file. Subclasses add their own fields.
func to_dict() -> Dictionary:
	return {
		"type": str(get_type_id()),
		"id": str(id),
		"title": title,
		"description": description,
		"origin": str(origin.id),
		"destination": str(destination.id) if destination != null else "",
		"reward": reward,
		"status": get_status_text(),
	}


## Problems with saved data for this type; empty when load_dict() can use it.
func validate_dict(data: Dictionary, registry: ContentRegistry) -> Array[String]:
	var problems: Array[String] = []
	if not SaveData.is_id(data.get("id")):
		problems.append("contract has no id")
	if not data.get("title") is String:
		problems.append("contract title is not text")
	if not data.get("description") is String:
		problems.append("contract description is not text")
	if not SaveData.is_id(data.get("origin")) or registry.location(StringName(data["origin"])) == null:
		problems.append("contract origin is not a known location")
	var destination_id = data.get("destination", "")
	if requires_destination() or destination_id != "":
		if not SaveData.is_id(destination_id) or registry.location(StringName(destination_id)) == null:
			problems.append("contract destination is not a known location")
	if not SaveData.is_int(data.get("reward")) or data["reward"] < 0:
		problems.append("contract reward is not a non-negative whole number")
	if not data.get("status") is String or not Status.has(data["status"]):
		problems.append("contract status is not valid")
	return problems


## Fills this contract from data that passed validate_dict().
func load_dict(data: Dictionary, registry: ContentRegistry) -> void:
	id = StringName(data["id"])
	title = data["title"]
	description = data["description"]
	origin = registry.location(StringName(data["origin"]))
	var destination_id: String = data.get("destination", "")
	destination = registry.location(StringName(destination_id)) if destination_id != "" else null
	reward = int(data["reward"])
	status = Status[data["status"]]
