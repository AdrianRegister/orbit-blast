class_name ZoneMap
extends RefCounted
## The zones of one faction: for each system where the faction is present, whether it
## is the capital, core, inner territory or frontier, and which centre of power it
## belongs to. A pure calculation on a jump graph (plain ids and Callables, no
## game objects), so it is tested on small made-up networks. ZoneManager feeds it the
## real galaxy.
##
## From every centre of power a search spreads out over the systems the faction is
## present in, one jump at a time. A system takes the nearest centre as its region (a
## tie goes to the more important centre) and its zone from the number of jumps:
##   0 jumps       CAPITAL for the capital, CORE for any other centre
##   1..core_max   CORE (only if the centre has enough links to project a core)
##   up to inner_max  INNER
##   beyond, or cut off from every centre   FRONTIER
## A system with many links is then promoted one step (hub_promotion_links). Systems
## where the faction is not present have no zone.

enum Zone { NONE, CAPITAL, CORE, INNER, FRONTIER }

const ZONE_NAMES := ["NONE", "CAPITAL", "CORE", "INNER", "FRONTIER"]

## System id -> Zone, for the systems the faction is present in.
var zones: Dictionary = {}
## System id -> the centre of power it belongs to (&"" if it is cut off from them all).
var regions: Dictionary = {}
## System id -> jumps from its centre (-1 if cut off).
var hops: Dictionary = {}
## The centres this map was drawn from, most important first.
var centres: Array = []


func zone_of(system_id: StringName) -> Zone:
	return zones.get(system_id, Zone.NONE)


func region_of(system_id: StringName) -> StringName:
	return regions.get(system_id, &"")


func hops_of(system_id: StringName) -> int:
	return hops.get(system_id, -1)


## Draws the zones.
##   graph       the jump network.
##   present     Callable(id) -> bool: whether the faction is in that system (owns a
##               settlement there). The search only walks through such systems.
##   centres     the ids of the centres of power (each must be present).
##   capital     the id of the capital, or &"" for none (it must also be a centre).
##   importance  Callable(id) -> float, to break ties between centres.
static func compute(graph: GalaxyGraph, present: Callable, centres_of_power: Array, capital: StringName,
		importance: Callable, rules: ZoneRules) -> ZoneMap:
	var map := ZoneMap.new()
	var sources: Array = []
	for id in centres_of_power:
		if graph.has_node(id) and present.call(id):
			sources.append(id)
	sources.sort_custom(func(a, b) -> bool:
		var ia: float = importance.call(a)
		var ib: float = importance.call(b)
		if ia != ib:
			return ia > ib
		return str(a) < str(b))
	map.centres = sources

	# Spread from every centre at once; sources are queued most important first, so
	# a system equally near two centres is taken by the more important one.
	var queue: Array = []
	for source in sources:
		map.regions[source] = source
		map.hops[source] = 0
		queue.append(source)
	var head := 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		for other in graph.neighbours(current):
			if map.regions.has(other) or not present.call(other):
				continue
			map.regions[other] = map.regions[current]
			map.hops[other] = map.hops[current] + 1
			queue.append(other)

	for id in graph.nodes():
		if not present.call(id):
			continue
		if not map.regions.has(id):
			map.regions[id] = &""
			map.hops[id] = -1
			map.zones[id] = Zone.FRONTIER  # cut off from every centre of power
			continue
		var distance: int = map.hops[id]
		var centre: StringName = map.regions[id]
		var zone: Zone
		if distance == 0:
			zone = Zone.CAPITAL if id == capital else Zone.CORE
		elif distance <= rules.core_max_hops and graph.degree(centre) >= rules.core_requires_links:
			zone = Zone.CORE
		elif distance <= rules.inner_max_hops:
			zone = Zone.INNER
		else:
			zone = Zone.FRONTIER
		if distance > 0 and rules.hub_promotion_links > 0 and graph.degree(id) >= rules.hub_promotion_links:
			if zone == Zone.FRONTIER:
				zone = Zone.INNER
			elif zone == Zone.INNER:
				zone = Zone.CORE
		map.zones[id] = zone
	return map
