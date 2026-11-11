class_name Main
extends Node
## Composition root. Creates the player's data, hands the ship its stats,
## wires the systems together, and keeps the camera on the ship. It also
## registers every system that has state worth saving with the SaveManager and
## carries out the player part of loading a save.

## Stats for the ship the player starts with. Set in main.tscn.
@export var starting_ship_stats: ShipStats
## Credits the player starts with (development value).
@export var starting_credits: int = 500000
## Flavour text shown when a cargo delivery completes.
@export var delivery_flavour: FlavourPool

var player_data: PlayerData

## True from a new game starting until the player has named the first ship.
var _naming_first_ship: bool = false

@onready var _ship: PlayerShip = $PlayerShip
@onready var _camera: Camera2D = $Camera2D
@onready var _system: StarSystem = $StarSystem
@onready var _hud: Hud = $Hud
@onready var _targeting: TargetingManager = $Targeting
@onready var _game_state: GameStateManager = $GameState
@onready var _docking: DockingManager = $Docking
@onready var _settlement: SettlementScreen = $SettlementScreen
@onready var _economy: EconomyManager = $Economy
@onready var _ships: ShipManager = $Ships
@onready var _contracts: ContractManager = $Contracts
@onready var _trading: TradingScreen = $TradingScreen
@onready var _missions: MissionComputerScreen = $MissionComputerScreen
@onready var _shipyard: ShipyardScreen = $ShipyardScreen
@onready var _outfitters: OutfittersScreen = $OutfittersScreen
@onready var _name_prompt: NamePrompt = $NamePrompt
@onready var _popup: EventPopup = $EventPopup
@onready var _saves: SaveManager = $Save
@onready var _pause: PauseMenu = $PauseMenu


func _ready() -> void:
	player_data = PlayerData.new()
	player_data.credits = starting_credits
	_hud.track_ship(_ship)
	_system.start_traffic(_ship)
	if not _system.system_name.is_empty():
		_hud.set_system_name(_system.system_name)
	_targeting.target_changed.connect(_hud.set_target)

	_economy.credits_changed.connect(_hud.set_credits)
	_economy.cargo_changed.connect(_update_cargo_hud)
	_economy.setup(player_data)
	_ships.setup(_economy, player_data, _get_docked_location)
	_ships.active_ship_changed.connect(_ship.apply_ship)
	_ships.start_new_game(starting_ship_stats)
	_update_cargo_hud()
	_contracts.setup(_economy)
	_contracts.set_system_lookup(_get_system_name_of)
	_missions.setup(_contracts, _economy)
	_contracts.contract_completed.connect(_on_contract_completed)
	_settlement.mission_computer_requested.connect(_on_mission_computer_requested)
	_trading.setup(_economy)
	_shipyard.setup(_ships, _economy)
	_outfitters.setup(_ships, _economy)
	_settlement.shipyard_requested.connect(_on_shipyard_requested)
	_settlement.outfitters_requested.connect(_on_outfitters_requested)
	_shipyard.ship_purchased.connect(func(ship: OwnedShip) -> void: _name_prompt.ask(ship, "NAME YOUR NEW SHIP"))
	_name_prompt.named.connect(_on_ship_named)
	_settlement.trading_requested.connect(_on_trading_requested)

	_docking.setup(_targeting, _ship, _game_state)
	_docking.docking_denied.connect(_hud.show_target_message)
	_docking.docked.connect(_settlement.open)
	_docking.docked.connect(_on_docked)
	_docking.undocked.connect(_on_undocked)
	_settlement.depart_requested.connect(_docking.undock)
	_game_state.state_changed.connect(_on_game_state_changed)

	# Saving. Sections are applied in this order: money and cargo first, then
	# contracts (which are checked against the cargo), then where the player is.
	_saves.register_section(&"economy", _economy)
	_saves.register_section(&"fleet", _ships)
	_saves.register_section(&"contracts", _contracts)
	_saves.register_section(&"player", PlayerSection.new(self))
	_contracts.contracts_changed.connect(_saves.request_autosave)
	_ships.fleet_changed.connect(_saves.request_autosave)
	_economy.transaction_completed.connect(func(_quote: TradeQuote) -> void: _saves.request_autosave())
	_docking.docked.connect(func(_target: Targetable) -> void: _saves.request_autosave())
	_docking.undocked.connect(func(_target: Targetable) -> void: _saves.request_autosave())

	_pause.resume_requested.connect(_close_pause)
	_pause.save_requested.connect(_on_pause_save_requested)
	_pause.load_requested.connect(_on_pause_load_requested)
	_pause.quit_to_menu_requested.connect(_on_quit_to_menu_requested)
	_saves.saved.connect(func() -> void: _pause_status("GAME SAVED", false))
	_saves.save_failed.connect(func(reason: String) -> void: _pause_status("SAVE FAILED: %s" % reason, true))


# ------------------------------------------------------------ save and load

## Called when a game is started from the menu: from now on important actions
## are autosaved. (Not done in _ready, so tools and tests that run the scene
## directly never overwrite the player's save.)
func start_session() -> void:
	_saves.autosave_enabled = true


## Called when a NEW game is started from the menu. The flying is frozen until
## the player has named the starting ship; autosave begins after that.
func start_new_session() -> void:
	_naming_first_ship = true
	get_tree().paused = true
	_name_prompt.ask(_ships.get_active())


func _on_ship_named(ship_id: StringName, ship_name: String) -> void:
	_ships.rename(ship_id, ship_name)
	if _naming_first_ship:
		_naming_first_ship = false
		get_tree().paused = false
		start_session()
		_saves.request_autosave()


## Saves the game now. False if it could not be written.
func save_game() -> bool:
	return _saves.save_game()


## Loads the saved game into the running one. {"ok": bool, "error": String};
## if it fails the game is left as it was.
func load_game() -> Dictionary:
	return _saves.load_game()


func get_save_manager() -> SaveManager:
	return _saves


func get_player_ship() -> PlayerShip:
	return _ship


func get_player_data() -> PlayerData:
	return player_data


func get_system() -> StarSystem:
	return _system


## The location the player is docked at, or null when in open space.
func get_docked_target() -> Targetable:
	return _docking.docked_target


## Puts the player where a save says: closes every screen, switches to the
## saved star system if needed, restores the ship, and re-docks if the save was
## made while docked. NPC traffic is not saved, so it is cleared and started
## again. Called by PlayerSection with validated data.
func restore_player(system_id: StringName, ship_position: Vector2,
		ship_rotation: float, ship_velocity: Vector2, docked_at: StringName,
		registry: ContentRegistry) -> void:
	_trading.close()
	_missions.close()
	_shipyard.close()
	_outfitters.close()
	_name_prompt.visible = false
	_naming_first_ship = false
	_settlement.close()
	_popup.clear()
	_targeting.select(null)
	_docking.reset()
	_game_state.change_state(GameStateManager.State.FLYING)

	if _system.system_id != system_id:
		_swap_system(registry.system_scene(system_id))

	_ship.global_position = ship_position
	_ship.rotation = ship_rotation
	_ship.velocity = ship_velocity
	_system.restart_traffic(_ship)

	if docked_at != &"":
		var target := _find_location_target(docked_at)
		if target == null:
			push_warning("Saved dock location '%s' is not in this system; resuming in space." % docked_at)
		else:
			_docking.restore_docked(target)
			_settlement.open(target)
			_refresh_location_buttons(target)


## The location the player is docked at, or null in open space.
func _get_docked_location() -> InhabitedData:
	var target := _docking.docked_target
	return target.details as InhabitedData if target != null else null


func _swap_system(scene: PackedScene) -> void:
	remove_child(_system)
	_system.free()
	_system = scene.instantiate()
	add_child(_system)
	move_child(_system, 0)  # keep it drawn behind the ship
	if not _system.system_name.is_empty():
		_hud.set_system_name(_system.system_name)


func _find_location_target(location_id: StringName) -> Targetable:
	for node in get_tree().get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable != null and targetable.details is InhabitedData \
				and (targetable.details as InhabitedData).id == location_id and _system.is_ancestor_of(targetable):
			return targetable
	return null


# --------------------------------------------------------------- pause menu

## Esc opens the pause menu when nothing else has used the key (the trading and
## mission screens and the event popup consume it first).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _pause.visible:
		_open_pause()
		get_viewport().set_input_as_handled()


## Freezes the game (the ship keeps its speed) and shows the menu.
func _open_pause() -> void:
	get_tree().paused = true
	_pause.open(_saves.has_save())


func _close_pause() -> void:
	_pause.close()
	get_tree().paused = false


func _pause_status(text: String, is_error: bool) -> void:
	if _pause.visible:
		_pause.show_status(text, is_error)
		_pause.set_load_enabled(_saves.has_save())


func _on_pause_save_requested() -> void:
	_saves.save_game()  # the saved / save_failed signals report the outcome


func _on_pause_load_requested() -> void:
	var result := _saves.load_game()
	if result["ok"]:
		_close_pause()
	else:
		_pause.show_status(result["error"].to_upper(), true)


## Leaves the game for the main menu. Nothing is saved on the way out; the
## game has already been autosaved after every important action.
func _on_quit_to_menu_requested() -> void:
	get_tree().paused = false
	# Loaded here rather than preloaded: the menu preloads this scene.
	get_tree().root.add_child(load("res://scenes/ui/main_menu.tscn").instantiate())
	queue_free()


# --------------------------------------------------------------- game flow

## Decides what each game state means for the systems that depend on it.
func _on_game_state_changed(new_state: GameStateManager.State, _previous: GameStateManager.State) -> void:
	var flying: bool = new_state == GameStateManager.State.FLYING
	_ship.set_flight_enabled(flying)
	_hud.visible = flying
	_targeting.set_process_unhandled_input(flying)


func _update_cargo_hud() -> void:
	var cargo: CargoHold = _economy.get_cargo()
	_hud.set_cargo(cargo.get_used(), cargo.capacity, _economy.get_cargo_lines())


func _on_trading_requested() -> void:
	if _docking.docked_target != null:
		_trading.open(_docking.docked_target)


## Runs after the settlement screen has opened: deliveries are made first, so
## the mission button reflects the contracts as they now stand.
func _on_docked(target: Targetable) -> void:
	_contracts.on_docked(target)
	_refresh_location_buttons(target)


func _refresh_location_buttons(target: Targetable) -> void:
	var location := target.details as InhabitedData
	_settlement.set_mission_computer_enabled(location != null and _contracts.has_contracts_for(location))
	_settlement.set_shipyard_enabled(location != null and not location.shipyard_ships.is_empty())
	_settlement.set_outfitters_enabled(location != null and not location.outfitter_upgrades.is_empty())


## The name of the star system a location is in, or "" if it is not in the
## loaded system. A galaxy lookup replaces this once there are several systems.
func _get_system_name_of(location: InhabitedData) -> String:
	for node in _system.get_inhabited_nodes():
		if node.data == location:
			return _system.system_name
	return ""


## Tells the player about a finished contract in a popup, with a random line of
## flavour text. The reward has already been paid.
func _on_contract_completed(contract: Contract) -> void:
	var place: String = contract.destination.display_name
	var flavour: String = delivery_flavour.pick({"destination": place}) if delivery_flavour != null else ""
	_popup.show_event("DELIVERY COMPLETE", flavour, [
		["CONTRACT", contract.title],
		["CARGO DELIVERED", contract.get_requirement_text()],
		["DELIVERED TO", place],
		["REWARD", "+%s CR" % NumberFormat.with_commas(contract.reward)],
	])


func _on_mission_computer_requested() -> void:
	if _docking.docked_target != null:
		_missions.open(_docking.docked_target)


func _on_shipyard_requested() -> void:
	if _docking.docked_target != null:
		_shipyard.open(_docking.docked_target)


func _on_outfitters_requested() -> void:
	if _docking.docked_target != null:
		_outfitters.open(_docking.docked_target)


func _on_undocked(_target: Targetable) -> void:
	_trading.close()
	_missions.close()
	_shipyard.close()
	_outfitters.close()
	_settlement.close()


func _process(_delta: float) -> void:
	_camera.global_position = _ship.global_position
	# The HUD covers the right edge of the window. Shift the view right by half
	# the panel width so the ship sits in the middle of the remaining play area.
	var window_width: float = get_viewport().get_visible_rect().size.x
	_camera.offset.x = window_width * _hud.get_panel_width_fraction() * 0.5
