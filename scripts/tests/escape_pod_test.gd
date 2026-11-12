extends SceneTree
## Headless test of the player's destruction: the escape pod. Run through the
## real game scene:
##   Godot --headless --path . --script res://scripts/tests/escape_pod_test.gd </dev/null

const PATH := "user://escape_pod_test.json"

var _failures: int = 0
var _main: Main


func _init() -> void:
	_clean()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.get_node("Save").save_path = PATH
	root.add_child(_main)
	await process_frame
	await process_frame

	var system := _main.get_system()
	var player := _main.get_player_ship()
	var ships: ShipManager = _main.get_node("Ships")
	var economy: EconomyManager = _main.get_node("Economy")
	var contracts: ContractManager = _main.get_node("Contracts")
	var combat: CombatManager = _main.get_node("Combat")
	var content := ContentRegistry.new()
	var earth: InhabitedData = load("res://resources/locations/earth.tres")
	var shuttle: ShipStats = load("res://resources/ships/shuttle_stats.tres")
	var data := _main.get_player_data()
	system.get_node("Traffic").reset()
	system.get_node("Traffic").set_process(false)

	# --- Set the scene: a second ship in storage, cargo, a delivery contract, credits.
	var interceptor: ShipStats = load("res://resources/ships/interceptor_stats.tres")
	var stored := data.fleet.create_ship(interceptor, "Stored")
	stored.set_flag(OwnedShip.FLAG_PREVIOUS_SHIP, true)
	var flying := ships.get_active()
	var food: Commodity = load("res://resources/commodities/food.tres")
	var credits_before := data.credits
	data.cargo.capacity = 50
	data.cargo.add(food.id, 5)
	var delivery := CargoDeliveryContract.new()
	delivery.id = &"contract_pod_test"
	delivery.commodity = food
	delivery.quantity = 5
	delivery.origin = earth
	delivery.destination = earth
	delivery.status = Contract.Status.ACCEPTED
	delivery.quantity_in_hold = 5
	contracts._active.append(delivery)
	data.cargo.add_lot(delivery.id, food.id, 5, "test")
	var explore := ExplorationContract.new()
	explore.id = &"contract_pod_explore"
	explore.origin = earth
	explore.status = Contract.Status.ACCEPTED
	contracts._active.append(explore)
	_main.set_last_landed(&"earth")
	var reputation: ReputationManager = _main.get_node("Reputation")
	var rep_before := reputation.get_reputation(content.faction(&"faction_1"))

	# --- The player is destroyed.
	var reports: Array[DestructionReport] = []
	combat.player_destroyed.connect(func(report: DestructionReport) -> void: reports.append(report))
	var mine := player.combatant
	_check(mine.is_alive(), "the player starts alive")
	var killer := Hit.new()
	killer.damage = 100000.0
	killer.attacker = null
	mine.take_hit(killer)
	_check(not mine.is_alive(), "overwhelming damage destroys the player's ship")
	_check(reports.size() == 1 and reports[0].victim_is_player, "player_destroyed is announced once, naming the player")
	_check(_main.is_escape_pod_active(), "Main is now in the escape pod sequence")
	_check(not player.flight_enabled and not player.visible, "the wreck cannot fly and is hidden")
	_check(not _main.get_save_manager().autosave_enabled, "autosave is held off while the ship is destroyed")

	# While it happens, a second hit changes nothing and jumping is refused.
	mine.take_hit(killer)
	_check(reports.size() == 1, "a dead ship cannot be destroyed twice")
	_check(not _main.try_jump().ok, "no jumping during the sequence")

	# --- The pod lands (called directly; the timer and flash are only the delay).
	_main.respawn_in_escape_pod()
	_check(not _main.is_escape_pod_active(), "the sequence ends when the pod lands")
	var now := ships.get_active()
	_check(data.fleet.get_ship(flying.id) == null, "the destroyed ship is gone from the fleet")
	_check(now == stored and not now.has_flag(OwnedShip.FLAG_PREVIOUS_SHIP), "the stored ship became the active ship")
	_check(data.cargo.get_used() == 0, "all cargo is lost")
	_check(delivery.status == Contract.Status.FAILED and contracts.get_failed().has(delivery) and not contracts.get_active().has(delivery), "the delivery contract failed")
	_check(contracts.get_active().has(explore), "an exploration contract carries nothing and stays")
	contracts._active.erase(explore)  # (made-up contract: keep it out of the save written below)
	_check(data.credits == credits_before, "credits are kept")
	_check(is_equal_approx(reputation.get_reputation(content.faction(&"faction_1")), rep_before), "reputation is kept")
	_check(_main.get_docked_target() != null and (_main.get_docked_target().details as InhabitedData).id == &"earth", "the player wakes docked at the last place they landed")
	_check(player.visible and mine.is_alive(), "the new ship is whole and alive")
	_check(is_equal_approx(mine.health.state.hull, now.get_specs().hull), "the replacement is at full hull")
	_check(player.stats.max_speed == now.get_specs().max_speed, "the player flies the replacement's numbers")

	# --- No other ship: a basic ship is provided.
	var contracts_failed_before := contracts.get_failed().size()
	_main.set_last_landed(&"")  # never landed: the fallback place
	_main.respawn_in_escape_pod()
	var basic := ships.get_active()
	_check(data.fleet.get_ship(now.id) == null and basic.model == _main.starting_ship_stats, "with no ship left the player is given a basic one")
	_check(basic.weapons.size() == shuttle.weapon_mounts.size() and basic.weapons[0] != null and basic.condition.is_full(), "the new ship is armed and undamaged")
	_check(_main.get_docked_target() != null and (_main.get_docked_target().details as InhabitedData).id == _main.fallback_respawn.id, "with no last landing, the pod goes to the fallback place")
	_check(contracts.get_failed().size() == contracts_failed_before, "nothing more fails when there was no cargo contract")

	# --- The timed sequence runs by itself (delay, flash, landing) and saves once.
	_main.start_session()  # autosave on: the pod must then save immediately
	_main.set_last_landed(&"earth")
	var again := player.combatant
	again.take_hit(killer)
	_check(_main.is_escape_pod_active(), "a second destruction starts the sequence again")
	var started := Time.get_ticks_msec()
	while _main.is_escape_pod_active() and Time.get_ticks_msec() - started < 10000:
		await process_frame
	_check(not _main.is_escape_pod_active(), "the sequence finishes by itself (delay and flash)")
	_check(FileAccess.file_exists(PATH), "the game was saved straight after the pod landed")
	_check(_main.get_save_manager().autosave_enabled, "autosave is back on")
	if FileAccess.file_exists(PATH):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_check(saved is Dictionary and saved.has("fleet") and saved.has("player"), "the save file is readable")
		if saved is Dictionary and saved.has("player"):
			_check(saved["player"]["mode"] == "docked" and saved["player"]["docked_at"] == "earth", "the saved game has the player docked at Earth")
			var saved_ids: Array = (saved["fleet"]["ships"] as Array).map(func(entry: Dictionary) -> String: return entry["id"])
			_check(not saved_ids.has(str(basic.id)), "the ship that was destroyed is not in the saved fleet")

	print("ESCAPE POD TESTS: ", "all passed" if _failures == 0 else "%d FAILED" % _failures)
	_clean()
	quit(1 if _failures > 0 else 0)


func _clean() -> void:
	for path in [PATH, PATH + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS  ", label)
	else:
		print("FAIL  ", label)
		_failures += 1
