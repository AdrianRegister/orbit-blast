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
## Where it must be completed.
var destination: InhabitedData
## Credits paid on completion.
var reward: int = 0
var status: Status = Status.AVAILABLE


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
		"destination": str(destination.id),
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
	for key in ["origin", "destination"]:
		if not SaveData.is_id(data.get(key)) or registry.location(StringName(data[key])) == null:
			problems.append("contract %s is not a known location" % key)
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
	destination = registry.location(StringName(data["destination"]))
	reward = int(data["reward"])
	status = Status[data["status"]]
