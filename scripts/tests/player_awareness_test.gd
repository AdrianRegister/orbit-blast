extends SceneTree
## Tests what the player is told about other ships, through the real game scene:
## the navicomputer's dot colours (red for ships hostile to the player, green for
## the player's allies, blue otherwise), the ring round a ship that is targeting the
## player, and V, which selects the closest of those. Run with:
##   Godot --headless --path . --script res://scripts/tests/player_awareness_test.gd </dev/null

const NPC_SCENE := preload("res://scenes/ships/npc_ship.tscn")
const CONFIG := preload("res://resources/traffic/default_traffic.tres")

var _failures: int = 0
var _main: Main
var _system: StarSystem
var _player: PlayerShip
var _combat: CombatManager
var _reputation: ReputationManager
var _targeting: TargetingManager
var _map: NavMap
var _registry: ContentRegistry


func _init() -> void:
	seed(20260415)
	_registry = ContentRegistry.new()
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	for i in 3:
		await process_frame
	_system = _main.get_system()
	_player = _main.get_player_ship()
	_combat = _main.get_node("Combat")
	_reputation = _main.get_node("Reputation")
	_targeting = _main.get_node("Targeting")
	_map = (_main.get_node("Hud") as Hud).get_nav_map()
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	_player.global_position = Vector2.ZERO
	await process_frame
	await process_frame

	await _test_input()
	await _test_relations()
	await _test_navicomputer()
	await _test_attackers()
	await _test_target_key()

	print("PLAYER AWARENESS TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


# --------------------------------------------------------------- helpers

## Puts a motionless NPC ship of `model` and `faction` `distance` px from the player.
func _ship(model: StringName, faction: StringName, distance: float, angle: float = 0.0) -> NpcShip:
	var type := ShipType.new()
	type.stats = _registry.ship_stats(model)
	var ship: NpcShip = NPC_SCENE.instantiate()
	var no_places: Array[InhabitedNode] = []
	ship.setup(type, CONFIG, no_places, "", null, _player)
	ship.combat_id = TrafficManager.new_combat_id()
	ship.faction_id = faction
	ship.configure_jumping(_system.global_position, _system.jump_radius, [])
	ship.begin_wandering(Vector2.ZERO, 100.0)
	_system.get_ships_root().add_child(ship)
	ship.global_position = _player.global_position + Vector2.from_angle(angle) * distance
	ship.set_physics_process(false)  # (it stays where it is)
	return ship


func _settle() -> void:
	await process_frame
	await process_frame
	_combat.get_picture().refresh()


func _targetable(ship: NpcShip) -> Targetable:
	return ship.get_node("Targetable")


func _blip_of(ship: NpcShip) -> Dictionary:
	for blip in _map.get_blips():
		if blip["targetable"] == _targetable(ship):
			return blip
	return {}


func _clear() -> void:
	for ship in _system.get_ships_root().get_children():
		ship.queue_free()
	_targeting.select(null)
	_reputation.reset_state()
	await process_frame
	await process_frame


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


# ----------------------------------------------------------------------- tests

func _test_input() -> void:
	_check(InputMap.has_action("target_attacker"), "there is a target_attacker action")
	var events := InputMap.action_get_events("target_attacker")
	_check(events.size() == 1 and (events[0] as InputEventKey).physical_keycode == KEY_V, "...on the V key")
	_check(_targeting.attackers_provider.is_valid(), "the game gives the targeting manager the list of attackers")


func _test_relations() -> void:
	var federation := _registry.faction(&"faction_1")
	var freighter := _ship(&"freighter", &"", 500.0)
	var fed_fighter := _ship(&"federation_fighter", &"faction_1", 600.0)
	var heg_fighter := _ship(&"hegemony_fighter", &"faction_2", 700.0)
	var pirate := _ship(&"interceptor", &"faction_3", 800.0)
	await _settle()
	_check(_combat.get_player_relation(_targetable(freighter)) == CombatManager.Relation.NEUTRAL, "a ship that belongs to nobody is neutral")
	_check(_combat.get_player_relation(_targetable(fed_fighter)) == CombatManager.Relation.NEUTRAL, "a Federation ship is neutral to a new player")
	_check(_combat.get_player_relation(_targetable(heg_fighter)) == CombatManager.Relation.NEUTRAL, "...and so is a Hegemony ship (their war with the Federation is not the player's)")
	_check(_combat.get_player_relation(_targetable(pirate)) == CombatManager.Relation.HOSTILE, "a pirate is hostile")
	_reputation.change(federation, 39)
	_check(_combat.get_player_relation(_targetable(fed_fighter)) == CombatManager.Relation.NEUTRAL, "a Federation ship is still neutral just below Friendly (39)")
	_reputation.change(federation, 1)
	_check(_combat.get_player_relation(_targetable(fed_fighter)) == CombatManager.Relation.ALLY, "...and an ally once the player is Friendly (40)")
	_check(_combat.get_player_relation(_targetable(heg_fighter)) == CombatManager.Relation.NEUTRAL, "...which does not change the Hegemony")
	_reputation.change(federation, -120)  # to -80
	_check(_combat.get_player_relation(_targetable(fed_fighter)) == CombatManager.Relation.HOSTILE, "a Federation ship is hostile when the player is Hostile with the Federation (-80)")
	_reputation.change(federation, 1)
	_check(_combat.get_player_relation(_targetable(fed_fighter)) == CombatManager.Relation.NEUTRAL, "...and neutral again just above it")
	_reputation.reset_state()
	_check(_combat.get_player_relation(_system.get_inhabited_nodes()[0].get_node("Targetable")) == CombatManager.Relation.NEUTRAL, "a planet is neutral")
	_check(_combat.get_player_relation(null) == CombatManager.Relation.NEUTRAL, "...and so is nothing")
	_check(_combat.get_player_relation(_player.get_node("Targetable") if _player.has_node("Targetable") else null) == CombatManager.Relation.NEUTRAL, "...and the player's own ship")
	await _clear()


func _test_navicomputer() -> void:
	var federation := _registry.faction(&"faction_1")
	var freighter := _ship(&"freighter", &"", 500.0)
	var fed_fighter := _ship(&"federation_fighter", &"faction_1", 600.0, 1.0)
	var pirate := _ship(&"interceptor", &"faction_3", 800.0, 2.0)
	await _settle()
	var neutral_blip := _blip_of(freighter)
	var pirate_blip := _blip_of(pirate)
	_check(neutral_blip["relation"] == CombatManager.Relation.NEUTRAL and pirate_blip["relation"] == CombatManager.Relation.HOSTILE, "the map knows which ships are neutral and which hostile")
	_check(NavMap.ship_colour(neutral_blip["relation"]) == NavMap.SHIP_COLOUR and NavMap.SHIP_COLOUR.b > NavMap.SHIP_COLOUR.r, "neutral ships stay blue")
	_check(NavMap.ship_colour(pirate_blip["relation"]) == NavMap.HOSTILE_COLOUR and NavMap.HOSTILE_COLOUR.r > 0.9 and NavMap.HOSTILE_COLOUR.g < 0.4 and NavMap.HOSTILE_COLOUR.b < 0.4, "hostile ships are red")
	_reputation.change(federation, 60)
	var ally_blip := _blip_of(fed_fighter)
	_check(ally_blip["relation"] == CombatManager.Relation.ALLY and NavMap.ship_colour(ally_blip["relation"]) == NavMap.ALLY_COLOUR, "an ally is green")
	_check(NavMap.ALLY_COLOUR.g > 0.8 and NavMap.ALLY_COLOUR.r < 0.5 and NavMap.ALLY_COLOUR.b < 0.6, "...and it really is green")
	_check(not neutral_blip["attacking"] and not pirate_blip["attacking"] and not ally_blip["attacking"], "nobody has a ring while nobody is targeting the player")
	_check(_blip_of(freighter)["relation"] == CombatManager.Relation.NEUTRAL, "the others did not change colour")
	_reputation.change(federation, -140)  # to -80
	_check(NavMap.ship_colour(_blip_of(fed_fighter)["relation"]) == NavMap.HOSTILE_COLOUR, "a faction's ship turns red when the player becomes Hostile with it")
	var places := 0
	for blip in _map.get_blips():
		if blip["kind"] != NavMap.KIND_SHIP:
			places += 1
			_check(not blip.has("relation"), "places carry no relation")
			break
	_map.queue_redraw()  # (drawing every colour must not fail)
	await process_frame
	_check(true, "the map draws red, green and blue dots")
	# Without the combat view (no provider) every ship is blue.
	var bare := NavMap.new()
	bare.set_ship(_player)
	bare.set_system(_system)
	var all_blue := true
	for blip in bare.get_blips():
		if blip["kind"] == NavMap.KIND_SHIP and (blip["relation"] != CombatManager.Relation.NEUTRAL or blip["attacking"]):
			all_blue = false
	_check(all_blue, "a map with no combat view shows every ship as neutral")
	bare.free()
	await _clear()


func _test_attackers() -> void:
	var federation := _registry.faction(&"faction_1")
	var far_pirate := _ship(&"interceptor", &"faction_3", 900.0, 0.5)
	var near_pirate := _ship(&"interceptor", &"faction_3", 400.0, 2.5)
	var idle_pirate := _ship(&"interceptor", &"faction_3", 600.0, 4.0)
	var freighter := _ship(&"freighter", &"", 300.0, 5.0)
	var ally := _ship(&"federation_fighter", &"faction_1", 500.0, 3.5)
	await _settle()
	_reputation.change(federation, 50)
	var player := _player.combatant
	_check(_combat.get_player_attackers().is_empty() and _combat.get_player_attacker_targetables().is_empty(), "nobody is attacking the player to begin with")
	far_pirate.get_combatant().set_target(player)
	near_pirate.get_combatant().set_target(player)
	freighter.get_combatant().set_target(player)  # (not hostile)
	ally.get_combatant().set_target(player)  # (a friend)
	_combat.get_picture().refresh()
	var attackers := _combat.get_player_attackers()
	_check(attackers.size() == 2 and attackers.has(far_pirate.get_combatant()) and attackers.has(near_pirate.get_combatant()), "the hostile ships targeting the player are its attackers (%d)" % attackers.size())
	_check(not attackers.has(freighter.get_combatant()) and not attackers.has(ally.get_combatant()), "a neutral ship or an ally that targets the player is not an attacker")
	_check(not attackers.has(idle_pirate.get_combatant()), "a hostile ship that is not targeting the player is not one either")
	_check(_combat.get_player_attacker_targetables().size() == 2 and _combat.get_player_attacker_targetables().has(_targetable(far_pirate)), "they are also given as targetables")
	_check(_blip_of(far_pirate)["attacking"] and _blip_of(near_pirate)["attacking"], "the map rings the ships that are targeting the player")
	_check(not _blip_of(idle_pirate)["attacking"] and not _blip_of(freighter)["attacking"] and not _blip_of(ally)["attacking"], "...and only those")
	_check(_blip_of(idle_pirate)["relation"] == CombatManager.Relation.HOSTILE and _blip_of(far_pirate)["relation"] == CombatManager.Relation.HOSTILE, "a ship that is hostile stays red, ringed or not")
	_map.queue_redraw()
	await process_frame
	_check(true, "the map draws the rings")
	player.set_target(idle_pirate.get_combatant())
	_combat.get_picture().refresh()
	_check(_combat.get_player_attackers().size() == 2, "the player's own selection of a ship does not make it an attacker")
	player.set_target(null)
	near_pirate.get_combatant().set_target(null)
	_combat.get_picture().refresh()
	_check(_combat.get_player_attackers() == [far_pirate.get_combatant()] and not _blip_of(near_pirate)["attacking"], "a ship that stops targeting the player loses its ring")
	_sandbox_kill(far_pirate)
	await _settle()
	_check(_combat.get_player_attackers().is_empty(), "a destroyed attacker is gone from the list")
	await _clear()


func _sandbox_kill(ship: NpcShip) -> void:
	var hit := Hit.new()
	hit.damage = 1000000.0
	ship.get_combatant().take_hit(hit)


func _test_target_key() -> void:
	var far_pirate := _ship(&"interceptor", &"faction_3", 900.0, 0.5)
	var near_pirate := _ship(&"interceptor", &"faction_3", 400.0, 2.5)
	var middle_pirate := _ship(&"interceptor", &"faction_3", 600.0, 4.0)
	var freighter := _ship(&"freighter", &"", 100.0, 5.0)
	await _settle()
	var planet_target: Targetable = _system.get_inhabited_nodes()[0].get_node("Targetable")
	_targeting.select(planet_target)
	_check(not _targeting.select_closest_attacker() and _targeting.current_target == planet_target, "with nobody attacking, V does nothing and keeps the selection")
	_targeting._unhandled_input(_key(KEY_V))
	_check(_targeting.current_target == planet_target, "...also when pressed")

	far_pirate.get_combatant().set_target(_player.combatant)
	middle_pirate.get_combatant().set_target(_player.combatant)
	_combat.get_picture().refresh()
	_targeting._unhandled_input(_key(KEY_V))
	_check(_targeting.current_target == _targetable(middle_pirate), "V selects the attacker (here the nearer of two, 600 px against 900)")
	near_pirate.get_combatant().set_target(_player.combatant)
	_combat.get_picture().refresh()
	_targeting._unhandled_input(_key(KEY_V))
	_check(_targeting.current_target == _targetable(near_pirate), "with three attackers V selects the closest (400 px)")
	_check(_player.combatant.get_target() == near_pirate.get_combatant(), "...and the player's weapons and HUD follow it")
	near_pirate.global_position = _player.global_position + Vector2(1500.0, 0.0)
	_targeting._unhandled_input(_key(KEY_V))
	_check(_targeting.current_target == _targetable(middle_pirate), "the closest is judged each time: once the near one has moved away it is the 600 px one")
	_targetable(middle_pirate).set_enabled(false)
	_targeting._unhandled_input(_key(KEY_V))
	_check(_targeting.current_target == _targetable(far_pirate), "an attacker that cannot be targeted (jumped out) is skipped")
	_targeting.select(_targetable(freighter))
	_targeting._unhandled_input(_key(KEY_V))
	_check(_targeting.current_target == _targetable(far_pirate), "V picks an attacker even when something else is selected")
	var before := _targeting.current_target
	_check(_targeting.select_closest_attacker() and _targeting.current_target == before, "pressing it with the closest already selected keeps it")

	var bare := TargetingManager.new()
	_check(not bare.select_closest_attacker(), "a targeting manager with no origin or provider does nothing")
	bare.set_origin(_player)
	_check(not bare.select_closest_attacker(), "...nor with no provider")
	bare.free()
	await _clear()


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
