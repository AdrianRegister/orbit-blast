extends SceneTree
## Tests the tactical profiles (Phase 3.3, step 6): that the five named profiles exist and are
## valid and different, that recipes and the spawner give units their profile, and what each
## setting does in a fight in the real game scene: a mercenary does not go looking for a fight
## but a patrol does, a patrol will not take odds worse than 2 to 1 and an attack group will, a
## pirate goes for the freighter before the armed escort, a unit gives up a chase past its
## leash, and a fleet's default objective. Time is sped up (Engine.time_scale). Run with:
##   Godot --headless --path . --script res://scripts/tests/profile_test.gd </dev/null
## Pass scenario names after `--` to run only some: files, spawn, proactive, odds, cargo, leash, fleet.
##
## (Ships get destroyed and freed during these fights: conditions read them through helpers that
## cope with that, and never capture them in a lambda.)

const SPEED := 5.0
const ALL := ["files", "spawn", "proactive", "odds", "cargo", "leash", "fleet"]
const State := Formation.State
const NAMES := [&"military_patrol", &"military_attack", &"convoy_escort", &"pirate", &"mercenary"]

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
	seed(20260419)
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
			"files":
				_test_files()
			"spawn":
				await _test_spawn()
			"proactive":
				await _test_proactive()
			"odds":
				await _test_odds()
			"cargo":
				await _test_cargo()
			"leash":
				await _test_leash()
			"fleet":
				await _test_fleet()
	Engine.time_scale = 1.0

	print("PROFILE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _type(id: StringName) -> ShipType:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(id)
	return type


func _profile(id: StringName) -> TacticalProfile:
	return _registry.tactical_profile(id)


## A formation of `models` for `faction`, its leader at `offset` from the middle of the system,
## fighting under `profile` (null: its own).
func _unit(kind: Formation.Kind, shape_id: StringName, models: Array, faction: StringName, offset: Vector2,
		profile: TacticalProfile = null, heading: float = 0.0) -> Formation:
	var types: Array[ShipType] = []
	for model in models:
		types.append(_type(model))
	var none: Array[Vector2] = []
	return FleetSpawner.spawn_formation(_system, _player, CombatSandbox.TRAFFIC_CONFIG, kind, _registry.formation_shape(shape_id),
			types, _centre + offset, heading, faction, 300.0, null, none, profile)


## A lone ship, held still unless `free`.
func _ship(model: StringName, faction: StringName, offset: Vector2, free: bool = false) -> NpcShip:
	var ship := _sandbox.spawn_ship(_type(model), faction, _centre + offset, PI, CombatSandbox.BATTLE_EXITS)
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
	_combat.get_hostility().clear()  # (grudges would carry over into the next scenario)
	_combat.get_picture().refresh()


## (untyped: `ship` may already be freed)
func _gone(ship) -> bool:
	return not is_instance_valid(ship) or ship.is_queued_for_deletion() or not ship.get_combatant().is_alive()


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


func _rating(models: Array) -> float:
	var total := 0.0
	for model in models:
		total += CombatRating.of(_registry.ship_stats(model))
	return total


# ----------------------------------------------------------------------- tests

func _test_files() -> void:
	var seen := {}
	for id in NAMES + [&"default"]:
		var profile := _profile(id)
		_check(profile != null and profile.id == id and profile.validate().is_empty(), "the %s profile exists and is valid" % id)
		if profile != null:
			seen[[profile.proactive, profile.max_odds, profile.pursuit_leash, profile.withdraw_losses, profile.target_bias_cargo, profile.guard_radius]] = true
	_check(seen.size() == NAMES.size() + 1, "...and they are all different (%d distinct settings)" % seen.size())
	var mercenary := _profile(&"mercenary")
	var pirate := _profile(&"pirate")
	_check(not mercenary.proactive and _profile(&"military_patrol").proactive and pirate.proactive, "a mercenary retaliates only; patrols and pirates go looking")
	_check(_profile(&"military_attack").max_odds > _profile(&"military_patrol").max_odds and pirate.max_odds < _profile(&"military_patrol").max_odds, "an attack group takes worse odds than a patrol, a pirate takes better")
	_check(_profile(&"military_attack").pursuit_leash > _profile(&"military_patrol").pursuit_leash, "an attack group chases further than a patrol")
	_check(pirate.target_bias_cargo > 0.0 and _profile(&"military_patrol").target_bias_cargo == 0.0, "only pirates prefer cargo ships")
	_check(pirate.withdraw_losses < _profile(&"military_patrol").withdraw_losses, "pirates break off sooner than a patrol")
	_check(_profile(&"convoy_escort").withdraw_losses >= 1.0, "convoy escorts never withdraw: the convoy runs while they fight")
	for id in [&"squadron", &"battle_group", &"fleet"]:
		_check(_registry.formation_recipe(id).tactical_profile == _profile(&"military_patrol"), "the %s recipe names the military patrol profile" % id)
	_check(_registry.formation_recipe(&"convoy").tactical_profile == _profile(&"convoy_escort"), "the convoy recipe names the convoy escort profile")


func _test_spawn() -> void:
	var models := [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter"]
	var plain := _unit(Formation.Kind.SQUADRON, &"wedge", models, &"faction_1", Vector2(-6000.0, 0.0))
	_check(plain.commander.profile == TacticalProfile.default() or plain.commander.profile == null or plain.commander.profile.id == &"default", "a formation spawned with no profile uses the default (%s)" % plain.commander.profile.id)
	var pirates := _unit(Formation.Kind.SQUADRON, &"wedge", models, &"faction_3", Vector2(-6000.0, 800.0), _profile(&"pirate"))
	_check(pirates.commander.profile.id == &"pirate", "a profile given to the spawner is used")
	var plan := FormationPlan.new()
	plan.recipe = _registry.formation_recipe(&"squadron")
	for model in models:
		plan.ships.append(_type(model))
	plan.shape = _registry.formation_shape(&"wedge")
	var none: Array[Vector2] = []
	var from_recipe: Formation = FleetSpawner.spawn_plan(_system, _player, CombatSandbox.TRAFFIC_CONFIG, plan, _centre + Vector2(-6000.0, -800.0), 0.0, &"faction_1", 300.0, null, none)
	_check(from_recipe.commander.profile.id == &"military_patrol", "a plan takes the profile its recipe names")
	var overridden: Formation = FleetSpawner.spawn_plan(_system, _player, CombatSandbox.TRAFFIC_CONFIG, plan, _centre + Vector2(-6000.0, 1600.0), 0.0, &"faction_3", 300.0, null, none, null, _profile(&"mercenary"))
	_check(overridden.commander.profile.id == &"mercenary", "...unless the spawner overrides it")
	var convoy := _unit(Formation.Kind.CONVOY, &"convoy_diamond", [&"freighter", &"federation_fighter"], &"faction_1", Vector2(-6000.0, -1600.0), _profile(&"convoy_escort"))
	_check(convoy.commander.profile.id == &"convoy_escort", "a convoy can be given the escort profile")
	# A fleet and the battle groups in it.
	var fleet_plan := FormationPlan.new()
	fleet_plan.recipe = _registry.formation_recipe(&"fleet")
	fleet_plan.ships.append(_type(&"federation_capital_ship"))
	var group := FormationPlan.new()
	group.recipe = _registry.formation_recipe(&"battle_group")
	group.ships.append(_type(&"federation_cruiser"))
	group.ships.append(_type(&"federation_frigate"))
	group.shape = _registry.formation_shape(&"screen")
	fleet_plan.children.append(group)
	var fleet: WarFleet = FleetSpawner.spawn_plan(_system, _player, CombatSandbox.TRAFFIC_CONFIG, fleet_plan, _centre + Vector2(-7000.0, 4000.0), 0.0, &"faction_3", 300.0, null, none, null, _profile(&"pirate"))
	_check(fleet.commander.profile.id == &"pirate" and fleet.get_battle_groups()[0].commander.profile.id == &"pirate", "a fleet's profile override reaches its battle groups too")
	await _clear()


func _test_proactive() -> void:
	var models := [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"]
	# Two units with the same ships stand 3500 px from an enemy that does nothing (it is held still).
	var patrol := _unit(Formation.Kind.SQUADRON, &"wedge", models, &"faction_1", Vector2(-1800.0, -900.0), _profile(&"military_patrol"))
	var mercenaries := _unit(Formation.Kind.SQUADRON, &"wedge", models, &"faction_1", Vector2(-1800.0, 900.0), _profile(&"mercenary"))
	var enemy := _ship(&"hegemony_frigate", &"faction_2", Vector2(1500.0, 0.0))
	var box := {"patrol": patrol, "mercs": mercenaries, "enemy": enemy}
	var engaged := await _wait_until(func() -> bool: return _state(box["patrol"]) in [State.INTERCEPTING, State.ATTACKING], 30.0, 0.25)
	_check(engaged, "a patrol goes for an enemy it merely sees")
	await _wait(2.0)
	_check(_state(mercenaries) == State.FOLLOWING, "...but mercenaries, in sight of the same enemy, leave it alone (state %d)" % _state(mercenaries))
	# The enemy now targets one of the mercenaries: they retaliate.
	var victim: NpcShip = mercenaries.get_ships()[1]
	enemy.get_combatant().set_target(victim.get_combatant())
	var retaliates := await _wait_until(func() -> bool: return _state(box["mercs"]) in [State.INTERCEPTING, State.ATTACKING], 20.0, 0.25)
	_check(retaliates, "...until it targets one of them, and then they fight")
	await _clear()

	# A grudge does it too: the enemy fires on the unit once.
	mercenaries = _unit(Formation.Kind.SQUADRON, &"wedge", models, &"faction_1", Vector2(-600.0, 0.0), _profile(&"mercenary"))
	enemy = _ship(&"hegemony_frigate", &"faction_2", Vector2(1400.0, 0.0))
	box = {"mercs": mercenaries}
	await _wait(3.0)
	_check(mercenaries.state == State.FOLLOWING, "(setup) mercenaries 2000 px from an enemy that is not hostile-acting stay put")
	var hit := Hit.new()
	hit.damage = 1.0
	hit.attacker = enemy.get_combatant()
	var victim_ship: NpcShip = mercenaries.get_ships()[1]
	enemy.get_combatant().set_target(victim_ship.get_combatant())  # (a grudge is for a deliberate attack)
	victim_ship.get_combatant().take_hit(hit)
	enemy.get_combatant().set_target(null)  # (so nothing but the grudge is left to go on)
	var grudge := await _wait_until(func() -> bool: return _state(box["mercs"]) in [State.INTERCEPTING, State.ATTACKING], 20.0, 0.25)
	_check(grudge, "a shot at one of them gives the whole unit a grudge, and they fight")
	await _clear()


func _test_odds() -> void:
	var own := [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"]
	var own_rating := _rating(own)
	# An enemy mix whose strength is about three times the unit's: more than a patrol takes (2),
	# less than an attack group does (4).
	var mix: Array = []
	var best := INF
	for frigates in 5:
		for cruisers in 3:
			for fighters in 9:
				var trial: Array = []
				for i in frigates:
					trial.append(&"hegemony_frigate")
				for i in cruisers:
					trial.append(&"hegemony_cruiser")
				for i in fighters:
					trial.append(&"hegemony_fighter")
				if trial.is_empty():
					continue
				var odds := _rating(trial) / own_rating
				if absf(odds - 3.0) < best:
					best = absf(odds - 3.0)
					mix = trial
	var odds := _rating(mix) / own_rating
	_check(odds > 2.2 and odds < 3.8, "(setup) the enemy is %.1f times as strong as the unit" % odds)
	var patrol := _unit(Formation.Kind.SQUADRON, &"wedge", own, &"faction_1", Vector2(-2500.0, -2500.0), _profile(&"military_patrol"))
	var attackers := _unit(Formation.Kind.SQUADRON, &"wedge", own, &"faction_1", Vector2(-2500.0, 2500.0), _profile(&"military_attack"))
	for index in mix.size():
		_ship(mix[index], &"faction_2", Vector2(1500.0, -500.0 + 120.0 * index))
	var box := {"patrol": patrol, "attackers": attackers, "patrol_withdrew": false, "attackers_withdrew": false}
	await _wait_until(func() -> bool:
		box["patrol_withdrew"] = box["patrol_withdrew"] or _state(box["patrol"]) == State.WITHDRAWING
		box["attackers_withdrew"] = box["attackers_withdrew"] or _state(box["attackers"]) == State.WITHDRAWING
		return box["patrol_withdrew"] and _state(box["attackers"]) in [State.INTERCEPTING, State.ATTACKING], 40.0, 0.25)
	_check(box["patrol_withdrew"], "a patrol that meets a force three times its strength withdraws")
	_check(not box["attackers_withdrew"] and _state(attackers) in [State.INTERCEPTING, State.ATTACKING], "...an attack group meeting the same force fights")
	await _clear()


func _test_cargo() -> void:
	var models := [&"federation_fighter", &"federation_fighter", &"federation_fighter"]
	var results := {}
	for profile_id in [&"pirate", &"default"]:
		var unit := _unit(Formation.Kind.SQUADRON, &"wedge", models, &"faction_3", Vector2(-1000.0, 0.0), _profile(profile_id))
		# The freighter and an armed escort that is the bigger threat, side by side.
		var freighter := _ship(&"freighter", &"faction_1", Vector2(1300.0, -80.0))
		var escort := _ship(&"federation_heavy_fighter", &"faction_1", Vector2(1300.0, 80.0))
		var box := {"unit": unit, "freighter": freighter, "escort": escort, "on_freighter": 0, "on_escort": 0}
		await _wait_until(func() -> bool:
			var counts := [0, 0]
			var current = box["unit"]
			if not is_instance_valid(current):
				return true
			for ship in current.get_ships():
				var order: CombatOrder = ship.get_pilot().order
				if order != null and order.kind == CombatOrder.Kind.ENGAGE and order.target != null:
					if is_instance_valid(box["freighter"]) and order.target == box["freighter"].get_combatant():
						counts[0] += 1
					elif is_instance_valid(box["escort"]) and order.target == box["escort"].get_combatant():
						counts[1] += 1
			box["on_freighter"] = counts[0]
			box["on_escort"] = counts[1]
			return counts[0] + counts[1] >= 2, 40.0, 0.25)
		results[profile_id] = [box["on_freighter"], box["on_escort"]]
		await _clear()
	_check(results[&"pirate"][0] > 0 and results[&"pirate"][0] >= results[&"pirate"][1], "pirates go for the freighter (%d on it, %d on the armed escort)" % results[&"pirate"])
	_check(results[&"default"][1] > results[&"default"][0], "a unit with no taste for cargo goes for the armed escort (%d on the freighter, %d on it)" % [results[&"default"][0], results[&"default"][1]])


func _test_leash() -> void:
	var models := [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter", &"federation_fighter"]
	var short := _profile(&"military_patrol").duplicate() as TacticalProfile
	short.pursuit_leash = 2600.0
	short.id = &"short_leash"
	var unit := _unit(Formation.Kind.SQUADRON, &"wedge", models, &"faction_1", Vector2(-2000.0, 0.0), short)
	var enemy := _ship(&"hegemony_cruiser", &"faction_2", Vector2(2000.0, 0.0))
	var box := {"unit": unit, "enemy": enemy, "fought": false, "gave_up": false}
	await _wait_until(func() -> bool:
		var current = box["unit"]
		if not is_instance_valid(current) or _gone(box["enemy"]):
			return true
		box["fought"] = box["fought"] or current.state in [State.INTERCEPTING, State.ATTACKING]
		box["gave_up"] = box["gave_up"] or (box["fought"] and current.state == State.FOLLOWING)
		return box["gave_up"], 60.0, 0.25)
	_check(box["fought"], "the unit goes after an enemy 4000 px away")
	_check(box["gave_up"] and not _gone(enemy), "...and gives up the chase past its leash, with the enemy still there, and returns to its route")
	var ignored: Dictionary = unit.commander._ignored if is_instance_valid(unit) else {}
	_check(ignored.has(enemy.get_combatant()), "...and it ignores that enemy for a while instead of going straight back")
	await _clear()


func _test_fleet() -> void:
	var defensive := _profile(&"military_patrol").duplicate() as TacticalProfile
	defensive.default_objective = 1
	var plan := FormationPlan.new()
	plan.recipe = _registry.formation_recipe(&"fleet")
	plan.ships.append(_type(&"federation_capital_ship"))
	plan.ships.append(_type(&"federation_capital_ship"))
	var none: Array[Vector2] = []
	var fleet: WarFleet = FleetSpawner.spawn_plan(_system, _player, CombatSandbox.TRAFFIC_CONFIG, plan, _centre + Vector2(-4000.0, 0.0), 0.0, &"faction_1", 300.0, null, none, null, defensive)
	await _wait(3.0)
	_check(fleet.commander.objective == FleetCommander.Objective.DEFENSIVE, "a fleet whose profile is defensive starts out defending")
	_check(fleet.commander.point.distance_to(fleet.flagship.global_position) < 2500.0 and fleet.commander.point != Vector2.ZERO, "...the place where it first stood")
	await _clear()

	# A mercenary fleet does not go looking for a fight; a patrol fleet does.
	for id in [&"military_patrol", &"mercenary"]:
		fleet = FleetSpawner.spawn_plan(_system, _player, CombatSandbox.TRAFFIC_CONFIG, plan, _centre + Vector2(-4500.0, 0.0), 0.0, &"faction_1", 300.0, null, none, null, _profile(id))
		_ship(&"hegemony_cruiser", &"faction_2", Vector2(-1200.0, 0.0))
		var box := {"fleet": fleet}
		var engaged := await _wait_until(func() -> bool: return is_instance_valid(box["fleet"]) and box["fleet"].commander.get_state() == FleetCommander.State.ENGAGING, 25.0, 0.25)
		if id == &"military_patrol":
			_check(engaged, "a patrol fleet engages an enemy it sees")
		else:
			_check(not engaged, "a mercenary fleet leaves it alone")
		await _clear()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
