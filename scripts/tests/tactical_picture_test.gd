extends SceneTree
## Tests the awareness a combat AI relies on, in the real game scene (the combat
## sandbox's system): the CombatManager gives every ship the hostility rules, the
## TacticalPicture answers who is near, who is hostile and who is shooting at whom,
## and an attack on a ship starts a grudge. Run with:
##   Godot --headless --path . --script res://scripts/tests/tactical_picture_test.gd </dev/null

var _failures: int = 0
var _main: Main
var _system: StarSystem
var _player: PlayerShip
var _registry: ContentRegistry
var _combat: CombatManager
var _sandbox: CombatSandbox


func _init() -> void:
	seed(20260413)
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
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	_player.global_position = Vector2(30000.0, 30000.0)  # (far from everything)
	await process_frame
	await process_frame

	await _test_wiring()
	await _test_hostiles()
	await _test_pirates()
	await _test_targeting()
	await _test_grudge()

	print("TACTICAL PICTURE TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

func _type(id: StringName) -> ShipType:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(id)
	return type


func _ship(model: StringName, faction: StringName, at: Vector2) -> NpcShip:
	var ship := _sandbox.spawn_ship(_type(model), faction, at, 0.0)
	return ship


func _settle() -> void:
	# Ships register on the frame after they appear; the picture then looks again.
	await process_frame
	await process_frame
	_combat.get_picture().refresh()


func _combatants(ships: Array) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for ship in ships:
		result.append(ship.get_combatant())
	return result


# ----------------------------------------------------------------------- tests

func _test_wiring() -> void:
	var picture := _combat.get_picture()
	_check(picture != null and picture.get_parent() == _system, "the picture is a node under the star system (freed with it)")
	_check(_combat.get_hostility() != null, "the combat manager owns the hostility rules")
	var ship := _ship(&"federation_fighter", &"faction_1", Vector2(0.0, 0.0))
	await _settle()
	_check(ship.get_combatant().hostility == _combat.get_hostility(), "a ship that enters the system is given the hostility rules")
	_check(_player.combatant.hostility == _combat.get_hostility(), "...and so is the player")
	var rating := ship.get_combatant().rating
	_check(rating > 0.0 and is_equal_approx(rating, CombatRating.of(_registry.ship_stats(&"federation_fighter"))), "a combatant knows its combat rating (%.0f)" % rating)
	_check(ship.get_combatant().ship_class != null and ship.get_combatant().ship_class.id == &"fighter" and ship.get_combatant().is_armed(), "...its class, and that it is armed")
	_check(ship.get_combatant().weapons.get_dps() > ship.get_combatant().weapons.get_dps(true) - 0.001 and ship.get_combatant().weapons.get_dps(true) > 0.0, "...and its firepower, in all and in light weapons")
	var cruiser := _ship(&"federation_cruiser", &"faction_1", Vector2(100.0, 0.0))
	await _settle()
	_check(cruiser.get_combatant().weapons.get_dps(true) == 0.0 and cruiser.get_combatant().weapons.get_dps() > 0.0, "a cruiser has no light-weapon firepower")
	_check(picture.get_combatants().has(ship.get_combatant()) and picture.get_combatants().has(_player.combatant), "the picture lists the ships, and the player")
	var listed := picture.get_combatants().size()
	_sandbox.clear_battle()
	await _settle()
	_check(picture.get_combatants().size() == listed - 2, "ships that are gone are no longer listed")


func _test_hostiles() -> void:
	var picture := _combat.get_picture()
	var sides := _sandbox.spawn_battle(
			{"faction": &"faction_1", "model": &"federation_fighter", "count": 3},
			{"faction": &"faction_2", "model": &"hegemony_fighter", "count": 2})
	var civilian := _ship(&"freighter", &"", _player.global_position + Vector2(-300.0, 0.0))
	await _settle()
	var federation := _combatants(sides["a"])
	var hegemony := _combatants(sides["b"])
	var seen := picture.hostiles_near(federation[0], 100000.0)
	_check(seen.size() == hegemony.size() and seen.all(func(c: Combatant) -> bool: return hegemony.has(c)), "a Federation ship sees the Hegemony ships as hostile (%d)" % seen.size())
	_check(not seen.has(federation[1]) and not seen.has(civilian.get_combatant()) and not seen.has(_player.combatant), "...and not its own side, a ship that belongs to nobody, or the player")
	var sorted := true
	for index in range(1, seen.size()):
		if federation[0].global_position.distance_to(seen[index - 1].global_position) > federation[0].global_position.distance_to(seen[index].global_position):
			sorted = false
	_check(sorted, "hostiles are listed nearest first")
	_check(picture.hostiles_near(federation[0], 10.0).is_empty(), "...and only those within the radius")
	var from_hegemony := picture.hostiles_near(hegemony[0], 100000.0)
	_check(from_hegemony.size() == federation.size(), "the Hegemony sees the Federation the same way (%d)" % from_hegemony.size())
	_check(picture.hostiles_near(civilian.get_combatant(), 100000.0).is_empty(), "a ship that belongs to nobody has no enemies")
	_check(federation[0].is_hostile_to(hegemony[0]) and hegemony[0].is_hostile_to(federation[0]) and not federation[0].is_hostile_to(federation[1]), "Combatant.is_hostile_to agrees")
	_sandbox.clear_battle()
	await _settle()


func _test_pirates() -> void:
	var picture := _combat.get_picture()
	var pirate := _ship(&"interceptor", &"faction_3", Vector2(0.0, 0.0))
	var federation := _ship(&"federation_fighter", &"faction_1", Vector2(400.0, 0.0))
	var civilian := _ship(&"freighter", &"", Vector2(-400.0, 0.0))
	await _settle()
	var seen := picture.hostiles_near(pirate.get_combatant(), 5000.0)
	_check(seen.has(federation.get_combatant()) and seen.has(civilian.get_combatant()), "a pirate sees a Federation ship and a freighter as hostile")
	_check(picture.hostiles_near(federation.get_combatant(), 5000.0).has(pirate.get_combatant()), "...and they see it")
	_check(picture.hostiles_near(civilian.get_combatant(), 5000.0).has(pirate.get_combatant()), "...even a ship that belongs to nobody")
	_player.global_position = Vector2(500.0, 0.0)
	_check(pirate.get_combatant().is_hostile_to(_player.combatant), "pirates are hostile to the player too")
	_player.global_position = Vector2(30000.0, 30000.0)
	_sandbox.clear_battle()
	await _settle()


func _test_targeting() -> void:
	var picture := _combat.get_picture()
	var first := _ship(&"federation_fighter", &"faction_1", Vector2(0.0, 0.0))
	var second := _ship(&"federation_fighter", &"faction_1", Vector2(0.0, 80.0))
	var enemy := _ship(&"hegemony_fighter", &"faction_2", Vector2(3000.0, 0.0))
	var other_enemy := _ship(&"hegemony_fighter", &"faction_2", Vector2(-3000.0, 0.0))
	await _settle()
	var a := first.get_combatant()
	var b := second.get_combatant()
	var e := enemy.get_combatant()
	var o := other_enemy.get_combatant()
	_check(picture.targeters_of(e).is_empty() and picture.count_targeters(e) == 0, "nobody is targeting the enemy yet")
	a.set_target(e)
	picture.refresh()
	_check(picture.targeters_of(e) == [a] and picture.count_targeters(e) == 1, "a ship that targets another is counted as targeting it")
	b.set_target(e)
	picture.refresh()
	_check(picture.count_targeters(e) == 2 and picture.count_targeters(o) == 0, "...two of them, and none on the other enemy")
	_player.combatant.set_target(e)
	picture.refresh()
	_check(picture.count_targeters(e) == 2, "the player's own selection is not an attack and is not counted")
	_player.combatant.set_target(null)

	_check(picture.threats_to(e).has(a) and picture.threats_to(e).has(b), "ships targeting a ship are threats to it")
	_check(not picture.threats_to(o).has(a), "...and a ship that targets another is not")
	_check(not picture.threats_to(e).has(o), "(a ship that is not hostile or not aiming at it is not a threat)")
	_check(not picture.threats_to(a).has(e), "a ship that is far away and not targeting me is not a threat")
	# An armed hostile that closes to within its weapon reach is a threat even before it chooses a target.
	enemy.global_position = first.global_position + Vector2(300.0, 0.0)
	_check(picture.threats_to(a).has(e), "...but an armed hostile within its weapon reach of me is")
	enemy.global_position = first.global_position + Vector2(5000.0, 0.0)
	b.set_target(null)
	picture.refresh()
	_check(picture.count_targeters(e) == 1, "a ship that drops its target stops being counted")

	# A destroyed target is forgotten.
	a.set_target(e)
	picture.refresh()
	var before := picture.get_combatants().size()
	_sandbox.kill_ship(enemy)
	await _settle()
	_check(picture.get_combatants().size() == before - 1, "a destroyed ship is gone from the picture")
	_check(a.is_alive() and a.get_target() == null, "...and the ship that was targeting it has no target any more")
	_check(picture.count_targeters(o) == 0, "...and nobody is counted as targeting anything")
	_sandbox.clear_battle()
	await _settle()


func _test_grudge() -> void:
	var hostility := _combat.get_hostility()
	var federation := _ship(&"federation_fighter", &"faction_1", Vector2(0.0, 0.0))
	var other := _ship(&"federation_fighter", &"faction_1", Vector2(200.0, 0.0))
	var civilian := _ship(&"freighter", &"", Vector2(-300.0, 0.0))
	await _settle()
	var player := _player.combatant
	_check(not federation.get_combatant().is_hostile_to(player), "(setup) a Federation ship is not hostile to the player (no reputation in the sandbox)")
	var hit := Hit.from_weapon(load("res://resources/weapons/light_blaster.tres"), player, federation.global_position)
	federation.get_combatant().take_hit(hit)
	_check(hostility.get_reason(federation.get_combatant(), player) == Hostility.REASON_GRUDGE, "the player hitting a ship starts a grudge with its faction")
	_check(other.get_combatant().is_hostile_to(player), "...and the rest of the faction is hostile to the player")
	_check(not civilian.get_combatant().is_hostile_to(player), "...but not a ship that belongs to nobody")
	_check(not federation.get_combatant().is_hostile_to(other.get_combatant()), "...nor do the Federation's ships fall out with each other")
	# A hit by an NPC starts one too.
	var enemy := _ship(&"hegemony_fighter", &"faction_2", Vector2(0.0, 300.0))
	await _settle()
	var neutral := _ship(&"freighter", &"", Vector2(0.0, -300.0))
	await _settle()
	_check(not enemy.get_combatant().is_hostile_to(neutral.get_combatant()), "(setup) a Hegemony ship and a lone freighter are at peace")
	neutral.get_combatant().take_hit(Hit.from_weapon(load("res://resources/weapons/light_blaster.tres"), enemy.get_combatant(), neutral.global_position))
	_check(enemy.get_combatant().is_hostile_to(neutral.get_combatant()), "a ship that attacks a lone freighter has a grudge with it")
	hostility.clear()
	_check(not federation.get_combatant().is_hostile_to(player) and not enemy.get_combatant().is_hostile_to(neutral.get_combatant()), "clearing (what a change of system does) forgets every grudge")
	_sandbox.clear_battle()
	await _settle()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
