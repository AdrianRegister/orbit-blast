extends SceneTree
## Headless test of the dev combat sandbox, started the way a player starts it:
## from the main menu button.
##   Godot --headless --path . --script res://scripts/tests/combat_sandbox_test.gd </dev/null

const UNUSED_SAVE := "user://dev_sandbox_unused.json"

var _failures: int = 0


func _init() -> void:
	if FileAccess.file_exists(UNUSED_SAVE):
		DirAccess.remove_absolute(UNUSED_SAVE)
	var menu: MainMenu = load("res://scenes/ui/main_menu.tscn").instantiate()
	menu.save_path = "user://combat_sandbox_test_menu.json"  # (never the real save)
	root.add_child(menu)
	await process_frame
	var button: Button = menu.get_node("%SandboxButton")
	_check(button.text == "DEV COMBAT SANDBOX", "the main menu has a DEV COMBAT SANDBOX button")
	button.pressed.emit()
	await process_frame
	await process_frame
	await process_frame
	_check(not is_instance_valid(menu) or menu.is_queued_for_deletion(), "the menu closes")

	var main: Main = null
	for child in root.get_children():
		if child is Main:
			main = child
	_check(main != null and main.sandbox_mode, "a Main in sandbox mode is running")
	if main == null:
		quit(1)
		return

	var system := main.get_system()
	var player := main.get_player_ship()
	var data := main.get_player_data()
	var ships: ShipManager = main.get_node("Ships")
	var reputation: ReputationManager = main.get_node("Reputation")
	var registry := ContentRegistry.new()

	# --- One isolated system with one planet.
	_check(system.system_id == &"dev_combat_sandbox" and system.system_name == "Combat Sandbox", "the only system is the sandbox system")
	_check(not registry.has_system(system.system_id), "it is not on the galaxy map")
	var places := system.get_inhabited_nodes()
	_check(places.size() == 1 and places[0].data.display_name == "Proving Ground", "one planet")
	var planet: InhabitedData = places[0].data
	_check(registry.location(planet.id) == null, "the sandbox planet is not part of the real game's content")

	# --- Everything is for sale.
	_check(planet.shipyard_ships.size() == registry.all_ship_stats().size() and not planet.shipyard_ships.is_empty(), "the shipyard lists every ship (%d)" % planet.shipyard_ships.size())
	_check(planet.outfitter_upgrades.size() == registry.all_upgrades().size(), "the outfitter lists every upgrade")
	_check(planet.outfitter_weapons.size() == registry.all_weapons().size(), "the outfitter lists every weapon")
	_check(ships.get_ships_for_sale(planet).size() == planet.shipyard_ships.size(), "faction-locked ships are for sale too")

	# --- The player: 500,000,000 credits and a Light Frigate.
	_check(data.credits == 500000000, "the player has 500,000,000 credits")
	_check(ships.get_active().model.id == &"light_frigate", "the player flies a Light Frigate")
	_check(player.combatant.weapons.has_weapons(), "it is armed")

	# --- The system starts empty (ships come from the dev panels), and nothing in the sandbox
	# charges a reputation, whoever the player shoots.
	_check(_live_ships(system).is_empty(), "the sandbox system starts with no NPC ships")
	var spawned := (main.get_node("Combat") as CombatManager).get_picture()
	_check(spawned != null, "(setup) the combat picture exists")
	var before := JSON.stringify(reputation.save_state())
	var dummy_type := ShipType.new()
	dummy_type.stats = registry.ship_stats(&"federation_fighter")
	var sandbox: CombatSandbox
	for child in main.get_children():
		if child is CombatSandbox:
			sandbox = child
	var target := sandbox.spawn_ship(dummy_type, &"faction_1", system.global_position, 0.0)
	await process_frame
	var tc: Combatant = target.get_node("Combatant")
	var hit := Hit.new()
	hit.damage = 5.0
	hit.attacker = player.combatant
	tc.take_hit(hit)
	var killer := Hit.new()
	killer.damage = 100000.0
	killer.attacker = player.combatant
	tc.take_hit(killer)
	_check(not tc.is_alive(), "a ship can be destroyed")
	_check(JSON.stringify(reputation.save_state()) == before, "destroying it changes nobody's reputation")
	await process_frame
	await process_frame
	_check(_live_ships(system).is_empty(), "nothing replaces it: the system stays empty")

	# --- Trade: land and buy a Federation cruiser (faction-locked in the real game).
	var targeting: TargetingManager = main.get_node("Targeting")
	var docking: DockingManager = main.get_node("Docking")
	var planet_target: Targetable = places[0].get_node("Targetable")
	docking.restore_docked(planet_target)
	var cruiser: ShipStats = load("res://resources/ships/federation_cruiser_stats.tres")
	var cost := ships.get_net_price(cruiser, 0)
	var result := ships.buy_ship(cruiser, false)
	_check(result.ok and data.credits == 500000000 - cost, "a Federation cruiser can be bought here: %s" % result.message)
	_check(ships.get_active().model.id == &"federation_cruiser" and ships.get_active().weapons[0] != null, "and it comes armed")
	var heavy: WeaponDefinition = load("res://resources/weapons/heavy_blaster.tres")
	_check(ships.sell_weapon(heavy).ok and ships.quote_weapon(heavy).ok, "weapons can be sold and bought back here")
	_check(ships.quote_repair().message == "Your ship is undamaged.", "repairs work here too")

	# --- Isolation: no jumping, no map, no saving, no contracts.
	_check(not main.try_jump().ok, "jumping is disabled")
	_check(not main._can_open_map(), "the galaxy map is disabled")
	main._on_pause_save_requested()
	_check(not FileAccess.file_exists(UNUSED_SAVE), "saving from the pause menu writes nothing")
	var contracts: ContractManager = main.get_node("Contracts")
	_check(not contracts.has_contracts_for(planet), "the sandbox planet offers no contracts")

	# --- Dying keeps the player in the sandbox, docked at the planet, in a Light Frigate.
	docking.reset()
	main.set_last_landed(&"")
	var credits_before_death := data.credits
	main.respawn_in_escape_pod()
	_check(main.get_system().system_id == &"dev_combat_sandbox", "the escape pod stays in the sandbox system")
	_check(main.get_docked_target() != null and (main.get_docked_target().details as InhabitedData).id == planet.id, "the player wakes docked at the Proving Ground")
	_check(ships.get_active().model.id == &"light_frigate", "the lost cruiser is replaced by the Light Frigate kept in storage")
	_check(data.credits == credits_before_death, "credits are kept")

	# --- Leaving the sandbox returns to the main menu.
	main._on_quit_to_menu_requested()
	await process_frame
	await process_frame
	var back := false
	for child in root.get_children():
		if child is MainMenu:
			back = true
	_check(back, "quitting the sandbox returns to the main menu")

	print("COMBAT SANDBOX TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	if FileAccess.file_exists(UNUSED_SAVE):
		DirAccess.remove_absolute(UNUSED_SAVE)
	quit(1 if _failures > 0 else 0)


## NPC ships in the system that are not on their way out of the game.
func _live_ships(system: StarSystem) -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for child in system.get_ships_root().get_children():
		var ship := child as NpcShip
		if ship != null and not ship.is_queued_for_deletion() and ship.visible:
			result.append(ship)
	return result


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
