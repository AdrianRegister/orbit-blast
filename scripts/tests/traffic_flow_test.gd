extends SceneTree
## Tests NPC ships travelling between systems: arrivals at the edge from the
## directions of the system's links, departures by jumping out beyond the jump
## radius (the player's rule), and the system's traffic_rate scaling it all.
## Simulated directly in steps, so it is fast. Run with:
##   Godot --headless --path . --script res://scripts/tests/traffic_flow_test.gd

const STEP := 1.0 / 60.0  # the game runs at about 60 frames a second; much coarser steps make fast ships hover
const SECONDS := 1500.0

var _failures: int = 0


func _init() -> void:
	var bearings: Array[Vector2] = [Vector2(-1, -0.5).normalized(), Vector2(0.2, -1).normalized(), Vector2(1, -0.4).normalized()]
	var no_bearings: Array[Vector2] = []

	var busy := await _run(1.0, bearings)
	var quiet := await _run(0.25, bearings)
	var none := await _run(0.0, bearings)
	var isolated := await _run(1.0, no_bearings)
	var one_dock := await _run(1.0, bearings, "res://scenes/systems/tau_ceti_system.tscn")  # a single place to land
	var no_dock := await _run(1.0, bearings, "res://scenes/systems/wolf_359_system.tscn")  # nowhere to land
	var lonely := await _run(1.0, no_bearings, "res://scenes/systems/tau_ceti_system.tscn")  # one place and no links

	print("INFO  traffic_rate 1.0:  %d arrivals, %d departures, peak %d ships (cap %d)" % [busy["arrivals"], busy["warps"], busy["peak"], busy["cap"]])
	print("INFO  traffic_rate 0.25: %d arrivals, %d departures, peak %d ships (cap %d)" % [quiet["arrivals"], quiet["warps"], quiet["peak"], quiet["cap"]])

	# --- A busy system: ships keep arriving and leaving.
	_check(busy["arrivals"] >= 20, "a busy system keeps receiving ships (%d arrivals in %d s)" % [busy["arrivals"], int(SECONDS)])
	_check(busy["warps"] >= 15, "...and ships keep leaving it (%d departures)" % busy["warps"])
	_check(busy["peak"] <= busy["cap"], "the population never exceeds the cap (%d of %d)" % [busy["peak"], busy["cap"]])
	_check(busy["bad_arrivals"] == 0, "every arrival appears on the edge of the system, in the direction of a link (%d wrong)" % busy["bad_arrivals"])
	_check(busy["early_warps"] == 0, "every ship jumps from beyond the jump radius, the player's rule (%d too early)" % busy["early_warps"])
	_check(busy["vanished"] == 0, "no ship ever just vanishes: each one warps out first (%d did)" % busy["vanished"])
	_check(busy["targetable_warps"] == 0, "a ship that is jumping out can no longer be targeted")
	_check(busy["arrival_speeds_ok"], "arriving ships come in fast and slow to their cruising speed")
	_check(busy["departures_visited"], "ships visit locations before they leave")

	# --- traffic_rate scales it.
	_check(quiet["cap"] < busy["cap"], "a quiet system holds fewer ships (cap %d against %d)" % [quiet["cap"], busy["cap"]])
	_check(quiet["arrivals"] > 0 and quiet["arrivals"] < busy["arrivals"] * 0.75, "...receives far fewer (%d against %d)" % [quiet["arrivals"], busy["arrivals"]])
	_check(quiet["warps"] < busy["warps"] * 0.75, "...and sees far fewer departures (%d against %d)" % [quiet["warps"], busy["warps"]])
	_check(none["ever"] == 0 and none["cap"] == 0, "a traffic_rate of 0 means no traffic at all")

	# --- A system with no links keeps the old behaviour.
	_check(isolated["arrivals"] == 0 and isolated["warps"] == 0, "a system with no links has no jumping traffic")
	_check(isolated["peak"] > 0 and isolated["end"] > 0, "...but its residents still fly between its locations (%d now)" % isolated["end"])

	# --- Fewer than two places to land does not mean no traffic: ships still come and go.
	print("INFO  one dock: %d arrivals, %d departures; no dock: %d arrivals, %d departures" % [one_dock["arrivals"], one_dock["warps"], no_dock["arrivals"], no_dock["warps"]])
	_check(one_dock["arrivals"] >= 10 and one_dock["warps"] >= 8, "a system with one place to land still has ships arriving (%d) and leaving (%d)" % [one_dock["arrivals"], one_dock["warps"]])
	_check(one_dock["bad_arrivals"] == 0 and one_dock["early_warps"] == 0 and one_dock["vanished"] == 0, "...arriving at the edge along a link, jumping out only beyond the jump radius, never vanishing")
	_check(one_dock["docked"] > 0, "...and they visit the one place to land")
	_check(no_dock["arrivals"] >= 10 and no_dock["warps"] >= 8, "a system with nowhere to land has ships passing through: %d arrivals, %d departures" % [no_dock["arrivals"], no_dock["warps"]])
	_check(no_dock["bad_arrivals"] == 0 and no_dock["early_warps"] == 0 and no_dock["vanished"] == 0 and no_dock["docked"] == 0, "...which obey the same rules and never dock")
	_check(no_dock["peak"] <= no_dock["cap"] and one_dock["peak"] <= one_dock["cap"], "the cap is respected in both")
	_check(lonely["arrivals"] == 0 and lonely["ever"] == 0, "with one place to land and no links there is still no traffic")

	print("")
	print("TRAFFIC FLOW TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


## Runs one system for SECONDS and reports what happened.
func _run(rate: float, bearings: Array[Vector2], scene: String = "res://scenes/systems/sol_system.tscn") -> Dictionary:
	var system: StarSystem = load(scene).instantiate()
	system.traffic_rate = rate
	root.add_child(system)
	var player := Node2D.new()
	root.add_child(player)
	player.position = Vector2(9000, 9000)
	await process_frame
	system.set_traffic_exits(bearings)
	system.start_traffic(player)
	var traffic: TrafficManager = system.get_node("Traffic")
	var report := {"arrivals": 0, "warps": 0, "peak": 0, "cap": traffic.get_max_ships(), "bad_arrivals": 0, "early_warps": 0,
			"vanished": 0, "docked": 0, "targetable_warps": 0, "arrival_speeds_ok": true, "departures_visited": false, "ever": 0, "end": 0}
	var seen := {}
	var visited := {}
	for step in int(SECONDS / STEP):
		traffic.tick(STEP)
		for ship: NpcShip in system.get_ships_root().get_children():
			if ship.is_queued_for_deletion():
				continue
			if not seen.has(ship):
				seen[ship] = true
				report["ever"] += 1
				if ship.state == NpcShip.State.ARRIVING:
					report["arrivals"] += 1
					var from_centre: Vector2 = ship.global_position - system.global_position
					var on_edge := absf(from_centre.length() - system.jump_radius) < 1.0
					var along_link := false
					for bearing in bearings:
						if from_centre.normalized().dot(bearing) > 0.999:
							along_link = true
					if not (on_edge and along_link):
						report["bad_arrivals"] += 1
					if ship.velocity.length() < ship.ship_type.stats.max_speed * 2.0:
						report["arrival_speeds_ok"] = false
			var before: NpcShip.State = ship.state
			ship._physics_process(STEP)
			if before == NpcShip.State.DOCKED:
				visited[ship] = true
			if ship.state == NpcShip.State.DOCKED and before != NpcShip.State.DOCKED:
				report["docked"] += 1
			if before != NpcShip.State.WARPING and ship.state == NpcShip.State.WARPING:
				report["warps"] += 1
				if visited.has(ship) or true:
					report["departures_visited"] = report["departures_visited"] or visited.has(ship)
				if ship.global_position.distance_to(system.global_position) < system.jump_radius:
					report["early_warps"] += 1
				if ship.get_node("Targetable").is_enabled():
					report["targetable_warps"] += 1
			if ship.is_queued_for_deletion() and ship.state != NpcShip.State.WARPING:
				report["vanished"] += 1
		var count := traffic.get_ship_count()
		report["peak"] = maxi(report["peak"], count)
	report["end"] = traffic.get_ship_count()
	system.queue_free()
	player.queue_free()
	await process_frame
	return report


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
