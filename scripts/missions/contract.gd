class_name Contract
extends RefCounted
## One mission offered to or accepted by the player (runtime data, not saved
## data). This is the base for every mission type: the mission computer only
## uses what is declared here, so a combat or exploration contract can be added
## later as another subclass without changing the interface.
##
## Created by a ContractSource; its id and status are managed by the
## ContractManager.

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
