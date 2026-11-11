class_name Galaxy
extends Resource
## The whole galaxy as static data: which star systems exist, where they sit on
## the galaxy map, and which are connected by jump links. One resource,
## resources/universe/galaxy.tres. It holds no player state (what is discovered
## lives in TravelManager) and never copies a system's id or name: those are read
## from the system scenes themselves the first time they are needed.
##
## To add a system: make its scene, add a GalaxySystem for it and a SystemLink
## (or several) in galaxy.tres. Nothing else needs to change.

@export var systems: Array[GalaxySystem] = []
@export var links: Array[SystemLink] = []
## Jump cost per map unit of distance, for links that do not set their own cost.
@export var fuel_per_unit: float = 0.1

var _by_id: Dictionary = {}  # StringName -> GalaxySystem
var _summaries: Dictionary = {}  # StringName -> SystemSummary
var _location_system: Dictionary = {}  # location id -> system id
var _entries: Array[Dictionary] = []  # {"system", "summary"} for every listed system
var _link_by_pair: Dictionary = {}  # "a|b" (sorted) -> SystemLink
var _neighbour_ids: Dictionary = {}  # system id -> Array[StringName]
var _indexed_link_count: int = -1
var _indexed: bool = false


# ------------------------------------------------------------------ systems

func has_system(id: StringName) -> bool:
	_ensure_index()
	return _by_id.has(id)


## All system ids, in the order they are listed.
func get_system_ids() -> Array[StringName]:
	_ensure_index()
	var ids: Array[StringName] = []
	for entry in _entries:
		if not ids.has(entry["summary"].id) and entry["summary"].id != &"":
			ids.append(entry["summary"].id)
	return ids


func get_scene(id: StringName) -> PackedScene:
	_ensure_index()
	var system: GalaxySystem = _by_id.get(id)
	return system.scene if system != null else null


func get_map_position(id: StringName) -> Vector2:
	_ensure_index()
	var system: GalaxySystem = _by_id.get(id)
	return system.map_position if system != null else Vector2.ZERO


## The faction a system is claimed by on the map, or null. This is NOT who owns
## the system's settlements or controls it: ask the TerritoryManager
## (get_control) for that.
func get_claim(id: StringName) -> Faction:
	_ensure_index()
	var system: GalaxySystem = _by_id.get(id)
	return system.claim if system != null else null


func is_start_discovered(id: StringName) -> bool:
	_ensure_index()
	var system: GalaxySystem = _by_id.get(id)
	return system != null and system.start_discovered


## A description of the system for the map, whether or not it is loaded. Built
## once and kept. Null for an unknown id.
func get_summary(id: StringName) -> SystemSummary:
	_ensure_index()
	return _summaries.get(id)


## The system that contains the location with this id, or &"" if none does.
func system_of_location(location_id: StringName) -> StringName:
	_ensure_index()
	return _location_system.get(location_id, &"")


## Whether people live in the system (see SystemSummary.inhabited).
func is_inhabited(id: StringName) -> bool:
	var summary := get_summary(id)
	return summary != null and summary.inhabited


# -------------------------------------------------------------------- links

## The cheapest chain of systems from `a` to `b` along the links, both ends
## included ([a] if they are the same system), or an empty array if there is no
## way. Cost is the links' jump costs, so a short fuel route beats a short hop count.
func find_route(a: StringName, b: StringName) -> Array[StringName]:
	var route: Array[StringName] = []
	if not has_system(a) or not has_system(b):
		return route
	var best := {a: 0}
	var came_from := {}
	var open: Array[StringName] = [a]
	while not open.is_empty():
		var current: StringName = open[0]
		for candidate in open:
			if best[candidate] < best[current]:
				current = candidate
		open.erase(current)
		if current == b:
			break
		for neighbour in get_neighbours(current):
			var cost: int = best[current] + get_jump_cost(current, neighbour)
			if not best.has(neighbour) or cost < best[neighbour]:
				best[neighbour] = cost
				came_from[neighbour] = current
				open.append(neighbour)
	if not best.has(b):
		return route
	var step: StringName = b
	route.append(step)
	while step != a:
		step = came_from[step]
		route.push_front(step)
	return route


## Total jump cost along a route from find_route() (0 for none or a single system).
func get_route_cost(route: Array[StringName]) -> int:
	var total := 0
	for i in range(1, route.size()):
		total += get_jump_cost(route[i - 1], route[i])
	return total

func are_connected(a: StringName, b: StringName) -> bool:
	return _find_link(a, b) != null


## Ids of the systems directly linked to `id`.
func get_neighbours(id: StringName) -> Array[StringName]:
	_ensure_links()
	var result: Array[StringName] = []
	result.assign(_neighbour_ids.get(id, []))
	return result


## Every system within `max_jumps` jumps of `origin` (counting the fewest jumps,
## not the cheapest route): {system id: jumps}, including the origin at 0. One
## breadth-first search, so it stays fast however big the galaxy is.
func get_reachable(origin: StringName, max_jumps: int) -> Dictionary:
	_ensure_links()
	var reached := {}
	if not _by_id.has(origin):
		return reached
	reached[origin] = 0
	var queue: Array[StringName] = [origin]
	var head := 0
	while head < queue.size():
		var current: StringName = queue[head]
		head += 1
		if reached[current] >= max_jumps:
			continue
		for neighbour in _neighbour_ids.get(current, []):
			if not reached.has(neighbour):
				reached[neighbour] = reached[current] + 1
				queue.append(neighbour)
	return reached


## Fuel needed to jump between two connected systems: the link's own cost if it
## has one, otherwise the map distance times fuel_per_unit (at least 1). -1 if
## the systems are not connected.
func get_jump_cost(a: StringName, b: StringName) -> int:
	var link := _find_link(a, b)
	if link == null:
		return -1
	if link.fuel_cost > 0:
		return link.fuel_cost
	return maxi(1, ceili(get_map_position(a).distance_to(get_map_position(b)) * fuel_per_unit))


# --------------------------------------------------------------- validation

## Human-readable problems with the galaxy data; empty when it is sound.
func validate() -> Array[String]:
	var problems: Array[String] = []
	_ensure_index()
	var seen := {}
	for system in systems:
		if system == null or system.scene == null:
			problems.append("a galaxy system has no scene")
	for entry in _entries:
		var summary: SystemSummary = entry["summary"]
		for problem in summary.problems:
			problems.append("system '%s': %s" % [summary.id, problem])
		if summary.id == &"":
			problems.append("a system scene has no system_id")
		elif seen.has(summary.id):
			problems.append("system id '%s' is used twice" % summary.id)
		seen[summary.id] = true
	var pairs := {}
	for link in links:
		if link == null:
			problems.append("links has an empty entry")
			continue
		if not seen.has(link.a) or not seen.has(link.b):
			problems.append("link %s - %s refers to an unknown system" % [link.a, link.b])
			continue
		if link.a == link.b:
			problems.append("system '%s' is linked to itself" % link.a)
		var key := "%s|%s" % [link.a, link.b] if str(link.a) < str(link.b) else "%s|%s" % [link.b, link.a]
		if pairs.has(key):
			problems.append("link %s - %s is listed twice" % [link.a, link.b])
		pairs[key] = true
		if link.fuel_cost < 0:
			problems.append("link %s - %s has a negative fuel cost" % [link.a, link.b])
	var ids := get_system_ids()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			if get_map_position(ids[i]).distance_to(get_map_position(ids[j])) < 1.0:
				problems.append("systems '%s' and '%s' share a map position" % [ids[i], ids[j]])
	if not ids.is_empty():
		var reachable := _reachable_from(ids[0])
		for id in ids:
			if not reachable.has(id):
				problems.append("system '%s' cannot be reached from '%s'" % [id, ids[0]])
	return problems


# ------------------------------------------------------------------ helpers

func _pair_key(a: StringName, b: StringName) -> String:
	return "%s|%s" % [a, b] if str(a) < str(b) else "%s|%s" % [b, a]


func _find_link(a: StringName, b: StringName) -> SystemLink:
	_ensure_links()
	return _link_by_pair.get(_pair_key(a, b))


func _reachable_from(start: StringName) -> Dictionary:
	var reached := {start: true}
	var queue: Array[StringName] = [start]
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		for neighbour in get_neighbours(current):
			if not reached.has(neighbour):
				reached[neighbour] = true
				queue.append(neighbour)
	return reached


## Reads each system scene once to learn its id, name and locations.
func _ensure_index() -> void:
	if _indexed:
		return
	_indexed = true
	for system in systems:
		if system == null or system.scene == null:
			continue
		var summary := SystemSummary.from_scene(system.scene)
		_entries.append({"system": system, "summary": summary})
		if summary.id == &"" or _by_id.has(summary.id):
			continue  # reported by validate(); the first system with an id wins
		_by_id[summary.id] = system
		_summaries[summary.id] = summary
		for location_id in summary.location_ids:
			_location_system[location_id] = summary.id
	_index_links()


## Rebuilds the link lookups if links were added or removed since they were built.
func _ensure_links() -> void:
	_ensure_index()
	if _indexed_link_count != links.size():
		_index_links()


func _index_links() -> void:
	_link_by_pair.clear()
	_neighbour_ids.clear()
	_indexed_link_count = links.size()
	for link in links:
		if link == null:
			continue
		_link_by_pair[_pair_key(link.a, link.b)] = link
		if not _neighbour_ids.has(link.a):
			_neighbour_ids[link.a] = []
		if not _neighbour_ids.has(link.b):
			_neighbour_ids[link.b] = []
		_neighbour_ids[link.a].append(link.b)
		_neighbour_ids[link.b].append(link.a)
