extends SceneTree
## Headless checks of NPC traffic, run against the real main scene. Run with:
##   Godot --headless --path . --script res://scripts/tests/npc_traffic_test.gd
## Exits with code 1 if any check fails.

const STEP := 1.0 / 30.0
## Ships keep flying for a few frames before they are measured.
const MOVE_TOLERANCE := 100.0

var _failures: int = 0


func _init() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var system: StarSystem = main.get_node("StarSystem")
	var traffic: TrafficManager = system.get_node("Traffic")
	var ships_root: Node2D = system.get_ships_root()
	var player: PlayerShip = main.get_node("PlayerShip")
	var targeting: TargetingManager = main.get_node("Targeting")
	var hud: Hud = main.get_node("Hud")
	var config: TrafficConfig = traffic.config

	_check(config.validate().is_empty(), "traffic config validates: %s" % [config.validate()])
	for type in config.ship_types:
		_check(type.validate().is_empty(), "%s ship type validates" % type.display_name)

	# --- Ship sizes and art orientation ---------------------------------------
	var by_name: Dictionary = {}
	for type in config.ship_types:
		by_name[type.display_name] = type
	var shuttle: ShipType = by_name["Shuttle"]
	var freighter: ShipType = by_name["Freighter"]
	var interceptor: ShipType = by_name["Interceptor"]
	_check(is_equal_approx(shuttle.get_size().x, 75.0), "shuttle is 75 px wide (%s)" % shuttle.get_size().x)
	_check(is_equal_approx(freighter.get_size().x, 200.0), "freighter is 200 px wide (%s)" % freighter.get_size().x)
	_check(is_equal_approx(interceptor.get_size().x, shuttle.get_size().x * 0.8), "interceptor is 80%% of the shuttle (%s px)" % interceptor.get_size().x)
	var npc_scene: Node = load("res://scenes/ships/npc_ship.tscn").instantiate()
	_check(is_equal_approx(npc_scene.get_node("Visual/Sprite2D").rotation, PI / 2.0), "NPC sprite is turned +90 degrees (art points up)")
	npc_scene.free()
	var player_scene: Node = load("res://scenes/ships/player_ship.tscn").instantiate()
	_check(is_equal_approx(player_scene.get_node("Sprite2D").rotation, PI / 2.0), "player sprite is turned +90 degrees (art points up)")
	var owned := OwnedShip.new()
	owned.model = shuttle.stats
	player_scene.add_child(Node.new())  # (the sprite is a child; no tree needed)
	player_scene._sprite = player_scene.get_node("Sprite2D")
	player_scene.apply_ship(owned)
	_check(is_equal_approx(player_scene.get_node("Sprite2D").scale.x * 500.0, 75.0), "player sprite takes the model's scale (75 px wide)")
	player_scene.free()

	# --- Initial population ----------------------------------------------------
	var expected_initial: int = roundi(config.max_ships * config.initial_fill_fraction)
	_check(traffic.get_ship_count() == expected_initial,
			"%d ships in flight at load (expected %d)" % [traffic.get_ship_count(), expected_initial])
	_check_spawn_positions(ships_root, player, system, config, "initial ships")

	# --- Targeting: cycles ---------------------------------------------------------
	var ships: Array = _live_ships(ships_root)
	var ship_targets: Array = ships.map(func(s: NpcShip) -> Targetable: return s.get_node("Targetable"))
	targeting.select(null)
	var seen_ships: Dictionary = {}
	for i in ships.size() + 1:
		targeting.select_next(Targetable.SHIP_GROUP)
		_check(targeting.current_target in ship_targets, "T cycle selects a ship (step %d)" % i)
		seen_ships[targeting.current_target] = true
	_check(seen_ships.size() == ships.size(), "T cycle visits all %d ships and wraps" % ships.size())

	targeting.select(null)
	var location_count: int = system.get_inhabited_nodes().size()
	var seen_locations: Dictionary = {}
	for i in location_count + 1:
		targeting.select_next(Targetable.LOCATION_GROUP)
		_check(not (targeting.current_target in ship_targets), "Tab cycle selects a location (step %d)" % i)
		seen_locations[targeting.current_target] = true
	_check(seen_locations.size() == location_count, "Tab cycle visits all %d locations and wraps" % location_count)

	# Selecting a ship, then pressing the Tab cycle, must go to a location.
	targeting.select(ship_targets[0])
	targeting.select_next(Targetable.LOCATION_GROUP)
	_check(not (targeting.current_target in ship_targets), "Tab from a selected ship goes to a location")

	# Disabled (docked) ships are skipped and drop the selection.
	var hidden_target: Targetable = ship_targets[0]
	targeting.select(hidden_target)
	hidden_target.set_enabled(false)
	_check(targeting.current_target == null, "selected ship that becomes unavailable clears the target")
	targeting.select(null)
	var visited_hidden := false
	for i in ships.size() + 1:
		targeting.select_next(Targetable.SHIP_GROUP)
		if targeting.current_target == hidden_target:
			visited_hidden = true
	_check(not visited_hidden, "T cycle skips a disabled ship")
	hidden_target.set_enabled(true)
	targeting.select(null)

	# --- HUD shows an NPC -------------------------------------------------------------
	var shown: NpcShip = ships[1]
	targeting.select(shown.get_node("Targetable"))
	var hud_name: Label = hud.get_node("%NameLabel")
	var hud_rows: VBoxContainer = hud.get_node("%DetailRows")
	_check(hud_name.text == shown.ship_type.display_name, "HUD shows the ship name (%s)" % hud_name.text)
	_check(hud_rows.get_child_count() == 3, "HUD shows 3 detail rows (faction, ship, status)")
	var dock_target: Targetable = shown.get_node("Targetable")
	_check(not dock_target.is_dockable(), "NPC ships are not dockable")
	targeting.select(null)

	# --- Mouse selection ---------------------------------------------------------------
	await physics_frame
	await physics_frame
	var clicked: NpcShip = _live_ships(ships_root).filter(func(s: NpcShip) -> bool: return s.visible)[0]
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = root.get_canvas_transform() * clicked.global_position
	targeting._unhandled_input(click)
	_check(targeting.current_target == clicked.get_node("Targetable"), "left-click selects an NPC ship")
	targeting.select(null)

	# --- Simulation: states, docking, despawn, caps -------------------------------------
	player.global_position = Vector2.ZERO
	var states_seen: Dictionary = {}
	var known_ships: Dictionary = {}
	# Ships present at load were checked above; they have since flown on a little.
	for initial_ship in _live_ships(ships_root):
		known_ships[initial_ship] = {"last_dock": null}
	var max_count := 0
	var count_sum := 0
	var total_created := 0
	var despawned := 0
	var dock_problems := 0
	var docked_observations := 0
	var docked_problems := 0
	var retrograde_seen := false
	var repeat_destination := 0
	var player_spawn_violations := 0
	var seconds := 1200.0
	var steps := int(seconds / STEP)
	var vanished_in_view := 0  # ships that disappeared without warping out
	var warp_starts := 0
	var early_warps := 0
	for step in steps:
		if step == steps / 2:
			# Halfway: the player flies far away, so finished ships may now leave unseen.
			player.global_position = Vector2(8000, 8000)
		traffic.tick(STEP)
		for ship: NpcShip in _live_ships(ships_root):
			if not known_ships.has(ship):
				known_ships[ship] = {"last_dock": null}
				total_created += 1
				if ship.global_position.distance_to(player.global_position) < config.min_spawn_distance_from_player:
					player_spawn_violations += 1
			var before: NpcShip.State = ship.state
			var destination_before: InhabitedNode = ship.destination
			ship._physics_process(STEP)
			if before != NpcShip.State.WARPING and ship.state == NpcShip.State.WARPING:
				warp_starts += 1
				if ship.global_position.distance_to(system.global_position) < system.jump_radius:
					early_warps += 1
			if ship.is_queued_for_deletion() and ship.state != NpcShip.State.WARPING:
				vanished_in_view += 1
			states_seen[ship.state] = true
			if ship.state == NpcShip.State.DOCKED:
				docked_observations += 1
				if not ship.visible or not ship.get_node("Targetable").is_enabled() \
						or ship.velocity != Vector2.ZERO:
					docked_problems += 1
			if ship.state == NpcShip.State.APPROACHING and ship.velocity.length() > 50.0 \
					and Vector2.from_angle(ship.get_heading()).dot(ship.velocity.normalized()) < -0.5:
				retrograde_seen = true
			if before != NpcShip.State.DOCKED and ship.state == NpcShip.State.DOCKED:
				var distance: float = ship.global_position.distance_to(destination_before.global_position)
				if distance > destination_before.get_dock_range() or ship.velocity.length() >= NpcShip.DOCK_SPEED:
					dock_problems += 1
				known_ships[ship]["last_dock"] = destination_before
			if before == NpcShip.State.DOCKED and ship.state == NpcShip.State.TRAVELLING:
				if ship.destination == known_ships[ship]["last_dock"]:
					repeat_destination += 1
		var count: int = traffic.get_ship_count()
		max_count = maxi(max_count, count)
		count_sum += count
	for ship in known_ships:
		if not is_instance_valid(ship) or ship.is_queued_for_deletion():
			despawned += 1
	print("INFO  average population over the run: %.1f ships" % (float(count_sum) / steps))
	_check(max_count <= config.max_ships, "population never exceeded %d (peak %d)" % [config.max_ships, max_count])
	_check(states_seen.has(NpcShip.State.TRAVELLING) and states_seen.has(NpcShip.State.APPROACHING)
			and states_seen.has(NpcShip.State.DOCKED), "ships went through TRAVELLING, APPROACHING and DOCKED")
	_check(dock_problems == 0, "every docking happened within range and below dock speed (%d problems)" % dock_problems)
	_check(docked_observations > 0 and docked_problems == 0,
			"docked ships stay visible, targetable and stopped (%d observations, %d problems)" % [docked_observations, docked_problems])
	_check(retrograde_seen, "ships turn retrograde to brake before docking")
	_check(repeat_destination == 0, "ships depart for a different location than they docked at")
	_check(vanished_in_view == 0, "no ship ever just vanished: every one that left warped out first")
	_check(warp_starts > 0 and early_warps == 0, "ships only jump from beyond the jump radius (%d jumps, %d too early)" % [warp_starts, early_warps])
	_check(despawned > 0, "ships leave the system after their visits (%d left)" % despawned)
	_check(total_created > expected_initial, "replacements spawned (%d ships created in total)" % total_created)
	_check(player_spawn_violations == 0, "no ship spawned within %d px of the player" % int(config.min_spawn_distance_from_player))
	_check(traffic.get_ship_count() > 0, "traffic is still running after %d s (%d ships)" % [int(seconds), traffic.get_ship_count()])

	# --- Cleanup with the system ------------------------------------------------------------
	var leftover: Array = _live_ships(ships_root)
	main.remove_child(system)
	system.free()
	await process_frame
	var survivors := 0
	for ship in leftover:
		if is_instance_valid(ship):
			survivors += 1
	_check(survivors == 0, "freeing the system leaves no NPC ships behind")

	print("")
	print("NPC TRAFFIC TESTS: %s" % ("all passed" if _failures == 0 else "%d FAILED" % _failures))
	main.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _live_ships(ships_root: Node2D) -> Array:
	return ships_root.get_children().filter(
			func(node: Node) -> bool: return not node.is_queued_for_deletion())


func _check_spawn_positions(ships_root: Node2D, player: Node2D, system: StarSystem,
		config: TrafficConfig, label: String) -> void:
	var ok := true
	var ships: Array = _live_ships(ships_root)
	for ship: NpcShip in ships:
		if ship.global_position.distance_to(player.global_position) < config.min_spawn_distance_from_player - MOVE_TOLERANCE:
			ok = false
		for location in system.get_inhabited_nodes():
			if ship.global_position.distance_to(location.global_position) < location.get_dock_range() + config.spawn_clearance - MOVE_TOLERANCE:
				ok = false
		for other: NpcShip in ships:
			if other != ship and ship.global_position.distance_to(other.global_position) < config.ship_spacing - MOVE_TOLERANCE:
				ok = false
	_check(ok, "%s are clear of the player, locations and each other" % label)


func _check(condition: bool, description: String) -> void:
	print("PASS  " if condition else "FAIL  ", description)
	if not condition:
		_failures += 1
