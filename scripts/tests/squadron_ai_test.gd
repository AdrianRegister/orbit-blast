extends SceneTree
## Tests the unit commander (Phase 3.3, step 4) in the real game scene: a squadron meets
## an enemy and goes through its states, shares out its targets, re-forms afterwards,
## re-allocates when it loses ships, and withdraws when it is outmatched; a convoy's
## escorts guard its freighters while the freighters fly on. Time is sped up
## (Engine.time_scale), so it takes a minute or two. Run with:
##   Godot --headless --path . --script res://scripts/tests/squadron_ai_test.gd </dev/null
## Pass scenario names after `--` to run only some: basics, fight, losses, leader, withdraw, convoy.
##
## (Ships get destroyed and freed during these fights: conditions read them through
## helpers that cope with that, and never capture them in a lambda.)

const SPEED := 5.0
const ALL := ["basics", "fight", "losses", "leader", "withdraw", "convoy"]
const State := Formation.State

var _failures: int = 0
var _main: Main
var _system: StarSystem
var _player: PlayerShip
var _sandbox: CombatSandbox
var _combat: CombatManager
var _registry: ContentRegistry
var _centre: Vector2
var _parked: Vector2 = Vector2(30000.0, 30000.0)


func _init() -> void:
	seed(20260417)
	_registry = ContentRegistry.new()
	_main = CombatSandbox.build_main()
	root.add_child(_main)
	for i in 5:
		await process_frame
	_system = _main.get_system()
	_player = _main.get_player_ship()
	_combat = _main.get_node("Combat")
	for child in _main.get_children():
		if child is CombatSandbox:
			_sandbox = child
	_centre = _system.global_position
	_player.global_position = _parked
	await _clear()

	var wanted: Array = OS.get_cmdline_user_args()
	if wanted.is_empty():
		wanted = ALL
	Engine.time_scale = SPEED
	for name in wanted:
		match name:
			"basics":
				await _test_basics()
			"fight":
				await _test_fight()
			"losses":
				await _test_losses()
			"leader":
				await _test_wounded_leader()
			"withdraw":
				await _test_withdraw()
			"convoy":
				await _test_convoy()
	Engine.time_scale = 1.0

	print("SQUADRON AI TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _type(id: StringName) -> ShipType:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(id)
	return type


## A formation of `models` for `faction`, its leader at `offset` from the middle of the system.
func _unit(kind: Formation.Kind, shape_id: StringName, models: Array, faction: StringName, offset: Vector2, heading: float = 0.0) -> Formation:
	var types: Array[ShipType] = []
	for model in models:
		types.append(_type(model))
	return FleetSpawner.spawn_formation(_system, _player, CombatSandbox.TRAFFIC_CONFIG, kind, _registry.formation_shape(shape_id),
			types, _centre + offset, heading, faction, 300.0)


## A lone ship, held still unless `free` (then it is a free agent that fights on its own).
func _ship(model: StringName, faction: StringName, offset: Vector2, heading: float = PI, free: bool = false) -> NpcShip:
	var ship := _sandbox.spawn_ship(_type(model), faction, _centre + offset, heading, CombatSandbox.BATTLE_EXITS)
	if not free:
		ship.set_physics_process(false)
	return ship


func _clear() -> void:
	_sandbox.clear_formations()
	_sandbox.clear_battle()
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	await process_frame
	await process_frame
	_combat.get_picture().refresh()


## (untyped: `ship` may already be freed)
func _gone(ship) -> bool:
	return not is_instance_valid(ship) or ship.is_queued_for_deletion() or not ship.get_combatant().is_alive()


func _alive_count(ships: Array) -> int:
	var count := 0
	for ship in ships:
		if not _gone(ship):
			count += 1
	return count


func _wait_until(condition: Callable, limit: float, step: float = 0.5) -> bool:
	var waited := 0.0
	while waited < limit:
		if condition.call():
			return true
		await create_timer(step).timeout
		waited += step
	return condition.call()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _state(unit) -> int:
	return unit.state if is_instance_valid(unit) else -1


## The kind of order a ship's pilot holds, or -1 for none (or the ship is gone).
func _order_kind(ship) -> int:
	if _gone(ship) or ship.get_pilot().order == null:
		return -1
	return ship.get_pilot().order.kind


func _order_target(ship) -> Combatant:
	if _gone(ship) or ship.get_pilot().order == null:
		return null
	return ship.get_pilot().order.target


# ----------------------------------------------------------------------- tests

func _test_basics() -> void:
	var squadron := _unit(Formation.Kind.SQUADRON, &"wedge", [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter"], &"faction_1", Vector2(-6000.0, 0.0))
	await _wait(3.0)
	_check(squadron.commander != null and squadron.commander.get_parent() == squadron, "a formation has a commander")
	_check(squadron.state == State.FOLLOWING and squadron.commander.get_state() == State.FOLLOWING, "with no enemy in sight the unit is FOLLOWING its route")
	var held := true
	var firing := true
	for ship in squadron.get_ships():
		held = held and (ship == squadron.lead or ship.state == NpcShip.State.IN_FORMATION)
		firing = firing and _order_kind(ship) == CombatOrder.Kind.FIRE_AT_WILL
	_check(held, "...its members hold their slots")
	_check(firing, "...and every ship is told to fire at will at what comes in reach")
	_check(TacticalProfile.default().validate().is_empty(), "the default tactical profile is valid")
	await _clear()


func _test_fight() -> void:
	var squadron := _unit(Formation.Kind.SQUADRON, &"wedge", [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"], &"faction_1", Vector2(-2500.0, 0.0))
	var box := {"unit": squadron, "enemies": []}
	box["start_shape"] = squadron.shape
	for offset in [Vector2(1200.0, -200.0), Vector2(1200.0, 0.0), Vector2(1200.0, 200.0)]:
		box["enemies"].append(_ship(&"hegemony_fighter", &"faction_2", offset, PI, true))
	var members: Array = squadron.get_ships()
	var saw_intercept := {"value": false, "shape": null}
	var reached := await _wait_until(func() -> bool:
		var unit = box["unit"]
		if is_instance_valid(unit) and unit.state == State.INTERCEPTING:
			saw_intercept["value"] = true
			saw_intercept["shape"] = unit.shape
		return _state(unit) == State.ATTACKING, 40.0, 0.25)
	_check(reached, "a unit that meets an enemy goes to ATTACKING (it passed through INTERCEPTING: %s)" % saw_intercept["value"])
	if saw_intercept["value"]:
		_check(saw_intercept["shape"] == _registry.formation_shape(&"screen"), "...meeting light craft in a screen")

	await _wait(3.0)
	var engaged := 0
	var with_targets := 0
	var targets := {}
	for ship in members:
		if _order_kind(ship) == CombatOrder.Kind.ENGAGE:
			engaged += 1
			var target := _order_target(ship)
			if target != null:
				with_targets += 1
				targets[target] = targets.get(target, 0) + 1
	_check(engaged == _alive_count(members) and engaged >= 3, "every armed ship fights under an ENGAGE order (%d)" % engaged)
	_check(with_targets >= 3, "...and the commander named a target for them (%d)" % with_targets)
	_check(targets.size() >= 2, "...not all on the same enemy (%d different targets)" % targets.size())
	var broke := false
	for ship in members:
		broke = broke or (not _gone(ship) and ship.state == NpcShip.State.ENGAGED)
	_check(broke, "the ships have left their slots to fight")

	var won := await _wait_until(func() -> bool: return _alive_count(box["enemies"]) == 0, 90.0)
	_check(won, "the squadron wins (%d of %d enemies left)" % [_alive_count(box["enemies"]), box["enemies"].size()])
	var calm := await _wait_until(func() -> bool: return _state(box["unit"]) == State.FOLLOWING, 30.0)
	_check(calm, "afterwards it goes back to FOLLOWING")
	var back := await _wait_until(func() -> bool:
		var unit = box["unit"]
		if not is_instance_valid(unit):
			return false
		for ship in unit.get_members():
			if ship.state != NpcShip.State.IN_FORMATION:
				return false
		return true, 40.0)
	_check(back, "...its ships fly back to their slots")
	var unit = box["unit"]
	if is_instance_valid(unit):
		_check(unit.shape == box["start_shape"], "...and it takes its own shape again")
		var orders_cleared := true
		for ship in unit.get_ships():
			orders_cleared = orders_cleared and _order_kind(ship) in [-1, CombatOrder.Kind.FIRE_AT_WILL]
		_check(orders_cleared, "...with nobody still ordered to fight")
		_check(unit.size() >= 3, "...with most of the squadron alive (%d)" % unit.size())
	await _clear()


func _test_losses() -> void:
	var squadron := _unit(Formation.Kind.SQUADRON, &"wedge", [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"], &"faction_1", Vector2(-1500.0, 0.0))
	var box := {"unit": squadron, "enemies": []}
	for offset in [Vector2(1000.0, -300.0), Vector2(1000.0, 0.0), Vector2(1000.0, 300.0)]:
		box["enemies"].append(_ship(&"hegemony_fighter", &"faction_2", offset, PI, true))
	await _wait_until(func() -> bool: return _state(box["unit"]) == State.ATTACKING, 30.0, 0.25)
	await _wait(2.0)
	var member: NpcShip = squadron.get_members()[0]
	box["victim"] = member
	_sandbox.kill_ship(member)
	await _wait(2.0)
	var alive := squadron.get_ships()
	var all_ordered := true
	var none_dead := true
	for ship in alive:
		if ship.get_combatant().is_armed():
			all_ordered = all_ordered and _order_kind(ship) == CombatOrder.Kind.ENGAGE
			var target := _order_target(ship)
			none_dead = none_dead and (target == null or (is_instance_valid(target) and target.is_alive()))
	_check(_state(squadron) == State.ATTACKING or squadron.size() == 0 or _alive_count(box["enemies"]) == 0, "losing a ship does not end the fight")
	_check(all_ordered and none_dead, "after a loss the survivors are ordered again, none to a dead target")

	if _alive_count(box["enemies"]) > 0 and is_instance_valid(squadron) and squadron.has_valid_lead():
		var lead := squadron.lead
		_sandbox.kill_ship(lead)
		await _wait(2.0)
		if is_instance_valid(squadron) and squadron.has_valid_lead():
			_check(squadron.lead != lead and squadron.lead != null, "a new leader takes over when the leader is lost")
			var wanted := {State.ATTACKING: CombatOrder.Kind.ENGAGE, State.WITHDRAWING: CombatOrder.Kind.WITHDRAW}
			var kind: int = wanted.get(squadron.state, CombatOrder.Kind.FIRE_AT_WILL)
			_check(_order_kind(squadron.lead) == kind, "...and is given the order that goes with what the unit is doing (state %d)" % squadron.state)
	await _clear()


## A wounded leader keeps fighting with its squadron until it dies (and then the next ship is
## promoted); the default profile withdraws only after 80% losses.
func _test_wounded_leader() -> void:
	var profile := TacticalProfile.default()
	_check(profile.flagship_withdraw_hull == 0.0 and profile.max_odds == 0.0 and is_equal_approx(profile.withdraw_losses, 0.8), "the default profile withdraws only at 80% losses")
	var squadron := _unit(Formation.Kind.SQUADRON, &"wedge", [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"], &"faction_1", Vector2(-1500.0, 0.0))
	var box := {"unit": squadron, "enemies": []}
	for offset in [Vector2(1000.0, -300.0), Vector2(1000.0, 0.0), Vector2(1000.0, 300.0), Vector2(1000.0, 500.0)]:
		box["enemies"].append(_ship(&"hegemony_fighter", &"faction_2", offset, PI, true))
	await _wait_until(func() -> bool: return _state(box["unit"]) == State.ATTACKING, 30.0, 0.25)
	await _wait(1.0)
	var lead := squadron.lead
	var wounded: NpcShip = squadron.get_members()[0]
	var wounded_state: DefenceState = wounded.get_combatant().health.state
	wounded_state.hull = wounded_state.max_hull * 0.05  # (below the formation's disabled limit)
	await _wait(1.0)
	_check(_gone(wounded) or wounded.formation == squadron, "a badly wounded member is not released while the unit is fighting")
	var state: DefenceState = lead.get_combatant().health.state
	state.hull = state.max_hull * 0.05  # (it is nearly dead; its doctrine would have it run)
	await _wait(0.5)
	var steps := 0
	var held := true
	var ran := false
	var withdrew := false
	while steps < 12 and not _gone(lead):  # (until it dies, if it does)
		await _wait(0.25)
		steps += 1
		if _gone(lead):
			break
		ran = ran or lead.get_pilot().mode == ShipPilot.Mode.RETREAT
		withdrew = withdrew or _state(box["unit"]) == State.WITHDRAWING
		held = held and _order_kind(lead) == CombatOrder.Kind.ENGAGE
	_check(not withdrew, "a leader at 5% hull does not make the unit withdraw")
	_check(not ran, "...and does not run from the fight itself")
	_check(held, "...it keeps its ENGAGE order")
	_check(is_instance_valid(squadron) and squadron.size() >= 2, "the squadron is still there")
	if _gone(lead) and is_instance_valid(squadron) and squadron.has_valid_lead():
		_check(squadron.lead != lead and _state(squadron) != State.WITHDRAWING, "when it dies the next ship is promoted and the unit fights on")
	await _clear()


func _test_withdraw() -> void:
	var squadron := _unit(Formation.Kind.SQUADRON, &"wedge", [&"federation_fighter", &"federation_fighter"], &"faction_1", Vector2(-1500.0, 0.0))
	var cautious := TacticalProfile.default().duplicate() as TacticalProfile  # (the default only withdraws at 80% losses)
	cautious.max_odds = 2.5
	squadron.commander.profile = cautious
	var box := {"unit": squadron, "enemies": []}
	for model in [&"hegemony_cruiser", &"hegemony_cruiser", &"hegemony_frigate"]:
		box["enemies"].append(_ship(model, &"faction_2", Vector2(1200.0, randf_range(-300.0, 300.0)), PI))
	var lead := squadron.lead
	var start := lead.global_position
	_check(start != Vector2.ZERO and lead != null, "(the scenario ran)")
	var enemy_centre := _centre + Vector2(1200.0, 0.0)
	var started := await _wait_until(func() -> bool: return _state(box["unit"]) == State.WITHDRAWING, 40.0, 0.25)
	_check(started, "a unit that is far weaker than the enemy goes to WITHDRAWING")
	if started and is_instance_valid(squadron) and squadron.has_valid_lead():
		await _wait(1.5)
		_check(_order_kind(squadron.lead) == CombatOrder.Kind.WITHDRAW, "its leader is ordered to withdraw")
		var others_hold := true
		for ship in squadron.get_members():
			others_hold = others_hold and ship.state == NpcShip.State.IN_FORMATION
		_check(others_hold, "...and the rest keep their slots (the unit leaves together)")
		var before := squadron.lead.global_position.distance_to(enemy_centre)
		box["before"] = before
		box["enemy_centre"] = enemy_centre
		# (it first has to stop closing on the enemy and turn round)
		var ran := await _wait_until(func() -> bool:
			var unit = box["unit"]
			return not is_instance_valid(unit) or not unit.has_valid_lead() or unit.lead.global_position.distance_to(box["enemy_centre"]) > box["before"] + 500.0, 30.0)
		_check(ran, "the unit runs from the enemy")
	await _clear()


func _test_convoy() -> void:
	var convoy := _unit(Formation.Kind.CONVOY, &"convoy_diamond", [&"freighter", &"freighter", &"federation_fighter", &"federation_fighter"], &"faction_1", Vector2(-1500.0, 0.0))
	var box := {"unit": convoy, "enemies": []}
	var freighters: Array = []
	var escorts: Array = []
	for ship in convoy.get_ships():
		if ship.get_pilot().doctrine == null:
			freighters.append(ship)
		else:
			escorts.append(ship)
	var start_shape := convoy.shape
	for offset in [Vector2(1000.0, 0.0)]:
		box["enemies"].append(_ship(&"federation_fighter", &"faction_3", offset, PI, true))
	var defending := await _wait_until(func() -> bool: return _state(box["unit"]) == State.DEFENDING, 30.0, 0.25)
	_check(defending, "a convoy that sees an enemy goes to DEFENDING")
	var guarding := await _wait_until(func() -> bool:
		for ship in escorts:
			if _order_kind(ship) == CombatOrder.Kind.GUARD:
				return true
		return false, 30.0, 0.25)
	_check(guarding, "...its escorts get GUARD orders when the enemy comes near the freighters")
	var freighters_flew := true
	var shape_kept := true
	var steps := 0
	while steps < 80 and _alive_count(box["enemies"]) > 0:
		await _wait(0.5)
		steps += 1
		for ship in freighters:
			freighters_flew = freighters_flew and (_gone(ship) or ship.state != NpcShip.State.ENGAGED)
		shape_kept = shape_kept and (not is_instance_valid(convoy) or convoy.shape == start_shape)
	_check(freighters_flew, "the freighters never leave the convoy to fight")
	_check(shape_kept, "a convoy keeps its shape (its freighters are the middle of it)")
	_check(_alive_count(box["enemies"]) == 0, "the escorts drive off or destroy the attackers (%d left)" % _alive_count(box["enemies"]))
	var calm := await _wait_until(func() -> bool: return _state(box["unit"]) == State.FOLLOWING, 30.0)
	_check(calm, "afterwards it goes back to FOLLOWING")
	var back := await _wait_until(func() -> bool:
		var unit = box["unit"]
		if not is_instance_valid(unit):
			return false
		for ship in unit.get_members():
			if ship.state != NpcShip.State.IN_FORMATION:
				return false
		return true, 40.0)
	_check(back, "...and the escorts are back in their slots")
	await _clear()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
