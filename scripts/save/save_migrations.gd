class_name SaveMigrations
extends RefCounted
## Brings an older save up to the version this game reads, one step at a time.
##
## To change the save format in a way old saves can't simply do without
## (renaming or restructuring something): raise CURRENT_VERSION by one and add a
## step to _steps() under the OLD version number: a function that takes the
## old document and returns the new one. Adding a new optional field does not
## need a step: readers use defaults for absent optional keys.
##
## A save with a version NEWER than CURRENT_VERSION is refused rather than
## guessed at.

const CURRENT_VERSION := 2


## {old_version: Callable(document: Dictionary) -> Dictionary}
static func _steps() -> Dictionary:
	return {1: _v1_to_v2}


## Version 2 added the fleet. A version 1 save had one ship, named in the
## player section: it becomes the only ship of the fleet, named after its model.
static func _v1_to_v2(document: Dictionary) -> Dictionary:
	var player: Dictionary = document.get("player", {})
	var model: String = str(player.get("ship", "shuttle"))
	player.erase("ship")
	document["fleet"] = {
		"next_id": 2,
		"active": "ship_1",
		"ships": [{"id": "ship_1", "model": model, "name": model.capitalize(), "upgrades": [], "flags": []}],
	}
	return document


## Returns {"ok": bool, "data": Dictionary, "error": String}. `target` and
## `step_table` exist so tests can exercise the mechanism.
static func migrate(data: Dictionary, target: int = CURRENT_VERSION, step_table: Dictionary = {}) -> Dictionary:
	var table: Dictionary = step_table if not step_table.is_empty() else _steps()
	var version = data.get("version")
	if not SaveData.is_int(version) or int(version) < 1:
		return _fail("The save file has no valid version")
	var current := int(version)
	if current > target:
		return _fail("The save was made by a newer version of the game (save version %d, this game reads up to %d)"
				% [current, target])
	var result := data.duplicate(true)
	while current < target:
		if not table.has(current):
			return _fail("The save (version %d) cannot be upgraded" % current)
		result = table[current].call(result)
		current += 1
		result["version"] = current
	return {"ok": true, "data": result, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}
