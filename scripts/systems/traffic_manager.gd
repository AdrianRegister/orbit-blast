class_name TrafficManager
extends Node
## Keeps a star system populated with ambient NPC ships. It is a child of the
## StarSystem scene, so every system gets traffic and the NPCs (children of the
## system's `Ships` node) are freed together with the system; nothing can be
## left behind when systems are switched.
##
## It decides what spawns and where; NpcShip decides how a ship behaves.
##
## Besides single ships it places two kinds of unit (Phase 3.3, step 7):
##   - MILITARY PATROLS: a system that one faction controls keeps that faction's patrols flying
##     a loop around it (how many, and of which recipe, comes from the system's class: see
##     StarSystem.get_patrol_orders). They never dock or leave; a destroyed patrol is replaced
##     after `patrol_respawn_delay`.
##   - CONVOYS: now and then a cargo convoy (TrafficConfig.convoy_recipe) arrives, or is already
##     in flight, instead of a single ship. Its leader has a traffic route like any other ship (it
##     visits places and leaves by a link) and the convoy goes with it.

const NPC_SCENE := preload("res://scenes/ships/npc_ship.tscn")
## How many random positions are tried before giving up until the next tick.
const SPAWN_ATTEMPTS := 12
## Set on every ship of a patrol (see get_ship_count).
const PATROL_META := &"traffic_patrol"

@export var config: TrafficConfig

## Gives every NPC ship a combat id that is never reused during the session, so
## a hostile act against one ship is only ever counted once.
static var _next_combat_id: int = 1


## A combat id no other NPC ship has had this session (also used for ships
## spawned outside the traffic, such as formations).
static func new_combat_id() -> StringName:
	var id := StringName("npc_%d" % _next_combat_id)
	_next_combat_id += 1
	return id

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
## The patrols the system should have (see StarSystem.get_patrol_orders), and for each patrol
## its Formation (null: none now) and the seconds until a missing one is replaced.
var _patrol_order: Dictionary = {}
var _patrols: Array = []
var _patrol_wait: Array[float] = []
var _patrol_active: Array[bool] = []


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
	if _rate <= 0.0:
		return  # a system can have no traffic at all
	# Ships come in from, and go out to, neighbouring systems whatever the system
	# holds: they visit its locations if it has any and otherwise just pass through.
	# A system with no links needs two places to land so its residents have
	# somewhere to fly between.
	if _exit_bearings.is_empty() and _locations.size() < 2:
		return

	_running = true
	_start_patrols()
	for i in roundi(get_max_ships() * config.initial_fill_fraction):
		_spawn_in_flight()
	set_process(true)


## How many ships count against the cap: every one in the system (the patrols' too, unless the
## config says they do not count).
func get_ship_count() -> int:
	var count := 0
	for ship in _system.get_ships_root().get_children():
		if ship.is_queued_for_deletion():
			continue
		if not config.patrols_count_toward_cap and ship.has_meta(PATROL_META):
			continue
		count += 1
	return count


## Advances the spawn timer. Public so tests can step time directly.
func tick(delta: float) -> void:
	if not _running:
		return
	_tick_patrols(delta)
	_spawn_timer += delta
	if _spawn_timer >= get_spawn_interval():
		_spawn_timer = 0.0
		if get_ship_count() < get_max_ships():
			# With links to other systems, new ships jump in from them; a system
			# with none has residents who undock from its locations instead.
			if _exit_bearings.is_empty():
				_spawn_at_location()
			elif not _roll_convoy() or not _spawn_convoy_arrival():
				_spawn_arrival()


func _process(delta: float) -> void:
	tick(delta)


## A ship that is already part way through its journey: between two locations,
## on its way to the only location, or (with none) crossing the system.
func _spawn_in_flight() -> bool:
	if get_ship_count() >= get_max_ships():
		return false
	if _locations.size() < 2:
		return _spawn_in_flight_alone()
	if _roll_convoy() and _spawn_convoy_in_flight():
		return true
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


## Initial traffic for a system with fewer than two locations (it has links).
func _spawn_in_flight_alone() -> bool:
	for attempt in SPAWN_ATTEMPTS:
		var bearing: Vector2 = _exit_bearings.pick_random()
		if _locations.is_empty():
			var position: Vector2 = _system.global_position + bearing.rotated(randf_range(-0.6, 0.6)) * _system.jump_radius * randf_range(0.2, 0.9)
			if _is_clear(position, null):
				var ship := _create_ship(null, null, position)
				ship.begin_departure(bearing)
				return true
		else:
			var destination: InhabitedNode = _locations[0]
			var edge: Vector2 = _system.global_position + bearing * _system.jump_radius
			var position: Vector2 = edge.lerp(destination.global_position, randf_range(0.3, 0.8))
			if _is_clear(position, null):
				var ship := _create_ship(destination, destination, position)
				ship.velocity = (destination.global_position - position).normalized() * ship.ship_type.stats.max_speed * 0.8
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
		# With no location to visit the ship is passing through: aim it at somewhere
		# near the centre.
		var destination: InhabitedNode = _locations.pick_random() if not _locations.is_empty() else null
		var aim: Vector2 = destination.global_position if destination != null \
				else _system.global_position + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 600.0)
		if _is_clear(position, null):
			var ship := _create_ship(destination, destination, position)
			ship.begin_arrival((aim - position).normalized())
			return true
	return false


func _create_ship(origin: InhabitedNode, destination: InhabitedNode, position: Vector2) -> NpcShip:
	var ship: NpcShip = NPC_SCENE.instantiate()
	var faction: String = _system.get_owner_name(origin.data) if origin != null and origin.data != null else ""
	ship.setup(_pick_ship_type(), config, _locations, faction, destination, _player)
	ship.combat_id = new_combat_id()
	ship.faction_id = _system.get_owner_id(origin.data) if origin != null and origin.data != null else &""
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
	return options.pick_random() if not options.is_empty() else excluding


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


# -------------------------------------------------------------------- patrols

## The patrols this system keeps: asks the system (see StarSystem.get_patrol_orders), and puts
## each patrol out at once.
func _start_patrols() -> void:
	_patrols.clear()
	_patrol_wait.clear()
	_patrol_active.clear()
	_patrol_order = _system.get_patrol_orders()
	if _patrol_order.is_empty():
		return
	for index in int(_patrol_order.get("count", 0)):
		_patrols.append(null)
		_patrol_wait.append(0.0)  # (0: put out on the next look)
		_patrol_active.append(false)
	_tick_patrols(0.0)


## How many patrols the system keeps (0 when it has none).
func get_patrol_count() -> int:
	return _patrols.size()


## The patrol formations flying now.
func get_patrols() -> Array[Formation]:
	var result: Array[Formation] = []
	for patrol in _patrols:
		if is_instance_valid(patrol) and not patrol.is_queued_for_deletion():
			result.append(patrol)
	return result


## Puts out the patrols that are missing, once the wait for each is over.
func _tick_patrols(delta: float) -> void:
	for index in _patrols.size():
		if _patrol_active[index]:
			var patrol = _patrols[index]
			if is_instance_valid(patrol) and not patrol.is_queued_for_deletion():
				continue
			_patrol_active[index] = false  # (it was lost: the replacement comes after the delay)
			_patrols[index] = null
			_patrol_wait[index] = config.patrol_respawn_delay
		_patrol_wait[index] -= delta
		if _patrol_wait[index] <= 0.0:
			var unit := _spawn_patrol()
			if unit != null:
				_patrols[index] = unit
				_patrol_active[index] = true
			else:
				_patrol_wait[index] = config.patrol_respawn_delay  # (nothing to make one of: try again later)


## A patrol of the controlling faction, on its loop. Null if one cannot be made (no recipe, or the
## faction has no ships for it).
func _spawn_patrol() -> Formation:
	var recipe: FormationRecipe = _patrol_order.get("recipe")
	if recipe == null:
		recipe = config.patrol_recipe
	if recipe == null:
		return null
	var faction_id: StringName = _patrol_order.get("faction", &"")
	var plan := FleetComposer.compose(recipe, faction_id, FleetComposer.all_ship_types())
	if plan == null:
		return null
	var loop := _patrol_loop()
	for attempt in SPAWN_ATTEMPTS:
		var start := randi() % loop.size()
		if not _is_clear(loop[start], null):
			continue
		var route: Array[Vector2] = []
		for step in loop.size():  # (the loop, beginning with the point after the one it starts at)
			route.append(loop[(start + 1 + step) % loop.size()])
		var heading := (route[0] - loop[start]).angle()
		var unit := FleetSpawner.spawn_plan(_system, _player, config, plan, loop[start], heading, faction_id, 700.0, null, route)
		if unit is Formation:
			_label_ships(unit, str(_patrol_order.get("faction_name", "")), true)
			return unit
		return null
	return null


## The points of a patrol loop: on a circle round the middle of the system, in a random direction.
func _patrol_loop() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var radius := _system.jump_radius * config.patrol_loop_radius_fraction
	var first := randf() * TAU
	var direction := 1.0 if randf() < 0.5 else -1.0
	for index in config.patrol_loop_points:
		var angle := first + direction * TAU * index / config.patrol_loop_points
		points.append(_system.global_position + Vector2.from_angle(angle) * radius)
	return points


## Sets the faction label of every ship of `unit` and, for a patrol, marks them as patrol ships.
func _label_ships(unit: Formation, faction_name: String, patrol: bool) -> void:
	for ship in unit.get_all_ships():
		if not faction_name.is_empty():
			ship.set_faction_label(faction_name)
		if patrol:
			ship.set_meta(PATROL_META, true)


# -------------------------------------------------------------------- convoys

## Whether the next spawn is a convoy: its weight against all the single ships' together.
func _roll_convoy() -> bool:
	if config.convoy_recipe == null or config.convoy_spawn_weight <= 0.0 or _locations.is_empty():
		return false
	var total := 0.0
	for ship_type in config.ship_types:
		total += ship_type.spawn_weight
	return randf() < config.convoy_spawn_weight / (total + config.convoy_spawn_weight)


## A convoy that has just jumped in at the edge of the system, bound for one of its places.
func _spawn_convoy_arrival() -> bool:
	for attempt in SPAWN_ATTEMPTS:
		var bearing: Vector2 = _exit_bearings.pick_random()
		var position: Vector2 = _system.global_position + bearing * _system.jump_radius
		if not _is_clear(position, null):
			continue
		var destination: InhabitedNode = _locations.pick_random()
		var heading := (destination.global_position - position).normalized()
		var unit := _make_convoy(destination, position, heading)
		if unit == null:
			return false  # (no room under the cap, or it cannot be made: a single ship comes instead)
		unit.lead.begin_arrival(heading)
		return true
	return false


## A convoy already on its way between two places.
func _spawn_convoy_in_flight() -> bool:
	for attempt in SPAWN_ATTEMPTS:
		var origin: InhabitedNode = _locations.pick_random()
		var destination: InhabitedNode = _random_other(origin)
		var position: Vector2 = origin.global_position.lerp(destination.global_position, randf_range(0.2, 0.8))
		if not _is_clear(position, null):
			continue
		var heading := (destination.global_position - position).normalized()
		var unit := _make_convoy(destination, position, heading)
		if unit == null:
			return false
		unit.lead.velocity = heading * unit.lead.ship_type.stats.max_speed * 0.8
		return true
	return false


## Makes a convoy heading for `destination`, its leader at `position` facing `heading`. Null if
## its ships do not fit under the cap, or the recipe cannot be built.
func _make_convoy(destination: InhabitedNode, position: Vector2, heading: Vector2) -> Formation:
	var faction_id: StringName = _system.get_owner_id(destination.data) if destination.data != null else &""
	var faction_name: String = _system.get_owner_name(destination.data) if destination.data != null else ""
	var plan := FleetComposer.compose(config.convoy_recipe, faction_id, FleetComposer.all_ship_types())
	if plan == null or get_ship_count() + plan.ship_count() > get_max_ships():
		return null
	var route := func(lead: NpcShip) -> void:
		lead.setup(lead.ship_type, config, _locations, faction_name, destination, _player)
		lead.configure_jumping(_system.global_position, _system.jump_radius, _exit_bearings)
	var none: Array[Vector2] = []
	var unit := FleetSpawner.spawn_plan(_system, _player, config, plan, position, heading.angle(), faction_id, 700.0, null, none, null, null, route)
	if not unit is Formation:
		return null
	_label_ships(unit, faction_name, false)
	return unit


## Stops the traffic and removes every NPC ship at once.
func reset() -> void:
	_running = false
	set_process(false)
	_spawn_timer = 0.0
	_patrols.clear()
	_patrol_wait.clear()
	_patrol_active.clear()
	_patrol_order = {}
	if _system == null:
		return
	if is_instance_valid(_system.get_formations_root()):
		for unit in _system.get_formations_root().get_children():
			unit.queue_free()
	for ship in _system.get_ships_root().get_children():
		_system.get_ships_root().remove_child(ship)
		ship.free()
