extends SceneTree
## Tests formation movement through the real game scene (the combat sandbox's
## system): members holding station, the leader's speed and turn limits, losses,
## leader promotion, recovery, changing shape, jumping in and out, and avoidance.
## It runs in real time (about two minutes); pass scenario names after `--` to run only
## those, for example `-- wedge shapes`.
##   Godot --headless --path . --script res://scripts/tests/formation_movement_test.gd </dev/null

const CONFIG := preload("res://resources/traffic/default_traffic.tres")
const DT := 1.0 / 60.0
const HEAVY := &"federation_heavy_fighter"
const FIGHTER := &"federation_fighter"
const FRIGATE := &"federation_frigate"
const CRUISER := &"federation_cruiser"
## A fixed racetrack for leaders, well clear of the sandbox planet at (1500, 0) (a leader
## overshoots a corner by about its turning circle, some 500 px), so every run flies the same route.
const TRACK: Array[Vector2] = [Vector2(-2400.0, -1100.0), Vector2(0.0, -1100.0), Vector2(0.0, 900.0), Vector2(-2400.0, 900.0)]

var _failures: int = 0
var _main: Main
var _system: StarSystem
var _player: PlayerShip
var _registry: ContentRegistry
var _events: Array = []


func _init() -> void:
	seed(20260101)
	_registry = ContentRegistry.new()
	_main = CombatSandbox.build_main()
	root.add_child(_main)
	for i in 5:
		await process_frame
	_system = _main.get_system()
	_player = _main.get_player_ship()
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()  # the sandbox's own target ship: not needed here
	_player.global_position = Vector2(30000.0, 30000.0)  # out of everyone's way
	await process_frame

	var only := OS.get_cmdline_user_args()
	var scenarios := {
		"wedge": _test_squadron_wedge, "wander": _test_wander_stress, "shapes": _test_every_shape, "member": _test_member_destroyed,
		"leader": _test_leader_destroyed, "dissolve": _test_dissolve, "separated": _test_separated,
		"disabled": _test_disabled, "recovery": _test_recovery, "shape_change": _test_change_shape,
		"jump": _test_jump_in_and_out, "planet": _test_planet_avoidance, "player": _test_player_avoidance}
	for name in scenarios:
		if only.is_empty() or only.has(name):
			print("--- ", name)
			await scenarios[name].call()

	print("FORMATION MOVEMENT TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _types(ids: Array) -> Array[ShipType]:
	var types: Array[ShipType] = []
	for id in ids:
		var type := ShipType.new()
		type.stats = _registry.ship_stats(id)
		types.append(type)
	return types


## Spawns a formation whose leader flies the racetrack (or, with `wander`, wanders at
## random, which is much harder to follow).
func _spawn(ids: Array, shape_id: StringName, kind: Formation.Kind = Formation.Kind.SQUADRON,
		at: Vector2 = TRACK[0], heading: float = 0.0, tuning: FormationTuning = null, wander: bool = false) -> Formation:
	var patrol: Array[Vector2] = []
	if not wander:
		patrol = TRACK
	var formation := FleetSpawner.spawn_formation(_system, _player, CONFIG, kind, _registry.formation_shape(shape_id),
			_types(ids), at, heading, &"", 700.0, tuning, patrol)
	_events.clear()
	formation.member_lost.connect(func(ship, reason: StringName) -> void: _events.append(["lost", reason]))
	formation.leader_changed.connect(func(_old, _new) -> void: _events.append(["leader"]))
	formation.shape_changed.connect(func(_shape: FormationShape) -> void: _events.append(["shape"]))
	formation.dissolved.connect(func() -> void: _events.append(["dissolved"]))
	return formation


func _run(seconds: float) -> void:
	for i in int(seconds / DT):
		await physics_frame


func _clear() -> void:
	for formation in _system.get_formations_root().get_children():
		for ship in (formation as Formation).get_ships():
			ship.queue_free()
		formation.queue_free()
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	await process_frame
	await process_frame


func _count(kind: String) -> int:
	return _events.filter(func(event: Array) -> bool: return event[0] == kind).size()


func _reasons() -> Array:
	return _events.filter(func(event: Array) -> bool: return event[0] == "lost").map(func(event: Array) -> StringName: return event[1])


## Flies the formation for `seconds`, measuring after the first `settle` seconds:
## how often every member is near its slot, the closest any two ships came
## (relative to their sizes), and the leader's fastest speed and turn.
func _measure(formation: Formation, seconds: float, settle: float) -> Dictionary:
	var result := {"samples": 0, "on_station": 0, "closest": INF, "lead_speed": 0.0, "lead_turn": 0.0, "worst_error": 0.0, "turn_ratio": 0.0}
	var last_heading := formation.lead.get_heading()
	for step in int(seconds / DT):
		await physics_frame
		if not is_instance_valid(formation) or not formation.has_valid_lead():
			break
		var lead := formation.lead
		result["lead_speed"] = maxf(result["lead_speed"], lead.velocity.length())
		var turn := absf(angle_difference(last_heading, lead.get_heading())) / DT
		result["lead_turn"] = maxf(result["lead_turn"], turn)
		result["turn_ratio"] = maxf(result["turn_ratio"], turn / lead.formation_turn_cap)
		last_heading = lead.get_heading()
		if step * DT < settle:
			continue
		var ships := formation.get_ships()
		var all_near := true
		for ship in ships:
			if ship == lead:
				continue
			var error := formation.get_slot_error(ship)
			result["worst_error"] = maxf(result["worst_error"], error)
			if error > formation.station_tolerance * 2.0:
				all_near = false
		result["samples"] += 1
		result["on_station"] += 1 if all_near else 0
		for a in ships.size():
			for b in range(a + 1, ships.size()):
				var room: float = ships[a].get_hit_radius() + ships[b].get_hit_radius()
				result["closest"] = minf(result["closest"], ships[a].global_position.distance_to(ships[b].global_position) / room)
	return result


func _fraction(result: Dictionary) -> float:
	return float(result["on_station"]) / maxf(float(result["samples"]), 1.0)


func _all_on_station(formation: Formation) -> bool:
	for ship in formation.get_members():
		if formation.get_slot_error(ship) > formation.station_tolerance * 2.0:
			return false
	return true


# ----------------------------------------------------------------- tests

func _test_squadron_wedge() -> void:
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge")
	_check(formation.size() == 4 and formation.lead.ship_type.stats.id == HEAVY, "the strongest ship, the heavy fighter, leads the squadron")
	_check(formation.get_flagship() == formation.lead, "for a squadron the leader is the flagship")
	var slow := minf(_registry.ship_stats(HEAVY).max_speed, _registry.ship_stats(FIGHTER).max_speed)
	_check(is_equal_approx(formation.lead.formation_speed_cap, slow * 0.9), "the leader's cruise speed is 90%% of the slowest member (%d)" % int(formation.lead.formation_speed_cap))
	_check(formation.lead.formation_turn_cap < formation.lead.ship_type.stats.turn_rate, "the leader turns slower than it could alone, so the outer ships keep up")
	var members := formation.get_members()
	_check(members.all(func(ship: NpcShip) -> bool: return ship.state == NpcShip.State.IN_FORMATION and ship.formation == formation), "every other ship is a member in formation")
	_check(formation.lead.state == NpcShip.State.WANDERING and formation.lead.led_formation == formation, "the leader flies its own route and leads the formation")
	_check(formation.get_ships().all(func(ship: NpcShip) -> bool: return ship.get_hit_radius() > 0.0), "(setup) every ship has a size")
	for ship in formation.get_ships():
		_check(formation.get_slot_error(ship) < 1.0, "a new formation starts snapped into its slots")
		break

	var result := await _measure(formation, 20.0, 8.0)
	_check(_fraction(result) >= 0.9, "members hold station while the leader flies around (%.0f%% of the time, worst %d px)" % [_fraction(result) * 100.0, int(result["worst_error"])])
	_check(result["lead_speed"] <= formation.lead.formation_speed_cap + 0.5, "the leader never exceeds the formation's cruise speed")
	_check(result["turn_ratio"] <= 1.15, "the leader never turns faster than the formation's limit (%.0f%% of it at most)" % (result["turn_ratio"] * 100.0))
	_check(result["closest"] >= 1.0, "no two ships come closer than their sizes (%.2f)" % result["closest"])
	_check(formation.size() == 4 and _events.is_empty(), "nobody was lost")
	var facing := true
	for ship in formation.get_members():
		facing = facing and absf(angle_difference(ship.get_heading(), formation.get_frame_heading())) < 0.6
	_check(facing, "settled members face the way the formation is heading")
	await _clear()


## A leader that wanders at random makes sudden turns and reversals: a harder test,
## so the standard is looser.
func _test_wander_stress() -> void:
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge", Formation.Kind.SQUADRON, Vector2(-1500.0, -400.0), 0.0, null, true)
	var result := await _measure(formation, 30.0, 8.0)
	_check(_fraction(result) >= 0.6, "behind a leader wandering at random the squadron still holds station (%.0f%% of the time, worst %d px)" % [_fraction(result) * 100.0, int(result["worst_error"])])
	_check(result["closest"] >= 1.0 and result["turn_ratio"] <= 1.15, "and nobody overlaps, and the turn limit holds")
	_check(formation.size() == 4 and _events.is_empty(), "and nobody is lost")
	await _clear()


func _test_every_shape() -> void:
	var fleet := [CRUISER, FRIGATE, FRIGATE, FIGHTER, FIGHTER, FIGHTER]
	var convoy := [&"bulk_freighter", &"freighter", &"interceptor", &"interceptor", &"interceptor", &"light_frigate"]
	var cases := [
		[&"wedge", fleet, Formation.Kind.BATTLE_GROUP], [&"line", fleet, Formation.Kind.BATTLE_GROUP],
		[&"diamond", [FRIGATE, FIGHTER, FIGHTER, FIGHTER, FIGHTER], Formation.Kind.SQUADRON],
		[&"screen", [CRUISER, FRIGATE, FIGHTER, FIGHTER, FIGHTER, HEAVY], Formation.Kind.BATTLE_GROUP],
		[&"convoy", convoy, Formation.Kind.CONVOY], [&"convoy_diamond", convoy, Formation.Kind.CONVOY]]
	for entry in cases:
		var formation := _spawn(entry[1], entry[0], entry[2])
		var result := await _measure(formation, 20.0, 10.0)
		var label := String(entry[0])
		_check(formation.size() == entry[1].size() and _events.is_empty(), "%s: nobody left the formation" % label)
		_check(_fraction(result) >= 0.8, "%s: ships hold their slots (%.0f%% of the time, worst %d px)" % [label, _fraction(result) * 100.0, int(result["worst_error"])])
		_check(result["closest"] >= 1.0, "%s: no two ships overlap (%.2f)" % [label, result["closest"]])
		_check(result["turn_ratio"] <= 1.15, "%s: the leader respects its turn limit (%.0f%%)" % [label, result["turn_ratio"] * 100.0])
		if entry[2] == Formation.Kind.CONVOY:
			_check(formation.lead.ship_type.stats.ship_class.carries_cargo(), "%s: a freighter leads the convoy" % label)
			_check(formation.get_flagship().ship_type.stats.ship_class.carries_cargo() == false, "%s: the flagship is the strongest escort, not a freighter" % label)
		await _clear()


func _test_member_destroyed() -> void:
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge")
	await _run(8.0)
	var victim: NpcShip = formation.get_members()[1]
	_kill(victim)
	await physics_frame
	_check(formation.size() == 3 and _reasons() == [Formation.REASON_DESTROYED], "a destroyed member leaves the formation")
	await _run(12.0)
	_check(_all_on_station(formation), "the survivors close ranks onto their new slots")
	var slots := {}
	for ship in formation.get_ships():
		slots[formation.get_slot(ship).index] = true
	_check(slots.size() == 3 and slots.has(0) and slots.has(1) and slots.has(2), "the three ships hold slots 0, 1 and 2 (ranks closed up)")
	_check(formation.get_ships().all(func(ship: NpcShip) -> bool: return is_instance_valid(ship)), "no freed ship is still listed")
	await _clear()


func _test_leader_destroyed() -> void:
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge")
	await _run(8.0)
	var old_lead := formation.lead
	var centre := old_lead._wander_centre
	_kill(old_lead)
	await physics_frame
	var new_lead := formation.lead
	_check(_count("leader") == 1 and new_lead != old_lead and is_instance_valid(new_lead), "a new leader takes over when the leader is destroyed")
	_check(new_lead.ship_type.stats.id == FIGHTER and formation.size() == 3, "the strongest remaining ship leads (a fighter) and the formation has three ships")
	_check(new_lead.led_formation == formation and new_lead.formation == null, "the new leader leads and is no longer a follower")
	_check(new_lead.state == NpcShip.State.WANDERING and new_lead._wander_centre == centre, "it carries on the old leader's route (state and wander centre)")
	_check(new_lead.formation_speed_cap < INF and new_lead.formation_turn_cap < INF, "it is given the formation's speed and turn limits")
	_check(not is_instance_valid(old_lead) or old_lead.led_formation == null, "the lost leader no longer leads anything")
	await _run(14.0)
	_check(_all_on_station(formation), "the formation re-forms on the new leader")
	await _clear()


func _test_dissolve() -> void:
	var formation := _spawn([FIGHTER, FIGHTER], &"line")
	var survivor := formation.lead
	_kill(formation.get_members()[0])
	await physics_frame
	await physics_frame
	_check(_count("dissolved") == 1 and (not is_instance_valid(formation) or formation.is_queued_for_deletion()), "a formation with too few ships breaks up")
	_check(survivor.led_formation == null and survivor.formation_speed_cap == INF and survivor.formation_turn_cap == INF, "the survivor is an ordinary ship again, with no limits")
	_check(survivor.state == NpcShip.State.WANDERING, "and carries on its way")
	await _clear()

	var again := _spawn([FIGHTER, FIGHTER], &"line")
	var member: NpcShip = again.get_members()[0]
	_kill(again.lead)
	await physics_frame
	await physics_frame
	_check(member.formation == null and member.state == NpcShip.State.WANDERING, "when the leader is the one lost, the last member carries on alone")
	await _clear()


func _test_separated() -> void:
	var tuning: FormationTuning = FormationTuning.shared().duplicate()
	tuning.lost_distance = 600.0
	tuning.lost_time = 1.0
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge", Formation.Kind.SQUADRON, Vector2(-1500.0, -400.0), 0.0, tuning)
	await _run(6.0)
	var stray: NpcShip = formation.get_members()[0]
	stray.set_physics_process(false)  # it cannot catch up
	stray.global_position += Vector2(0.0, 2000.0)
	await _run(3.0)
	_check(_reasons() == [Formation.REASON_SEPARATED], "a member that stays far from its slot is released as separated")
	_check(formation.size() == 3 and stray.formation == null and stray.state == NpcShip.State.WANDERING, "it is out of the formation and carries on alone")
	await _clear()


func _test_disabled() -> void:
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge")
	await _run(4.0)
	var wreck: NpcShip = formation.get_members()[0]
	var health := wreck.get_combatant().health.state
	health.hull = health.max_hull * 0.1
	await physics_frame
	await physics_frame
	_check(_reasons() == [Formation.REASON_DISABLED] and wreck.formation == null, "a heavily damaged member falls out of formation")
	_check(formation.size() == 3, "the others carry on")
	await _clear()


func _test_recovery() -> void:
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge")
	await _run(6.0)
	var straggler: NpcShip = formation.get_members()[2]
	var behind := formation.get_slot_world_position(straggler) - Vector2.from_angle(formation.lead.get_heading()) * 600.0
	straggler.global_position = behind
	straggler.velocity = Vector2.ZERO
	_check(formation.get_slot_error(straggler) > formation.catch_up_distance, "(setup) the straggler is beyond the catch-up distance (%d px)" % int(formation.get_slot_error(straggler)))
	await _run(15.0)
	_check(formation.get_ships().has(straggler) and formation.is_on_station(straggler) or formation.get_slot_error(straggler) <= formation.station_tolerance * 2.0, "a member that fell behind catches up and rejoins its slot")
	_check(_events.is_empty(), "and is not released on the way")
	await _clear()


func _test_change_shape() -> void:
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge")
	await _run(8.0)
	formation.set_shape(_registry.formation_shape(&"line"))
	_check(_count("shape") == 1 and formation.shape.id == &"line", "changing the shape is announced")
	_check(formation.get_members()[0].details.status.contains("Line"), "the ships' status line shows the new shape")
	var jump := 0.0
	var before := {}
	for ship in formation.get_ships():
		before[ship] = ship.global_position
	for step in int(20.0 / DT):
		await physics_frame
		for ship in formation.get_ships():
			var stats := ship.ship_type.stats
			jump = maxf(jump, (ship.global_position - before[ship]).length() / (stats.max_speed * DT))
			before[ship] = ship.global_position
	_check(jump <= 1.05, "ships fly to their new slots instead of jumping there (fastest %.2f of top speed)" % jump)
	_check(_all_on_station(formation), "the formation settles into the new shape")
	var abreast := true
	for ship in formation.get_members():
		abreast = abreast and absf((ship.global_position - formation.lead.global_position).rotated(-formation.lead.get_heading()).x) < formation.station_tolerance * 3.0
	_check(abreast, "the ships are now abreast of the leader")
	formation.set_shape(formation.shape)
	_check(_count("shape") == 1, "setting the same shape again does nothing")
	await _clear()


func _test_jump_in_and_out() -> void:
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge", Formation.Kind.SQUADRON, Vector2(-300.0, 0.0), 0.0)
	var ships := formation.get_ships()
	var lead := formation.lead
	lead.configure_jumping(_system.global_position, _system.jump_radius, [Vector2.RIGHT])
	lead.begin_arrival(Vector2.RIGHT)
	await physics_frame
	await physics_frame
	var worst := 0.0
	var slaved_frames := 0
	while lead.state == NpcShip.State.ARRIVING:
		for ship in formation.get_members():
			var ideal := lead.global_position + formation.get_slot(ship).offset.rotated(lead.get_heading())
			worst = maxf(worst, ship.global_position.distance_to(ideal))
		slaved_frames += 1
		await physics_frame
		if slaved_frames > 600:
			break
	_check(slaved_frames > 5 and worst < 70.0, "while the leader jumps in, members stay locked to their slots (worst %d px over %d frames)" % [int(worst), slaved_frames])
	_check(formation.get_members().all(func(ship: NpcShip) -> bool: return ship.state == NpcShip.State.IN_FORMATION), "and are released into normal flight, still in formation")

	var warped := false
	for step in int(30.0 / DT):
		await physics_frame
		if lead.state == NpcShip.State.WARPING:
			warped = true
			break
	_check(warped, "the leader flies out and starts to jump")
	await physics_frame
	await physics_frame
	var targetables_off := true
	for ship in formation.get_members():
		targetables_off = targetables_off and not ship.get_node("Targetable").is_enabled()
	_check(targetables_off, "the members stop being targetable as they jump with the leader")
	for step in int(10.0 / DT):
		await physics_frame
		if not is_instance_valid(lead) or lead.is_queued_for_deletion():
			break
	await physics_frame
	await physics_frame
	await physics_frame
	var all_gone := ships.all(func(ship) -> bool: return not is_instance_valid(ship) or ship.is_queued_for_deletion())
	_check(all_gone, "the whole formation leaves with its leader")
	_check(not is_instance_valid(formation) or formation.is_queued_for_deletion(), "and the formation is gone")
	_check(_count("dissolved") == 1, "its end is announced once")
	await _clear()


func _test_planet_avoidance() -> void:
	var planet := _system.get_inhabited_nodes()[0]
	var radius: float = planet.data.size * 0.5
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge", Formation.Kind.SQUADRON, planet.global_position, 0.0)
	await _run(10.0)
	var lead_distance := formation.lead.global_position.distance_to(planet.global_position)
	_check(lead_distance >= radius * 0.85, "a formation spawned on a planet drifts out of it (leader %d px from the centre of a %d px planet)" % [int(lead_distance), int(radius)])
	var inside := false
	for ship in formation.get_members():
		inside = inside or ship.global_position.distance_to(planet.global_position) < radius * 0.6
	_check(not inside, "no member is left deep inside the planet")
	await _clear()


func _test_player_avoidance() -> void:
	var spot := Vector2(-1500.0, 1500.0)
	_player.global_position = spot
	var formation := _spawn([HEAVY, FIGHTER, FIGHTER, FIGHTER], &"wedge", Formation.Kind.SQUADRON, spot, 0.0)
	await _run(6.0)
	var worst := INF
	for ship in formation.get_ships():
		var room: float = ship.get_hit_radius() + _player.stats.hit_radius
		worst = minf(worst, ship.global_position.distance_to(_player.global_position) / room)
	_check(worst >= 0.9, "a formation spawned on top of the player moves clear of them (closest %.2f of the sizes)" % worst)
	_player.global_position = Vector2(30000.0, 30000.0)
	await _clear()


func _kill(ship: NpcShip) -> void:
	var hit := Hit.new()
	hit.damage = 1000000.0
	ship.get_combatant().take_hit(hit)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
