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

	# --- One freighter drifting around the centre, not firing, with no faction.
	var targets := _live_ships(system)
	_check(targets.size() == 1 and targets[0].ship_type.stats.id == &"freighter", "exactly one NPC, a freighter")
	var target: NpcShip = targets[0]
	_check(target.state == NpcShip.State.WANDERING, "it wanders")
	_check(target.faction_id == &"" and target.faction_name == "", "it belongs to nobody")
	var start := target.global_position
	var travelled := 0.0
	var farthest := 0.0
	var last := start
	for i in 900:
		await physics_frame
		travelled += target.global_position.distance_to(last)
		last = target.global_position
		farthest = maxf(farthest, target.global_position.distance_to(system.global_position))
	_check(travelled > 300.0, "it keeps moving (%d px in 15 s)" % int(travelled))
	_check(farthest < CombatSandbox.TARGET_WANDER_RADIUS * 1.6, "it stays around the centre (farthest %d px)" % int(farthest))
	_check(target.state == NpcShip.State.WANDERING, "it never docks or leaves")
	var fired := system.get_projectiles_root().get_children().filter(func(n: Node) -> bool: return n is Projectile)
	_check(fired.is_empty(), "it never fires")

	# --- No reputation hit for attacking or destroying it.
	var before := JSON.stringify(reputation.save_state())
	var tc: Combatant = target.get_node("Combatant")
	var hit := Hit.new()
	hit.damage = 5.0
	hit.attacker = player.combatant
	tc.take_hit(hit)
	var killer := Hit.new()
	killer.damage = 100000.0
	killer.attacker = player.combatant
	tc.take_hit(killer)
	_check(not tc.is_alive(), "the target can be destroyed")
	_check(JSON.stringify(reputation.save_state()) == before, "destroying it changes nobody's reputation")

	# --- A new one appears a few seconds later.
	var started := Time.get_ticks_msec()
	var replacement: NpcShip = null
	while Time.get_ticks_msec() - started < 8000:
		await process_frame
		var live := _live_ships(system)
		if live.size() == 1 and live[0] != target:
			replacement = live[0]
			break
	_check(replacement != null, "a new target ship replaces the destroyed one")

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
