extends SceneTree
## Headless test of saving and loading the real game scene: credits, cargo,
## contracts, markets, position, docked state, star system, NPC regeneration,
## autosave, and damaged files. Uses a throwaway file in user://. Run with:
##   Godot --headless --path . --script res://scripts/tests/save_game_test.gd

const PATH := "user://save_game_test.json"

var _failures: int = 0
var _main: Main
var _saves: SaveManager
var _economy: EconomyManager
var _contracts: ContractManager
var _ship: PlayerShip
var _player: PlayerData
var _docking: DockingManager
var _targeting: TargetingManager


func _init() -> void:
	_clean()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.starting_ship_stats = load("res://resources/ships/freighter_stats.tres")  # a hold big enough for the test cargo
	_main.get_node("Save").save_path = PATH
	root.add_child(_main)
	await process_frame
	await process_frame
	_saves = _main.get_save_manager()
	_economy = _main.get_node("Economy")
	_contracts = _main.get_node("Contracts")
	_contracts.set_source(FixedContractSource.new())
	_docking = _main.get_node("Docking")
	_targeting = _main.get_node("Targeting")
	_ship = _main.get_player_ship()
	_player = _main.get_player_data()
	var earth: InhabitedData = load("res://resources/locations/earth.tres")
	var mars: InhabitedData = load("res://resources/locations/mars.tres")
	var food: Commodity = load("res://resources/commodities/food.tres")
	var popup: EventPopup = _main.get_node("EventPopup")
	var settlement: SettlementScreen = _main.get_node("SettlementScreen")

	# --- New game: no save, nothing written.
	_check(not _saves.has_save(), "a new game has no save")
	var result := _main.load_game()
	_check(not result["ok"] and result["error"] == SaveFile.NO_SAVE, "Continue with no save fails cleanly: %s" % result["error"])
	_check(_player.credits == 500000 and _player.cargo.get_used() == 0, "a failed load leaves the new game alone")
	await process_frame
	await process_frame
	_check(not FileAccess.file_exists(PATH), "a new game writes nothing until a session starts")

	# --- A game with history, in space.
	_economy.buy(_economy.get_market(earth), food, 25)
	_contracts.accept(_contracts.get_available(earth)[0], earth)  # Food to Mars, 40
	_ship.global_position = Vector2(1234, -567)
	_ship.rotation = 1.25
	_ship.velocity = Vector2(120, -40)
	var saved_text := _document_text()
	var credits_saved := _player.credits
	_check(_saves.save_game(), "manual save succeeds")

	# --- Change everything, then load.
	_player.credits = 5
	_economy.get_cargo().remove(&"food", 10)
	_contracts.accept(_contracts.get_available(earth)[1], earth)
	_economy.buy(_economy.get_market(earth), food, 3)
	_ship.global_position = Vector2.ZERO
	_ship.rotation = 0.0
	_ship.velocity = Vector2.ZERO
	var old_npcs := _npc_nodes()
	result = _main.load_game()
	_check(result["ok"], "load succeeds: %s" % result["error"])
	_check(_document_text() == saved_text, "credits, cargo, contracts and markets are exactly as saved")
	_check(_player.credits == credits_saved, "credits restored")
	_check(_ship.global_position.distance_to(Vector2(1234, -567)) < 0.01, "position restored")
	_check(is_equal_approx(_ship.rotation, 1.25) and _ship.velocity.distance_to(Vector2(120, -40)) < 0.01,
			"heading and velocity restored")
	_check(_main.get_docked_target() == null, "in space, as saved")
	_check(_player.cargo.get_used() == 25 + 40, "cargo restored, including contract cargo (%d)" % _player.cargo.get_used())

	# --- NPCs are regenerated, not duplicated.
	var npcs := _npc_nodes()
	# The initial fill is half the cap (5); placing each ship can fail a few times, so allow fewer.
	_check(npcs.size() > 0 and npcs.size() <= 5, "fresh traffic of the usual size (%d)" % npcs.size())
	var none_survived := true
	for npc in old_npcs:
		if is_instance_valid(npc):
			none_survived = false
	_check(none_survived, "the old NPC ships are gone")
	for i in 3:
		_main.load_game()
	_check(_npc_nodes().size() > 0 and _npc_nodes().size() <= 5, "loading again and again does not add NPCs (%d)" % _npc_nodes().size())
	_check(_document_text() == saved_text, "loading repeatedly changes nothing")
	_check(_player.cargo.get_used() == 65 and _contracts.get_active().size() == 1, "...nor duplicates cargo or contracts")

	# --- Docked save: arrive at the destination, deliver, save, reload.
	_dock("Mars")
	await process_frame
	_check(_main.get_docked_target() != null and popup.visible, "docked at Mars, delivery popup shown")
	_check(_contracts.get_completed().size() == 1 and _contracts.get_active().is_empty(), "contract delivered")
	var credits_after_delivery := _player.credits
	_check(credits_after_delivery > credits_saved, "reward paid once")
	var docked_text := _document_text()
	_saves.save_game()
	_player.credits = 1
	popup.clear()
	result = _main.load_game()
	_check(result["ok"], "load of a docked save succeeds: %s" % result["error"])
	_check(_main.get_docked_target() != null and _main.get_docked_target().target_name == "Mars", "restored docked at Mars")
	_check(settlement.visible, "the settlement screen is open again")
	_check(not popup.visible, "no delivery popup after loading")
	_check(_player.credits == credits_after_delivery, "credits restored, reward not paid a second time")
	_check(_document_text() == docked_text, "docked state restored exactly")
	_check(_contracts.get_completed().size() == 1 and _contracts.get_active().is_empty(),
			"completed contract stays completed")
	_check(not _main.get_node("Hud").visible, "the HUD is hidden while docked")
	# --- Loading a save made in space while docked.
	_write_doc_with(func(d: Dictionary) -> void:
		d["player"]["mode"] = "space"
		d["player"].erase("docked_at"))
	result = _main.load_game()
	_check(result["ok"] and _main.get_docked_target() == null and not settlement.visible,
			"loading an in-space save while docked returns to flight")
	_check(_main.get_node("Hud").visible, "the HUD is back")

	# --- Autosave.
	_clean()
	_main.start_session()
	_saves.min_autosave_interval = 0.0  # spacing is tested in save_file_test.gd; keep this test independent of timing
	var writes := [0]
	_saves.saved.connect(func() -> void: writes[0] += 1)
	var failures: Array[String] = []
	_saves.save_failed.connect(func(reason: String) -> void: failures.append(reason))
	_contracts.accept(_contracts.get_available(earth)[0] if not _contracts.get_available(earth).is_empty()
			else _contracts.get_available(mars)[0], earth if not _contracts.get_available(earth).is_empty() else mars)
	_economy.buy(_economy.get_market(earth), food, 2)
	await process_frame
	await process_frame
	_check(writes[0] == 1 and FileAccess.file_exists(PATH), "accepting a contract and trading in one moment autosaves once (%d, failures: %s)" % [writes[0], failures])
	var autosaved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_check(autosaved["economy"]["credits"] == _player.credits, "the autosave holds the current credits")
	_check(autosaved["contracts"]["active"].size() == _contracts.get_active().size(), "...and the current contracts")

	# --- Damaged file: the game carries on unchanged.
	_saves.autosave_enabled = false
	var before_text := _document_text()
	_write(PATH, '{"version": 1, "economy": {"cred')
	_write(PATH + ".bak", "nonsense")
	result = _main.load_game()
	_check(not result["ok"], "a damaged save is refused: %s" % result["error"])
	_check(_document_text() == before_text, "the running game is untouched by a refused load")
	_write_doc_with(func(d: Dictionary) -> void: d["economy"]["credits"] = -10)
	_check(not _main.load_game()["ok"] and _document_text() == before_text, "an invalid save is refused before anything changes")
	_write_doc_with(func(d: Dictionary) -> void: d["version"] = 99)
	result = _main.load_game()
	_check(not result["ok"] and "newer version" in result["error"], "a newer save is refused: %s" % result["error"])

	# --- Fleet: ships, names, upgrades and the active ship survive a load.
	var upgrade: UpgradeDefinition = load("res://resources/upgrades/engine_1.tres")
	var ships: ShipManager = _main.get_node("Ships")
	var first_ship := _player.fleet.get_active()
	first_ship.upgrades.append(upgrade)
	ships.rename(first_ship.id, "Old Faithful")
	var kept := _player.fleet.create_ship(load("res://resources/ships/shuttle_stats.tres"), "Spare")
	kept.set_flag(OwnedShip.FLAG_PREVIOUS_SHIP, true)
	_check(_saves.save_game(), "save with two ships")
	var first_id := first_ship.id
	_player.fleet.clear()
	_player.fleet.create_ship(load("res://resources/ships/interceptor_stats.tres"), "Impostor")
	_player.fleet.active_id = &"ship_1"
	_check(_main.load_game()["ok"], "load the fleet")
	_check(_player.fleet.ships.size() == 2 and _player.fleet.get_active().id == first_id, "both ships and the active ship restored")
	_check(_player.fleet.get_active().ship_name == "Old Faithful" and _player.fleet.get_active().upgrades.size() == 1, "name and upgrades restored")
	_check(_player.fleet.get_ship(kept.id) != null and _player.fleet.get_ship(kept.id).is_previous(), "kept ship and its PREVIOUS_SHIP flag restored")
	_check(_ship.stats.max_speed > _player.fleet.get_active().model.max_speed, "the flying ship uses the upgraded specs")
	_check(_player.cargo.capacity == _player.fleet.get_active().get_specs().cargo_capacity, "hold capacity follows the active ship")
	_write_doc_with(func(d: Dictionary) -> void: d["fleet"]["active"] = "ship_99")
	_check(not _main.load_game()["ok"], "a fleet whose active ship is missing is refused")
	_write_doc_with(func(d: Dictionary) -> void: d["fleet"]["ships"][0]["name"] = "")
	_check(not _main.load_game()["ok"], "an empty ship name is refused")
	_write_doc_with(func(d: Dictionary) -> void: d["fleet"]["ships"][0]["upgrades"] = ["engine_2"])
	_check(not _main.load_game()["ok"], "a tier without the tier below it is refused")
	_write_doc_with(func(d: Dictionary) -> void: d["fleet"]["ships"][0]["model"] = "battleship")
	_check(not _main.load_game()["ok"], "an unknown ship model is refused")
	_write_doc_with(func(d: Dictionary) -> void: d["fleet"]["next_id"] = 1)
	_check(not _main.load_game()["ok"], "a next_id that would reuse an id is refused")

	# --- A version 1 save (no fleet, ship named in the player section) still loads.
	_write_doc_with(func(d: Dictionary) -> void:
		d["version"] = 1
		d.erase("fleet")
		d["player"]["ship"] = "shuttle")
	result = _main.load_game()
	_check(result["ok"], "a version 1 save loads: %s" % result["error"])
	_check(_player.fleet.ships.size() == 1 and _player.fleet.get_active().model.id == &"shuttle" and _player.fleet.get_active().ship_name == "Shuttle", "it becomes a fleet of one shuttle")
	_check(_player.cargo.capacity == 20, "and the hold takes the shuttle's size (cargo above it stays, nothing is lost)")

	# --- Star system: saved id decides which system is loaded.
	var second := _make_second_system()
	var galaxy := Galaxy.new()
	for scene in [load("res://scenes/systems/sol_system.tscn"), second]:
		var entry := GalaxySystem.new()
		entry.scene = scene
		galaxy.systems.append(entry)
	galaxy.systems[1].map_position = Vector2(100, 0)
	var link := SystemLink.new()
	link.a = &"sol"
	link.b = &"quiet"
	galaxy.links.append(link)
	_saves.set_registry(ContentRegistry.new(galaxy))
	_write_doc_with(func(d: Dictionary) -> void:
		d["player"]["system"] = "quiet"
		d["player"]["mode"] = "space"
		d["player"]["position"] = [50.0, 60.0])
	var old_system := _main.get_system()
	result = _main.load_game()
	_check(result["ok"], "a save in another system loads: %s" % result["error"])
	_check(_main.get_system().system_id == &"quiet" and _main.get_system() != old_system, "the saved star system is loaded")
	_check(not is_instance_valid(old_system) or old_system.is_queued_for_deletion(), "the old system is gone")
	_check(_ship.global_position.distance_to(Vector2(50, 60)) < 0.01, "position restored in the new system")
	_write_doc_with(func(d: Dictionary) -> void: d["player"]["system"] = "sol")
	result = _main.load_game()
	_check(result["ok"] and _main.get_system().system_id == &"sol", "and back to Sol")
	_check(_npc_nodes().size() > 0, "Sol has fresh traffic again")
	var system_count := 0
	for child in _main.get_children():
		if child is StarSystem:
			system_count += 1
	_check(system_count == 1, "only one star system exists after switching")
	_write_doc_with(func(d: Dictionary) -> void: d["player"]["system"] = "andromeda")
	_check(not _main.load_game()["ok"], "a save in an unknown system is refused")

	_clean()
	_main.queue_free()
	await process_frame
	print("")
	if _failures == 0:
		print("SAVE GAME TESTS: all passed")
	else:
		print("SAVE GAME TESTS: %d FAILED" % _failures)
	quit(1 if _failures > 0 else 0)


## The saved form of the whole game (without the time), for comparing states.
func _document_text() -> String:
	var document := _saves.build_document()
	document.erase("saved_at")
	return JSON.stringify(document)


## Rewrites the save file from the current game after letting `change` edit it.
func _write_doc_with(change: Callable) -> void:
	var document := _saves.build_document()
	change.call(document)
	_write(PATH, JSON.stringify(document))


func _npc_nodes() -> Array[Node]:
	return _main.get_system().get_ships_root().get_children()


func _dock(place: String) -> void:
	for node in get_nodes_in_group(Targetable.GROUP):
		if node.target_name == place:
			_ship.global_position = node.global_position + Vector2(0, 100)
			_ship.velocity = Vector2.ZERO
			_targeting.select(node)
	_docking.try_dock()


func _make_second_system() -> PackedScene:
	var system: StarSystem = load("res://scenes/systems/sol_system.tscn").instantiate()  # a valid system (it needs a planet)
	system.system_id = &"quiet"
	system.system_name = "Quiet"
	var packed := PackedScene.new()
	packed.pack(system)
	system.free()
	return packed


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(PATH + suffix)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS  ", description)
	else:
		print("FAIL  ", description)
		_failures += 1
