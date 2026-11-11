extends Node
## Composition root. Creates the player's data, hands the ship its stats,
## and keeps the camera on the ship.

## Stats for the ship the player starts with. Set in main.tscn.
@export var starting_ship_stats: ShipStats
## Credits the player starts with (development value).
@export var starting_credits: int = 500000
## Flavour text shown when a cargo delivery completes.
@export var delivery_flavour: FlavourPool

var player_data: PlayerData

@onready var _ship: PlayerShip = $PlayerShip
@onready var _camera: Camera2D = $Camera2D
@onready var _system: StarSystem = $StarSystem
@onready var _hud: Hud = $Hud
@onready var _targeting: TargetingManager = $Targeting
@onready var _game_state: GameStateManager = $GameState
@onready var _docking: DockingManager = $Docking
@onready var _settlement: SettlementScreen = $SettlementScreen
@onready var _economy: EconomyManager = $Economy
@onready var _contracts: ContractManager = $Contracts
@onready var _trading: TradingScreen = $TradingScreen
@onready var _missions: MissionComputerScreen = $MissionComputerScreen
@onready var _popup: EventPopup = $EventPopup


func _ready() -> void:
	player_data = PlayerData.new()
	player_data.ship_stats = starting_ship_stats
	player_data.credits = starting_credits
	player_data.cargo.capacity = starting_ship_stats.cargo_capacity
	_ship.stats = player_data.ship_stats
	_hud.track_ship(_ship)
	_system.start_traffic(_ship)
	if not _system.system_name.is_empty():
		_hud.set_system_name(_system.system_name)
	_targeting.target_changed.connect(_hud.set_target)

	_economy.credits_changed.connect(_hud.set_credits)
	_economy.cargo_changed.connect(_update_cargo_hud)
	_economy.setup(player_data)
	_update_cargo_hud()
	_contracts.setup(_economy)
	_contracts.set_system_lookup(_get_system_name_of)
	_missions.setup(_contracts, _economy)
	_contracts.contract_completed.connect(_on_contract_completed)
	_settlement.mission_computer_requested.connect(_on_mission_computer_requested)
	_trading.setup(_economy)
	_settlement.trading_requested.connect(_on_trading_requested)

	_docking.setup(_targeting, _ship, _game_state)
	_docking.docking_denied.connect(_hud.show_target_message)
	_docking.docked.connect(_settlement.open)
	_docking.docked.connect(_on_docked)
	_docking.undocked.connect(_on_undocked)
	_settlement.depart_requested.connect(_docking.undock)
	_game_state.state_changed.connect(_on_game_state_changed)


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
	var location := target.details as InhabitedData
	_settlement.set_mission_computer_enabled(location != null and _contracts.has_contracts_for(location))


## The system a location is in, or "" if it is not in the loaded system. A
## galaxy lookup replaces this once there are several systems.
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


func _on_undocked(_target: Targetable) -> void:
	_trading.close()
	_missions.close()
	_settlement.close()


func _process(_delta: float) -> void:
	_camera.global_position = _ship.global_position
	# The HUD covers the right edge of the window. Shift the view right by half
	# the panel width so the ship sits in the middle of the remaining play area.
	var window_width: float = get_viewport().get_visible_rect().size.x
	_camera.offset.x = window_width * _hud.get_panel_width_fraction() * 0.5
