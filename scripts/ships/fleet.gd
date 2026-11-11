class_name Fleet
extends RefCounted
## Every ship the player owns, and which one is being flown. Pure data and
## queries plus its own save format; ShipManager is the only code that changes
## it during play. Ships the player replaced but kept stay here, flagged
## PREVIOUS_SHIP, so the future hangar/fleet can list them.

const ID_PREFIX := "ship_"

## id -> OwnedShip
var ships: Dictionary = {}
var active_id: StringName = &""
## Number used for the next ship id, so ids are never reused.
var next_id: int = 1


func get_active() -> OwnedShip:
	return ships.get(active_id)


func get_ship(id: StringName) -> OwnedShip:
	return ships.get(id)


## Ships the game shows the player: everything except replaced ships.
func get_visible_ships() -> Array[OwnedShip]:
	var result: Array[OwnedShip] = []
	for ship: OwnedShip in ships.values():
		if not ship.is_previous():
			result.append(ship)
	return result


## Adds a new ship of `model` with a fresh id. It is not made active.
func create_ship(model: ShipStats, ship_name: String) -> OwnedShip:
	var ship := OwnedShip.new()
	ship.id = StringName("%s%d" % [ID_PREFIX, next_id])
	next_id += 1
	ship.model = model
	ship.ship_name = ship_name
	ships[ship.id] = ship
	return ship


func remove(id: StringName) -> void:
	ships.erase(id)


func clear() -> void:
	ships.clear()
	active_id = &""
	next_id = 1


# ------------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var list: Array = []
	for ship: OwnedShip in ships.values():
		var upgrade_ids: Array = []
		for upgrade in ship.upgrades:
			upgrade_ids.append(str(upgrade.id))
		var flag_names: Array = []
		for flag in ship.flags:
			flag_names.append(str(flag))
		list.append({"id": str(ship.id), "model": str(ship.model.id), "name": ship.ship_name,
				"upgrades": upgrade_ids, "flags": flag_names})
	return {"next_id": next_id, "active": str(active_id), "ships": list}


## Problems with saved fleet data; empty when load_state() can use it.
static func validate_state(data: Variant, registry: ContentRegistry) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary:
		return ["fleet is not an object"]
	var list = data.get("ships")
	if not list is Array or list.is_empty():
		return ["fleet has no ships"]
	var seen := {}
	var highest := 0
	for entry in list:
		if not entry is Dictionary:
			problems.append("a fleet entry is not an object")
			continue
		var id = entry.get("id")
		if not SaveData.is_id(id) or not str(id).begins_with(ID_PREFIX) or not str(id).substr(ID_PREFIX.length()).is_valid_int():
			problems.append("a ship has an invalid id")
			continue
		if seen.has(id):
			problems.append("ship id '%s' is used twice" % id)
			continue
		highest = maxi(highest, int(str(id).substr(ID_PREFIX.length())))
		var model: ShipStats = registry.ship_stats(StringName(entry["model"])) if SaveData.is_id(entry.get("model")) else null
		if model == null:
			problems.append("ship '%s' has an unknown model" % id)
		if not entry.get("name") is String or entry["name"].is_empty() or OwnedShip.clean_name(entry["name"]) != entry["name"]:
			problems.append("ship '%s' has an invalid name" % id)
		var flags = entry.get("flags", [])
		if not flags is Array:
			problems.append("ship '%s' flags is not a list" % id)
		var installed: Array[UpgradeDefinition] = []
		var upgrade_ids = entry.get("upgrades")
		if not upgrade_ids is Array:
			problems.append("ship '%s' upgrades is not a list" % id)
		else:
			for upgrade_id in upgrade_ids:
				var upgrade: UpgradeDefinition = registry.upgrade(StringName(upgrade_id)) if SaveData.is_id(upgrade_id) else null
				if upgrade == null:
					problems.append("ship '%s' has an unknown upgrade" % id)
				else:
					installed.append(upgrade)
			problems.append_array(_validate_upgrade_rules(str(id), installed))
		seen[id] = entry
	if not problems.is_empty():
		return problems
	if not SaveData.is_int(data.get("next_id")) or data["next_id"] <= highest:
		problems.append("fleet next_id is not above every ship id")
	var active = data.get("active")
	if not SaveData.is_id(active) or not seen.has(active):
		problems.append("the active ship is not in the fleet")
	elif (seen[active].get("flags", []) as Array).has(str(OwnedShip.FLAG_PREVIOUS_SHIP)):
		problems.append("the active ship is marked as a previous ship")
	return problems


static func _validate_upgrade_rules(ship_id: String, installed: Array[UpgradeDefinition]) -> Array[String]:
	var problems: Array[String] = []
	var counts := {}
	for upgrade in installed:
		counts[upgrade.id] = counts.get(upgrade.id, 0) + 1
		if counts[upgrade.id] > upgrade.max_per_ship:
			problems.append("ship '%s' has too many '%s' upgrades" % [ship_id, upgrade.id])
		if upgrade.category != UpgradeDefinition.Category.CARGO and upgrade.tier > 1:
			var has_lower := false
			for other in installed:
				if other.category == upgrade.category and other.tier == upgrade.tier - 1:
					has_lower = true
			if not has_lower:
				problems.append("ship '%s' has '%s' without the tier below it" % [ship_id, upgrade.id])
	return problems


## Replaces the fleet with validated saved data.
func load_state(data: Dictionary, registry: ContentRegistry) -> void:
	clear()
	for entry in data["ships"]:
		var ship := OwnedShip.new()
		ship.id = StringName(entry["id"])
		ship.model = registry.ship_stats(StringName(entry["model"]))
		ship.ship_name = entry["name"]
		for upgrade_id in entry["upgrades"]:
			ship.upgrades.append(registry.upgrade(StringName(upgrade_id)))
		for flag in entry.get("flags", []):
			ship.flags.append(StringName(flag))
		ships[ship.id] = ship
	active_id = StringName(data["active"])
	next_id = int(data["next_id"])
