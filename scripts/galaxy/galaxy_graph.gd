class_name GalaxyGraph
extends RefCounted
## Plain graph analysis of the jump network: how many links a system has, how many
## jumps apart systems are, which are chokepoints, and which carry the most transit.
## It works on an adjacency table, so it can be tested on small made-up networks and
## used with the real galaxy through from_galaxy(). Distances count jumps, never
## map distance.
##
## It is used by validation and the design tools, and by the zone calculation.
## Nothing here changes anything.

## System id -> Array of neighbour ids (every link listed from both ends).
var _adjacency: Dictionary = {}


## `adjacency` maps each system id to its neighbours. A link listed from one end
## only is added to the other.
func _init(adjacency: Dictionary = {}) -> void:
	for id in adjacency:
		_add_node(id)
		for other in adjacency[id]:
			_add_node(other)
			if not _adjacency[id].has(other):
				_adjacency[id].append(other)
			if not _adjacency[other].has(id):
				_adjacency[other].append(id)


static func from_galaxy(galaxy: Galaxy) -> GalaxyGraph:
	var adjacency := {}
	for id in galaxy.get_system_ids():
		adjacency[id] = galaxy.get_neighbours(id)
	return GalaxyGraph.new(adjacency)


func _add_node(id: Variant) -> void:
	if not _adjacency.has(id):
		_adjacency[id] = []


func nodes() -> Array:
	return _adjacency.keys()


func has_node(id: Variant) -> bool:
	return _adjacency.has(id)


func neighbours(id: Variant) -> Array:
	return _adjacency.get(id, [])


## Number of jump links the system has.
func degree(id: Variant) -> int:
	return neighbours(id).size()


## Fewest jumps from the nearest of `sources` to every system reachable from them:
## {id: jumps}. If `allowed` is given (a Callable taking an id and returning
## bool), only systems it accepts are walked through and reported; a source it
## rejects is ignored.
func hops_from(sources: Array, allowed: Callable = Callable()) -> Dictionary:
	var reached := {}
	var queue: Array = []
	for source in sources:
		if _adjacency.has(source) and not reached.has(source) and (not allowed.is_valid() or allowed.call(source)):
			reached[source] = 0
			queue.append(source)
	var head := 0
	while head < queue.size():
		var current = queue[head]
		head += 1
		for other in _adjacency[current]:
			if reached.has(other):
				continue
			if allowed.is_valid() and not allowed.call(other):
				continue
			reached[other] = reached[current] + 1
			queue.append(other)
	return reached


## Connected groups of systems, each an Array of ids.
func components() -> Array:
	var seen := {}
	var result: Array = []
	for id in _adjacency:
		if seen.has(id):
			continue
		var group := hops_from([id]).keys()
		for member in group:
			seen[member] = true
		result.append(group)
	return result


## Systems whose removal would split the network (chokepoints): every route
## between some pair of other systems passes through them.
func articulation_points() -> Array:
	var discovery := {}
	var low := {}
	var found := {}
	var counter := [0]
	for root in _adjacency:
		if not discovery.has(root):
			_visit(root, null, discovery, low, found, counter)
	return found.keys()


func _visit(node: Variant, parent: Variant, discovery: Dictionary, low: Dictionary, found: Dictionary, counter: Array) -> void:
	discovery[node] = counter[0]
	low[node] = counter[0]
	counter[0] += 1
	var children := 0
	for other in _adjacency[node]:
		if not discovery.has(other):
			children += 1
			_visit(other, node, discovery, low, found, counter)
			low[node] = mini(low[node], low[other])
			if parent != null and low[other] >= discovery[node]:
				found[node] = true
		elif other != parent:
			low[node] = mini(low[node], discovery[other])
	if parent == null and children > 1:
		found[node] = true


## How much transit each system carries: for every pair of other systems, the
## share of their shortest routes that pass through it, summed (betweenness
## centrality). A hub joining many routes scores high; a dead end scores 0.
## {id: score}.
func betweenness() -> Dictionary:
	var score := {}
	for id in _adjacency:
		score[id] = 0.0
	for source in _adjacency:
		var stack: Array = []
		var predecessors := {}
		var paths := {}
		var distance := {}
		for id in _adjacency:
			predecessors[id] = []
			paths[id] = 0.0
			distance[id] = -1
		paths[source] = 1.0
		distance[source] = 0
		var queue: Array = [source]
		var head := 0
		while head < queue.size():
			var current = queue[head]
			head += 1
			stack.append(current)
			for other in _adjacency[current]:
				if distance[other] < 0:
					distance[other] = distance[current] + 1
					queue.append(other)
				if distance[other] == distance[current] + 1:
					paths[other] += paths[current]
					predecessors[other].append(current)
		var dependency := {}
		for id in _adjacency:
			dependency[id] = 0.0
		while not stack.is_empty():
			var node = stack.pop_back()
			for pred in predecessors[node]:
				dependency[pred] += (paths[pred] / paths[node]) * (1.0 + dependency[node])
			if node != source:
				score[node] += dependency[node]
	for id in score:
		score[id] /= 2.0  # every pair was counted from both ends
	return score
