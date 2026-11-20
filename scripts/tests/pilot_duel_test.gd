extends SceneTree
## Tests NPC pilots in the real game scene (the combat sandbox's system): who
## fires and when, who attacks whom, how the different kinds of ship fight, running
## away and jumping out, standing down, and the player being attacked. Time is sped
## up (Engine.time_scale), so it takes a minute or two. Run with:
##   Godot --headless --path . --script res://scripts/tests/pilot_duel_test.gd </dev/null
## Pass scenario names after `--` to run only some: pilots, fire_rules, neutral, war,
## pirate, two_on_one, big_ships, fighters_v_cruiser, retreat, chase, formation, battle_line, standoff, support, point_defence, player.
##
## (Ships get destroyed and freed during these fights, so conditions that wait on
## them read them from a dictionary `box`, never capture them: a lambda that has
## captured a freed object cannot be called.)

const SPEED := 5.0
const ALL := ["pilots", "fire_rules", "neutral", "war", "pirate", "two_on_one", "big_ships", "fighters_v_cruiser", "retreat", "chase", "formation", "battle_line", "standoff", "support", "point_defence", "player"]

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
	seed(20260416)
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
			"pilots":
				await _test_pilots_exist()
			"fire_rules":
				await _test_fire_rules()
			"neutral":
				await _test_neutral()
			"war":
				await _test_war()
			"pirate":
				await _test_pirate_and_freighter()
			"two_on_one":
				await _test_two_on_one()
			"big_ships":
				await _test_big_ships()
			"fighters_v_cruiser":
				await _test_fighters_v_cruiser()
			"retreat":
				await _test_retreat()
			"chase":
				await _test_chase()
			"formation":
				await _test_formation_members()
			"battle_line":
				await _test_battle_line()
			"standoff":
				await _test_standoff()
			"support":
				await _test_support()
			"point_defence":
				await _test_point_defence()
			"player":
				await _test_player()
	Engine.time_scale = 1.0

	print("PILOT DUEL TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _type(id: StringName) -> ShipType:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(id)
	return type


## A ship at `offset` from the middle of the system (far from the player).
func _ship(model: StringName, faction: StringName, offset: Vector2, heading: float = 0.0, exits: Array[Vector2] = []) -> NpcShip:
	return _sandbox.spawn_ship(_type(model), faction, _centre + offset, heading, exits)


func _frozen(model: StringName, faction: StringName, offset: Vector2, heading: float = 0.0) -> NpcShip:
	var ship := _ship(model, faction, offset, heading)
	ship.set_physics_process(false)  # (it stays put, and its pilot does not act)
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


## Waits (in game seconds) until `condition` is true or `limit` seconds have passed.
## Returns whether it became true.
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


func _mode_of(ship) -> int:
	return ship.get_pilot().mode if not _gone(ship) else -1


# ----------------------------------------------------------------------- tests

func _test_pilots_exist() -> void:
	var fighter := _frozen(&"federation_fighter", &"faction_1", Vector2(0.0, 0.0))
	var freighter := _frozen(&"freighter", &"", Vector2(300.0, 0.0))
	var cruiser := _frozen(&"hegemony_cruiser", &"faction_2", Vector2(-300.0, 0.0))
	await _wait(0.2)
	_check(fighter.get_pilot() != null and freighter.get_pilot() != null and cruiser.get_pilot() != null, "every NPC ship has a pilot")
	_check(fighter.get_pilot().doctrine == _registry.ship_class(&"fighter").get_doctrine(), "a fighter's pilot flies the fighter doctrine")
	_check(cruiser.get_pilot().doctrine == _registry.ship_class(&"cruiser").get_doctrine(), "...a cruiser's the cruiser doctrine")
	_check(freighter.get_pilot().doctrine == null, "a freighter's pilot has none (it only runs)")
	_check(fighter.get_pilot().mode == ShipPilot.Mode.IDLE and fighter.state != NpcShip.State.ENGAGED, "ships start out not engaged")
	_check(fighter.is_free_agent() and fighter.can_fight(), "a lone ship is a free agent that can fight")
	await _clear()


func _test_fire_rules() -> void:
	# --- Fixed guns fire only when the nose is on the target and it is in reach.
	var shooter := _frozen(&"federation_fighter", &"faction_1", Vector2.ZERO, 0.0)
	var target := _frozen(&"hegemony_fighter", &"faction_2", Vector2(400.0, 0.0))
	await _wait(0.2)
	var sc := shooter.get_combatant()
	var tc := target.get_combatant()
	sc.set_target(tc)
	_check(sc.fire_at_will() == 1 and sc.weapons.shots_fired == 1, "a fighter with its nose on a target in reach fires its gun")
	_check(sc.fire_at_will() == 0, "...and nothing more until they have cooled down")
	sc.weapons.tick(10.0)
	target.global_position = _centre + Vector2(400.0, 400.0)
	_check(sc.fire_at_will() == 0, "a target 45 degrees off the nose is not fired at")
	target.global_position = _centre + Vector2(400.0, 20.0)
	_check(sc.fire_at_will() == 1, "...but one only 3 degrees off is")
	sc.weapons.tick(10.0)
	target.global_position = _centre + Vector2(1500.0, 0.0)
	_check(sc.fire_at_will() == 0, "a target beyond the reach of the guns is not fired at")
	target.global_position = _centre + Vector2(400.0, 0.0)
	sc.weapons.tick(10.0)
	sc.health.energy = 0.0
	_check(sc.fire_at_will() == 0, "a ship with no energy cannot fire")
	sc.health.energy = sc.health.max_energy
	sc.set_target(null)
	_check(sc.fire_at_will() == 0, "with no target there is nothing to fire at")
	shooter.set_heading(PI)
	sc.set_target(tc)  # (the nose now points away: the target is behind the ship)
	sc.weapons.tick(10.0)
	_check(sc.fire_at_will() == 0, "a target behind the ship is not fired at")
	await _clear()

	# --- Big guns pass through nimble ships, so a pilot does not waste them on one.
	var cruiser := _frozen(&"federation_cruiser", &"faction_1", Vector2.ZERO, 0.0)
	var fighter := _frozen(&"hegemony_fighter", &"faction_2", Vector2(500.0, 0.0))
	await _wait(0.2)
	var cc := cruiser.get_combatant()
	cc.set_target(fighter.get_combatant())
	_check(cc.fire_at_will() == 0, "a cruiser, dead on a fighter, fires nothing: its medium and heavy guns would pass through it")
	_check(cc.fire() > 0, "(while an ordinary fire() would have wasted shots)")
	cc.weapons.tick(10.0)
	var frigate_target := _frozen(&"hegemony_frigate", &"faction_2", Vector2(0.0, 500.0))
	cc.set_target(frigate_target.get_combatant())
	var turrets := cc.fire_at_will()
	_check(turrets == 2, "a frigate abeam is fired at by the two turrets (the fixed gun does not point at it): %d" % turrets)
	cc.weapons.tick(10.0)
	frigate_target.global_position = _centre + Vector2(-500.0, 0.0)
	_check(cc.fire_at_will() == 0, "...but not one dead astern, outside every arc and the nose")
	await _clear()

	# --- A frigate can still use its light turrets on a fighter, but not its medium cannon.
	var frigate := _frozen(&"federation_frigate", &"faction_1", Vector2.ZERO, 0.0)
	var nimble := _frozen(&"hegemony_fighter", &"faction_2", Vector2(400.0, 0.0))
	await _wait(0.2)
	frigate.get_combatant().set_target(nimble.get_combatant())
	var fired := frigate.get_combatant().fire_at_will()
	_check(fired == 2 and frigate.get_combatant().weapons.shots_fired == 2, "a frigate fires its two light turrets at a fighter, not its pulse cannon (%d)" % fired)
	await _clear()


func _test_neutral() -> void:
	var first := _ship(&"federation_fighter", &"faction_1", Vector2(-200.0, 0.0))
	var second := _ship(&"federation_fighter", &"faction_1", Vector2(200.0, 0.0))
	var freighter := _ship(&"freighter", &"", Vector2(0.0, 300.0))
	await _wait(6.0)
	var calm := true
	for ship in [first, second, freighter]:
		calm = calm and ship.get_pilot().mode == ShipPilot.Mode.IDLE and ship.state != NpcShip.State.ENGAGED
	_check(calm, "ships with no enemy about stay out of combat")
	_check(first.get_combatant().weapons.shots_fired == 0 and second.get_combatant().weapons.shots_fired == 0, "...and fire nothing: Federation ships are not hostile to each other, or to a neutral ship")
	_check(first.state == NpcShip.State.WANDERING, "...they carry on with what they were doing")
	await _clear()


func _test_war() -> void:
	# The Federation and the Hegemony are at war: a Federation fighter attacks a Hegemony
	# freighter (a ship that cannot fight back), which runs.
	var box := {}
	box["fighter"] = _ship(&"federation_fighter", &"faction_1", Vector2(-500.0, 0.0))
	box["freighter"] = _ship(&"freighter", &"faction_2", Vector2(500.0, 0.0))
	var engaged: bool = await _wait_until(func() -> bool: return _mode_of(box["fighter"]) == ShipPilot.Mode.ATTACK and _mode_of(box["freighter"]) == ShipPilot.Mode.FLEE, 10.0, 0.25)
	_check(engaged, "a Federation fighter attacks a Hegemony freighter, which runs")
	await _clear()


func _test_pirate_and_freighter() -> void:
	var box := {}
	box["pirate"] = _ship(&"interceptor", &"faction_3", Vector2(-500.0, 0.0))
	box["freighter"] = _ship(&"freighter", &"", Vector2(500.0, 0.0))
	var pirate: NpcShip = box["pirate"]
	var freighter: NpcShip = box["freighter"]
	var running: bool = await _wait_until(func() -> bool: return _mode_of(box["freighter"]) == ShipPilot.Mode.FLEE, 10.0, 0.25)
	_check(running, "a freighter runs from an armed pirate")
	_check(freighter.state == NpcShip.State.ENGAGED and freighter.details.status == "Fleeing", "...its ship is in the engaged state and says so (%s)" % freighter.details.status)
	_check(pirate.get_pilot().mode == ShipPilot.Mode.ATTACK and pirate.get_combatant().get_target() == freighter.get_combatant(), "the pirate attacks the freighter")
	_check(pirate.details.status.begins_with("Engaging"), "...and its status says so (%s)" % pirate.details.status)
	await _wait(1.0)
	_check(_gone(freighter) or freighter.get_combatant().weapons.shots_fired == 0, "the freighter never fires")
	var killed: bool = await _wait_until(func() -> bool: return _gone(box["freighter"]), 60.0)
	_check(killed, "the pirate catches and destroys the freighter")
	var stood_down: bool = await _wait_until(func() -> bool: return _mode_of(box["pirate"]) == ShipPilot.Mode.IDLE and box["pirate"].state == NpcShip.State.WANDERING, 15.0)
	_check(stood_down, "with nobody left to fight the pirate stands down and goes back to what it was doing")
	await _clear()


func _test_two_on_one() -> void:
	var allies: Array = [
		_ship(&"federation_fighter", &"faction_1", Vector2(-700.0, -100.0)),
		_ship(&"federation_fighter", &"faction_1", Vector2(-700.0, 100.0))]
	var box := {"enemy": _ship(&"hegemony_fighter", &"faction_2", Vector2(700.0, 0.0)), "allies": allies}
	# (With one light blaster each a duel takes a while, and the lone fighter, hurt, may run
	# rather than die: it is destroyed, jumps out, or is running from them. Any of those is
	# two fighters seeing off one.)
	var won: bool = await _wait_until(func() -> bool: return _gone(box["enemy"]) or _mode_of(box["enemy"]) == ShipPilot.Mode.RETREAT, 180.0)
	_check(won, "two fighters see off one (it is destroyed, jumps out, or runs)")
	var both_fired := true
	for ship in allies:
		both_fired = both_fired and (_gone(ship) or ship.get_combatant().weapons.shots_fired > 0)
	_check(both_fired, "...both of them shooting")
	if _gone(box["enemy"]):
		var settled: bool = await _wait_until(func() -> bool:
			for ship in box["allies"]:
				if not _gone(ship) and (ship.get_pilot().mode != ShipPilot.Mode.IDLE or ship.state != NpcShip.State.WANDERING):
					return false
			return true, 20.0)
		_check(settled, "the survivors stand down and go back to their route")
		for ship in allies:
			if not _gone(ship):
				_check(ship.get_combatant().get_target() == null and ship.details.status == "Drifting around the system", "...with no target and their old status (%s)" % ship.details.status)
	await _clear()


func _test_big_ships() -> void:
	# A cruiser cannot hurt fighters, so it does not pick them as targets.
	var cruiser := _ship(&"federation_cruiser", &"faction_1", Vector2(-800.0, 0.0))
	var fighters: Array = [
		_ship(&"hegemony_fighter", &"faction_2", Vector2(800.0, -100.0)),
		_ship(&"hegemony_fighter", &"faction_2", Vector2(800.0, 100.0))]
	var box := {"fighters": fighters, "attacked": false}
	var elapsed := 0.0
	while elapsed < 10.0:
		await _wait(0.5)
		elapsed += 0.5
		for ship in box["fighters"]:
			if not _gone(ship):
				box["attacked"] = box["attacked"] or ship.get_pilot().mode == ShipPilot.Mode.ATTACK or ship.get_combatant().weapons.shots_fired > 0
	var cc := cruiser.get_combatant()
	_check(cc.get_target() == null and cruiser.get_pilot().mode == ShipPilot.Mode.IDLE, "a cruiser with only fighters in sight picks no target and does not give chase")
	_check(cc.weapons.shots_fired == 0, "...and fires nothing at them")
	var attacks := 1 if box["attacked"] else 0
	await _clear()
	# (The cruiser's point defence can kill a pair of fighters before they get a shot in: one
	# run proves little either way, so the fighters must attack in most of three runs.)
	for run in 2:
		cruiser = _ship(&"federation_cruiser", &"faction_1", Vector2(-800.0, 0.0))
		box = {"fighters": [
				_ship(&"hegemony_fighter", &"faction_2", Vector2(800.0, -100.0)),
				_ship(&"hegemony_fighter", &"faction_2", Vector2(800.0, 100.0))], "attacked": false}
		elapsed = 0.0
		while elapsed < 10.0:
			await _wait(0.5)
			elapsed += 0.5
			for ship in box["fighters"]:
				if not _gone(ship):
					box["attacked"] = box["attacked"] or ship.get_pilot().mode == ShipPilot.Mode.ATTACK or ship.get_combatant().weapons.shots_fired > 0
		attacks += 1 if box["attacked"] else 0
		await _clear()
	_check(attacks >= 2, "the fighters attack the cruiser (in %d of 3 runs)" % attacks)

	# Against a frigate it does fight, and wins.
	box = {}
	box["big"] = _ship(&"federation_cruiser", &"faction_1", Vector2(-800.0, 0.0))
	box["frigate"] = _ship(&"hegemony_frigate", &"faction_2", Vector2(800.0, 0.0))
	var big: NpcShip = box["big"]
	var beaten: bool = await _wait_until(func() -> bool: return _gone(box["frigate"]) or _mode_of(box["frigate"]) == ShipPilot.Mode.RETREAT, 90.0)
	_check(beaten, "a cruiser beats a frigate, which is destroyed or runs")
	_check(not _gone(big) and big.get_combatant().health.state.hull > big.get_combatant().health.state.max_hull * 0.5, "...with the cruiser hardly scratched")
	await _clear()


func _test_fighters_v_cruiser() -> void:
	# (a cruiser's point defence beats three: see the point_defence scenario)
	var fighters: Array = []
	for i in 8:
		fighters.append(_ship(&"federation_fighter", &"faction_1", Vector2(-700.0, (i - 3.5) * 130.0)))
	var box := {"cruiser": _ship(&"hegemony_cruiser", &"faction_2", Vector2(700.0, 0.0))}
	var killed: bool = await _wait_until(func() -> bool: return _gone(box["cruiser"]), 120.0)
	_check(killed, "eight fighters wear down a cruiser that has no fighter cover")
	_check(_alive_count(fighters) >= 1, "...and at least one survives (%d)" % _alive_count(fighters))
	await _clear()


func _test_retreat() -> void:
	# A badly damaged fighter runs from an armed enemy that cannot hurt it, and jumps out.
	var exits: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT]
	var box := {}
	box["hurt"] = _ship(&"hegemony_fighter", &"faction_2", Vector2(300.0, 0.0), 0.0, exits)
	box["cruiser"] = _ship(&"federation_cruiser", &"faction_1", Vector2(-300.0, 0.0))
	var hurt: NpcShip = box["hurt"]
	var cruiser: NpcShip = box["cruiser"]
	hurt.get_combatant().health.state.hull = hurt.get_combatant().health.state.max_hull * 0.1
	await _wait(0.5)
	var ran: bool = await _wait_until(func() -> bool: return _mode_of(box["hurt"]) == ShipPilot.Mode.RETREAT, 5.0, 0.25)
	_check(ran, "a fighter with 10% hull left retreats from an enemy")
	_check(_gone(hurt) or hurt.details.status == "Retreating", "...and says so")
	var away: bool = await _wait_until(func() -> bool: return _gone(box["hurt"]) or box["hurt"].state == NpcShip.State.WARPING or box["hurt"].global_position.distance_to(box["cruiser"].global_position) > 1500.0, 20.0, 0.25)
	_check(away, "...and runs from it")
	var jumped: bool = await _wait_until(func() -> bool: return not is_instance_valid(box["hurt"]) or box["hurt"].is_queued_for_deletion() or box["hurt"].state == NpcShip.State.WARPING, 40.0)
	_check(jumped, "...and, with a way out of the system, jumps out")
	_check(cruiser.get_combatant().health.state.hull == cruiser.get_combatant().health.state.max_hull, "(the cruiser never touched it)")
	await _clear()

	# With no way out it just keeps its distance, and stands down when it is safe.
	var trapped_box := {}
	trapped_box["trapped"] = _ship(&"hegemony_fighter", &"faction_2", Vector2(300.0, 0.0))
	trapped_box["guard"] = _ship(&"federation_cruiser", &"faction_1", Vector2(-300.0, 0.0))
	var trapped: NpcShip = trapped_box["trapped"]
	trapped.get_combatant().health.state.hull = trapped.get_combatant().health.state.max_hull * 0.1
	await _wait(0.5)
	var started: bool = await _wait_until(func() -> bool: return _mode_of(trapped_box["trapped"]) == ShipPilot.Mode.RETREAT, 5.0, 0.25)
	_check(started and not trapped.can_flee_by_jump(), "(setup) a retreating ship with nowhere to jump to")
	var far: bool = await _wait_until(func() -> bool: return trapped_box["trapped"].global_position.distance_to(trapped_box["guard"].global_position) > 2500.0, 20.0, 0.25)
	_check(far, "it runs until it is well clear of the enemy")
	trapped_box["guard"].queue_free()
	var calm: bool = await _wait_until(func() -> bool: return _mode_of(trapped_box["trapped"]) == ShipPilot.Mode.IDLE and trapped_box["trapped"].state != NpcShip.State.ENGAGED, 20.0)
	_check(calm, "...and stands down once there is no enemy in sight")
	await _clear()


func _test_chase() -> void:
	# A badly hurt fighter with no way out of the system runs from an equally fast, healthy
	# one. The chaser must not follow it across the galaxy: it gives up at its leash, and
	# both then stand down. (The runner cannot be killed here, so the chase cannot end that way.)
	var box := {}
	box["runner"] = _ship(&"hegemony_fighter", &"faction_2", Vector2(300.0, 0.0))
	box["chaser"] = _ship(&"federation_fighter", &"faction_1", Vector2(-300.0, 0.0))
	var runner: NpcShip = box["runner"]
	var chaser: NpcShip = box["chaser"]
	var state := runner.get_combatant().health.state
	state.shield = 1000000.0
	state.max_shield = 1000000.0
	state.hull = state.max_hull * 0.1
	var leash := AiTuning.shared().pursuit_leash
	var chasing: bool = await _wait_until(func() -> bool: return _mode_of(box["runner"]) == ShipPilot.Mode.RETREAT and _mode_of(box["chaser"]) == ShipPilot.Mode.ATTACK, 10.0, 0.25)
	_check(chasing, "(setup) a hurt fighter runs and a healthy one chases it")
	var gave_up: bool = await _wait_until(func() -> bool: return _mode_of(box["chaser"]) == ShipPilot.Mode.IDLE, 40.0, 0.25)
	_check(gave_up, "the chaser gives up the chase")
	_check(chaser.global_position.distance_to(_centre) < leash * 2.5, "...not far past its leash (%d px from the centre, leash %d)" % [chaser.global_position.distance_to(_centre), leash])
	_check(chaser.get_combatant().get_target() == null and chaser.state != NpcShip.State.ENGAGED, "...and goes back to what it was doing")
	var settled: bool = await _wait_until(func() -> bool: return _mode_of(box["runner"]) == ShipPilot.Mode.IDLE and _mode_of(box["chaser"]) == ShipPilot.Mode.IDLE, 40.0)
	_check(settled, "the runner then stands down too, once the chaser is out of sight")
	await _wait(10.0)
	_check(runner.global_position.distance_to(_centre) < leash * 4.0 and chaser.global_position.distance_to(_centre) < leash * 4.0, "neither ends up far from the system (%d and %d px)" % [runner.global_position.distance_to(_centre), chaser.global_position.distance_to(_centre)])
	await _clear()


func _test_formation_members() -> void:
	# Members of a formation do not fight on their own: with no enemy about they hold their
	# slots (the squadron commander orders them to fight when there is one: squadron_ai_test).
	var shape: FormationShape = _registry.formation_shape(&"wedge")
	var squadron := _sandbox.spawn_formation(shape, [&"federation_heavy_fighter", &"federation_fighter", &"federation_fighter"], Formation.Kind.SQUADRON)
	await _wait(4.0)
	var held := true
	for ship in squadron.get_members():
		held = held and ship.state == NpcShip.State.IN_FORMATION and ship.get_pilot().mode == ShipPilot.Mode.IDLE and not ship.is_free_agent()
	_check(held and squadron.get_members().size() == 2, "the members of a formation are not free agents: they stay in their slots")
	_check(squadron.lead.led_formation == squadron and not squadron.lead.is_free_agent(), "...nor is its leader")
	await _clear()


func _test_point_defence() -> void:
	# A cruiser's point defence shoots fighters by itself (the cruiser has no target and its
	# pilot is off), never a frigate, and is left out of the numbers that describe its guns.
	var cruiser := _frozen(&"federation_cruiser", &"faction_1", Vector2.ZERO, 0.0)
	var frigate := _frozen(&"hegemony_frigate", &"faction_2", Vector2(350.0, 0.0))
	await _wait(0.2)
	var cc := cruiser.get_combatant()
	var weapons := cc.weapons
	_check(weapons.has_point_defence() and weapons.get_point_defence_range() > 0.0, "(setup) a cruiser carries point defence")
	_check(weapons.get_longest_range() == 1000.0 and weapons.get_dps(true) == 0.0, "...which is left out of its reach and its damage against nimble ships (so it still picks no fighter as a target)")
	_check(weapons.get_dps(true, true) > 0.0, "...but can be asked for")
	await _wait(2.0)
	_check(weapons.point_defence_shots == 0 and weapons.shots_fired == 0, "point defence does not fire at a frigate (%d shots)" % weapons.point_defence_shots)
	var fighter := _frozen(&"hegemony_fighter", &"faction_2", Vector2(300.0, 100.0))
	var box := {"fighter": fighter}
	var start_hull: float = fighter.get_combatant().health.state.hull + fighter.get_combatant().health.state.shield
	await _wait(3.0)
	_check(weapons.point_defence_shots > 0, "...but does at a fighter, with the cruiser aiming at nothing (%d shots)" % weapons.point_defence_shots)
	_check(weapons.shots_fired == 0, "...and the guns stay quiet")
	var hurt: bool = _gone(box["fighter"]) or box["fighter"].get_combatant().health.state.hull + box["fighter"].get_combatant().health.state.shield < start_hull
	_check(hurt, "...and hits it")
	var before := weapons.point_defence_shots
	weapons.tick(10.0)
	cc.fire()
	_check(weapons.shots_fired == 3 and weapons.point_defence_shots == before, "the fire button fires the three guns and not the point defence")
	await _clear()

	# A fighter pack against a cruiser: with point defence the cruiser beats three, and a
	# big enough pack still kills it.
	# (Each is a fight with random elements that a single run can lose by luck, so each check is
	# the majority of three runs.)
	var survived_three := 0
	var died_to_eight := 0
	for run in 3:
		var three := await _pack_v_cruiser(3)
		var eight := await _pack_v_cruiser(8)
		survived_three += 0 if three["cruiser_dead"] else 1
		died_to_eight += 1 if eight["cruiser_dead"] else 0
		print("  (run %d: 3 fighters v cruiser: cruiser %s; 8 fighters: cruiser %s)" % [run + 1, "dead" if three["cruiser_dead"] else "alive", "dead" if eight["cruiser_dead"] else "alive"])
	_check(survived_three >= 2, "a cruiser with point defence beats three fighters (%d of 3 runs)" % survived_three)
	_check(died_to_eight >= 2, "...but eight fighters still bring it down (%d of 3 runs)" % died_to_eight)


## A pack of `count` Federation fighters against a Hegemony cruiser, until one side is
## gone (or 200 s): whether the cruiser died, how many fighters were left, how long it took.
func _pack_v_cruiser(count: int) -> Dictionary:
	var pack: Array = []
	for i in count:
		pack.append(_ship(&"federation_fighter", &"faction_1", Vector2(-700.0, (i - (count - 1) / 2.0) * 130.0)))
	var box := {"cruiser": _ship(&"hegemony_cruiser", &"faction_2", Vector2(700.0, 0.0)), "fighters": pack}
	var elapsed := 0.0
	while elapsed < 200.0 and not _gone(box["cruiser"]) and _alive_count(box["fighters"]) > 0:
		await _wait(1.0)
		elapsed += 1.0
	var result := {"cruiser_dead": _gone(box["cruiser"]), "left": _alive_count(pack), "seconds": int(elapsed)}
	await _clear()
	return result


func _test_battle_line() -> void:
	# Two fleets fight. Cruisers lead the lines and advance on the enemy's big ships, and fighters
	# and frigates fight around them: nobody wanders off across the system.
	var fleet_a := {"faction": &"faction_1", "ships": [
			{"model": &"federation_fighter", "count": 4}, {"model": &"federation_frigate", "count": 2},
			{"model": &"federation_cruiser", "count": 1}]}
	var fleet_b := {"faction": &"faction_2", "ships": [
			{"model": &"hegemony_fighter", "count": 4}, {"model": &"hegemony_frigate", "count": 2},
			{"model": &"hegemony_cruiser", "count": 1}]}
	var sides: Dictionary = _sandbox.spawn_battle(fleet_a, fleet_b)
	var all: Array = []
	var cruisers: Array = []
	var starts := {}
	for key in ["a", "b"]:
		for ship in sides[key]:
			all.append(ship)
			if ship.ship_type.stats.ship_class.id == &"cruiser":
				cruisers.append(ship)
				starts[ship] = ship.global_position
	var tuning := AiTuning.shared()
	var worst_stray := 0.0
	var cruiser_fired := false
	var fought := false
	var elapsed := 0.0
	while elapsed < 120.0:
		await _wait(1.0)
		elapsed += 1.0
		var middle := Vector2.ZERO
		var count := 0
		for ship in all:
			if not _gone(ship):
				middle += ship.global_position
				count += 1
		if count == 0:
			break
		middle /= count
		for ship in all:
			if _gone(ship) or ship.state == NpcShip.State.WARPING:
				continue
			var pilot: ShipPilot = ship.get_pilot()
			if pilot.mode == ShipPilot.Mode.RETREAT:
				continue
			fought = fought or ship.get_combatant().weapons.shots_fired > 0
			worst_stray = maxf(worst_stray, ship.global_position.distance_to(middle))
		for cruiser in cruisers:
			if not _gone(cruiser):
				cruiser_fired = cruiser_fired or cruiser.get_combatant().weapons.shots_fired > 0
	print("  (battle line: worst stray %d px from the middle)" % worst_stray)
	_check(fought, "(setup) the fleets fight")
	_check(worst_stray < tuning.screen_radius * 2.0, "no ship strays far from the middle of the battle (%d px)" % worst_stray)
	_check(cruiser_fired, "the cruisers close on the enemy until they are in range, and fire")
	await _clear()


func _test_standoff() -> void:
	# Two lines start out of weapon range of each other, with fighters between the cruisers.
	# Nobody stares: the cruisers pick each other as targets from far off and advance.
	var box := {"cruisers": []}
	box["cruisers"].append(_ship(&"federation_cruiser", &"faction_1", Vector2(-1150.0, 0.0), 0.0, CombatSandbox.BATTLE_EXITS))
	box["cruisers"].append(_ship(&"hegemony_cruiser", &"faction_2", Vector2(1150.0, 0.0), PI, CombatSandbox.BATTLE_EXITS))
	for y in [-200.0, 200.0]:
		_ship(&"federation_fighter", &"faction_1", Vector2(-600.0, y), 0.0, CombatSandbox.BATTLE_EXITS)
		_ship(&"hegemony_fighter", &"faction_2", Vector2(600.0, y), PI, CombatSandbox.BATTLE_EXITS)
	var start_gap: float = box["cruisers"][0].global_position.distance_to(box["cruisers"][1].global_position)
	box["closest"] = start_gap
	var fired := await _wait_until(func() -> bool:
		var cruisers: Array = box["cruisers"]
		if _gone(cruisers[0]) or _gone(cruisers[1]):
			return true
		box["closest"] = minf(box["closest"], cruisers[0].global_position.distance_to(cruisers[1].global_position))
		return cruisers[0].get_combatant().weapons.shots_fired > 0 and cruisers[1].get_combatant().weapons.shots_fired > 0, 90.0, 0.5)
	_check(start_gap > 2000.0, "(setup) the cruisers start well out of each other's weapon range (%d px)" % start_gap)
	_check(fired, "both cruisers advanced through the fight and opened fire on each other (closest %d px)" % box["closest"])
	await _clear()


func _test_support() -> void:
	# A cruiser with nothing it can hurt (only enemy fighters) flies up to cover its own
	# fighters: within point-defence range of what they are fighting.
	var cruiser := _ship(&"federation_cruiser", &"faction_1", Vector2(-2200.0, 0.0), 0.0, CombatSandbox.BATTLE_EXITS)
	var box := {"cruiser": cruiser, "enemies": [], "saw_support": false, "closest": INF}
	for offset in [Vector2(-1800.0, -150.0), Vector2(-1800.0, 150.0)]:
		_ship(&"federation_fighter", &"faction_1", offset, 0.0, CombatSandbox.BATTLE_EXITS)
	for offset in [Vector2(0.0, -250.0), Vector2(0.0, -80.0), Vector2(0.0, 80.0), Vector2(0.0, 250.0)]:
		box["enemies"].append(_ship(&"hegemony_fighter", &"faction_2", offset, PI, CombatSandbox.BATTLE_EXITS))
	var pd_range: float = cruiser.get_combatant().weapons.get_point_defence_range()
	var start_gap := cruiser.global_position.distance_to(_centre)
	await _wait_until(func() -> bool:
		var ship = box["cruiser"]
		if _gone(ship):
			return true
		box["saw_support"] = box["saw_support"] or ship.get_pilot().mode == ShipPilot.Mode.SUPPORT
		for enemy in box["enemies"]:
			if not _gone(enemy):
				box["closest"] = minf(box["closest"], ship.global_position.distance_to(enemy.global_position))
		return _alive_count(box["enemies"]) == 0, 90.0, 0.5)
	_check(box["saw_support"], "a cruiser with only fighters to look at goes into SUPPORT when its own fighters are fighting")
	_check(box["closest"] < start_gap * 0.5, "...and moves up behind them (from %d px to %d px of the enemy)" % [start_gap, box["closest"]])
	_check(not _gone(cruiser) and cruiser.get_combatant().weapons.point_defence_shots > 0, "...and its point defence fires on the enemy fighters (%d shots)" % cruiser.get_combatant().weapons.point_defence_shots)
	_check(pd_range > 0.0, "(setup) the cruiser has point defence")
	await _clear()


func _test_player() -> void:
	# A pirate attacks the player, who then sees it as an attacker and can select it with V.
	_player.global_position = _centre
	_player.velocity = Vector2.ZERO
	var box := {}
	box["pirate"] = _ship(&"interceptor", &"faction_3", Vector2(900.0, 0.0))
	var pirate: NpcShip = box["pirate"]
	await _wait(0.5)
	var targeting: TargetingManager = _main.get_node("Targeting")
	var player := _player.combatant
	var attacked: bool = await _wait_until(func() -> bool: return box["pirate"].get_combatant().get_target() == player, 10.0, 0.25)
	_check(attacked, "a pirate that comes upon the player targets them")
	_combat.get_picture().refresh()
	_check(_combat.get_player_attackers().has(pirate.get_combatant()), "...which makes it one of the player's attackers")
	var hit: bool = await _wait_until(func() -> bool: return player.health.state.shield < player.health.state.max_shield, 20.0)
	_check(hit, "...and it shoots the player")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	event.pressed = true
	targeting._unhandled_input(event)
	_check(targeting.current_target != null and targeting.current_target == pirate.get_node("Targetable"), "V selects the pirate")

	# A docked (or jumping) player is out of the fight.
	_player.set_flight_enabled(false)
	_check(not player.is_in_play(), "a docked player is out of play")
	_combat.get_picture().refresh()
	_check(not _combat.get_picture().get_combatants().has(player), "...NPC pilots do not see them")
	var shield_before := player.health.state.shield
	var hull_before := player.health.state.hull
	await _wait(4.0)
	_check(player.health.state.hull == hull_before and player.health.state.shield >= shield_before, "...and cannot be hit (shield %d, hull %d)" % [player.health.state.shield, player.health.state.hull])
	_player.set_flight_enabled(true)
	_check(player.is_in_play(), "back in flight they are in play again")
	_player.begin_warp()
	_check(not player.is_in_play(), "...and out of it while jumping")
	_player.end_warp()
	_check(player.is_in_play(), "...and back when the jump ends")
	_player.global_position = _parked
	await _clear()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
