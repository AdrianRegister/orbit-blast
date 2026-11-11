class_name TravelManager
extends Node
## The rules of travelling between star systems and the player's record of
## which systems are discovered. It does not touch scenes: Main asks it whether
## a jump is allowed and then does the loading. Discovery lives here, apart from
## any map drawing, so exploration contracts can later call discover().
##
## The current system is not stored here (the loaded StarSystem is the single
## source); it is read through a provider function. The "galaxy" save section
## holds only the discovered systems.

## A system was discovered for the first time.
signal system_discovered(system_id: StringName)
## The set of discovered systems changed in any way (including a load).
signal discovery_changed
## The selected jump destination changed (or was cleared).
signal destination_changed

var _galaxy: Galaxy
## Returns the id of the system the player is in.
var _current_provider: Callable
var _discovered: Dictionary = {}  # StringName -> true
## The system chosen on the galaxy map as the next jump, or &"" for none. The
## navicomputer works towards it; J jumps to it.
var _destination: StringName = &""


func setup(galaxy: Galaxy, current_provider: Callable) -> void:
	_galaxy = galaxy
	_current_provider = current_provider
	reset_state()


func get_galaxy() -> Galaxy:
	return _galaxy


func get_current_id() -> StringName:
	return _current_provider.call() if _current_provider.is_valid() else &""


# ---------------------------------------------------------------- discovery

func is_discovered(system_id: StringName) -> bool:
	return _discovered.has(system_id)


func get_discovered() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_discovered.keys())
	return result


## Marks a system as discovered. True if it was new.
func discover(system_id: StringName) -> bool:
	if not _galaxy.has_system(system_id) or _discovered.has(system_id):
		return false
	_discovered[system_id] = true
	system_discovered.emit(system_id)
	discovery_changed.emit()
	return true


# -------------------------------------------------------------- destination

func get_destination() -> StringName:
	return _destination


## Chooses the next jump destination. It must be linked to the current system.
## False (nothing changed) if it is not.
func set_destination(system_id: StringName) -> bool:
	if not _galaxy.are_connected(get_current_id(), system_id):
		return false
	if _destination != system_id:
		_destination = system_id
		destination_changed.emit()
	return true


func clear_destination() -> void:
	if _destination != &"":
		_destination = &""
		destination_changed.emit()


# ------------------------------------------------------------------ jumping

## Whether the player may jump to `target_id` now. `distance_from_centre` is how
## far the ship is from the middle of the current system and `docked` whether
## the player is docked. Changes nothing.
func check_jump(target_id: StringName, distance_from_centre: float, docked: bool) -> JumpCheck:
	var check := JumpCheck.new()
	var current := get_current_id()
	check.distance = distance_from_centre
	if not _galaxy.has_system(target_id):
		check.reason = "Unknown system."
		return check
	if target_id == current:
		check.reason = "You are already in this system."
		return check
	var target_name := _galaxy.get_summary(target_id).system_name
	if not _galaxy.are_connected(current, target_id):
		check.reason = "There is no jump route from %s to %s." % [_name_of(current), target_name]
		return check
	check.reachable = true
	check.cost = _galaxy.get_jump_cost(current, target_id)
	check.required_distance = _galaxy.get_summary(current).jump_radius
	if docked:
		check.reason = "Depart before jumping."
	elif distance_from_centre < check.required_distance:
		check.reason = "Too close to the system centre (%s of %s px)." % [
				NumberFormat.with_commas(roundi(distance_from_centre)), NumberFormat.with_commas(roundi(check.required_distance))]
	elif not _has_fuel(check.cost):
		check.reason = "Not enough fuel (%d needed)." % check.cost
	else:
		check.ok = true
	return check


func _name_of(system_id: StringName) -> String:
	var summary := _galaxy.get_summary(system_id)
	return summary.system_name if summary != null else str(system_id)


## Where fuel will be checked once ships have fuel. Always enough for now; the
## jump cost is already worked out and shown.
func _has_fuel(_cost: int) -> bool:
	return true


# ------------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var ids: Array = []
	for id in _discovered:
		ids.append(str(id))
	ids.sort()
	return {"discovered": ids, "destination": str(_destination)}


func validate_state(data: Variant, registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary or not data.get("discovered") is Array:
		return ["galaxy discovered is not a list"]
	for id in data["discovered"]:
		if not SaveData.is_id(id) or not registry.has_system(StringName(id)):
			problems.append("discovered system '%s' does not exist" % id)
	var destination = data.get("destination", "")
	if not destination is String or (destination != "" and not registry.has_system(StringName(destination))):
		problems.append("the selected destination does not exist")
	return problems


## Replaces the discovered set with validated saved data. The system the player
## is in is always discovered.
func load_state(data: Dictionary, _registry: ContentRegistry) -> void:
	_discovered.clear()
	for id in data["discovered"]:
		_discovered[StringName(id)] = true
	_discovered[get_current_id()] = true
	_destination = &""
	set_destination(StringName(data.get("destination", "")))  # dropped if not linked to where we are
	discovery_changed.emit()
	destination_changed.emit()


## Used when a save has no galaxy section (saves from before the map existed):
## the starting systems plus the one the player is in.
func reset_state() -> void:
	_discovered.clear()
	for id in _galaxy.get_system_ids():
		if _galaxy.is_start_discovered(id):
			_discovered[id] = true
	var current := get_current_id()
	if current != &"":
		_discovered[current] = true
	_destination = &""
	discovery_changed.emit()
	destination_changed.emit()
