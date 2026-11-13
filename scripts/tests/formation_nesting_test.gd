extends SceneTree
## Tests nested formations and fleets through the real game scene (the combat
## sandbox's system): squadrons inside a battle group, their leaders being swapped
## and their survivors taken in, a battle group's own losses, jumping with the
## leader, a convoy built from a plan, and a fleet's leash and flagship. Runs in real
## time (about four minutes); pass scenario names after `--` to run only those.
##   Godot --headless --path . --script res://scripts/tests/formation_nesting_test.gd </dev/null

const CONFIG := preload("res://resources/traffic/default_traffic.tres")
const DT := 1.0 / 60.0
const FACTION := &"faction_1"
const HEAVY := &"federation_heavy_fighter"
const FIGHTER := &"federation_fighter"
const FRIGATE := &"federation_frigate"
const CRUISER := &"federation_cruiser"
const CAPITAL := &"federation_capital_ship"
## The same racetrack the formation movement test uses.
const TRACK: Array[Vector2] = [Vector2(-2400.0, -1100.0), Vector2(0.0, -1100.0), Vector2(0.0, 900.0), Vector2(-2400.0, 900.0)]

var _failures: int = 0
var _main: Main
var _system: StarSystem
var _player: PlayerShip
var _registry: ContentRegistry
var _events: Array = []


func _init() -> void:
	seed(20260202)
	_registry = ContentRegistry.new()
	_main = CombatSandbox.build_main()
	root.add_child(_main)
	for i in 5:
		await process_frame
	_system = _main.get_system()
	_player = _main.get_player_ship()
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	_player.global_position = Vector2(30000.0, 30000.0)
	await process_frame

	var only := OS.get_cmdline_user_args()
	var scenarios := {
		"structure": _test_structure, "hold": _test_battle_group_holds, "shapes": _test_battle_group_shapes,
		"squad_leader": _test_squadron_leader_destroyed, "group_leader": _test_battle_group_leader_destroyed,
		"adopt": _test_squadron_dissolves, "jump": _test_nested_jump, "convoy": _test_convoy_plan,
		"fleet": _test_fleet_structure, "leash": _test_fleet_leash, "flagship": _test_flagship_lost}
	for name in scenarios:
		if only.is_empty() or only.has(name):
			print("--- ", name)
			await scenarios[name].call()

	print("FORMATION NESTING TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _type(id: StringName) -> ShipType:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(id)
	return type


## A plan written by hand, so the tests do not depend on a random draw.
func _unit(recipe_id: StringName, ids: Array, shape_id: StringName = &"", children: Array = []) -> FormationPlan:
	var plan := FormationPlan.new()
	plan.recipe = _registry.formation_recipe(recipe_id)
	for id in ids:
		plan.ships.append(_type(id))
	if shape_id != &"":
		plan.shape = _registry.formation_shape(shape_id)
	for child in children:
		plan.children.append(child)
	return plan


func _squadron(ids: Array = [HEAVY, FIGHTER, FIGHTER]) -> FormationPlan:
	return _unit(&"squadron", ids, &"wedge")


func _battle_group_plan(shape_id: StringName = &"screen", squadrons: int = 2) -> FormationPlan:
	var children: Array = []
	for i in squadrons:
		children.append(_squadron())
	return _unit(&"battle_group", [CRUISER, FRIGATE], shape_id, children)


func _spawn(plan: FormationPlan, at: Vector2 = TRACK[0], heading: float = 0.0, fly_track: bool = true) -> Node:
	var patrol: Array[Vector2] = []
	if fly_track:
		patrol = TRACK
	var unit := FleetSpawner.spawn_plan(_system, _player, CONFIG, plan, at, heading, FACTION, 700.0, null, patrol)
	_events.clear()
	if unit is Formation:
		unit.member_lost.connect(func(_ship, reason: StringName) -> void: _events.append(["lost", reason]))
		unit.leader_changed.connect(func(_old, _new) -> void: _events.append(["leader"]))
		unit.dissolved.connect(func() -> void: _events.append(["dissolved"]))
	elif unit is WarFleet:
		unit.flagship_changed.connect(func(_old, _new) -> void: _events.append(["flagship"]))
		unit.dissolved.connect(func() -> void: _events.append(["fleet_dissolved"]))
	return unit


func _run(seconds: float) -> void:
	for i in int(seconds / DT):
		await physics_frame


func _clear() -> void:
	for unit in _system.get_formations_root().get_children():
		var ships: Array[NpcShip] = []
		if unit is Formation:
			ships = (unit as Formation).get_all_ships()
		elif unit is WarFleet:
			ships = (unit as WarFleet).get_all_ships()
		for ship in ships:
			ship.queue_free()
		unit.queue_free()
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	await process_frame
	await process_frame


func _kill(ship: NpcShip) -> void:
	var hit := Hit.new()
	hit.damage = 1000000.0
	ship.get_combatant().take_hit(hit)


func _count(kind: String) -> int:
	return _events.filter(func(event: Array) -> bool: return event[0] == kind).size()


## The formation and every formation led from inside it.
func _formations_of(root_formation: Formation) -> Array[Formation]:
	var result: Array[Formation] = [root_formation]
	for ship in root_formation.get_all_ships():
		var inner: Formation = ship.led_formation
		if inner != null and inner != root_formation and not result.has(inner):
			result.append(inner)
	return result


func _all_near(formations: Array[Formation]) -> bool:
	for formation in formations:
		if not is_instance_valid(formation):
			continue
		for ship in formation.get_members():
			if formation.get_slot_error(ship) > formation.station_tolerance * 2.0:
				return false
	return true


func _worst_error(formations: Array[Formation]) -> float:
	var worst := 0.0
	for formation in formations:
		if is_instance_valid(formation):
			for ship in formation.get_members():
				worst = maxf(worst, formation.get_slot_error(ship))
	return worst


func _closest_ratio(ships: Array[NpcShip]) -> float:
	var closest := INF
	for a in ships.size():
		for b in range(a + 1, ships.size()):
			var room: float = ships[a].get_hit_radius() + ships[b].get_hit_radius()
			closest = minf(closest, ships[a].global_position.distance_to(ships[b].global_position) / room)
	return closest


## Flies for `seconds`, sampling after `settle`: how often every member of every
## formation inside `root_formation` is near its slot, the worst error, and the
## closest any two ships came (relative to their sizes).
func _measure(root_formation: Formation, seconds: float, settle: float) -> Dictionary:
	var result := {"samples": 0, "near": 0, "worst": 0.0, "closest": INF}
	for step in int(seconds / DT):
		await physics_frame
		if not is_instance_valid(root_formation) or not root_formation.has_valid_lead():
			break
		if step * DT < settle:
			continue
		var formations := _formations_of(root_formation)
		result["samples"] += 1
		result["near"] += 1 if _all_near(formations) else 0
		result["worst"] = maxf(result["worst"], _worst_error(formations))
		result["closest"] = minf(result["closest"], _closest_ratio(root_formation.get_all_ships()))
	return result


func _fraction(result: Dictionary) -> float:
	return float(result["near"]) / maxf(float(result["samples"]), 1.0)


# ----------------------------------------------------------------- tests

func _test_structure() -> void:
	var plan := _battle_group_plan()
	var group := _spawn(plan) as Formation
	_check(group != null and group.kind == Formation.Kind.BATTLE_GROUP, "spawning a battle group plan gives a battle group")
	_check(group.get_all_ships().size() == plan.ship_count() and plan.ship_count() == 8, "it holds every ship of the plan (%d)" % group.get_all_ships().size())
	_check(group.size() == 4, "its own formation holds the larger ships and one leader per squadron (%d)" % group.size())
	_check(group.lead.ship_type.stats.id == CRUISER, "the strongest of its own ships, the cruiser, leads it")
	_check(group.parent == null, "a battle group has no parent")
	var squadrons := _formations_of(group).filter(func(formation: Formation) -> bool: return formation != group)
	_check(squadrons.size() == 2, "it has its two squadrons")
	var single_roles := true
	for squadron in squadrons:
		_check(squadron.parent == group, "each squadron knows its battle group")
		_check(squadron.kind == Formation.Kind.SQUADRON and squadron.size() == 3, "each squadron is a squadron of three")
		var squad_lead: NpcShip = squadron.lead
		_check(squad_lead.led_formation == squadron and squad_lead.formation == group, "a squadron's leader leads the squadron and is a member of the battle group")
		_check(squad_lead.state == NpcShip.State.IN_FORMATION, "... and flies in the battle group's formation")
		_check(group.get_ships().has(squad_lead), "the battle group holds that leader")
		for member in squadron.get_members():
			if member.led_formation != null or member.formation != squadron:
				single_roles = false
	_check(single_roles, "a squadron's other ships are plain members of it")
	_check(group.lead.state == NpcShip.State.WANDERING or group.lead.state == NpcShip.State.TRAVELLING, "only the battle group's leader flies a route")

	# The battle group cruises at a speed everyone in it, squadrons included, can keep up with.
	var slowest := INF
	for ship in group.get_all_ships():
		slowest = minf(slowest, ship.ship_type.stats.max_speed)
	_check(group.lead.formation_speed_cap <= slowest * 0.9 + 0.01, "its cruise speed is within 90%% of its slowest ship (%d <= %d)" % [int(group.lead.formation_speed_cap), int(slowest * 0.9)])
	for squadron in squadrons:
		_check(squadron.lead.formation_speed_cap <= squadron.lead.ship_type.stats.max_speed, "(a squadron has its own limits too)")
	_check(group.get_rating() > squadrons[0].get_rating() * 2.0, "a battle group's rating counts the squadrons inside it")
	_check(group.get_root_lead() == group.lead and squadrons[0].get_root_lead() == group.lead, "every ship follows the battle group leader's route")
	var squadron_error: float = squadrons[0].get_slot_error(squadrons[0].get_members()[0])
	_check(squadron_error < 1.0, "a new battle group starts with its squadrons snapped into their slots (%.1f px)" % squadron_error)
	await _clear()


func _test_battle_group_holds() -> void:
	var group := _spawn(_battle_group_plan()) as Formation
	var result := await _measure(group, 55.0, 15.0)
	_check(_fraction(result) >= 0.85, "every ship in a battle group and its squadrons holds station while it flies (%.0f%% of the time, worst %d px)" % [_fraction(result) * 100.0, int(result["worst"])])
	_check(result["closest"] >= 0.6, "no two ships collide (closest %.2f of their combined sizes)" % result["closest"])
	_check(_count("lost") == 0 and _count("dissolved") == 0, "nobody is lost along the way")
	await _clear()


func _test_battle_group_shapes() -> void:
	for shape_id in [&"diamond", &"wedge", &"screen"]:
		var group := _spawn(_battle_group_plan(shape_id)) as Formation
		var result := await _measure(group, 24.0, 12.0)
		_check(_fraction(result) >= 0.8, "%s: a battle group holds its squadrons in place (%.0f%%, worst %d px)" % [shape_id, _fraction(result) * 100.0, int(result["worst"])])
		_check(result["closest"] >= 0.6, "%s: no collisions (closest %.2f)" % [shape_id, result["closest"]])
		await _clear()


func _test_squadron_leader_destroyed() -> void:
	var group := _spawn(_battle_group_plan()) as Formation
	await _run(6.0)
	var squadron: Formation = _formations_of(group).filter(func(formation: Formation) -> bool: return formation != group)[0]
	var old_lead = squadron.lead
	var size_before := group.size()
	var slot_before: int = group.get_slot(old_lead).index
	_kill(old_lead)
	await _run(0.1)
	_check(squadron.lead != old_lead and squadron.has_valid_lead(), "the squadron promotes a new leader (%s)" % squadron.lead.ship_type.display_name)
	var new_lead: NpcShip = squadron.lead
	_check(new_lead.formation == group and new_lead.led_formation == squadron, "the new leader takes the old one's place in the battle group")
	var holds_old := false
	for ship in group.get_ships():
		holds_old = holds_old or ship == old_lead
	_check(group.get_ships().has(new_lead) and not holds_old, "the battle group holds the new leader, not the dead one")
	_check(group.size() == size_before, "the battle group does not shrink (%d)" % group.size())
	_check(_count("lost") == 0, "so the battle group reports no loss")
	_check(new_lead.state == NpcShip.State.IN_FORMATION, "the new leader flies in the battle group's formation")
	await _run(20.0)
	_check(group.get_slot(new_lead) != null and group.get_slot_error(new_lead) <= group.station_tolerance * 2.0,
			"the new leader is on station in the battle group (%d px)" % int(group.get_slot_error(new_lead)))
	_check(_all_near(_formations_of(group)), "and its squadron re-forms behind it")
	_check(slot_before >= 0, "(the old leader had a slot)")
	await _clear()


func _test_battle_group_leader_destroyed() -> void:
	var group := _spawn(_battle_group_plan()) as Formation
	await _run(6.0)
	var squadrons := _formations_of(group).filter(func(formation: Formation) -> bool: return formation != group)
	var old_lead: NpcShip = group.lead
	var old_state := old_lead.state
	_kill(old_lead)
	await _run(0.1)
	_check(group.lead != old_lead and group.has_valid_lead(), "the battle group promotes a new leader")
	_check(group.lead.ship_type.stats.id == FRIGATE, "the strongest ship that leads nothing else, the frigate, takes over")
	_check(group.lead.led_formation == group and group.lead.formation == null, "it leads the battle group and follows nobody")
	_check(group.lead.state == old_state or group.lead.state == NpcShip.State.WANDERING, "and carries on the old leader's route")
	_check(_count("leader") == 1, "the change is announced once")
	for squadron in squadrons:
		_check(is_instance_valid(squadron) and squadron.parent == group, "the squadrons are still part of the battle group")
	await _run(22.0)
	_check(_all_near(_formations_of(group)), "everyone settles into the new battle group (worst %d px)" % int(_worst_error(_formations_of(group))))
	await _clear()


func _test_squadron_dissolves() -> void:
	var group := _spawn(_battle_group_plan()) as Formation
	await _run(5.0)
	var squadron: Formation = _formations_of(group).filter(func(formation: Formation) -> bool: return formation != group)[0]
	var members := squadron.get_members()
	var old_lead: NpcShip = squadron.lead
	_kill(members[0])
	await _run(0.2)
	_check(is_instance_valid(squadron) and squadron.size() == 2, "a squadron of two is still a squadron")
	_kill(old_lead)
	await _run(0.3)
	var survivor: NpcShip = members[1]
	_check(not is_instance_valid(squadron) or squadron.is_queued_for_deletion(), "a squadron left with one ship dissolves")
	_check(is_instance_valid(survivor) and survivor.formation == group and survivor.state == NpcShip.State.IN_FORMATION,
			"its survivor is taken in by the battle group")
	_check(group.get_ships().has(survivor) and group.get_slot(survivor) != null, "... and has a slot in it")
	await _run(14.0)
	_check(group.get_slot_error(survivor) <= group.station_tolerance * 2.0, "... which it holds (%d px)" % int(group.get_slot_error(survivor)))
	var other: Formation = _formations_of(group).filter(func(formation: Formation) -> bool: return formation != group)[0]
	_check(other.parent == group and other.size() == 3, "the other squadron is untouched")
	await _clear()


func _test_nested_jump() -> void:
	var plan := _battle_group_plan()
	var group := _spawn(plan, Vector2(-300.0, 0.0), 0.0, false) as Formation
	var all_ships := group.get_all_ships()
	var lead := group.lead
	lead.configure_jumping(_system.global_position, _system.jump_radius, [Vector2.RIGHT])
	lead.begin_arrival(Vector2.RIGHT)
	await physics_frame
	await physics_frame
	var squadrons := _formations_of(group).filter(func(formation: Formation) -> bool: return formation != group)
	var worst := 0.0
	var frames := 0
	while lead.state == NpcShip.State.ARRIVING:
		_check_once(squadrons[0].is_slaved() and group.is_slaved(), "while the battle group's leader jumps in, its squadrons are locked too")
		for squadron in squadrons:
			for ship in squadron.get_members():
				var ideal: Vector2 = squadron.lead.global_position + squadron.get_slot(ship).offset.rotated(squadron.get_frame_heading())
				worst = maxf(worst, ship.global_position.distance_to(ideal))
		frames += 1
		await physics_frame
		if frames > 600:
			break
	_check(frames > 5 and worst < 90.0, "a squadron's ships stay on their slots through the jump (worst %d px over %d frames)" % [int(worst), frames])
	_check(not squadrons[0].is_slaved() and squadrons[0].get_members().all(func(ship: NpcShip) -> bool: return ship.state == NpcShip.State.IN_FORMATION),
			"the squadrons are released into normal flight, still in formation")

	var warped := false
	for step in int(40.0 / DT):
		await physics_frame
		if lead.state == NpcShip.State.WARPING:
			warped = true
			break
	_check(warped, "the battle group's leader flies out and starts to jump")
	await physics_frame
	await physics_frame
	var all_off := true
	for squadron in squadrons:
		for ship in squadron.get_members():
			all_off = all_off and not ship.get_node("Targetable").is_enabled()
	_check(all_off, "the squadrons' ships stop being targetable as they jump with it")
	for step in int(10.0 / DT):
		await physics_frame
		if not is_instance_valid(lead) or lead.is_queued_for_deletion():
			break
	for i in 4:
		await physics_frame
	var all_gone := all_ships.all(func(ship) -> bool: return not is_instance_valid(ship) or ship.is_queued_for_deletion())
	_check(all_gone, "the whole battle group, its squadrons included, leaves with its leader")
	await _clear()


func _test_convoy_plan() -> void:
	var plan := _unit(&"convoy", [&"bulk_freighter", &"freighter", &"interceptor", &"interceptor", &"light_frigate"], &"convoy")
	var convoy := _spawn(plan) as Formation
	_check(convoy != null and convoy.kind == Formation.Kind.CONVOY, "a convoy plan gives a convoy")
	_check(convoy.lead.ship_type.stats.ship_class.carries_cargo(), "a freighter leads it")
	_check(convoy.get_flagship().ship_type.stats.ship_class.id != &"freighter", "its flagship is an escort, not a freighter")
	var result := await _measure(convoy, 28.0, 10.0)
	_check(_fraction(result) >= 0.85, "a convoy built from a plan holds its ring (%.0f%%, worst %d px)" % [_fraction(result) * 100.0, int(result["worst"])])
	await _clear()


func _test_fleet_structure() -> void:
	var fleet := _spawn(_fleet_plan(), TRACK[0], 0.0) as WarFleet
	await physics_frame
	_check(fleet != null and fleet.has_flagship(), "spawning a fleet plan gives a fleet with a flagship")
	_check(fleet.flagship.ship_type.stats.ship_class.is_capital(), "the flagship is a capital ship")
	_check(fleet.flagship.formation == null and fleet.flagship.led_formation == null, "a fleet has no formation: its flagship leads nothing and follows nothing")
	_check(fleet.get_battle_groups().size() == 2, "the fleet has its two battle groups")
	_check(fleet.get_units().size() == 3, "three units are on its leash: the other capital ship and each battle group's leader (%d)" % fleet.get_units().size())
	for unit in fleet.get_units():
		_check(unit.fleet == fleet, "each unit knows its fleet")
	_check(fleet.flagship.fleet == fleet, "so does the flagship")
	_check(fleet.get_all_ships().size() == 2 + 2 * 8, "the fleet holds every ship of the plan (%d)" % fleet.get_all_ships().size())
	_check(fleet.cohesion_radius >= fleet.tuning.fleet_cohesion_radius, "the cohesion radius is at least the tuned one (%d)" % int(fleet.cohesion_radius))

	var slowest := INF
	for unit in fleet.get_units():
		slowest = minf(slowest, unit.effective_max_speed())
	_check(fleet.flagship.formation_speed_cap <= slowest * 0.9 + 0.01, "the flagship is held to 90%% of the slowest part's speed (%d)" % int(fleet.flagship.formation_speed_cap))
	_check(fleet.get_rating() > 0.0, "a fleet has a rating")

	# The parts start apart: no overlapping ships.
	var ships := fleet.get_all_ships()
	var closest := _closest_ratio(ships)
	_check(closest >= 0.95, "a new fleet has no overlapping ships (closest %.2f)" % closest)
	var groups := fleet.get_battle_groups()
	var apart := true
	for a in groups.size():
		for b in range(a + 1, groups.size()):
			var gap: float = groups[a].lead.global_position.distance_to(groups[b].lead.global_position)
			if gap < groups[a].get_extent() + groups[b].get_extent():
				apart = false
	_check(apart, "the battle groups start clear of each other")

	# They keep together over time.
	var worst_gap := 0.0
	var recalled_ever := false
	var near_group := 0
	var off_by_kind := {}
	var samples := 0
	for step in int(60.0 / DT):
		await physics_frame
		for unit in fleet.get_units():
			worst_gap = maxf(worst_gap, unit.global_position.distance_to(fleet.flagship.global_position))
			recalled_ever = recalled_ever or fleet.is_recalled(unit)
		if step * DT > 20.0 and step % 10 == 0:
			samples += 1
			near_group += 1 if _all_near(_fleet_formations(fleet)) else 0
			for formation in _fleet_formations(fleet):
				if not _all_near([formation] as Array[Formation]):
					off_by_kind[formation.kind] = off_by_kind.get(formation.kind, 0) + 1
	_check(worst_gap <= fleet.cohesion_radius * 1.6, "no part strays far beyond the cohesion radius (%d of %d px)" % [int(worst_gap), int(fleet.cohesion_radius)])
	_check(float(near_group) / maxf(float(samples), 1.0) >= 0.7, "the battle groups hold their own formations while the fleet moves (%d / %d, off by kind %s)" % [near_group, samples, off_by_kind])
	_check(recalled_ever or worst_gap < fleet.cohesion_radius, "(a unit that left the radius was recalled: %s)" % recalled_ever)
	await _clear()


func _test_fleet_leash() -> void:
	var fleet := _spawn(_fleet_plan(), TRACK[0], 0.0) as WarFleet
	await _run(3.0)
	var capital: NpcShip = fleet.get_units().filter(func(ship: NpcShip) -> bool: return ship.ship_type.stats.ship_class.is_capital())[0]
	_check(not fleet.is_recalled(capital), "a part inside the radius flies its own route")
	var far := fleet.flagship.global_position + Vector2(-1.0, 0.0) * fleet.cohesion_radius * 1.5
	capital.global_position = far
	capital.velocity = Vector2.ZERO
	await _run(0.2)
	_check(fleet.is_recalled(capital) and capital.recall_target == fleet.flagship, "a part beyond the radius is recalled")
	var returned := false
	var held_off_flagship := true
	for step in int(90.0 / DT):
		await physics_frame
		if capital.global_position.distance_to(fleet.flagship.global_position) < capital.get_hit_radius() + fleet.flagship.get_hit_radius():
			held_off_flagship = false
		if not fleet.is_recalled(capital):
			returned = true
			break
	_check(returned, "it flies back and is released once within %d%% of the radius" % int(fleet.tuning.fleet_release_fraction * 100.0))
	_check(capital.recall_target == null, "and goes back to its own route")
	_check(held_off_flagship, "it never ran into the flagship on the way")
	_check(capital.global_position.distance_to(fleet.flagship.global_position) <= fleet.cohesion_radius, "it is back inside the radius")
	await _clear()


func _test_flagship_lost() -> void:
	var fleet := _spawn(_fleet_plan(), TRACK[0], 0.0) as WarFleet
	await _run(4.0)
	var old_flagship := fleet.flagship
	var capital: NpcShip = fleet.get_units().filter(func(ship: NpcShip) -> bool: return ship.ship_type.stats.ship_class.is_capital())[0]
	var groups := fleet.get_battle_groups()
	_kill(old_flagship)
	await _run(0.2)
	_check(fleet.has_flagship() and fleet.flagship == capital, "when the flagship falls, the other capital ship becomes the flagship")
	_check(_count("flagship") == 1, "the change is announced once")
	_check(not fleet.get_units().has(capital) and fleet.get_units().size() == 2, "it leaves the leash and the battle group leaders stay on it")
	_check(capital.fleet == fleet, "(it is still in the fleet)")
	await _run(3.0)
	_check(is_instance_valid(fleet) and fleet.flagship.formation_speed_cap < INF, "the new flagship is speed-limited like the old one")
	_kill(fleet.flagship)
	await _run(0.3)
	_check(_count("fleet_dissolved") == 1, "with no capital ship left the fleet dissolves")
	var released := true
	for group in groups:
		if is_instance_valid(group) and is_instance_valid(group.lead):
			released = released and group.lead.fleet == null and group.lead.recall_target == null
	_check(released, "and its battle groups carry on alone")
	_check(groups.all(func(group) -> bool: return is_instance_valid(group) and group.size() == 4), "... still in formation")
	await _clear()


## Every battle group of the fleet and every squadron inside them.
func _fleet_formations(fleet: WarFleet) -> Array[Formation]:
	var result: Array[Formation] = []
	for group in fleet.get_battle_groups():
		for formation in _formations_of(group):
			if not result.has(formation):
				result.append(formation)
	return result


func _fleet_plan() -> FormationPlan:
	return _unit(&"fleet", [CAPITAL, CAPITAL], &"", [_battle_group_plan(&"screen", 2), _battle_group_plan(&"diamond", 2)])


var _once: Dictionary = {}


## A check inside a loop that is reported once.
func _check_once(condition: bool, label: String) -> void:
	if not condition:
		_check(false, label)
	elif not _once.has(label):
		_once[label] = true
		_check(true, label)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
