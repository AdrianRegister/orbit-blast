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
## The player has been within docking range of every body in a system for the
## first time: it is now scouted. Not emitted when a save is loaded.
signal system_scouted(system_id: StringName)
## The set of scouted bodies changed (a new body reached, or a load).
signal scouting_changed

var _galaxy: Galaxy
## Returns the id of the system the player is in.
var _current_provider: Callable
var _discovered: Dictionary = {}  # StringName -> true
## The system chosen on the galaxy map as the next jump, or &"" for none. The
## navicomputer works towards it; J jumps to it.
var _destination: StringName = &""
## system id -> {location id: true}: the bodies (planets, moons, gas giants,
## stations) the player has been within docking range of. A system is scouted
## when it has all of them.
var _scouted_nodes: Dictionary = {}


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


# ----------------------------------------------------------------- scouting

## (bodies reached, bodies in the system) for a system.
func get_scouting_progress(system_id: StringName) -> Vector2i:
	var summary := _galaxy.get_summary(system_id)
	if summary == null:
		return Vector2i.ZERO
	return Vector2i(_scouted_nodes.get(system_id, {}).size(), summary.location_ids.size())


## True once every body of the system has been reached.
func is_scouted(system_id: StringName) -> bool:
	var progress := get_scouting_progress(system_id)
	return progress.y > 0 and progress.x >= progress.y


## Records the bodies of the loaded `system` that `position` is within docking
## range of. Only a discovered system can be scouted. Called every frame by Main
## while the ship is flying; announces `system_scouted` when the last body is
## reached.
func update_scouting(system: StarSystem, position: Vector2) -> void:
	var system_id := system.system_id
	if not is_discovered(system_id) or is_scouted(system_id):
		return
	var found := false
	for node in system.get_inhabited_nodes():
		if node.data == null:
			continue
		var reached: Dictionary = _scouted_nodes.get_or_add(system_id, {})
		if not reached.has(node.data.id) and position.distance_to(node.global_position) <= node.get_dock_range():
			reached[node.data.id] = true
			found = true
	if not found:
		return
	scouting_changed.emit()
	if is_scouted(system_id):
		system_scouted.emit(system_id)


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
	var scouted := {}
	for system_id in _scouted_nodes:
		var nodes: Array = []
		for location_id in _scouted_nodes[system_id]:
			nodes.append(str(location_id))
		nodes.sort()
		scouted[str(system_id)] = nodes
	return {"discovered": ids, "destination": str(_destination), "scouted_nodes": scouted}


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
	var scouted = data.get("scouted_nodes", {})
	if not scouted is Dictionary:
		problems.append("scouted_nodes is not an object")
	else:
		for system_id in scouted:
			var summary := _galaxy.get_summary(StringName(system_id))
			if summary == null:
				problems.append("scouted system '%s' does not exist" % system_id)
			elif not scouted[system_id] is Array:
				problems.append("scouted bodies of '%s' are not a list" % system_id)
			else:
				for location_id in scouted[system_id]:
					if not SaveData.is_id(location_id) or not summary.location_ids.has(StringName(location_id)):
						problems.append("'%s' is not a body of system '%s'" % [location_id, system_id])
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
	_scouted_nodes.clear()
	for system_id in data.get("scouted_nodes", {}):
		var reached := {}
		for location_id in data["scouted_nodes"][system_id]:
			reached[StringName(location_id)] = true
		_scouted_nodes[StringName(system_id)] = reached
	discovery_changed.emit()
	destination_changed.emit()
	scouting_changed.emit()


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
	_scouted_nodes.clear()
	discovery_changed.emit()
	destination_changed.emit()
	scouting_changed.emit()
