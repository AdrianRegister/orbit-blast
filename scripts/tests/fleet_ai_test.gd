extends SceneTree
## Tests battle group roles and fleet command (Phase 3.3, step 5) in the real game scene:
## a battle group splits its squadrons into a screen and a strike force, a fleet matches its
## battle groups to the enemy's units, keeps its capital ships back, holds or defends a
## point, intercepts a target, withdraws on order, and fights on when its flagship is lost.
## Time is sped up (Engine.time_scale). Run with:
##   Godot --headless --path . --script res://scripts/tests/fleet_ai_test.gd </dev/null
## Pass scenario names after `--` to run only some: roles, fleet, objectives, withdraw, flagship.
##
## (Ships get destroyed and freed during these fights: conditions read them through helpers
## that cope with that, and never capture them in a lambda.)

const SPEED := 5.0
const ALL := ["roles", "fleet", "objectives", "withdraw", "flagship"]
const State := Formation.State
const Role := UnitCommander.Role
const Directive := UnitCommander.Directive

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
	seed(20260418)
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
			"roles":
				await _test_roles()
			"fleet":
				await _test_fleet()
			"objectives":
				await _test_objectives()
			"withdraw":
				await _test_withdraw()
			"flagship":
				await _test_flagship()
	Engine.time_scale = 1.0

	print("FLEET AI TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _type(id: StringName) -> ShipType:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(id)
	return type


## A plan written by hand, so the tests do not depend on a random draw.
func _plan(recipe_id: StringName, ids: Array, shape_id: StringName = &"", children: Array = []) -> FormationPlan:
	var plan := FormationPlan.new()
	plan.recipe = _registry.formation_recipe(recipe_id)
	for id in ids:
		plan.ships.append(_type(id))
	if shape_id != &"":
		plan.shape = _registry.formation_shape(shape_id)
	for child in children:
		plan.children.append(child)
	return plan


func _squadron() -> FormationPlan:
	return _plan(&"squadron", [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter"], &"wedge")


func _battle_group_plan(squadrons: int = 2) -> FormationPlan:
	var children: Array = []
	for i in squadrons:
		children.append(_squadron())
	return _plan(&"battle_group", [&"federation_cruiser", &"federation_frigate"], &"screen", children)


func _spawn(plan: FormationPlan, offset: Vector2, heading: float = 0.0) -> Node:
	var none: Array[Vector2] = []
	return FleetSpawner.spawn_plan(_system, _player, CombatSandbox.TRAFFIC_CONFIG, plan, _centre + offset, heading, &"faction_1", 300.0, null, none)


## An enemy ship (Hegemony), free to fight unless `frozen`.
func _enemy(model: StringName, offset: Vector2, frozen: bool = false, faction: StringName = &"faction_2") -> NpcShip:
	var ship := _sandbox.spawn_ship(_type(model), faction, _centre + offset, PI, CombatSandbox.BATTLE_EXITS)
	if frozen:
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


func _order_kind(ship) -> int:
	if _gone(ship) or ship.get_pilot().order == null:
		return -1
	return ship.get_pilot().order.kind


## The commanders of the squadrons of a battle group.
func _squadrons(group: Formation) -> Array[UnitCommander]:
	var result: Array[UnitCommander] = []
	for ship in group.get_ships():
		if ship.led_formation != null and ship.led_formation != group:
			result.append(ship.led_formation.commander)
	return result


# ----------------------------------------------------------------------- tests

func _test_roles() -> void:
	var group: Formation = _spawn(_battle_group_plan(2), Vector2(-3000.0, 0.0))
	var box := {"group": group, "enemies": []}
	for offset in [Vector2(1000.0, -300.0), Vector2(1000.0, 0.0), Vector2(1000.0, 300.0)]:
		box["enemies"].append(_enemy(&"hegemony_fighter", offset))
	var squadrons := _squadrons(group)
	_check(squadrons.size() == 2, "a battle group has two squadron commanders under it")
	var attacking := await _wait_until(func() -> bool: return is_instance_valid(box["group"]) and box["group"].state == State.ATTACKING, 40.0, 0.25)
	_check(attacking, "the battle group goes to ATTACKING")
	await _wait(2.0)
	var roles: Array = squadrons.map(func(c: UnitCommander) -> int: return c.role)
	_check(roles.count(Role.SCREEN) == 1 and roles.count(Role.STRIKE) == 1, "against light craft one squadron screens and the other strikes (%s)" % [roles])
	var screen: UnitCommander
	var strike: UnitCommander
	for commander in squadrons:
		if commander.role == Role.SCREEN:
			screen = commander
		elif commander.role == Role.STRIKE:
			strike = commander
	if screen != null and strike != null:
		_check(screen.get_state() == State.DEFENDING and strike.get_state() == State.ATTACKING, "...the screen is DEFENDING and the strikers ATTACKING")
		var core: Array[NpcShip] = group.commander.get_core_ships()
		var guards := 0
		var guarding_core := true
		box["screen"] = screen
		await _wait_until(func() -> bool:  # (they guard once an enemy comes near the big ships)
			for ship in box["screen"]._formation.get_ships():
				if _order_kind(ship) == CombatOrder.Kind.GUARD:
					return true
			return _alive_count(box["enemies"]) == 0, 40.0, 0.25)
		for ship in screen._formation.get_ships():
			if _order_kind(ship) == CombatOrder.Kind.GUARD:
				guards += 1
				guarding_core = guarding_core and core.has(ship.get_pilot().order.protectee)
		_check(guards >= 1 and guarding_core, "...the screen's ships guard the battle group's own big ships (%d guard orders)" % guards)
		var engaged := 0
		for ship in strike._formation.get_ships():
			if _order_kind(ship) == CombatOrder.Kind.ENGAGE:
				engaged += 1
		_check(engaged >= 2, "...the strike squadron's ships are ordered to engage (%d)" % engaged)
		_check(core.size() >= 2 and _order_kind(core[0]) == CombatOrder.Kind.ENGAGE, "...and the big ships fight under ENGAGE orders themselves")
	var won := await _wait_until(func() -> bool: return _alive_count(box["enemies"]) == 0, 120.0)
	_check(won, "the battle group wins (%d enemies left)" % _alive_count(box["enemies"]))
	var calm := await _wait_until(func() -> bool:
		if not is_instance_valid(box["group"]):
			return false
		for ship in box["group"].get_ships():
			if ship.led_formation != null and ship.led_formation != box["group"] and ship.led_formation.commander.role != Role.NONE:
				return false
		return box["group"].state == State.FOLLOWING, 40.0)
	_check(calm, "afterwards the roles are taken back and the unit is FOLLOWING again")
	await _clear()

	# --- No light craft: nobody needs screening, everyone strikes.
	group = _spawn(_battle_group_plan(2), Vector2(-2500.0, 0.0))
	box = {"group": group, "enemies": []}
	box["enemies"].append(_enemy(&"hegemony_cruiser", Vector2(1000.0, 0.0), true))
	squadrons = _squadrons(group)
	await _wait_until(func() -> bool: return is_instance_valid(box["group"]) and box["group"].state == State.ATTACKING, 40.0, 0.25)
	await _wait(2.0)
	var all_strike := true
	for commander in squadrons:
		all_strike = all_strike and commander.role == Role.STRIKE
	_check(all_strike, "against big ships only, every squadron strikes")
	await _clear()


func _test_fleet() -> void:
	var plan := _plan(&"fleet", [&"federation_capital_ship", &"federation_capital_ship"], &"", [_battle_group_plan(1), _battle_group_plan(1)])
	var fleet: WarFleet = _spawn(plan, Vector2(-4500.0, 0.0))
	await _wait(3.0)
	_check(fleet.commander != null and fleet.commander.get_parent() == fleet, "a fleet has a commander")
	_check(fleet.commander.get_state() == FleetCommander.State.FOLLOWING, "with no enemy in sight it is FOLLOWING")
	var held := true
	for group in fleet.get_battle_groups():
		held = held and group.commander.directive == Directive.HOLD
	_check(held and fleet.get_battle_groups().size() == 2, "...and its battle groups are told to hold, not to go out on their own")
	_check(_order_kind(fleet.flagship) == CombatOrder.Kind.FIRE_AT_WILL, "...and the flagship fires at will")

	# Two enemy units of different strength, and a lone cruiser, held still, 5000 px ahead.
	var box := {"fleet": fleet, "enemies": []}
	var squadron := _plan(&"squadron", [&"hegemony_heavy_fighter", &"hegemony_fighter", &"hegemony_fighter"], &"wedge")
	var small := _plan(&"squadron", [&"hegemony_fighter", &"hegemony_fighter"], &"wedge")
	var first: Formation = FleetSpawner.spawn_plan(_system, _player, CombatSandbox.TRAFFIC_CONFIG, squadron, _centre + Vector2(900.0, -500.0), PI, &"faction_2", 100.0)
	var second: Formation = FleetSpawner.spawn_plan(_system, _player, CombatSandbox.TRAFFIC_CONFIG, small, _centre + Vector2(900.0, 500.0), PI, &"faction_2", 100.0)
	for unit in [first, second]:
		for ship in unit.get_all_ships():
			ship.configure_jumping(_system.global_position, _system.jump_radius, CombatSandbox.BATTLE_EXITS)
			box["enemies"].append(ship)
	var engaging := await _wait_until(func() -> bool: return is_instance_valid(box["fleet"]) and box["fleet"].commander.get_state() == FleetCommander.State.ENGAGING, 60.0, 0.25)
	_check(engaging, "a fleet that sees the enemy goes to ENGAGING")
	await _wait(2.0)
	if is_instance_valid(fleet):
		var free := true
		var focuses: Array = []
		for group in fleet.get_battle_groups():
			free = free and group.commander.directive == Directive.FREE
			focuses.append(group.commander._focus)
		_check(free, "...its battle groups are set free to fight")
		var distinct: bool = focuses.size() == 2 and not focuses[0].is_empty() and not focuses[1].is_empty() and focuses[0] != focuses[1]
		_check(distinct, "...each matched to a different enemy unit (%s)" % [focuses.map(func(f: Array) -> int: return f.size())])
		var strongest: Formation = fleet.get_battle_groups()[0]
		for group in fleet.get_battle_groups():
			if group.get_rating() > strongest.get_rating():
				strongest = group
		var top_unit: Array = []
		if first.get_rating() >= second.get_rating():
			top_unit = first.get_all_ships().map(func(s: NpcShip) -> Combatant: return s.get_combatant())
		else:
			top_unit = second.get_all_ships().map(func(s: NpcShip) -> Combatant: return s.get_combatant())
		var matched: bool = strongest.commander._focus.size() > 0 and top_unit.has(strongest.commander._focus[0])
		_check(matched, "...the strongest group to the strongest enemy unit")
		var capitals_fight := true
		for ship in fleet.commander._capitals():
			capitals_fight = capitals_fight and (_order_kind(ship) == CombatOrder.Kind.ENGAGE or _gone(ship))
		_check(capitals_fight, "...and the capital ships are ordered to engage")
	var won := await _wait_until(func() -> bool: return _alive_count(box["enemies"]) == 0, 150.0)
	_check(won, "the fleet wins (%d enemies left)" % _alive_count(box["enemies"]))
	if won and is_instance_valid(fleet):
		var calm := await _wait_until(func() -> bool: return is_instance_valid(box["fleet"]) and box["fleet"].commander.get_state() == FleetCommander.State.FOLLOWING, 40.0)
		_check(calm, "afterwards it is FOLLOWING again")
	await _clear()


func _test_objectives() -> void:
	var plan := _plan(&"fleet", [&"federation_capital_ship", &"federation_capital_ship"], &"", [_battle_group_plan(1), _battle_group_plan(1)])
	var fleet: WarFleet = _spawn(plan, Vector2(-4500.0, 0.0))
	var box := {"fleet": fleet}
	var hold_point := _centre + Vector2(-4500.0, 1500.0)
	# DEFENSIVE: an enemy in sight but outside the area is not its business; the flagship goes to the point.
	var outsider := _enemy(&"hegemony_cruiser", Vector2(-1500.0, -1000.0), true)
	fleet.commander.set_objective(FleetCommander.Objective.DEFENSIVE, hold_point, null, 800.0)
	await _wait(4.0)
	_check(fleet.commander.get_state() == FleetCommander.State.FOLLOWING, "a defending fleet ignores an enemy outside its area")
	_check(_order_kind(fleet.flagship) == CombatOrder.Kind.MOVE, "...and its flagship is ordered to the point it holds")
	var before := fleet.flagship.global_position.distance_to(hold_point)
	await _wait(8.0)
	_check(fleet.flagship.global_position.distance_to(hold_point) < before, "...and heads for it")
	var intruder := _enemy(&"hegemony_frigate", Vector2.ZERO, true)
	intruder.global_position = hold_point + Vector2(300.0, 0.0)
	var engaged := await _wait_until(func() -> bool: return is_instance_valid(box["fleet"]) and box["fleet"].commander.get_state() == FleetCommander.State.ENGAGING, 20.0, 0.25)
	_check(engaged, "...but engages one inside it")
	_check(outsider != null and intruder != null, "(the scenario ran)")
	await _clear()

	# INTERCEPT: the flagship heads for where the target will be; engages once it has caught it.
	fleet = _spawn(plan, Vector2(-4500.0, 0.0))
	box = {"fleet": fleet}
	var runner := _enemy(&"hegemony_fighter", Vector2(2500.0, 800.0), false, &"faction_2")
	runner.set_physics_process(false)
	runner.velocity = Vector2.ZERO
	fleet.commander.set_objective(FleetCommander.Objective.INTERCEPT, Vector2.ZERO, runner.get_combatant())
	await _wait(3.0)
	_check(_order_kind(fleet.flagship) == CombatOrder.Kind.MOVE and fleet.commander.get_state() == FleetCommander.State.FOLLOWING, "an intercepting fleet flies at its target until it has caught it")
	var move_point: Vector2 = fleet.flagship.get_pilot().order.point if fleet.flagship.get_pilot().order != null else Vector2.ZERO
	_check(move_point.distance_to(runner.global_position) < 200.0, "...at where it is (it is standing still)")
	runner.global_position = fleet.flagship.global_position + Vector2(600.0, 0.0)  # (it is caught)
	var caught := await _wait_until(func() -> bool: return is_instance_valid(box["fleet"]) and box["fleet"].commander.get_state() == FleetCommander.State.ENGAGING, 20.0, 0.25)
	_check(caught, "...and engages once its target is within reach")
	_sandbox.kill_ship(runner)
	await _wait(2.5)
	if is_instance_valid(fleet):
		_check(fleet.commander.objective == FleetCommander.Objective.OFFENSIVE, "when the target is gone the fleet goes back to its normal objective")
	await _clear()


func _test_withdraw() -> void:
	var plan := _plan(&"fleet", [&"federation_capital_ship", &"federation_capital_ship"], &"", [_battle_group_plan(1), _battle_group_plan(1)])
	var fleet: WarFleet = _spawn(plan, Vector2(-4500.0, 0.0))
	var box := {"fleet": fleet}
	for offset in [Vector2(-1200.0, -300.0), Vector2(-1200.0, 300.0)]:
		_enemy(&"hegemony_cruiser", offset, true)
	await _wait_until(func() -> bool: return is_instance_valid(box["fleet"]) and box["fleet"].commander.get_state() == FleetCommander.State.ENGAGING, 60.0, 0.25)
	fleet.commander.order_withdraw()
	await _wait(2.0)
	_check(fleet.commander.get_state() == FleetCommander.State.WITHDRAWING, "order_withdraw() sends the fleet to WITHDRAWING")
	var groups_run := true
	for group in fleet.get_battle_groups():
		groups_run = groups_run and group.commander.directive == Directive.WITHDRAW and group.state == State.WITHDRAWING
	_check(groups_run, "...its battle groups withdraw")
	var capitals_run := true
	for ship in fleet.commander._capitals():
		capitals_run = capitals_run and _order_kind(ship) == CombatOrder.Kind.WITHDRAW
	_check(capitals_run, "...and so do the capital ships")
	await _clear()


func _test_flagship() -> void:
	var plan := _plan(&"fleet", [&"federation_capital_ship", &"federation_capital_ship"], &"", [_battle_group_plan(1)])
	var fleet: WarFleet = _spawn(plan, Vector2(-4500.0, 0.0))
	var box := {"fleet": fleet}
	for offset in [Vector2(-1500.0, -300.0), Vector2(-1500.0, 300.0)]:
		_enemy(&"hegemony_fighter", offset, true)
	await _wait_until(func() -> bool: return is_instance_valid(box["fleet"]) and box["fleet"].commander.get_state() == FleetCommander.State.ENGAGING, 60.0, 0.25)
	var old_flagship := fleet.flagship
	_sandbox.kill_ship(old_flagship)
	await _wait(3.0)
	_check(is_instance_valid(fleet) and fleet.has_flagship() and fleet.flagship != old_flagship, "a new flagship takes over when the flagship is lost")
	if is_instance_valid(fleet) and fleet.has_flagship():
		var state := fleet.commander.get_state()
		_check(state != FleetCommander.State.WITHDRAWING, "...and the fleet does not withdraw for it")
		_check(state != FleetCommander.State.ENGAGING or _order_kind(fleet.flagship) == CombatOrder.Kind.ENGAGE, "...the new flagship fights under orders like the rest")
	await _clear()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
