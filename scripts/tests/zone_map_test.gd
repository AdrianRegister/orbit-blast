extends SceneTree
## The zone calculation on small made-up jump networks, where every answer is known:
## capital, core, inner and frontier, hubs, dead ends, cut-off systems, and several
## centres of power. Run with:
##   Godot --headless --path . --script res://scripts/tests/zone_map_test.gd </dev/null

const Z := ZoneMap.Zone

var _failures: int = 0
var _rules: ZoneRules


func _init() -> void:
	_rules = load("res://resources/zones/zone_rules.tres")
	_check(_rules != null and _rules.validate().is_empty(), "the zone rules are valid")
	_check(_rules.core_max_hops == 1 and _rules.inner_max_hops == 3, "setup: the default reach is core 1, inner 3 (the tests rely on it)")

	_check_zones()
	_check_links()
	_check_hubs()
	_check_isolation()
	_check_mini_cores()
	_check_rules()
	_check_edges()

	print("")
	print("ZONE MAP TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _graph(edges: Array) -> GalaxyGraph:
	var adjacency := {}
	for edge in edges:
		if not adjacency.has(edge[0]):
			adjacency[edge[0]] = []
		adjacency[edge[0]].append(edge[1])
	return GalaxyGraph.new(adjacency)


func _everyone(_id: StringName) -> bool:
	return true


func _flat(_id: StringName) -> float:
	return 0.0


## The zones for a network where the faction is present everywhere except `absent`.
func _map(graph: GalaxyGraph, centres: Array, capital: StringName = &"", absent: Array = [],
		importance: Callable = Callable(), rules: ZoneRules = null) -> ZoneMap:
	var present := func(id: StringName) -> bool: return not absent.has(id)
	return ZoneMap.compute(graph, present, centres, capital, importance if importance.is_valid() else _flat,
			rules if rules != null else _rules)


func _zone_name(map: ZoneMap, id: StringName) -> String:
	return ZoneMap.ZONE_NAMES[map.zone_of(id)]


func _check_zones() -> void:
	# C is the capital with three neighbours; a chain runs out from one of them.
	var graph := _graph([[&"C", &"a"], [&"C", &"b"], [&"C", &"x"], [&"a", &"a2"], [&"a2", &"a3"], [&"a3", &"a4"], [&"a4", &"a5"]])
	var map := _map(graph, [&"C"], &"C")
	_check(map.zone_of(&"C") == Z.CAPITAL, "the capital is the capital zone")
	for id in [&"a", &"b", &"x"]:
		_check(map.zone_of(id) == Z.CORE, "%s, one jump from the capital, is core" % id)
	_check(map.zone_of(&"a2") == Z.INNER and map.zone_of(&"a3") == Z.INNER, "two and three jumps out is inner territory")
	_check(map.zone_of(&"a4") == Z.FRONTIER and map.zone_of(&"a5") == Z.FRONTIER, "beyond three jumps is frontier")
	_check(map.hops_of(&"a3") == 3 and map.hops_of(&"C") == 0, "hops count jumps from the centre")
	_check(map.region_of(&"a5") == &"C" and map.region_of(&"x") == &"C", "every system belongs to the capital's region")
	_check(map.zone_of(&"nowhere") == Z.NONE and map.region_of(&"nowhere") == &"" and map.hops_of(&"nowhere") == -1, "an unknown system has no zone")


func _check_links() -> void:
	# A dead end capital projects no core: its only neighbour is inner territory.
	var graph := _graph([[&"C", &"a"], [&"a", &"b"], [&"b", &"c"]])
	var map := _map(graph, [&"C"], &"C")
	_check(map.zone_of(&"C") == Z.CAPITAL, "a dead end can still be the capital")
	_check(map.zone_of(&"a") == Z.INNER, "but a centre with too few links projects no core (%s)" % _zone_name(map, &"a"))
	_check(map.zone_of(&"b") == Z.INNER and map.zone_of(&"c") == Z.INNER, "so the whole line is inner territory out to three jumps")


func _check_hubs() -> void:
	# a4 is four jumps out, which would be frontier, but it has many links.
	var edges := [[&"C", &"a"], [&"C", &"b"], [&"a", &"a2"], [&"a2", &"a3"], [&"a3", &"a4"],
			[&"a4", &"l1"], [&"a4", &"l2"], [&"a4", &"l3"], [&"a4", &"l4"]]
	var map := _map(_graph(edges), [&"C"], &"C")
	_check(map.hops_of(&"a4") == 4 and map.zone_of(&"a4") == Z.INNER, "a distant hub is promoted from frontier to inner (%s)" % _zone_name(map, &"a4"))
	_check(map.zone_of(&"l1") == Z.FRONTIER, "its dead end neighbours are not promoted")
	# An inner system that is a hub becomes core.
	var more := edges.duplicate()
	more.append_array([[&"a2", &"h1"], [&"a2", &"h2"]])
	var map2 := _map(_graph(more), [&"C"], &"C")
	_check(map2.zone_of(&"a2") == Z.CORE, "an inner hub is promoted to core (%s)" % _zone_name(map2, &"a2"))
	_check(map2.zone_of(&"C") == Z.CAPITAL, "the capital is never promoted or demoted")
	var off := ZoneRules.new()
	off.hub_promotion_links = 0
	var map3 := _map(_graph(more), [&"C"], &"C", [], Callable(), off)
	_check(map3.zone_of(&"a2") == Z.INNER and map3.zone_of(&"a4") == Z.FRONTIER, "promotion can be turned off")


func _check_isolation() -> void:
	# E is held by someone else, cutting b and c off from the capital.
	var graph := _graph([[&"C", &"a"], [&"C", &"a2"], [&"a", &"E"], [&"E", &"b"], [&"b", &"c"]])
	var map := _map(graph, [&"C"], &"C", [&"E"])
	_check(map.zone_of(&"E") == Z.NONE, "a system the faction is not in has no zone")
	_check(map.zone_of(&"b") == Z.FRONTIER and map.zone_of(&"c") == Z.FRONTIER, "systems cut off from every centre are frontier")
	_check(map.region_of(&"b") == &"" and map.hops_of(&"b") == -1, "and belong to no region")
	_check(map.zone_of(&"a") == Z.CORE, "systems still connected keep their zone")
	# A centre inside the cut-off part makes it a region of its own.
	var with_centre := _map(graph, [&"C", &"b"], &"C", [&"E"])
	_check(with_centre.zone_of(&"b") == Z.CORE and with_centre.region_of(&"c") == &"b", "a centre in the cut-off part gives it its own region")


func _check_mini_cores() -> void:
	# C - a - b - c - d - e - M - m1 : a conquered critical system M far from the capital.
	var edges := [[&"C", &"a"], [&"C", &"s1"], [&"a", &"b"], [&"b", &"c"], [&"c", &"d"], [&"d", &"e"], [&"e", &"M"], [&"M", &"m1"], [&"M", &"m2"]]
	var graph := _graph(edges)
	var alone := _map(graph, [&"C"], &"C")
	_check(alone.zone_of(&"M") == Z.FRONTIER and alone.zone_of(&"m1") == Z.FRONTIER, "without a centre of its own a far system is frontier")
	var both := _map(graph, [&"C", &"M"], &"C")
	_check(both.zone_of(&"M") == Z.CORE, "a second centre of power is core, not capital")
	_check(both.zone_of(&"m1") == Z.CORE and both.zone_of(&"e") == Z.CORE, "its neighbours form a core around it: a mini-core")
	_check(both.region_of(&"m1") == &"M" and both.region_of(&"a") == &"C", "each system belongs to its nearest centre")
	_check(both.hops_of(&"e") == 1 and both.hops_of(&"d") == 2, "hops are counted from the nearest centre")
	_check(both.zone_of(&"d") == Z.INNER, "inner territory grows around the new centre too")
	_check(both.centres == [&"C", &"M"] or both.centres == [&"M", &"C"], "the map lists both centres")
	# Removing the centre takes the mini-core away again.
	var removed := _map(graph, [&"C"], &"C")
	_check(removed.zones == alone.zones, "losing the centre returns the zones to what they were")

	# c is three jumps from C and three from M: the more important centre takes it.
	var c_important := _map(graph, [&"C", &"M"], &"C", [], func(id: StringName) -> float: return 100.0 if id == &"C" else 5.0)
	var m_important := _map(graph, [&"C", &"M"], &"C", [], func(id: StringName) -> float: return 100.0 if id == &"M" else 5.0)
	_check(c_important.region_of(&"c") == &"C", "a system equally near two centres goes to the more important one (capital)")
	_check(m_important.region_of(&"c") == &"M", "and to the other when that is the more important")
	_check(c_important.centres[0] == &"C" and m_important.centres[0] == &"M", "centres are listed most important first")

	# No centre at all: everything the faction holds is frontier.
	var none := _map(graph, [])
	_check(none.zone_of(&"a") == Z.FRONTIER and none.region_of(&"a") == &"", "a faction with no centre has only frontier")


func _check_rules() -> void:
	var graph := _graph([[&"C", &"a"], [&"C", &"b"], [&"a", &"a2"], [&"a2", &"a3"], [&"a3", &"a4"]])
	var wide := ZoneRules.new()
	wide.core_max_hops = 2
	wide.inner_max_hops = 4
	var map := _map(graph, [&"C"], &"C", [], Callable(), wide)
	_check(map.zone_of(&"a2") == Z.CORE and map.zone_of(&"a4") == Z.INNER, "the reach of each zone follows the rules")
	var strict := ZoneRules.new()
	strict.core_requires_links = 5
	var map2 := _map(graph, [&"C"], &"C", [], Callable(), strict)
	_check(map2.zone_of(&"a") == Z.INNER, "the links a centre needs to project a core follow the rules")
	_check(ZoneRules.new().validate().is_empty(), "default rules are valid")
	var bad := ZoneRules.new()
	bad.core_max_hops = 5
	bad.inner_max_hops = 2
	_check(not bad.validate().is_empty(), "rules whose inner reach is shorter than the core are rejected")


func _check_edges() -> void:
	var graph := _graph([[&"C", &"a"], [&"C", &"b"]])
	var map := _map(graph, [&"nowhere"], &"nowhere")
	_check(map.centres.is_empty() and map.zone_of(&"a") == Z.FRONTIER, "a centre that is not in the network is ignored")
	var absent := _map(graph, [&"C"], &"C", [&"C"])
	_check(absent.centres.is_empty() and absent.zone_of(&"C") == Z.NONE, "a centre the faction is not present in is ignored")
	var twice := _map(graph, [&"C", &"C"], &"C")
	_check(twice.zone_of(&"C") == Z.CAPITAL, "a centre listed twice is harmless")
	var map_a := _map(graph, [&"C"], &"C")
	var map_b := _map(graph, [&"C"], &"C")
	_check(map_a.zones == map_b.zones and map_a.regions == map_b.regions, "the same input always gives the same zones")


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
