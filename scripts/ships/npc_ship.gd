class_name NpcShip
extends Node2D
## An ambient AI ship that flies between inhabited locations of its system.
## It is told what it is (ShipType), where it can go (the system's locations)
## and how to behave (TrafficConfig) by the TrafficManager; it does not look
## anything up itself. The root does not rotate (so the Targetable's selection
## brackets stay upright); only the Visual child turns to the ship's heading.
##
## It flies like the player: thrust only pushes along the facing direction and
## the ship keeps its momentum, so to slow down it must turn retrograde and
## thrust against its velocity.
##
## State machine:
##   ARRIVING    - has just jumped in at the edge of the system, slowing down.
##   TRAVELLING  - flying at the destination at full speed.
##   APPROACHING - braking so it stops inside the destination's docking range.
##   DOCKED      - stopped at the location, still visible and targetable, for a
##                 while; then it flies on to a new destination.
##   DEPARTING   - has finished its visits and is flying out of the system.
##   WARPING     - jumping out: accelerating away until it is gone.
##
## Jumping obeys the player's rule: a ship only starts to warp once it is at
## least the system's jump radius from the system centre.

enum State { TRAVELLING, APPROACHING, DOCKED, ARRIVING, DEPARTING, WARPING }

## Docking needs the ship slower than this (pixels per second).
const DOCK_SPEED := 10.0
## Speed a ship arrives at when it jumps in, and how fast it slows down (px/s, px/s^2).
const ARRIVAL_SPEED := 3000.0
const ARRIVAL_DECELERATION := 3500.0
## Warp-out: acceleration and top speed (px/s^2, px/s), and how far past the
## jump radius it has gone when it is removed.
const WARP_ACCELERATION := 6000.0
const WARP_SPEED := 9000.0
const WARP_EXIT_MARGIN := 1200.0

## The ship aims to stop this fraction of the docking range from the centre,
## i.e. just inside the edge of the range.
const STOP_FRACTION := 0.9
## Braking uses this fraction of the ship's thrust, so it stops smoothly.
const BRAKE_FACTOR := 0.8
## Velocity errors smaller than this (px/s) are ignored when steering.
const STEER_DEADZONE := 8.0
## The ship only thrusts while facing within this angle of the direction it
## needs to accelerate in (radians).
const THRUST_ANGLE := 0.3

signal state_changed(new_state: State)

var ship_type: ShipType
var faction_name: String = ""
var destination: InhabitedNode
var state: State = State.TRAVELLING
var velocity: Vector2 = Vector2.ZERO
var details: NpcShipDetails

var _config: TrafficConfig
var _system_centre: Vector2 = Vector2.ZERO
var _jump_radius: float = 0.0
## Directions out of the system a ship can leave by (towards neighbouring
## systems). Empty = it cannot leave and keeps visiting forever.
var _exit_bearings: Array[Vector2] = []
var _exit_direction: Vector2 = Vector2.ZERO
var _destinations: Array[InhabitedNode] = []
var _player: Node2D
var _visits_left: int = 1
var _dock_time_left: float = 0.0

@onready var _visual: Node2D = $Visual
@onready var _sprite: Sprite2D = $Visual/Sprite2D
@onready var _targetable: Targetable = $Targetable


## Call before adding the ship to the tree.
func setup(type: ShipType, config: TrafficConfig, destinations: Array[InhabitedNode],
		faction: String, first_destination: InhabitedNode, player: Node2D) -> void:
	ship_type = type
	_config = config
	_destinations = destinations
	faction_name = faction
	destination = first_destination
	_player = player
	_visits_left = randi_range(config.visits_range.x, config.visits_range.y)


## Tells the ship where the system's centre is, how far out it may jump, and
## which directions lead to other systems. Call before adding it to the tree.
func configure_jumping(centre: Vector2, jump_radius: float, exit_bearings: Array[Vector2]) -> void:
	_system_centre = centre
	_jump_radius = jump_radius
	_exit_bearings = exit_bearings


## Starts the ship off as one that has just jumped in: moving fast along
## `heading` and slowing down to cruising speed. Call after adding it to the tree.
func begin_arrival(heading: Vector2) -> void:
	_face(heading.angle())
	velocity = heading.normalized() * ARRIVAL_SPEED
	_set_state(State.ARRIVING)


## The player's jump rule applied to this ship: far enough from the system centre.
func can_jump() -> bool:
	return _jump_radius > 0.0 and global_position.distance_to(_system_centre) >= _jump_radius


func _ready() -> void:
	_sprite.texture = ship_type.texture
	_sprite.scale = Vector2(ship_type.sprite_scale, ship_type.sprite_scale)
	details = NpcShipDetails.new()
	details.ship_type_name = ship_type.display_name
	details.faction_name = faction_name
	_targetable.configure(ship_type.display_name, "Ship (%s)" % ship_type.display_name,
			ship_type.get_size(), true, details)
	_set_state(State.TRAVELLING)
	_face(velocity.angle() if velocity.length() > 1.0 else _direction_to_destination().angle())


func _physics_process(delta: float) -> void:
	match state:
		State.TRAVELLING, State.APPROACHING:
			_fly(delta)
		State.DOCKED:
			_dock_time_left -= delta
			if _dock_time_left <= 0.0:
				_finish_visit()
		State.ARRIVING:
			_arrive(delta)
		State.DEPARTING:
			_depart(delta)
		State.WARPING:
			_warp(delta)


## The heading the ship is currently facing, in radians (0 = facing right).
func get_heading() -> float:
	return _visual.rotation


## Flies toward the destination. Works out the velocity it wants (top speed,
## falling to zero at the stopping point), then turns toward the direction it
## needs to accelerate in and thrusts once it faces that way. Braking therefore
## means turning retrograde first, and the braking curve starts early enough to
## leave time for that turn.
func _fly(delta: float) -> void:
	var stats: ShipStats = ship_type.stats
	var to_destination: Vector2 = destination.global_position - global_position
	var distance: float = to_destination.length()
	var dock_range: float = destination.get_dock_range()
	var speed: float = velocity.length()

	var turn_time: float = PI / stats.turn_rate
	var room: float = maxf(distance - dock_range * STOP_FRACTION - speed * turn_time, 0.0)
	var desired_speed: float = minf(stats.max_speed, sqrt(2.0 * stats.thrust * BRAKE_FACTOR * room))
	if desired_speed < stats.max_speed and state == State.TRAVELLING:
		_set_state(State.APPROACHING)

	var error: Vector2 = to_destination.normalized() * desired_speed - velocity
	var needs_thrust: bool = error.length() > STEER_DEADZONE
	if needs_thrust:
		_turn_toward(error.angle(), delta)
	elif speed > DOCK_SPEED:
		_turn_toward(velocity.angle(), delta)
	else:
		_turn_toward(to_destination.angle(), delta)

	if needs_thrust and absf(angle_difference(get_heading(), error.angle())) < THRUST_ANGLE:
		velocity += Vector2.from_angle(get_heading()) * stats.thrust * delta
	velocity = velocity.limit_length(stats.max_speed)
	global_position += velocity * delta

	if distance <= dock_range and velocity.length() < DOCK_SPEED:
		_dock()


## Same rule as the player: inside the docking range and (almost) stopped.
func _dock() -> void:
	velocity = Vector2.ZERO
	_visits_left -= 1
	_dock_time_left = randf_range(_config.dock_time_range.x, _config.dock_time_range.y)
	_set_state(State.DOCKED)


## The visit is over. If it has made all its visits it heads out of the system
## (when there is somewhere to jump to); otherwise it flies on to a different location.
func _finish_visit() -> void:
	if _visits_left <= 0:
		if not _exit_bearings.is_empty():
			_exit_direction = _exit_bearings.pick_random()
			_set_state(State.DEPARTING)
			return
		_visits_left = 1  # nowhere to jump to: keep visiting
	destination = _pick_destination(destination)
	_set_state(State.TRAVELLING)


## Jumped in: slows from arrival speed to its own top speed, then carries on to
## its first destination as normal.
func _arrive(delta: float) -> void:
	var heading := Vector2.from_angle(get_heading())
	var speed := maxf(velocity.length() - ARRIVAL_DECELERATION * delta, ship_type.stats.max_speed)
	velocity = heading * speed
	global_position += velocity * delta
	if speed <= ship_type.stats.max_speed:
		_set_state(State.TRAVELLING)


## Flies out along its exit direction at full speed. Once it is far enough from
## the centre (the same rule as the player) it warps away.
func _depart(delta: float) -> void:
	var stats: ShipStats = ship_type.stats
	var error: Vector2 = _exit_direction * stats.max_speed - velocity
	if error.length() > STEER_DEADZONE:
		_turn_toward(error.angle(), delta)
		if absf(angle_difference(get_heading(), error.angle())) < THRUST_ANGLE:
			velocity += Vector2.from_angle(get_heading()) * stats.thrust * delta
	velocity = velocity.limit_length(stats.max_speed)
	global_position += velocity * delta
	if can_jump():
		_begin_warp()


func _begin_warp() -> void:
	_targetable.set_enabled(false)  # it is gone as far as targeting is concerned
	if velocity.length() > 1.0:
		_face(velocity.angle())
	_set_state(State.WARPING)


## Accelerates hard along its heading and is removed once well clear of the system.
func _warp(delta: float) -> void:
	velocity += Vector2.from_angle(get_heading()) * WARP_ACCELERATION * delta
	velocity = velocity.limit_length(WARP_SPEED)
	global_position += velocity * delta
	if global_position.distance_to(_system_centre) >= _jump_radius + WARP_EXIT_MARGIN:
		queue_free()


func _pick_destination(excluding: InhabitedNode) -> InhabitedNode:
	var options: Array[InhabitedNode] = _destinations.filter(
			func(node: InhabitedNode) -> bool: return node != excluding)
	return options.pick_random() if not options.is_empty() else excluding


func _direction_to_destination() -> Vector2:
	var direction: Vector2 = destination.global_position - global_position
	return direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT


func _set_state(new_state: State) -> void:
	state = new_state
	var place: String = destination.get_object_name()
	match state:
		State.TRAVELLING:
			details.status = "Travelling to %s" % place
		State.APPROACHING:
			details.status = "Approaching %s" % place
		State.DOCKED:
			details.status = "Docked at %s" % place
		State.ARRIVING:
			details.status = "Arriving from another system"
		State.DEPARTING:
			details.status = "Leaving the system"
		State.WARPING:
			details.status = "Jumping out"
	state_changed.emit(state)


func _turn_toward(target_angle: float, delta: float) -> void:
	var step: float = ship_type.stats.turn_rate * delta
	_visual.rotation += clampf(angle_difference(_visual.rotation, target_angle), -step, step)


func _face(angle: float) -> void:
	_visual.rotation = angle
