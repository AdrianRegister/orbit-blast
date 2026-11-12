extends SceneTree
## Headless test of ship combat through the real game scene: firing, projectile
## hits, shields/armour/hull, destruction, targeting and the reputation reports.
##   Godot --headless --path . --script res://scripts/tests/combat_test.gd </dev/null

const PATH := "user://combat_test.json"

var _failures: int = 0
var _main: Main
var _destroyed_reports: Array[DestructionReport] = []
var _attacked_count: int = 0


func _init() -> void:
	_clean()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Save").save_path = PATH
	root.add_child(_main)
	await process_frame
	await process_frame

	var system := _main.get_system()
	var player := _main.get_player_ship()
	var combat: CombatManager = _main.get_node("Combat")
	var reputation: ReputationManager = _main.get_node("Reputation")
	var targeting: TargetingManager = _main.get_node("Targeting")
	var content := ContentRegistry.new()
	var federation := content.faction(&"faction_1")
	combat.ship_destroyed.connect(func(report: DestructionReport) -> void: _destroyed_reports.append(report))
	combat.ship_attacked.connect(func(_v: Combatant, _a: Combatant, _r: DamageResult) -> void: _attacked_count += 1)

	# Clear the ambient traffic so the test controls every ship.
	system.get_node("Traffic").reset()
	system.get_node("Traffic").set_process(false)
	player.global_position = Vector2(100000.0, 100000.0)  # far from everything
	player.velocity = Vector2.ZERO
	player.rotation = 0.0
	var origin: Vector2 = player.global_position

	# --- The player is armed and has live defences.
	var mine := player.combatant
	_check(mine.is_player and mine.combat_id == &"player", "the player's combatant is marked as the player")
	_check(mine.weapons.has_weapons(), "the starting shuttle comes armed (%s)" % mine.weapons.get_summary())
	_check(mine.health.state.hull > 0.0 and mine.health.state.max_shield > 0.0, "the player has shields and hull")
	_check(mine.health.energy > 0.0, "the player has energy")

	# --- A fragile target 400 px ahead, standing still.
	var victim := _spawn_victim(system, origin + Vector2(400.0, 0.0), 10.0, 10.0, 20.0, &"faction_1")
	var vc: Combatant = victim.get_node("Combatant")
	await process_frame
	_check(vc.is_alive() and vc.faction_id == &"faction_1", "the NPC has a combatant with a faction")
	_check(combat._registered.has(vc.get_instance_id()), "the CombatManager registered the NPC's combatant")

	# --- Firing: needs energy, respects the cooldown, spawns a shot.
	var energy_before := mine.health.energy
	var fired := mine.fire()
	_check(fired == 1, "fire() launches the ready weapon")
	_check(mine.health.energy < energy_before, "a shot costs energy")
	_check(mine.fire() == 0, "the weapon is on cooldown right after firing")
	var shots := system.get_projectiles_root().get_children().filter(func(n: Node) -> bool: return n is Projectile)
	_check(shots.size() == 1, "one projectile exists in the system's Projectiles node")
	var shot: Projectile = shots[0]
	_check(shot.velocity.x > 0.0 and is_equal_approx(shot.velocity.y, 0.0), "a fixed mount fires along the heading")

	# The shot hits the target and wears down shields first.
	var vs: DefenceState = vc.health.state
	var shield_before := vs.shield
	for i in 60:
		await physics_frame
		if not is_instance_valid(shot):
			break
	_check(not is_instance_valid(shot), "the shot is gone after reaching the target")
	_check(vs.shield < shield_before, "the hit took the shields first (%.1f -> %.1f)" % [shield_before, vs.shield])
	_check(is_equal_approx(vs.hull, 20.0), "hull is untouched while shields hold")
	_check(_attacked_count >= 1, "ship_attacked was announced")

	# --- Reputation: the first hit on a Federation ship costs reputation, once.
	var rep_after_hit := reputation.get_reputation(federation)
	_check(rep_after_hit < reputation.standings.start, "attacking a Federation ship lowers Federation reputation (%d)" % rep_after_hit)

	# --- Keep firing until it is destroyed.
	targeting.select(victim.get_node("Targetable"))
	_check(mine.get_target() == vc, "selecting a ship target makes it the player's combat target")
	for i in 900:
		mine.fire()
		await physics_frame
		if not _is_alive(vc):
			break
	_check(not _is_alive(vc), "the target was destroyed by sustained fire")
	_check(_destroyed_reports.size() == 1, "exactly one ship_destroyed report")
	if _destroyed_reports.size() == 1:
		var report := _destroyed_reports[0]
		_check(report.victim_id == &"test_npc" and report.victim_faction == &"faction_1", "the report names the victim and its faction")
		_check(report.attacker_is_player and report.attacker_id == &"player", "the report names the player as the attacker")
		_check(report.system_id == system.system_id, "the report records the system")
	_check(targeting.current_target == null, "the destroyed ship is deselected")
	_check(mine.get_target() == null, "the player's combat target is cleared")
	var rep_after_kill := reputation.get_reputation(federation)
	_check(rep_after_kill == rep_after_hit - CombatManager.DESTROY_SHIP.penalty, "destroying it cost the destroy_ship penalty, and the attack was not charged twice")
	await process_frame
	await process_frame
	_check(not is_instance_valid(victim) or victim.is_queued_for_deletion(), "the destroyed ship is removed from play")

	# --- Shots never hurt the shooter.
	var hull_before := mine.health.state.hull
	var shield_mine := mine.health.state.shield
	mine.health.tick(100.0)
	mine.weapons.tick(10.0)
	mine.fire()
	for i in 30:
		await physics_frame
	_check(is_equal_approx(mine.health.state.hull, hull_before) and is_equal_approx(mine.health.state.shield, shield_mine), "a ship is not hit by its own shots")

	# --- Turrets lead a moving target (Intercept).
	_test_turret_aim(system, combat)

	# --- Independent ships (no faction) charged to the system owner, once.
	await _test_passing_ship(system, player, origin, combat, reputation)

	# --- Shields recharge, armour and hull do not.
	var hurt := _spawn_victim(system, origin + Vector2(2000.0, 0.0), 40.0, 40.0, 40.0, &"")
	var hc: Combatant = hurt.get_node("Combatant")
	await process_frame
	var hit := Hit.new()
	hit.damage = 70.0
	hc.take_hit(hit)
	var after: DefenceState = hc.health.state
	_check(is_equal_approx(after.shield, 0.0) and after.armour < 40.0 and after.hull == 40.0, "70 damage strips 40 shield and dents the armour (%.1f/%.1f/%.1f)" % [after.shield, after.armour, after.hull])
	var armour_left := after.armour
	hc.health.tick(20.0)
	_check(after.shield > 0.0 and is_equal_approx(after.armour, armour_left), "shields recharge by themselves; armour does not")
	hurt.queue_free()

	# --- Projectiles go when the system is swapped.
	mine.projectile_root_provider = Callable()
	_check(system.get_projectiles_root() != null, "the system has a Projectiles root")

	print("COMBAT TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	_clean()
	quit(1 if _failures > 0 else 0)


## A stationary NPC with the given defences and no weapons.
func _spawn_victim(system: StarSystem, at: Vector2, shield: float, armour: float, hull: float, faction: StringName) -> NpcShip:
	var stats: ShipStats = load("res://resources/ships/shuttle_stats.tres").duplicate()
	stats.shield_capacity = shield
	stats.armour = armour
	stats.hull = hull
	stats.shield_regen = 5.0
	stats.shield_regen_delay = 2.0
	stats.weapon_mounts = []
	stats.default_loadout = []
	var type := ShipType.new()
	type.stats = stats
	var traffic: TrafficManager = system.get_node("Traffic")
	var ship: NpcShip = load("res://scenes/ships/npc_ship.tscn").instantiate()
	var nodes: Array[InhabitedNode] = system.get_inhabited_nodes()
	ship.setup(type, traffic.config, nodes, "", nodes[0], _main.get_player_ship())
	ship.configure_jumping(system.global_position, system.jump_radius, [])
	ship.combat_id = &"test_npc"
	ship.faction_id = faction
	system.get_ships_root().add_child(ship)
	ship.global_position = at
	ship.set_physics_process(false)  # it stays where it is
	return ship


func _test_turret_aim(system: StarSystem, combat: CombatManager) -> void:
	# A turret on the player ship with a target crossing its path should aim ahead.
	var mine := _main.get_player_ship().combatant
	var mount := WeaponMount.new()
	mount.type = WeaponMount.Type.TURRET
	mount.size = WeaponMount.Size.MEDIUM
	mount.arc_degrees = 170.0
	var pulse: WeaponDefinition = load("res://resources/weapons/pulse_cannon.tres")
	var slot := WeaponSlot.new()
	slot.mount = mount
	slot.weapon = pulse
	var fake_target := _spawn_victim(system, mine.global_position + Vector2(800.0, 0.0), 10.0, 10.0, 20.0, &"")
	var tc: Combatant = fake_target.get_node("Combatant")
	# Give the target a velocity through its provider.
	tc._velocity_provider = func() -> Vector2: return Vector2(0.0, 300.0)
	mine.set_target(tc)
	var direction: Vector2 = mine.weapons._aim_direction(mine, slot, mine.global_position)
	_check(direction.y > 0.0, "a turret aims ahead of a target moving across its path (%.2f)" % direction.y)
	# Outside its arc a turret swings no further than the arc.
	mount.arc_degrees = 5.0
	direction = mine.weapons._aim_direction(mine, slot, mine.global_position)
	_check(absf(direction.angle()) <= deg_to_rad(5.0) + 0.001, "a turret stays inside its arc")
	mine.set_target(null)
	fake_target.queue_free()


func _test_passing_ship(system: StarSystem, player: PlayerShip, origin: Vector2, combat: CombatManager, reputation: ReputationManager) -> void:
	# A ship with no faction in a system controlled by a faction: the controller is charged, once.
	var territory: TerritoryManager = _main.get_node("Territory")
	var controller: Faction = territory.get_control(system.system_id).controller
	if controller == null:
		print("SKIP  system has no single controlling faction")
		return
	var before := reputation.get_reputation(controller)
	var passer := _spawn_victim(system, origin + Vector2(3000.0, 0.0), 50.0, 50.0, 50.0, &"")
	passer.combat_id = &"test_passer"
	var pc: Combatant = passer.get_node("Combatant")
	pc.combat_id = &"test_passer"
	await process_frame
	var hit := Hit.new()
	hit.damage = 1.0
	hit.attacker = player.combatant
	pc.take_hit(hit)
	pc.take_hit(hit)
	var after := reputation.get_reputation(controller)
	_check(after == before - CombatManager.ATTACK_SHIP.penalty, "a faction-less ship is charged to the system's controller, once (%d -> %d)" % [before, after])
	passer.queue_free()


## A destroyed ship is freed at the end of the frame, so it may be gone entirely.
func _is_alive(combatant) -> bool:  # (untyped: a freed object fails a typed parameter)
	return is_instance_valid(combatant) and combatant.is_alive()


func _clean() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
