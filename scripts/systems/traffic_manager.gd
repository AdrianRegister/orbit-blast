class_name TrafficManager
extends Node
## Keeps a star system populated with ambient NPC ships. It is a child of the
## StarSystem scene, so every system gets traffic and the NPCs (children of the
## system's `Ships` node) are freed together with the system; nothing can be
## left behind when systems are switched.
##
## It decides what spawns and where; NpcShip decides how a ship behaves.

const NPC_SCENE := preload("res://scenes/ships/npc_ship.tscn")
## How many random positions are tried before giving up until the next tick.
const SPAWN_ATTEMPTS := 12

@export var config: TrafficConfig

var _system: StarSystem
var _player: Node2D
var _locations: Array[InhabitedNode] = []
var _running: bool = false
var _spawn_timer: float = 0.0
## From the system's traffic_rate.
var _rate: float = 1.0
## Directions of the links to neighbouring systems, as unit vectors. Ships
## arrive from and leave towards these. Empty = no inter-system traffic.
var _exit_bearings: Array[Vector2] = []


func _ready() -> void:
	set_process(false)


## Tells the manager which directions lead to other systems. Call before start().
func set_exit_bearings(bearings: Array[Vector2]) -> void:
	_exit_bearings = bearings


## Most ships this system holds at once: the config's cap scaled by the
## system's traffic_rate (at least one when there is any traffic).
func get_max_ships() -> int:
	if _rate <= 0.0:
		return 0
	return maxi(1, roundi(config.max_ships * _rate))


## Seconds between arrivals: the config's interval divided by the traffic_rate.
func get_spawn_interval() -> float:
	return config.spawn_interval / _rate if _rate > 0.0 else INF


## Starts the traffic for this system. `player` is kept clear of spawns.
## Called by Main for the current system (and by whatever swaps systems later).
func start(system: StarSystem, player: Node2D) -> void:
	_system = system
	_player = player
	_rate = system.traffic_rate
	_locations.assign(system.get_inhabited_nodes().filter(
			func(node: InhabitedNode) -> bool: return node.data != null and node.data.is_dockable()))
	if config == null:
		push_warning("%s: no TrafficConfig assigned; no traffic." % system.name)
		return
	var problems := config.validate()
	if not problems.is_empty():
		for problem in problems:
			push_error("%s traffic: %s" % [system.name, problem])
		return
	if _locations.size() < 2 or _rate <= 0.0:
		return  # Ships need somewhere to go from and to, and a system can have no traffic.

	_running = true
	for i in roundi(get_max_ships() * config.initial_fill_fraction):
		_spawn_in_flight()
	set_process(true)


func get_ship_count() -> int:
	var count := 0
	for ship in _system.get_ships_root().get_children():
		if not ship.is_queued_for_deletion():
			count += 1
	return count


## Advances the spawn timer. Public so tests can step time directly.
func tick(delta: float) -> void:
	if not _running:
		return
	_spawn_timer += delta
	if _spawn_timer >= get_spawn_interval():
		_spawn_timer = 0.0
		if get_ship_count() < get_max_ships():
			# With links to other systems, new ships jump in from them; a system
			# with none has residents who undock from its locations instead.
			if _exit_bearings.is_empty():
				_spawn_at_location()
			else:
				_spawn_arrival()


func _process(delta: float) -> void:
	tick(delta)


## A ship that already left a location and is on its way somewhere.
func _spawn_in_flight() -> bool:
	if get_ship_count() >= get_max_ships():
		return false
	for attempt in SPAWN_ATTEMPTS:
		var origin: InhabitedNode = _locations.pick_random()
		var destination: InhabitedNode = _random_other(origin)
		var position: Vector2 = origin.global_position.lerp(
				destination.global_position, randf_range(0.2, 0.8))
		if _is_clear(position, null):
			var ship := _create_ship(origin, destination, position)
			var type_speed: float = ship.ship_type.stats.max_speed
			ship.velocity = (destination.global_position - position).normalized() * type_speed * 0.8
			return true
	return false


## A ship that has just undocked from a random location.
func _spawn_at_location() -> bool:
	for attempt in SPAWN_ATTEMPTS:
		var origin: InhabitedNode = _locations.pick_random()
		var destination: InhabitedNode = _random_other(origin)
		var heading: Vector2 = (destination.global_position - origin.global_position).normalized()
		heading = heading.rotated(randf_range(-0.8, 0.8))
		var position: Vector2 = origin.global_position \
				+ heading * (origin.get_dock_range() + config.departure_clearance)
		if _is_clear(position, origin):
			_create_ship(origin, destination, position)
			return true
	return false


## A ship that has just jumped in at the edge of the system, from the direction
## of one of its links, heading for one of the locations.
func _spawn_arrival() -> bool:
	for attempt in SPAWN_ATTEMPTS:
		var bearing: Vector2 = _exit_bearings.pick_random()
		var position: Vector2 = _system.global_position + bearing * _system.jump_radius
		var destination: InhabitedNode = _locations.pick_random()
		if _is_clear(position, null):
			var ship := _create_ship(destination, destination, position)
			ship.begin_arrival((destination.global_position - position).normalized())
			return true
	return false


func _create_ship(origin: InhabitedNode, destination: InhabitedNode, position: Vector2) -> NpcShip:
	var ship: NpcShip = NPC_SCENE.instantiate()
	var faction: String = origin.data.faction_name if origin.data != null else ""
	ship.setup(_pick_ship_type(), config, _locations, faction, destination, _player)
	ship.configure_jumping(_system.global_position, _system.jump_radius, _exit_bearings)
	_system.get_ships_root().add_child(ship)
	ship.global_position = position
	return ship


## A spot is clear if it is away from the player, from every location (beyond
## its docking range) and from other ships. `own_origin` is the location the
## ship is leaving, which it is allowed to be close to.
func _is_clear(position: Vector2, own_origin: InhabitedNode) -> bool:
	if _player != null and position.distance_to(_player.global_position) \
			< config.min_spawn_distance_from_player:
		return false
	for location in _locations:
		if location == own_origin:
			continue
		if position.distance_to(location.global_position) \
				< location.get_dock_range() + config.spawn_clearance:
			return false
	for ship in _system.get_ships_root().get_children():
		if ship.visible and position.distance_to(ship.global_position) < config.ship_spacing:
			return false
	return true


func _random_other(excluding: InhabitedNode) -> InhabitedNode:
	var options: Array[InhabitedNode] = _locations.filter(
			func(node: InhabitedNode) -> bool: return node != excluding)
	return options.pick_random()


## Weighted random choice among the configured ship types.
func _pick_ship_type() -> ShipType:
	var total := 0.0
	for ship_type in config.ship_types:
		total += ship_type.spawn_weight
	if total <= 0.0:
		return config.ship_types.pick_random()
	var roll := randf() * total
	for ship_type in config.ship_types:
		roll -= ship_type.spawn_weight
		if roll <= 0.0:
			return ship_type
	return config.ship_types.back()


## Stops the traffic and removes every NPC ship at once.
func reset() -> void:
	_running = false
	set_process(false)
	_spawn_timer = 0.0
	if _system == null:
		return
	for ship in _system.get_ships_root().get_children():
		_system.get_ships_root().remove_child(ship)
		ship.free()
