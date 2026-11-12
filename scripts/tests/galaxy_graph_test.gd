extends SceneTree
## Graph analysis of the jump network, on small made-up networks (so the answers
## are known) and on the real galaxy (checked against the galaxy itself, never
## against a remembered layout). Run with:
##   Godot --headless --path . --script res://scripts/tests/galaxy_graph_test.gd </dev/null

var _failures: int = 0


func _init() -> void:
	_check_path()
	_check_star()
	_check_cycle()
	_check_filters()
	_check_components()
	_check_galaxy()

	print("")
	print("GALAXY GRAPH TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


func _sorted(values: Array) -> Array:
	var copy := values.duplicate()
	copy.sort_custom(func(a, b) -> bool: return str(a) < str(b))
	return copy


func _check_path() -> void:
	# a - b - c - d. A link listed from one end only still joins both.
	var graph := GalaxyGraph.new({&"a": [&"b"], &"b": [&"c"], &"c": [&"d"]})
	_check(graph.degree(&"a") == 1 and graph.degree(&"b") == 2, "degree counts the links, whichever end lists them")
	_check(graph.neighbours(&"b").has(&"a") and graph.neighbours(&"b").has(&"c"), "links run both ways")
	var hops := graph.hops_from([&"a"])
	_check(hops == {&"a": 0, &"b": 1, &"c": 2, &"d": 3}, "hops count jumps along a path: %s" % [hops])
	_check(_sorted(graph.articulation_points()) == [&"b", &"c"], "the middle of a path are chokepoints: %s" % [graph.articulation_points()])
	var between := graph.betweenness()
	_check(is_equal_approx(between[&"b"], 2.0) and is_equal_approx(between[&"c"], 2.0), "the middle of a path carries two pairs each")
	_check(between[&"a"] == 0.0 and between[&"d"] == 0.0, "the ends of a path carry no transit")


func _check_star() -> void:
	var graph := GalaxyGraph.new({&"hub": [&"a", &"b", &"c", &"d"]})
	_check(graph.degree(&"hub") == 4, "a hub has a link to each leaf")
	_check(graph.articulation_points() == [&"hub"], "a hub is a chokepoint")
	_check(is_equal_approx(graph.betweenness()[&"hub"], 6.0), "a hub of four leaves carries all six leaf pairs")
	_check(graph.hops_from([&"a"])[&"d"] == 2, "leaves are two jumps apart through the hub")


func _check_cycle() -> void:
	var graph := GalaxyGraph.new({&"a": [&"b"], &"b": [&"c"], &"c": [&"d"], &"d": [&"a"]})
	_check(graph.articulation_points().is_empty(), "a ring has no chokepoints")
	var between := graph.betweenness()
	var even := true
	for id in between:
		even = even and is_equal_approx(between[id], 0.5)
	_check(even, "every system of a ring of four carries half a pair")


func _check_filters() -> void:
	var graph := GalaxyGraph.new({&"a": [&"b"], &"b": [&"c"], &"c": [&"d"]})
	var not_b := func(id: StringName) -> bool: return id != &"b"
	_check(graph.hops_from([&"a"], not_b) == {&"a": 0}, "a blocked system cannot be walked through")
	_check(graph.hops_from([&"c"], not_b) == {&"c": 0, &"d": 1}, "walking stops at the blocked system")
	_check(graph.hops_from([&"b"], not_b).is_empty(), "a blocked source is ignored")
	var both := graph.hops_from([&"a", &"d"])
	_check(both[&"b"] == 1 and both[&"c"] == 1, "several sources: each system takes its nearest")
	_check(graph.hops_from([&"nowhere"]).is_empty(), "an unknown source reaches nothing")


func _check_components() -> void:
	var graph := GalaxyGraph.new({&"a": [&"b"], &"c": [&"d"], &"e": []})
	_check(graph.components().size() == 3, "separate groups are separate components (%d)" % graph.components().size())
	_check(not graph.hops_from([&"a"]).has(&"c"), "unconnected systems are unreachable")
	# A triangle with a tail: the join is a chokepoint, the triangle corners are not.
	var lollipop := GalaxyGraph.new({&"a": [&"b", &"c"], &"b": [&"c"], &"c": [&"d"]})
	_check(lollipop.articulation_points() == [&"c"], "the system joining a tail to a ring is the chokepoint")


func _check_galaxy() -> void:
	var galaxy: Galaxy = load("res://resources/universe/galaxy.tres")
	var graph := GalaxyGraph.from_galaxy(galaxy)
	var ids := galaxy.get_system_ids()
	_check(graph.nodes().size() == ids.size(), "the graph holds every system (%d)" % ids.size())
	var same := true
	var symmetric := true
	for id in ids:
		same = same and graph.degree(id) == galaxy.get_neighbours(id).size()
		for other in graph.neighbours(id):
			symmetric = symmetric and graph.neighbours(other).has(id)
	_check(same, "each system's degree is its number of galaxy links")
	_check(symmetric, "every link is listed from both ends")
	_check(graph.components().size() == 1, "the galaxy is one connected network")
	var from_first := graph.hops_from([ids[0]])
	var reachable := galaxy.get_reachable(ids[0], 1000)
	_check(from_first == reachable, "hops agree with the galaxy's own breadth first search")
	var between := graph.betweenness()
	var points := graph.articulation_points()
	var consistent := true
	for id in ids:
		if graph.degree(id) == 1:
			consistent = consistent and between[id] == 0.0 and not points.has(id)
	_check(consistent, "dead ends carry no transit and are never chokepoints")


func _check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  "), label)
	if not condition:
		_failures += 1
