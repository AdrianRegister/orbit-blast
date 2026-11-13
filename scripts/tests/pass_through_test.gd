extends SceneTree
## Tests what shots pass through, in the real game scene (the combat sandbox's
## system): allies (no friendly fire), the front rank of an enemy formation (which
## still shields what is behind it), and nimble ships (fighters and heavy fighters)
## against medium and heavy weapons, the player included.
##   Godot --headless --path . --script res://scripts/tests/pass_through_test.gd </dev/null

const CONFIG := preload("res://resources/traffic/default_traffic.tres")
const PROJECTILE_SCENE := preload("res://scenes/combat/projectile.tscn")
const LIGHT := preload("res://resources/weapons/light_blaster.tres")
const MEDIUM := preload("res://resources/weapons/pulse_cannon.tres")
const HEAVY := preload("res://resources/weapons/heavy_blaster.tres")
const FACTION_A := &"faction_1"
const FACTION_B := &"faction_2"
## Where the test puts things: far from the sandbox planet, in a line along +x.
const ORIGIN := Vector2(-3000.0, -2000.0)

var _failures: int = 0
var _main: Main
var _system: StarSystem
var _player: PlayerShip
var _registry: ContentRegistry
var _combat: CombatManager
var _next_id: int = 0


func _init() -> void:
	seed(20260303)
	_registry = ContentRegistry.new()
	_main = CombatSandbox.build_main()
	root.add_child(_main)
	for i in 5:
		await process_frame
	_system = _main.get_system()
	_player = _main.get_player_ship()
	_combat = _main.get_node("Combat")
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	_player.global_position = Vector2(30000.0, 30000.0)
	await process_frame

	await _test_allies()
	await _test_enemy_blocks()
	await _test_faction_less()
	await _test_nimble_ships()
	await _test_swarm_against_cruiser()
	await _test_player()

	print("PASS THROUGH TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

## A frozen NPC ship (it does not move or fly) of the given model and faction.
func _ship(model_id: StringName, faction: StringName, offset: Vector2) -> NpcShip:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(model_id)
	var ship: NpcShip = FleetSpawner.NPC_SCENE.instantiate()
	var no_places: Array[InhabitedNode] = []
	ship.setup(type, CONFIG, no_places, "", null, _player)
	_next_id += 1
	ship.combat_id = StringName("pass_test_%d" % _next_id)
	ship.faction_id = faction
	ship.configure_jumping(_system.global_position, _system.jump_radius, [])
	ship.begin_wandering(_system.global_position, 100.0)
	_system.get_ships_root().add_child(ship)
	ship.global_position = ORIGIN + offset
	ship.set_physics_process(false)
	return ship


func _settle() -> void:
	# New ships are registered with the combat manager on the next idle frame.
	await process_frame
	await process_frame
	await physics_frame


func _clear() -> void:
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	for node in _system.get_projectiles_root().get_children():
		node.queue_free()
	await process_frame
	await process_frame


func _total(combatant: Combatant) -> float:
	var state: DefenceState = combatant.health.state
	return state.shield + state.armour + state.hull


## Fires one shot from `shooter` along +x and waits until it has hit something or
## faded. (The shot starts just ahead of the shooter.)
func _shoot(shooter: Combatant, weapon: WeaponDefinition, from: Vector2) -> void:
	var projectile: Projectile = PROJECTILE_SCENE.instantiate()
	_system.get_projectiles_root().add_child(projectile)
	projectile.launch(weapon, shooter, from + Vector2(60.0, 0.0), Vector2.RIGHT * weapon.projectile_speed)
	for frame in 240:
		await physics_frame
		if not is_instance_valid(projectile) or projectile.is_queued_for_deletion():
			return


## Fires one shot of `weapon` from a ship of `shooter_faction` at the ships standing
## along +x, and returns how much each lost: [blocker, target].
func _line_of_fire(weapon: WeaponDefinition, shooter_faction: StringName, blocker_model: StringName,
		blocker_faction: StringName, target_model: StringName, target_faction: StringName) -> Array[float]:
	var shooter := _ship(&"federation_frigate", shooter_faction, Vector2.ZERO)
	var blocker := _ship(blocker_model, blocker_faction, Vector2(250.0, 0.0))
	var target := _ship(target_model, target_faction, Vector2(500.0, 0.0))
	await _settle()
	var before_blocker := _total(blocker.get_combatant())
	var before_target := _total(target.get_combatant())
	await _shoot(shooter.get_combatant(), weapon, shooter.global_position)
	var result: Array[float] = [before_blocker - _total(blocker.get_combatant()), before_target - _total(target.get_combatant())]
	await _clear()
	return result


# ----------------------------------------------------------------- tests

func _test_allies() -> void:
	print("--- allies")
	for weapon in [LIGHT, MEDIUM, HEAVY]:
		var lost := await _line_of_fire(weapon, FACTION_A, &"federation_frigate", FACTION_A, &"federation_frigate", FACTION_B)
		_check(lost[0] == 0.0, "%s: a shot passes through an ally of the shooter (it lost %.1f)" % [weapon.display_name, lost[0]])
		_check(lost[1] > 0.0, "%s: ... and hits the enemy behind it (%.1f)" % [weapon.display_name, lost[1]])
	var lost := await _line_of_fire(HEAVY, FACTION_A, &"federation_frigate", FACTION_A, &"federation_frigate", FACTION_A)
	_check(lost[0] == 0.0 and lost[1] == 0.0, "a shot goes through a line of allies and hurts none of them")


func _test_enemy_blocks() -> void:
	print("--- enemy blocks")
	for weapon in [LIGHT, MEDIUM, HEAVY]:
		var lost := await _line_of_fire(weapon, FACTION_A, &"federation_frigate", FACTION_B, &"federation_frigate", FACTION_B)
		_check(lost[0] > 0.0 and lost[1] == 0.0, "%s: an enemy in front takes the shot and shields the one behind (%.1f / %.1f)" % [weapon.display_name, lost[0], lost[1]])
	var lost := await _line_of_fire(HEAVY, FACTION_A, &"federation_frigate", FACTION_B, &"federation_frigate", FACTION_A)
	_check(lost[0] > 0.0 and lost[1] == 0.0, "an enemy in front stops a shot meant for an ally of the shooter behind it")


func _test_faction_less() -> void:
	print("--- faction-less")
	var lost := await _line_of_fire(HEAVY, &"", &"federation_frigate", &"", &"federation_frigate", &"")
	_check(lost[0] > 0.0 and lost[1] == 0.0, "ships that belong to nobody are nobody's allies: the first takes the shot (%.1f)" % lost[0])
	lost = await _line_of_fire(HEAVY, FACTION_A, &"federation_frigate", &"", &"federation_frigate", &"")
	_check(lost[0] > 0.0, "a ship with no faction is hit by a faction's shot")


func _test_nimble_ships() -> void:
	print("--- nimble ships")
	for model in [&"federation_fighter", &"federation_heavy_fighter"]:
		for weapon in [MEDIUM, HEAVY]:
			var lost := await _line_of_fire(weapon, FACTION_B, model, FACTION_A, &"federation_cruiser", FACTION_A)
			_check(lost[0] == 0.0, "%s: a %s shot passes through (%.1f)" % [model, weapon.display_name, lost[0]])
			_check(lost[1] > 0.0, "%s: ... and the ship behind it takes it (%.1f)" % [model, lost[1]])
		var light := await _line_of_fire(LIGHT, FACTION_B, model, FACTION_A, &"federation_cruiser", FACTION_A)
		_check(light[0] > 0.0 and light[1] == 0.0, "%s: a light weapon does hit it, and it shields what is behind (%.1f)" % [model, light[0]])
	# Anything bigger is hit by everything.
	for model in [&"federation_frigate", &"federation_cruiser", &"interceptor", &"freighter"]:
		for weapon in [LIGHT, MEDIUM, HEAVY]:
			var lost := await _line_of_fire(weapon, FACTION_B, model, FACTION_A, &"federation_cruiser", FACTION_A)
			_check(lost[0] > 0.0 and lost[1] == 0.0, "%s is hit by a %s" % [model, weapon.display_name])
	# Nimble ships evade fire from an ally too (it passes either way), and from anyone with no faction.
	var lost := await _line_of_fire(HEAVY, &"", &"federation_fighter", FACTION_A, &"federation_cruiser", FACTION_A)
	_check(lost[0] == 0.0 and lost[1] > 0.0, "a faction-less shooter's heavy shot passes a fighter too")


func _test_swarm_against_cruiser() -> void:
	print("--- swarm")
	var swarm: Array[NpcShip] = []
	for index in 6:
		swarm.append(_ship(&"federation_fighter", FACTION_B, Vector2(0.0, -60.0 * index)))
	var cruiser := _ship(&"federation_cruiser", FACTION_A, Vector2(400.0, 0.0))
	await _settle()
	var start := _total(cruiser.get_combatant())
	var rounds := 0
	while is_instance_valid(cruiser) and cruiser.get_combatant().is_alive() and rounds < 60:
		for fighter in swarm:
			var projectile: Projectile = PROJECTILE_SCENE.instantiate()
			_system.get_projectiles_root().add_child(projectile)
			var from := Vector2(fighter.global_position.x + 60.0, cruiser.global_position.y)
			projectile.launch(LIGHT, fighter.get_combatant(), from, Vector2.RIGHT * LIGHT.projectile_speed)
		for frame in 30:
			await physics_frame
		rounds += 1
	var destroyed := not is_instance_valid(cruiser) or not cruiser.get_combatant().is_alive()
	_check(destroyed or _total(cruiser.get_combatant()) < start, "light weapons wear a cruiser down")
	_check(destroyed, "a swarm of fighters with light weapons can destroy a cruiser with no fighter support (%d rounds)" % rounds)
	# ... and the cruiser's own heavy fire cannot touch them.
	var untouched := true
	for fighter in swarm:
		untouched = untouched and fighter.get_combatant().is_alive()
	_check(untouched, "(the fighters were never hurt)")
	await _clear()


func _test_player() -> void:
	print("--- the player")
	var fighter_model := _registry.ship_stats(&"federation_fighter")
	var combatant: Combatant = _player.combatant
	# A player flying a fighter is nimble too.
	combatant.setup(fighter_model, ShipSpecs.compute(fighter_model), fighter_model.default_loadout, null,
			func() -> float: return 0.0, func() -> Vector2: return Vector2.ZERO)
	_player.global_position = ORIGIN + Vector2(250.0, 0.0)
	var shooter := _ship(&"federation_frigate", FACTION_B, Vector2.ZERO)
	await _settle()
	_check(combatant.evasive, "a player in a fighter-class ship is nimble")
	for weapon in [MEDIUM, HEAVY]:
		var before := _total(combatant)
		await _shoot(shooter.get_combatant(), weapon, shooter.global_position)
		_check(_total(combatant) == before, "the player's fighter is passed through by a %s" % weapon.display_name)
	var before := _total(combatant)
	await _shoot(shooter.get_combatant(), LIGHT, shooter.global_position)
	_check(_total(combatant) < before, "... but not by a light blaster")

	# The player in an ordinary ship is hit by everything.
	var frigate_model := _registry.ship_stats(&"federation_frigate")
	combatant.setup(frigate_model, ShipSpecs.compute(frigate_model), frigate_model.default_loadout, null,
			func() -> float: return 0.0, func() -> Vector2: return Vector2.ZERO)
	_check(not combatant.evasive, "a player in a frigate is not nimble")
	before = _total(combatant)
	await _shoot(shooter.get_combatant(), HEAVY, shooter.global_position)
	_check(_total(combatant) < before, "... and a heavy blaster hits it")

	# An allied player (reputation at the threshold) and a faction's ships pass each other's shots.
	var reputation := {FACTION_B: 60}
	var allegiance := Allegiance.new()
	allegiance.setup(AllegianceRules.shared(), func(faction_id: StringName): return reputation.get(faction_id))
	combatant.allegiance = allegiance
	shooter.get_combatant().allegiance = allegiance
	before = _total(combatant)
	await _shoot(shooter.get_combatant(), HEAVY, shooter.global_position)
	_check(_total(combatant) == before, "a faction's shot passes through a player they are allied with")
	var behind := _ship(&"federation_frigate", FACTION_A, Vector2(600.0, 0.0))
	await _settle()
	behind.get_combatant().allegiance = allegiance  # (after the combat manager has given its own)
	var behind_before := _total(behind.get_combatant())
	await _shoot(combatant, HEAVY, ORIGIN + Vector2(250.0 - 60.0, 0.0))
	_check(_total(behind.get_combatant()) < behind_before, "... and the player's shot goes through an ally's ship to hit an enemy behind it")
	var friend := _ship(&"federation_frigate", FACTION_B, Vector2(400.0, 0.0))
	await _settle()
	friend.get_combatant().allegiance = allegiance
	var friend_before := _total(friend.get_combatant())
	await _shoot(combatant, HEAVY, ORIGIN + Vector2(250.0 - 60.0, 0.0))
	_check(_total(friend.get_combatant()) == friend_before, "the player's shot does not hit their faction's ship")
	reputation[FACTION_B] = 0
	await _shoot(combatant, HEAVY, ORIGIN + Vector2(250.0 - 60.0, 0.0))
	_check(_total(friend.get_combatant()) < friend_before, "once the reputation drops below the threshold it does")
	reputation[FACTION_B] = 60
	await _clear()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
