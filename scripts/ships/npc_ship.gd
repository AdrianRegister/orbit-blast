class_name NpcShip
extends Node2D
## An ambient AI ship that flies between inhabited locations of its system, or,
## in a system with nowhere to dock, passes through it.
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
##   DEPARTING   - has finished its visits (or has none to make) and is flying out
##                 of the system.
##   WARPING     - jumping out: accelerating away until it is gone.
##   WANDERING   - drifting between random points around a centre, never docking
##                 or leaving (the combat sandbox's target ship).
##   IN_FORMATION - a member of a Formation, holding station on its slot (see
##                 Formation). The leader of a formation is not in this state: it
##                 keeps whatever route state it has, flown at the formation's
##                 speed and turn limits, and its members follow it.
##
## Jumping obeys the player's rule: a ship only starts to warp once it is at
## least the system's jump radius from the system centre.

enum State { TRAVELLING, APPROACHING, DOCKED, ARRIVING, DEPARTING, WARPING, WANDERING, IN_FORMATION }

## A wandering ship cruises at this fraction of its top speed, and picks its
## next point once it is within this distance (pixels) of the current one.
const WANDER_SPEED_FRACTION := 0.6
const WANDER_ARRIVE_DISTANCE := 150.0
## A wandering ship picks its next point ahead of it: within this angle (radians)
## of its heading and at least this far away, trying this many times.
const WANDER_CONE := 1.4
const WANDER_MIN_LEG := 300.0
const WANDER_ATTEMPTS := 12
## A ship released from a formation with nowhere to go wanders within this
## distance of the system centre.
const WANDER_FALLBACK_RADIUS := 700.0

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
## Who this ship is in combat: a unique id (so each hostile act is only counted
## once) and the faction it belongs to ("" = none). Set before adding to the tree.
var combat_id: StringName = &""
var faction_id: StringName = &""

## The formation this ship is a member of (it follows that formation's leader),
## or null. A leader is not a member of its own formation.
var formation: Formation
## The formation this ship leads, or null. A ship can be a member of one
## formation and lead another (a squadron's leader inside a battle group).
var led_formation: Formation
## Limits a formation puts on its LEADER so every member can keep up: the top
## speed and turn rate it may use. Infinite (no limit) for everyone else.
var formation_speed_cap: float = INF
var formation_turn_cap: float = INF
## Also limits on a leader: the hardest it may accelerate (px/s^2) and start or
## stop turning (rad/s^2), so members can keep pace (see FormationSteering).
var formation_thrust_cap: float = INF
var formation_turn_accel_cap: float = INF
## The fleet this ship belongs to (a flagship, a second capital ship or a battle
## group's leader), or null. It supplies collision avoidance to a ship that leads
## no formation of its own.
var fleet: WarFleet
## While set, the ship has strayed from its fleet's flagship: it leaves its route
## and flies back to a point `recall_distance` from it (see WarFleet).
var recall_target: NpcShip
var recall_distance: float = 0.0

var _config: TrafficConfig
var _destroyed: bool = false
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
## How fast the ship is turning now (rad/s); only a formation leader's changes
## gradually (see _turn_toward).
var _turn_rate: float = 0.0
var _wander_centre: Vector2 = Vector2.ZERO
var _wander_radius: float = 0.0
var _wander_target: Vector2 = Vector2.ZERO
## A fixed loop of points to fly around instead of picking them at random (see
## begin_patrol), and which one is next.
var _patrol: Array[Vector2] = []
var _patrol_index: int = 0

@onready var _visual: Node2D = $Visual
@onready var _sprite: Sprite2D = $Visual/Sprite2D
@onready var _targetable: Targetable = $Targetable
@onready var _combatant: Combatant = $Combatant


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


## Starts the ship off as one that is simply leaving: flying out along
## `direction` at most of its top speed. Used for ships that pass through a system
## with no locations, and when such a system is first filled.
func begin_departure(direction: Vector2) -> void:
	_exit_direction = direction.normalized()
	_face(_exit_direction.angle())
	velocity = _exit_direction * effective_max_speed() * 0.8
	_set_state(State.DEPARTING)


## Starts the ship off as one that has just jumped in: moving fast along
## `heading` and slowing down to cruising speed. Call after adding it to the tree.
func begin_arrival(heading: Vector2) -> void:
	_face(heading.angle())
	velocity = heading.normalized() * ARRIVAL_SPEED
	_set_state(State.ARRIVING)


## Makes the ship drift aimlessly between random points within `radius` of
## `centre`, forever: it never docks, jumps or leaves. Call before adding it to
## the tree.
func begin_wandering(centre: Vector2, radius: float) -> void:
	_wander_centre = centre
	_wander_radius = radius
	_wander_target = _pick_wander_point()
	state = State.WANDERING


## Makes the ship fly around the given points in order, forever (a fixed route, so
## tests and demos are repeatable). Like wandering, it never docks or leaves.
## Call before adding it to the tree.
func begin_patrol(points: Array[Vector2]) -> void:
	_patrol = points.duplicate()
	_patrol_index = 0
	_wander_target = _patrol[0]
	state = State.WANDERING


## The player's jump rule applied to this ship: far enough from the system centre.
func can_jump() -> bool:
	return _jump_radius > 0.0 and global_position.distance_to(_system_centre) >= _jump_radius


# ------------------------------------------------------------- formations

## Becomes a member of `new_formation`: from now on the ship holds station on its
## slot instead of flying a route. Call before adding the ship to the tree (the
## formation's own setup comes after, once its ships exist).
func join_formation(new_formation: Formation) -> void:
	formation = new_formation
	state = State.IN_FORMATION


## Stops following a formation and carries on alone: a ship with places to go
## picks a destination; one with none leaves the system if it can, and otherwise
## wanders around the centre.
func leave_formation() -> void:
	formation = null
	if not _targetable.is_enabled() and state != State.WARPING:
		_targetable.set_enabled(true)
	if not _destinations.is_empty():
		destination = _pick_destination(destination)
		_set_state(State.TRAVELLING)
	elif not _exit_bearings.is_empty():
		_exit_direction = _pick_exit()
		_set_state(State.DEPARTING)
	else:
		begin_wandering(_system_centre, WANDER_FALLBACK_RADIUS)
		_set_state(State.WANDERING)


## Takes over `other`'s journey: its destination, visits, exit and wandering
## plan, and its state (a ship that was docked carries on to the same place and
## docks again). Used when a formation's leader is lost and a member takes the
## lead.
func take_over_route_from(other: NpcShip) -> void:
	destination = other.destination
	_visits_left = other._visits_left
	_dock_time_left = other._dock_time_left
	_exit_direction = other._exit_direction
	_exit_bearings = other._exit_bearings
	_destinations = other._destinations
	_wander_centre = other._wander_centre
	_wander_radius = other._wander_radius
	_wander_target = other._wander_target
	_patrol = other._patrol
	_patrol_index = other._patrol_index
	formation = null
	if other.state == State.DOCKED:
		_visits_left += 1  # it docks (and is counted) again when it gets there
		_set_state(State.TRAVELLING)
	else:
		_set_state(other.state)


## The top speed this ship may use now: its own, or the formation's cruise speed
## when it leads one.
func effective_max_speed() -> float:
	return minf(ship_type.stats.max_speed, formation_speed_cap)


## The turn rate this ship may use now (the formation's limit when it leads one).
func effective_turn_rate() -> float:
	return minf(ship_type.stats.turn_rate, formation_turn_cap)


## The thrust this ship may use now (the formation's limit when it leads one).
func effective_thrust() -> float:
	return minf(ship_type.stats.thrust, formation_thrust_cap)


func stats_max_speed() -> float:
	return ship_type.stats.max_speed


## Removes every limit a formation put on this ship as its leader.
func clear_formation_limits() -> void:
	formation_speed_cap = INF
	formation_turn_cap = INF
	formation_thrust_cap = INF
	formation_turn_accel_cap = INF


## Radius of the area that is hit by shots: how much room the ship takes.
func get_hit_radius() -> float:
	return ship_type.stats.get_hit_radius()


func get_combatant() -> Combatant:
	return _combatant


## Turns the ship to face `angle` at once (radians, 0 = facing right).
func set_heading(angle: float) -> void:
	_face(angle)


## What unit this ship belongs to, for combat reports and the HUD: {"kind", "id",
## "fleet_id"} (empty values for a ship in no formation). The unit is the formation
## the ship leads, or else the one it is a member of.
func get_organisation() -> Dictionary:
	var unit: Formation = led_formation if led_formation != null else formation
	if unit != null and not is_instance_valid(unit):
		unit = null
	var group: WarFleet = fleet if fleet != null and is_instance_valid(fleet) else null
	if group == null and unit != null:
		group = unit.get_fleet()
	return {
		"kind": Formation.kind_name(unit.kind) if unit != null else &"",
		"id": unit.id if unit != null else &"",
		"fleet_id": group.id if group != null else &"",
	}


## Updates the FORMATION and ROLE rows the HUD shows for this ship.
func refresh_organisation() -> void:
	if details == null:
		return
	var unit: Formation = led_formation if led_formation != null else formation
	if unit == null or not is_instance_valid(unit) or unit.shape == null:
		details.formation_text = ""
		details.role_text = ""
		return
	var slot := unit.get_slot(self)
	var kind_text := str(Formation.kind_name(unit.kind)).replace("_", " ")
	var place := "%s %s" % [unit.shape.display_name, kind_text]
	if slot != null:
		place += ", %d of %d" % [slot.index + 1, unit.size()]
	details.formation_text = place
	if fleet != null and is_instance_valid(fleet) and fleet.flagship == self:
		details.role_text = "Fleet flagship"
	elif led_formation != null:
		details.role_text = "%s leader" % kind_text.capitalize()
	else:
		details.role_text = "Member"


## Rewrites the status line the HUD shows (after the state's own text changed,
## for example a formation got a new shape).
func refresh_status() -> void:
	if details != null:
		_set_state(state)


## Holds station on this ship's slot in its formation: matches the leader's
## velocity plus a correction toward the slot, flown with the ship's own physics
## (turn, then thrust along the heading, at most its top speed). When it has
## nothing to correct it turns to face where the leader faces. While the leader
## jumps in or out, nothing can fly at warp speeds, so the ship is simply locked
## to its slot.
func _follow(delta: float) -> void:
	if formation == null or not is_instance_valid(formation):
		leave_formation()
		return
	if not formation.has_valid_lead():
		return  # the leader is gone this frame: the formation decides what happens (promote, or jump out with it)
	var lead := formation.lead
	var slot_position := formation.get_slot_world_position(self)
	if formation.is_slaved():
		global_position = slot_position
		velocity = lead.velocity
		_face(lead.get_heading())
		if formation.is_warping() and _targetable.is_enabled():
			_targetable.set_enabled(false)
		return

	# A member that leads a formation of its own (a squadron leader in a battle group)
	# flies with its full engines while it holds its place here: its squadron's limits
	# are for the leader's own route, and would stop it correcting a big error (it can
	# only circle its slot). The battle group's limits already allow for its squadrons.
	var free := led_formation != null
	var top_speed := stats_max_speed() if free else effective_max_speed()
	var thrust: float = ship_type.stats.thrust if free else effective_thrust()
	var tuning := formation.tuning
	var error: Vector2 = slot_position - global_position
	var catching_up: bool = error.length() > formation.catch_up_distance
	var desired := FormationSteering.follow_velocity(error, formation.get_slot_velocity(self), top_speed, catching_up, tuning)
	desired = (desired + formation.get_avoidance(self)).limit_length(top_speed)
	var correction: Vector2 = desired - velocity
	if correction.length() <= tuning.trim_range:
		# A small correction: station-keeping thrusters cancel it in any direction (a
		# ship cannot brake with forward-only engines without turning round), and
		# the nose stays with the leader.
		velocity += FormationSteering.trim_delta(correction, tuning.trim_thrust_fraction * thrust, delta)
		_turn_toward(formation.get_frame_heading(), delta, free)
	else:
		# A big one: main engines. Turn toward it, thrust once facing it.
		_turn_toward(correction.angle(), delta, free)
		if absf(angle_difference(get_heading(), correction.angle())) < THRUST_ANGLE:
			velocity += Vector2.from_angle(get_heading()) * thrust * delta
	velocity = velocity.limit_length(top_speed)
	global_position += velocity * delta


## Steering away from other ships and planets, for a ship that leads a formation
## (its members already get this in _follow). Zero for everyone else, so ordinary
## traffic flies exactly as before.
func _avoidance() -> Vector2:
	if led_formation != null:
		return led_formation.get_avoidance(self)
	if fleet != null and is_instance_valid(fleet):
		return fleet.get_avoidance(self)
	return Vector2.ZERO


## Flies back toward the fleet's flagship (it strayed beyond the fleet's leash):
## heads for a point `recall_distance` from it on this ship's side, matching its
## velocity, at up to this ship's own speed limit.
func _recall(delta: float) -> void:
	var away: Vector2 = global_position - recall_target.global_position
	var side := away.normalized() if away.length() > 1.0 else Vector2.RIGHT
	var aim: Vector2 = recall_target.global_position + side * recall_distance
	var top_speed := effective_max_speed()
	var wanted: Vector2 = recall_target.velocity + (aim - global_position).limit_length(top_speed)
	_cruise_toward(wanted, minf(wanted.length(), top_speed), delta)


func _ready() -> void:
	_sprite.texture = ship_type.texture
	_sprite.scale = Vector2.ONE * ship_type.sprite_scale
	details = NpcShipDetails.new()
	details.ship_type_name = ship_type.display_name
	details.faction_name = faction_name
	_targetable.configure(ship_type.display_name, "Ship (%s)" % ship_type.display_name,
			ship_type.get_size(), true, details)
	# Combat: NPCs carry their model's default weapons and the full damage model.
	# They do not fire yet; combat AI will drive the same Combatant later.
	_combatant.combat_id = combat_id
	_combatant.faction_id = faction_id
	_combatant.setup(ship_type.stats, ShipSpecs.compute(ship_type.stats), ship_type.stats.default_loadout,
			null, get_heading, func() -> Vector2: return velocity)
	_combatant.destroyed.connect(_on_destroyed)
	if state == State.WANDERING or state == State.IN_FORMATION:
		_set_state(state)
	elif state != State.DEPARTING and state != State.ARRIVING:
		_set_state(State.TRAVELLING)
	_face(velocity.angle() if velocity.length() > 1.0 else _direction_to_destination().angle())


## Hull reached zero: the ship is gone as far as the game is concerned. (The
## explosion and the reports are the CombatManager's job.)
func _on_destroyed(_victim: Combatant, _attacker: Combatant) -> void:
	if _destroyed:
		return
	_destroyed = true
	_targetable.set_enabled(false)  # clears the player's selection
	set_physics_process(false)
	visible = false
	queue_free()


func _physics_process(delta: float) -> void:
	if recall_target != null:
		if not is_instance_valid(recall_target) or recall_target.is_queued_for_deletion():
			recall_target = null
		elif state == State.WANDERING or state == State.TRAVELLING or state == State.APPROACHING:
			_recall(delta)
			return
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
		State.WANDERING:
			_wander(delta)
		State.IN_FORMATION:
			_follow(delta)


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
	var top_speed: float = effective_max_speed()
	var to_destination: Vector2 = destination.global_position - global_position
	var distance: float = to_destination.length()
	var dock_range: float = destination.get_dock_range()
	var speed: float = velocity.length()

	var turn_time: float = PI / effective_turn_rate()
	var room: float = maxf(distance - dock_range * STOP_FRACTION - speed * turn_time, 0.0)
	var desired_speed: float = minf(top_speed, sqrt(2.0 * effective_thrust() * BRAKE_FACTOR * room))
	if desired_speed < top_speed and state == State.TRAVELLING:
		_set_state(State.APPROACHING)

	var error: Vector2 = to_destination.normalized() * desired_speed + _avoidance() - velocity
	var needs_thrust: bool = error.length() > STEER_DEADZONE
	if needs_thrust:
		_turn_toward(error.angle(), delta)
	elif speed > DOCK_SPEED:
		_turn_toward(velocity.angle(), delta)
	else:
		_turn_toward(to_destination.angle(), delta)

	if needs_thrust and absf(angle_difference(get_heading(), error.angle())) < THRUST_ANGLE:
		velocity += Vector2.from_angle(get_heading()) * effective_thrust() * delta
	velocity = velocity.limit_length(top_speed)
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
	# With only one place to land there is nowhere else to fly to, so a ship that
	# can leave does so after its visit.
	if _visits_left <= 0 or (_destinations.size() < 2 and not _exit_bearings.is_empty()):
		if not _exit_bearings.is_empty():
			_exit_direction = _pick_exit()
			_set_state(State.DEPARTING)
			return
		_visits_left = 1  # nowhere to jump to: keep visiting
	destination = _pick_destination(destination)
	_set_state(State.TRAVELLING)


## Jumped in: slows from arrival speed to its own top speed, then carries on to
## its first destination as normal.
func _arrive(delta: float) -> void:
	var heading := Vector2.from_angle(get_heading())
	var top_speed := effective_max_speed()
	var speed := maxf(velocity.length() - ARRIVAL_DECELERATION * delta, top_speed)
	velocity = heading * speed
	global_position += velocity * delta
	if speed <= top_speed:
		if destination == null:
			# Nowhere to land here: carry on across the system and leave.
			_exit_direction = _pick_exit()
			_set_state(State.DEPARTING)
		else:
			_set_state(State.TRAVELLING)


## Flies out along its exit direction at full speed. Once it is far enough from
## the centre (the same rule as the player) it warps away.
func _depart(delta: float) -> void:
	var stats: ShipStats = ship_type.stats
	var top_speed := effective_max_speed()
	var error: Vector2 = _exit_direction * top_speed + _avoidance() - velocity
	if error.length() > STEER_DEADZONE:
		_turn_toward(error.angle(), delta)
		if absf(angle_difference(get_heading(), error.angle())) < THRUST_ANGLE:
			velocity += Vector2.from_angle(get_heading()) * effective_thrust() * delta
	velocity = velocity.limit_length(top_speed)
	global_position += velocity * delta
	if can_jump():
		_begin_warp()


## Cruises toward the current wander point (turning and thrusting like every
## other ship) and picks a new one on arrival.
func _wander(delta: float) -> void:
	var stats: ShipStats = ship_type.stats
	var top_speed := effective_max_speed()
	var to_target := _wander_target - global_position
	# A formation's leader starts its next leg early enough to round the corner.
	var arrive := WANDER_ARRIVE_DISTANCE
	if led_formation != null:
		arrive = maxf(arrive, velocity.length() / maxf(effective_turn_rate(), 0.1))
	if to_target.length() < arrive:
		_wander_target = _pick_wander_point()
		to_target = _wander_target - global_position
	if led_formation != null:
		_cruise_toward(to_target, top_speed * WANDER_SPEED_FRACTION, delta)
		return
	var error: Vector2 = to_target.normalized() * top_speed * WANDER_SPEED_FRACTION + _avoidance() - velocity
	if error.length() > STEER_DEADZONE:
		_turn_toward(error.angle(), delta)
		if absf(angle_difference(get_heading(), error.angle())) < THRUST_ANGLE:
			velocity += Vector2.from_angle(get_heading()) * effective_thrust() * delta
	velocity = velocity.limit_length(top_speed)
	global_position += velocity * delta


## Steady flight toward a point, for a formation's leader: the nose turns toward
## the point and the ship holds `speed` (thrusting sideways to bend its course
## while the speed limit trims the rest), so it rounds corners smoothly instead
## of braking and turning back on itself, which a formation behind it could not
## follow.
func _cruise_toward(to_target: Vector2, speed: float, delta: float) -> void:
	var aim: Vector2 = to_target.normalized() * speed + _avoidance()
	_turn_toward(aim.angle(), delta)
	# Always thrusting along the heading: below `speed` it speeds the ship up, and at
	# `speed` the limit below trims the length, so the thrust only bends the course.
	velocity += Vector2.from_angle(get_heading()) * effective_thrust() * delta
	velocity = velocity.limit_length(speed)
	global_position += velocity * delta


## A random point in the wander circle, preferring one the ship can head for
## without turning round: ahead of it (within WANDER_CONE) and not too close, so
## it makes smooth legs instead of U-turns (a formation behind it cannot follow
## a ship that reverses on the spot).
func _pick_wander_point() -> Vector2:
	if not _patrol.is_empty():
		_patrol_index = (_patrol_index + 1) % _patrol.size()
		return _patrol[_patrol_index]
	var heading := get_heading() if is_node_ready() else 0.0
	var candidate := _wander_centre
	for attempt in WANDER_ATTEMPTS:
		candidate = _wander_centre + Vector2.from_angle(randf() * TAU) * _wander_radius * sqrt(randf())
		var leg := candidate - global_position
		if leg.length() >= WANDER_MIN_LEG and absf(angle_difference(heading, leg.angle())) <= WANDER_CONE:
			return candidate
	return candidate


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


## A direction out of the system. A ship leaves by a different link from the one
## it is nearest to (the one it came in by), when there is a choice.
func _pick_exit() -> Vector2:
	var from_centre := global_position - _system_centre
	var options: Array[Vector2] = []
	for bearing in _exit_bearings:
		if _exit_bearings.size() == 1 or from_centre.length() < 1.0 or from_centre.normalized().dot(bearing) < 0.9:
			options.append(bearing)
	return options.pick_random() if not options.is_empty() else _exit_bearings.pick_random()


func _pick_destination(excluding: InhabitedNode) -> InhabitedNode:
	var options: Array[InhabitedNode] = _destinations.filter(
			func(node: InhabitedNode) -> bool: return node != excluding)
	return options.pick_random() if not options.is_empty() else excluding


func _direction_to_destination() -> Vector2:
	if destination == null:
		return Vector2.RIGHT
	var direction: Vector2 = destination.global_position - global_position
	return direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT


func _set_state(new_state: State) -> void:
	state = new_state
	var place: String = destination.get_object_name() if destination != null else ""
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
			details.status = "Leaving the system" if destination != null else "Passing through the system"
		State.WARPING:
			details.status = "Jumping out"
		State.WANDERING:
			details.status = "Drifting around the system"
		State.IN_FORMATION:
			var shape_name := formation.shape.display_name if formation != null and formation.shape != null else ""
			details.status = "In formation (%s)" % shape_name if not shape_name.is_empty() else "In formation"
	refresh_organisation()
	state_changed.emit(state)


## Turns toward `target_angle` at up to the effective turn rate. A formation's
## leader also has a limit on how fast its turn rate may change (formation_turn_accel_cap),
## and slows its turn in time to stop on the target without overshooting, so the
## formation's slots swing smoothly. Anyone else turns at the full rate at once.
func _turn_toward(target_angle: float, delta: float, free: bool = false) -> void:
	if free:
		# (No formation limits: the ship's own turn rate.)
		var own_rate: float = ship_type.stats.turn_rate
		_turn_rate = clampf(angle_difference(_visual.rotation, target_angle) / delta, -own_rate, own_rate)
		_visual.rotation += _turn_rate * delta
		return
	var max_rate := effective_turn_rate()
	var difference := angle_difference(_visual.rotation, target_angle)
	var wanted := clampf(difference / delta, -max_rate, max_rate)
	if formation_turn_accel_cap != INF:
		var stopping_rate := sqrt(2.0 * formation_turn_accel_cap * absf(difference))
		wanted = clampf(wanted, -stopping_rate, stopping_rate)
		_turn_rate = move_toward(_turn_rate, wanted, formation_turn_accel_cap * delta)
	else:
		_turn_rate = wanted
	_visual.rotation += _turn_rate * delta


func _face(angle: float) -> void:
	_visual.rotation = angle
