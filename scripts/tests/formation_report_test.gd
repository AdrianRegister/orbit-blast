extends SceneTree
## Tests the formation information on combat events: the unit a destroyed ship
## belonged to in the DestructionReport, and the FORMATION and ROLE rows the HUD
## shows for an NPC ship. Uses the real game scene (the combat sandbox's system).
##   Godot --headless --path . --script res://scripts/tests/formation_report_test.gd </dev/null

const CONFIG := preload("res://resources/traffic/default_traffic.tres")
const FACTION := &"faction_1"
const HEAVY := &"federation_heavy_fighter"
const FIGHTER := &"federation_fighter"
const FRIGATE := &"federation_frigate"
const CRUISER := &"federation_cruiser"
const CAPITAL := &"federation_capital_ship"
const AT := Vector2(-3000.0, -2000.0)

var _failures: int = 0
var _main: Main
var _system: StarSystem
var _player: PlayerShip
var _registry: ContentRegistry
var _reports: Array[DestructionReport] = []


func _init() -> void:
	seed(20260404)
	_registry = ContentRegistry.new()
	_main = CombatSandbox.build_main()
	root.add_child(_main)
	for i in 5:
		await process_frame
	_system = _main.get_system()
	_player = _main.get_player_ship()
	(_main.get_node("Combat") as CombatManager).ship_destroyed.connect(func(report: DestructionReport) -> void: _reports.append(report))
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	_player.global_position = Vector2(30000.0, 30000.0)
	await process_frame

	await _test_loose_ship()
	await _test_squadron()
	await _test_battle_group()
	await _test_fleet()
	await _test_convoy()
	await _test_rows()

	print("FORMATION REPORT TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _type(id: StringName) -> ShipType:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(id)
	return type


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


func _squadron() -> FormationPlan:
	return _unit(&"squadron", [HEAVY, FIGHTER, FIGHTER], &"wedge")


func _battle_group() -> FormationPlan:
	return _unit(&"battle_group", [CRUISER, FRIGATE], &"screen", [_squadron(), _squadron()])


func _spawn(plan: FormationPlan) -> Node:
	var no_patrol: Array[Vector2] = []
	var unit := FleetSpawner.spawn_plan(_system, _player, CONFIG, plan, AT, 0.0, FACTION, 700.0, null, no_patrol)
	await physics_frame
	await physics_frame
	return unit


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


## Destroys `ship` and returns the report about it.
func _destroy(ship: NpcShip) -> DestructionReport:
	var known := _reports.size()
	var hit := Hit.new()
	hit.damage = 1000000.0
	ship.get_combatant().take_hit(hit)
	await physics_frame
	await physics_frame
	return _reports[known] if _reports.size() > known else null


func _role(ship: NpcShip) -> String:
	for row in ship.details.get_rows():
		if row[0] == "ROLE":
			return row[1]
	return ""


func _formation_row(ship: NpcShip) -> String:
	for row in ship.details.get_rows():
		if row[0] == "FORMATION":
			return row[1]
	return ""


# ----------------------------------------------------------------- tests

func _test_loose_ship() -> void:
	print("--- loose ship")
	var ship: NpcShip = FleetSpawner.NPC_SCENE.instantiate()
	var no_places: Array[InhabitedNode] = []
	ship.setup(_type(&"freighter"), CONFIG, no_places, "", null, _player)
	ship.combat_id = &"report_test_loose"
	ship.begin_wandering(_system.global_position, 100.0)
	_system.get_ships_root().add_child(ship)
	ship.global_position = AT
	await physics_frame
	_check(_formation_row(ship) == "" and _role(ship) == "", "a ship in no formation has no FORMATION or ROLE row")
	var report := await _destroy(ship)
	_check(report != null and report.victim_formation_kind == &"" and report.victim_formation_id == &"" and report.victim_fleet_id == &"",
			"a destroyed loose ship's report names no unit")
	await _clear()


func _test_squadron() -> void:
	print("--- squadron")
	var squadron := await _spawn(_squadron()) as Formation
	var squadron_id := squadron.id
	var member: NpcShip = squadron.get_members()[0]
	var report := await _destroy(member)
	_check(report != null and report.victim_formation_kind == &"squadron" and report.victim_formation_id == squadron_id,
			"a destroyed squadron member's report names the squadron (%s %s)" % [report.victim_formation_kind, report.victim_formation_id])
	_check(report.victim_fleet_id == &"", "... and no fleet")
	var lead := squadron.lead
	var lead_report := await _destroy(lead)
	_check(lead_report != null and lead_report.victim_formation_kind == &"squadron" and lead_report.victim_formation_id == squadron_id,
			"so does a destroyed squadron leader's")
	var another := Formation.new()
	_check(another.id != squadron_id and another.id != &"", "every formation has its own id")
	another.free()
	await _clear()


func _test_battle_group() -> void:
	print("--- battle group")
	var group := await _spawn(_battle_group()) as Formation
	var squadron: Formation = null
	for ship in group.get_all_ships():
		if ship.led_formation != null and ship.led_formation != group:
			squadron = ship.led_formation
	var squadron_id := squadron.id
	var group_id := group.id
	var squad_member: NpcShip = squadron.get_members()[0]
	var report := await _destroy(squad_member)
	_check(report.victim_formation_kind == &"squadron" and report.victim_formation_id == squadron_id, "a squadron ship in a battle group is reported as the squadron's")
	var squad_lead: NpcShip = squadron.lead
	report = await _destroy(squad_lead)
	_check(report.victim_formation_kind == &"squadron" and report.victim_formation_id == squadron_id, "a squadron leader is reported as the squadron's, not the battle group's")
	var frigate: NpcShip = null
	for ship in group.get_members():
		if ship.ship_type.stats.id == FRIGATE:
			frigate = ship
	report = await _destroy(frigate)
	_check(report.victim_formation_kind == &"battle_group" and report.victim_formation_id == group_id, "a battle group's own ship is reported as the battle group's")
	_check(squadron_id != group_id, "(the squadron and the battle group have different ids)")
	var lead := group.lead
	report = await _destroy(lead)
	_check(report.victim_formation_kind == &"battle_group" and report.victim_formation_id == group_id, "so is its leader")
	await _clear()


func _test_fleet() -> void:
	print("--- fleet")
	var fleet := await _spawn(_unit(&"fleet", [CAPITAL, CAPITAL], &"", [_battle_group(), _battle_group()])) as WarFleet
	var group: Formation = fleet.get_battle_groups()[0]
	var member: NpcShip = group.get_members()[0]
	var report := await _destroy(member)
	_check(report.victim_fleet_id == fleet.id, "a ship in a fleet's battle group is reported with the fleet's id (%s)" % report.victim_fleet_id)
	var squadron: Formation = null
	for ship in group.get_all_ships():
		if ship.led_formation != null and ship.led_formation != group:
			squadron = ship.led_formation
	report = await _destroy(squadron.get_members()[0])
	_check(report.victim_formation_kind == &"squadron" and report.victim_fleet_id == fleet.id, "a squadron ship deep in a fleet is too (squadron inside a battle group inside a fleet)")
	var flagship := fleet.flagship
	report = await _destroy(flagship)
	_check(report.victim_formation_kind == &"" and report.victim_fleet_id == fleet.id, "the flagship belongs to the fleet and to no formation")
	await _clear()


func _test_convoy() -> void:
	print("--- convoy")
	var convoy := await _spawn(_unit(&"convoy", [&"bulk_freighter", &"freighter", &"interceptor", &"interceptor"], &"convoy")) as Formation
	var report := await _destroy(convoy.get_members()[0])
	_check(report.victim_formation_kind == &"convoy" and report.victim_formation_id == convoy.id, "a destroyed convoy ship is reported as the convoy's")
	await _clear()


func _test_rows() -> void:
	print("--- HUD rows")
	var group := await _spawn(_battle_group()) as Formation
	var squadron: Formation = null
	for ship in group.get_all_ships():
		if ship.led_formation != null and ship.led_formation != group:
			squadron = ship.led_formation
	var lead := group.lead
	_check(_formation_row(lead).begins_with("Defensive Screen battle group, "), "the battle group's leader's FORMATION row names the shape and kind (%s)" % _formation_row(lead))
	_check(_role(lead) == "Battle Group leader", "... and its ROLE says it leads (%s)" % _role(lead))
	var squad_lead := squadron.lead
	_check(_formation_row(squad_lead).contains("squadron") and _role(squad_lead) == "Squadron leader", "a squadron's leader is that squadron's leader (%s / %s)" % [_formation_row(squad_lead), _role(squad_lead)])
	var member: NpcShip = squadron.get_members()[0]
	_check(_formation_row(member).begins_with("Wedge squadron, ") and _role(member) == "Member", "a squadron's other ships are members (%s / %s)" % [_formation_row(member), _role(member)])
	_check(_formation_row(member).ends_with("of 3"), "the row says how many ships the unit has (%s)" % _formation_row(member))

	# It follows changes.
	var other: NpcShip = squadron.get_members()[1]
	await _destroy(other)
	await physics_frame
	_check(_formation_row(member).ends_with("of 2"), "... and follows a loss (%s)" % _formation_row(member))
	var changed: Array[bool] = [false]
	member.details.changed.connect(func() -> void: changed[0] = true)
	squadron.set_shape(_registry.formation_shape(&"line"))
	squadron._rebuild()
	await physics_frame
	_check(_formation_row(member).begins_with("Line squadron"), "... and a new shape (%s)" % _formation_row(member))
	_check(changed[0], "the HUD is told when the rows change")
	# A ship released from its formation has no rows.
	squadron.release(member)
	await physics_frame
	_check(_formation_row(member) == "" and _role(member) == "", "a ship released from its formation loses the rows")
	await _clear()

	var fleet := await _spawn(_unit(&"fleet", [CAPITAL, CAPITAL], &"", [_battle_group(), _battle_group()])) as WarFleet
	_check(fleet.flagship.details.get_rows().size() >= 3 and fleet.flagship.get_organisation()["fleet_id"] == fleet.id,
			"a fleet's flagship knows its fleet")
	fleet.flagship.refresh_organisation()
	_check(_role(fleet.flagship) == "" and _formation_row(fleet.flagship) == "", "(a flagship is in no formation, so it has no formation rows)")
	await _clear()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
