extends SceneTree
## Tests military patrols and convoys as ambient traffic (Phase 3.3, step 7) in the real game
## scene: a system a faction controls keeps that faction's patrols flying a loop round it (one
## in an ordinary system, two with gunboats or frigates in a military one), a destroyed patrol
## is replaced, a system nobody controls has none, and now and then a convoy arrives, visits
## places and leaves with all its ships, without ever overfilling the system. Time is sped up
## (Engine.time_scale). Run with:
##   Godot --headless --path . --script res://scripts/tests/military_traffic_test.gd </dev/null
## Pass scenario names after `--` to run only some: recipes, patrols, military, none, convoy, cap, hostile.

const SPEED := 5.0
const ALL := ["recipes", "patrols", "military", "none", "convoy", "cap", "hostile"]

var _failures: int = 0
var _main: Node
var _system: StarSystem
var _traffic: TrafficManager
var _config: TrafficConfig
var _player: PlayerShip
var _registry: ContentRegistry


func _init() -> void:
	seed(20260420)
	_registry = ContentRegistry.new()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	_system = _main.get_node("StarSystem")
	_traffic = _system.get_node("Traffic")
	_config = _traffic.config
	_player = _main.get_node("PlayerShip")

	var wanted: Array = OS.get_cmdline_user_args()
	if wanted.is_empty():
		wanted = ALL
	for name in wanted:
		match name:
			"recipes":
				_test_recipes()
			"patrols":
				await _test_patrols()
			"military":
				await _test_military()
			"none":
				await _test_none()
			"convoy":
				await _test_convoy()
			"cap":
				await _test_cap()
			"hostile":
				await _test_hostile()
	Engine.time_scale = 1.0

	print("MILITARY TRAFFIC TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

## (Re)starts the system's traffic with the patrols `orders` says (an empty dictionary: none).
func _restart(orders: Dictionary) -> void:
	_system.set_patrol_lookup(func(_id: StringName) -> Dictionary: return orders)
	_system.restart_traffic(_player)
	await process_frame


func _federation(count: int = 1, recipe: FormationRecipe = null) -> Dictionary:
	return {"faction": &"faction_1", "faction_name": "Federation", "count": count, "recipe": recipe}


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


func _classes(unit: Formation) -> Array:
	var result: Array = []
	for ship in unit.get_all_ships():
		result.append(ship.ship_type.stats.ship_class.id)
	return result


func _kill(ship) -> void:
	if not _gone(ship):
		var hit := Hit.new()
		hit.damage = 1000000.0
		ship.get_combatant().take_hit(hit)


# ----------------------------------------------------------------------- tests

func _test_recipes() -> void:
	var patrol := _registry.formation_recipe(&"patrol")
	var military := _registry.formation_recipe(&"patrol_military")
	_check(patrol != null and military != null and patrol.tactical_profile.id == &"military_patrol" and military.tactical_profile.id == &"military_patrol", "both patrol recipes exist and use the military patrol profile")
	_check(_config.patrol_recipe == patrol and _config.convoy_recipe == _registry.formation_recipe(&"convoy"), "the default traffic config names the patrol and convoy recipes")
	var fighters_only := true
	var capped := true
	var military_ok := true
	for i in 40:
		var plan := FleetComposer.compose(patrol, &"faction_1", FleetComposer.all_ship_types())
		var classes: Array = plan.ships.map(func(t: ShipType) -> StringName: return t.stats.ship_class.id)
		for id in classes:
			fighters_only = fighters_only and id in [&"fighter", &"heavy_fighter"]
		capped = capped and plan.ships.size() >= 2 and plan.ships.size() <= 4
		var big := FleetComposer.compose(military, &"faction_1", FleetComposer.all_ship_types())
		var support := 0
		var light := 0
		for type in big.ships:
			var id: StringName = type.stats.ship_class.id
			if id in [&"gunboat", &"frigate"]:
				support += 1
			elif id in [&"fighter", &"heavy_fighter"]:
				light += 1
		military_ok = military_ok and support >= 1 and support <= 2 and light >= 2 and light <= 4
	_check(fighters_only and capped, "an ordinary patrol is 2 to 4 fighters and heavy fighters, nothing else (40 drawn)")
	_check(military_ok, "a military patrol is 2 to 4 fighters and heavy fighters with 1 or 2 gunboats or frigates (40 drawn)")
	var hegemony := FleetComposer.compose(military, &"faction_2", FleetComposer.all_ship_types())
	_check(hegemony != null and hegemony.ships[0].stats.faction != null and hegemony.ships[0].stats.faction.id == &"faction_2", "the Hegemony's patrols are made of Hegemony ships")
	for id in [&"military_centre", &"military_output"]:
		var system_class: SystemClass = load("res://resources/system_classes/%s.tres" % id)
		_check(system_class.patrol_count == 2 and system_class.patrol_recipe == military, "the %s class has two military patrols" % id)
	for id in [&"rural", &"frontier", &"critical", &"economic_centre"]:
		var system_class: SystemClass = load("res://resources/system_classes/%s.tres" % id)
		_check(system_class.patrol_count == 1 and system_class.patrol_recipe == null, "the %s class has one ordinary patrol" % id)


func _test_patrols() -> void:
	await _restart(_federation())
	var patrols := _traffic.get_patrols()
	_check(_traffic.get_patrol_count() == 1 and patrols.size() == 1, "a system its faction controls gets its patrol when traffic starts")
	var patrol: Formation = patrols[0]
	_check(patrol.kind == Formation.Kind.SQUADRON and patrol.size() >= 2 and patrol.size() <= 4, "it is a squadron of 2 to 4 ships (%d)" % patrol.size())
	var fed := true
	var labelled := true
	var marked := true
	for ship in patrol.get_all_ships():
		fed = fed and ship.faction_id == &"faction_1"
		labelled = labelled and ship.faction_name == "Federation"
		marked = marked and ship.has_meta(TrafficManager.PATROL_META)
	_check(fed and labelled and marked, "...of Federation ships, shown as Federation, marked as patrol ships")
	_check(patrol.commander.profile.id == &"military_patrol", "...under the military patrol profile")
	_check(patrol.lead.state == NpcShip.State.WANDERING, "...its leader flying a patrol loop, never docking or leaving")
	# It keeps to a loop round the middle of the system.
	Engine.time_scale = SPEED
	var radius := _system.jump_radius * _config.patrol_loop_radius_fraction
	var worst := 0.0
	var steps := 0
	while steps < 60:
		await create_timer(1.0).timeout
		steps += 1
		if is_instance_valid(patrol) and patrol.has_valid_lead():
			worst = maxf(worst, absf(patrol.lead.global_position.distance_to(_system.global_position) - radius))
	Engine.time_scale = 1.0
	_check(worst < radius * 0.35, "the patrol stays on its loop round the system (never %d px off the circle of %d)" % [worst, radius])
	# It counts against the cap, or not, as the config says.
	var with_patrol := _traffic.get_ship_count()
	_config.patrols_count_toward_cap = false
	var without := _traffic.get_ship_count()
	_config.patrols_count_toward_cap = true
	_check(with_patrol - without == patrol.size(), "its ships count against the cap (and do not when the config says so)")


func _test_military() -> void:
	await _restart(_federation(2, _registry.formation_recipe(&"patrol_military")))
	var patrols := _traffic.get_patrols()
	_check(patrols.size() == 2, "a military system keeps two patrols")
	var supported := true
	for patrol in patrols:
		var classes := _classes(patrol)
		supported = supported and (classes.has(&"gunboat") or classes.has(&"frigate"))
	_check(supported, "...each with a gunboat or frigate among its ships")
	var apart: float = patrols[0].lead.global_position.distance_to(patrols[1].lead.global_position)
	_check(apart > 200.0, "...not on top of each other (%d px apart)" % apart)
	# What Main asks for a real military system.
	var galaxy: Galaxy = _main.galaxy
	var found := 0
	for id in galaxy.get_system_ids():
		var system_class := galaxy.get_system_class(id)
		if system_class != null and system_class.id in [&"military_centre", &"military_output"]:
			var orders: Dictionary = _main._patrols_for(id)
			if not orders.is_empty():
				found += 1
				_check(orders["count"] == 2 and orders["recipe"] == _registry.formation_recipe(&"patrol_military"), "%s (%s) is to have two military patrols" % [id, system_class.id])
	_check(found > 0, "(setup) the galaxy has controlled military systems (%d)" % found)
	_check(_main._patrols_for(&"sol")["count"] == 1 and _main._patrols_for(&"sol")["recipe"] == null, "an ordinary system is to have one ordinary patrol")


func _test_none() -> void:
	await _restart({})
	_check(_traffic.get_patrol_count() == 0 and _traffic.get_patrols().is_empty(), "a system nobody controls has no patrols")
	_check(_traffic.get_ship_count() > 0, "...but still has its ordinary traffic")
	# A faction with nothing to make a patrol of: the others are fine, it just waits.
	await _restart({"faction": &"faction_3", "faction_name": "Pirates", "count": 1, "recipe": null})
	_check(_traffic.get_patrols().is_empty(), "a faction with no warships gets no patrol, and nothing breaks")


func _test_convoy() -> void:
	# Convoys always, and short visits, so one can be followed through its whole journey.
	_config.convoy_spawn_weight = 1000000.0
	_config.max_ships = 40
	_config.visits_range = Vector2i(1, 1)
	_config.dock_time_range = Vector2(1.0, 2.0)
	await _restart({})
	var convoys: Array[Formation] = []
	for unit in _system.get_formations_root().get_children():
		if unit is Formation and unit.kind == Formation.Kind.CONVOY:
			convoys.append(unit)
	_check(not convoys.is_empty(), "a convoy is placed among the ships already in flight (%d)" % convoys.size())
	var convoy: Formation = convoys[0]
	_check(convoy.commander.profile.id == &"convoy_escort", "it is under the convoy escort profile")
	_check(convoy.lead.destination != null, "its leader has a place to go, like any other ship (%s)" % convoy.lead.destination.get_object_name())
	var labelled := true
	var ids := true
	for ship in convoy.get_all_ships():
		labelled = labelled and not ship.faction_name.is_empty()
		ids = ids and ship.faction_id != &""
	_check(labelled and ids, "...and its ships have a faction, shown in the target panel")
	var box := {"convoy": convoy, "lead": convoy.lead, "docked": false, "left": false}
	var members: Array = convoy.get_all_ships()
	Engine.time_scale = SPEED * 2.0
	var done := await _wait_until(func() -> bool:
		var unit = box["convoy"]
		if not is_instance_valid(unit) or unit.is_queued_for_deletion():
			box["left"] = true
			return true
		if is_instance_valid(box["lead"]):
			box["docked"] = box["docked"] or box["lead"].state == NpcShip.State.DOCKED
		return false, 400.0, 0.5)
	Engine.time_scale = 1.0
	_check(box["docked"], "the convoy's leader docks at its destination")
	_check(done and box["left"], "...and later the convoy leaves, as a whole")
	await process_frame
	await process_frame
	var survivors := 0
	for ship in members:
		if is_instance_valid(ship) and not ship.is_queued_for_deletion():
			survivors += 1
	_check(survivors == 0, "...with every ship of it gone (%d left)" % survivors)
	_config.convoy_spawn_weight = 0.5
	_config.max_ships = 10
	_config.visits_range = Vector2i(1, 3)
	_config.dock_time_range = Vector2(5.0, 15.0)


func _test_cap() -> void:
	# Convoys always, but room for only a few ships: the system is never overfilled.
	_config.convoy_spawn_weight = 1000000.0
	_config.max_ships = 3
	await _restart({})
	Engine.time_scale = SPEED
	var worst := 0
	var steps := 0
	while steps < 120:
		await create_timer(1.0).timeout
		steps += 1
		worst = maxi(worst, _traffic.get_ship_count())
	Engine.time_scale = 1.0
	_check(worst <= _traffic.get_max_ships(), "a system with room for %d ships never holds more (most %d)" % [_traffic.get_max_ships(), worst])
	var big := FleetComposer.compose(_config.convoy_recipe, &"faction_1", FleetComposer.all_ship_types())
	_check(big != null and big.ship_count() >= 2, "(setup) a convoy is at least two ships")
	_config.convoy_spawn_weight = 0.5
	_config.max_ships = 10


func _test_hostile() -> void:
	# A patrol replaces itself when it is destroyed, and takes the Hostile player on.
	_config.patrol_respawn_delay = 3.0
	await _restart(_federation())
	var first: Formation = _traffic.get_patrols()[0]
	var first_id := first.id  # (the formation is freed: only its id is kept)
	var old_ships := first.get_all_ships()
	for ship in old_ships:
		_kill(ship)
	await process_frame
	await process_frame
	_check(_traffic.get_patrols().is_empty() or _traffic.get_patrols()[0].id != first_id, "(setup) the patrol is wiped out")
	Engine.time_scale = SPEED
	var replaced := await _wait_until(func() -> bool: return not _traffic.get_patrols().is_empty() and _traffic.get_patrols()[0].id != first_id, 60.0, 0.5)
	Engine.time_scale = 1.0
	_check(replaced, "a destroyed patrol is replaced after the respawn delay")
	_config.patrol_respawn_delay = 90.0

	# The Federation turns on the player: its patrol attacks them.
	var reputation: ReputationManager = _main.get_node("Reputation")
	var federation: Faction = _registry.faction(&"faction_1")
	reputation.change(federation, -150)
	var combat: CombatManager = _main.get_node("Combat")
	var patrol: Formation = _traffic.get_patrols()[0]
	combat.get_picture().refresh()
	var lead_combatant: Combatant = patrol.lead.get_combatant()
	var player_combatant: Combatant = _player.combatant
	_check(lead_combatant.is_hostile_to(player_combatant), "a patrol is hostile to a player the Federation hates")
	reputation.reset_state()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
