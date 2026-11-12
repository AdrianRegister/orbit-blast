class_name Formation
extends Node
## A group of NPC ships holding station around a leader in a FormationShape:
## a squadron, a battle group or a convoy. (Fleets are not formations; see
## WarFleet.) It lives under the star system's `Formations` node, so it is freed
## with the system, and runs before its ships each physics frame.
##
## What it does:
##  - keeps the slots: for its members and shape it asks FormationGeometry for the
##    places and SlotAssigner for who holds which, and rebuilds them whenever a
##    member is lost or the shape changes;
##  - tells each member where its slot is (get_slot_world_position): the leader's
##    position and heading, plus the slot's offset in the leader's frame;
##  - limits the leader's speed and turn rate so every member can keep up;
##  - handles losses: destroyed members are removed and ranks close up; a
##    destroyed leader is replaced by the strongest remaining ship, which takes over
##    its route; heavily damaged members and members that have separated are
##    released to carry on alone; the formation breaks up when too few are left;
##  - supplies collision avoidance (get_avoidance): away from other ships and from
##    planets and stations.
##
## Members do the flying themselves (NpcShip, state IN_FORMATION) with the normal
## ship physics. The leader is an ordinary NPC flying its own route (traffic, or
## wandering) at the formation's cruise speed.
##
## It has no combat behaviour of its own: formation states (following, holding,
## attacking ...) and the flagship deciding them come with the NPC combat AI.

enum Kind { SQUADRON, BATTLE_GROUP, CONVOY }

## A ship left the formation (it was destroyed, released, or released itself).
## `reason` is one of the REASON_ constants.
signal member_lost(ship, reason: StringName)
## The leader was lost and `new_lead` took over.
signal leader_changed(old_lead, new_lead)
signal shape_changed(new_shape: FormationShape)
## The formation has broken up (too few ships, or its leader jumped out).
signal dissolved

const REASON_DESTROYED := &"destroyed"
const REASON_DISABLED := &"disabled"
const REASON_SEPARATED := &"separated"
const REASON_RELEASED := &"released"
## How quickly the measured turn rate follows the real one (1 = instantly).
const ANGULAR_SMOOTHING := 0.3

var kind: Kind = Kind.SQUADRON
var shape: FormationShape
var faction_id: StringName = &""
## The ship every slot is measured from, and the one that follows the route.
var lead: NpcShip
var tuning: FormationTuning

## Distance between neighbouring ships now (the shape's, widened for big ships).
var spacing: float = 0.0
## How close to its slot a ship counts as on station, and how far behind it
## breaks off to catch up (pixels).
var station_tolerance: float = 0.0
var catch_up_distance: float = 0.0

var _system: StarSystem
var _player: Node2D
## Every ship in the formation, the leader first. (Untyped on purpose: a ship
## that has been freed cannot be held in a typed variable, and ships get freed.)
var _ships: Array = []
var _slots: Array[FormationSlot] = []
var _seating: Dictionary = {}  # NpcShip -> FormationSlot
var _previous: Dictionary = {}  # NpcShip -> slot index it held, to keep ranks stable
var _off_station: Dictionary = {}  # NpcShip -> seconds spent beyond the lost distance
var _frame_origin: Vector2 = Vector2.ZERO
var _frame_heading: float = 0.0
## How fast the formation is turning (radians per second), smoothed.
var _angular_velocity: float = 0.0
var _bodies: Array[Dictionary] = []
var _obstacles: Array[Dictionary] = []
## What the leader's turn limit depends on, per member: {"max_speed", "turn_rate",
## "distance"}. Rebuilt with the slots; the limit itself follows the leader's speed.
var _followers: Array = []
var _dirty: bool = true
var _dissolving: bool = false
var _lead_state: NpcShip.State = NpcShip.State.TRAVELLING


# ------------------------------------------------------------------ setup

## Builds the formation from ships that are already in the scene tree. `ships`
## includes `lead_ship`. Every other ship should have called join_formation on
## this node before it entered the tree. `system` and `player` give it what
## avoidance needs to know about; `faction` is who the formation belongs to.
func setup(formation_kind: Kind, formation_shape: FormationShape, ships: Array[NpcShip], lead_ship: NpcShip,
		system: StarSystem, player: Node2D, formation_tuning: FormationTuning = null, faction: StringName = &"") -> void:
	kind = formation_kind
	shape = formation_shape
	faction_id = faction
	tuning = formation_tuning if formation_tuning != null else FormationTuning.shared()
	_system = system
	_player = player
	lead = lead_ship
	process_physics_priority = -10  # the slots are updated before the ships move
	_ships = []  # (untyped: duplicate() of a typed array would stay typed)
	_ships.append_array(ships)
	if not _ships.has(lead):
		_ships.push_front(lead)
	lead.formation = null
	lead.led_formation = self
	_lead_state = lead.state
	for ship in _ships:
		if ship != lead:
			ship.formation = self
		ship.get_combatant().destroyed.connect(_on_combatant_destroyed.bind(ship))
	for node in system.get_inhabited_nodes():
		_obstacles.append({"node": node, "position": node.global_position, "radius": _body_radius(node)})
	_rebuild()
	_frame_origin = lead.global_position
	_frame_heading = lead.get_heading()


## Snaps the whole formation into its shape with the leader at `origin` facing
## `heading`: used when it is created. Everyone stops, then moves with the leader.
func place_at(origin: Vector2, heading: float) -> void:
	_frame_origin = origin
	_frame_heading = heading
	for ship in _ships:
		ship.global_position = get_slot_world_position(ship)
		ship.set_heading(heading)
		ship.velocity = Vector2.ZERO


# ------------------------------------------------------------------ queries

func get_ships() -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in _ships:
		if is_instance_valid(ship):
			result.append(ship)
	return result


## The members, not counting the leader.
func get_members() -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in _ships:
		if ship != lead:
			result.append(ship)
	return result


func size() -> int:
	return _ships.size()


func has_valid_lead() -> bool:
	return lead != null and is_instance_valid(lead) and not lead.is_queued_for_deletion()


func get_slot(ship: NpcShip) -> FormationSlot:
	return _seating.get(ship)


## Where `ship`'s slot is in the world right now. A ship with no slot gets its
## own position (so it simply stays put).
func get_slot_world_position(ship: NpcShip) -> Vector2:
	var slot: FormationSlot = _seating.get(ship)
	if slot == null:
		return ship.global_position
	return _frame_origin + slot.offset.rotated(_frame_heading)


## How fast `ship`'s slot is moving: the leader's velocity plus the swing of the
## slot as the formation turns. Members fly to match it.
func get_slot_velocity(ship: NpcShip) -> Vector2:
	var slot: FormationSlot = _seating.get(ship)
	if slot == null or not has_valid_lead():
		return ship.velocity
	return FormationSteering.slot_velocity(lead.velocity, slot.offset.rotated(_frame_heading), _angular_velocity)


## The direction the slots are laid out along: the leader's direction of travel
## once it is moving, its nose when it is nearly stopped (blended between).
func get_frame_heading() -> float:
	return _frame_heading


func _travel_heading() -> float:
	var speed := lead.velocity.length()
	var blend := clampf((speed - tuning.travel_heading_speed) / maxf(tuning.travel_heading_blend, 0.001), 0.0, 1.0)
	return lerp_angle(lead.get_heading(), lead.velocity.angle(), blend)


## How far `ship` is from its slot (pixels).
func get_slot_error(ship: NpcShip) -> float:
	return ship.global_position.distance_to(get_slot_world_position(ship))


func is_on_station(ship: NpcShip) -> bool:
	return get_slot_error(ship) <= station_tolerance


## True while the leader is jumping in or out: ships move too fast to hold
## station, so members are simply locked to their slots.
func is_slaved() -> bool:
	return has_valid_lead() and (lead.state == NpcShip.State.ARRIVING or lead.state == NpcShip.State.WARPING)


## The strongest ship in the formation (the future flagship, the decision-maker
## once NPC combat AI exists). For squadrons and battle groups it is the leader.
func get_flagship() -> NpcShip:
	var best: NpcShip = null
	var best_rating := -INF
	for ship in _ships:
		var rating: float = CombatRating.of(ship.ship_type.stats)
		if rating > best_rating:
			best_rating = rating
			best = ship
	return best


## The formation's strength: the sum of its ships' ratings.
func get_rating() -> float:
	var total := 0.0
	for ship in _ships:
		total += CombatRating.of(ship.ship_type.stats)
	return total


## How far the formation reaches from its leader, counting the ships' own sizes:
## the room it needs when it is itself a member of a larger formation.
func get_extent() -> float:
	var reach := 0.0
	for slot in _slots:
		reach = maxf(reach, slot.offset.length())
	var biggest := 0.0
	for ship in _ships:
		biggest = maxf(biggest, ship.get_hit_radius())
	return reach + biggest


# ---------------------------------------------------------------- changes

## Changes the shape. The members fly to their new slots with the normal ship
## physics, so the formation re-forms smoothly.
func set_shape(new_shape: FormationShape) -> void:
	if new_shape == null or new_shape == shape:
		return
	shape = new_shape
	_dirty = true
	shape_changed.emit(shape)
	for ship in _ships:
		if ship.state == NpcShip.State.IN_FORMATION:
			ship.refresh_status()


## Takes a ship out of the formation and sends it on alone. (The reasons are
## recorded by `member_lost`.)
func release(ship: NpcShip, reason: StringName = REASON_RELEASED) -> void:
	if not _ships.has(ship) or ship == lead:
		return
	_remove_ship(ship, reason)
	if is_instance_valid(ship) and not ship.is_queued_for_deletion():
		ship.leave_formation()


# ----------------------------------------------------------------- avoidance

## A push (a velocity) that keeps `ship` clear of other ships (including the
## player) and of planets and stations. Used by members and by the leader.
func get_avoidance(ship: NpcShip) -> Vector2:
	var max_speed := ship.ship_type.stats.max_speed
	var radius := ship.get_hit_radius()
	var push := FormationSteering.separation(ship, ship.global_position, radius, _bodies,
			tuning.separation_margin, max_speed, tuning.separation_strength)
	var obstacles: Array[Dictionary] = []
	for obstacle in _obstacles:
		# A formation may gather at the place its leader is going to.
		if has_valid_lead() and obstacle["node"] == lead.destination:
			continue
		obstacles.append(obstacle)
	return push + FormationSteering.obstacle_push(ship.global_position, radius, obstacles,
			tuning.obstacle_margin, max_speed, tuning.obstacle_strength)


# ------------------------------------------------------------------ per frame

func _physics_process(delta: float) -> void:
	if _dissolving:
		return
	if not _handle_lost_ships():
		return
	if _dirty:
		_rebuild()
	var heading := _travel_heading()
	if delta > 0.0:
		var rate := angle_difference(_frame_heading, heading) / delta
		_angular_velocity = lerpf(_angular_velocity, rate, ANGULAR_SMOOTHING)
	_frame_heading = heading
	_frame_origin = lead.global_position + lead.velocity * delta  # where the leader will be this frame
	_lead_state = lead.state
	_update_bodies()
	_update_turn_cap()
	_check_members(delta)


## Drops ships that have been freed, and handles the leader going away. False if
## the formation has ended.
func _handle_lost_ships() -> bool:
	for ship in _ships.duplicate():
		if ship == lead:
			continue
		if not is_instance_valid(ship) or ship.is_queued_for_deletion():
			_remove_ship(ship, REASON_DESTROYED)
			if _dissolving:
				return false
	if not has_valid_lead():
		if _ships.has(lead):
			if _lead_state == NpcShip.State.WARPING:
				_leave_with_leader()
				return false
			_remove_ship(lead, REASON_DESTROYED)
		return not _dissolving
	return not _dissolving


## The leader jumped out of the system: so does everyone with it.
func _leave_with_leader() -> void:
	_dissolving = true
	for ship in _ships:
		if is_instance_valid(ship) and ship != lead:
			ship.formation = null
			ship.queue_free()
	_ships.clear()
	dissolved.emit()
	queue_free()


## Members that are heavily damaged, or have fallen too far behind for too long,
## are released to carry on alone.
func _check_members(delta: float) -> void:
	for ship in get_members():
		var combatant: Combatant = ship.get_combatant()
		if combatant != null:
			var health: DefenceState = combatant.health.state
			if health.max_hull > 0.0 and health.hull / health.max_hull < tuning.disabled_hull_fraction:
				release(ship, REASON_DISABLED)
				continue
		if is_slaved():
			continue
		if get_slot_error(ship) > tuning.lost_distance:
			_off_station[ship] = _off_station.get(ship, 0.0) + delta
			if _off_station[ship] >= tuning.lost_time:
				release(ship, REASON_SEPARATED)
		else:
			_off_station.erase(ship)


func _update_bodies() -> void:
	_bodies.clear()
	for child in _system.get_ships_root().get_children():
		var other := child as NpcShip
		if other != null and other.visible and not other.is_queued_for_deletion():
			_bodies.append({"node": other, "position": other.global_position, "radius": other.get_hit_radius()})
	if _player != null and is_instance_valid(_player):
		var specs = _player.get("stats")
		var player_radius: float = specs.hit_radius if specs != null else 30.0
		_bodies.append({"node": _player, "position": _player.global_position, "radius": player_radius})


## Radius of a planet or station, from its location data (its size is a diameter).
func _body_radius(node: InhabitedNode) -> float:
	return node.data.size * 0.5 if node.data != null else 100.0


# ------------------------------------------------------------ slots and losses

func _rebuild() -> void:
	_dirty = false
	_ships = _ships.filter(func(ship) -> bool: return is_instance_valid(ship) and not ship.is_queued_for_deletion())
	if _ships.is_empty():
		return
	var candidates: Array[SlotCandidate] = []
	var radii: Array = []
	for ship in _ships:
		var model: ShipStats = ship.ship_type.stats
		var footprint: float = _footprint_of(ship)
		radii.append(footprint)
		candidates.append(SlotCandidate.make(ship, CombatRating.of(model),
				model.ship_class.tier if model.ship_class != null else 0,
				model.ship_class.carries_cargo() if model.ship_class != null else false, footprint))
	spacing = FormationGeometry.compute_spacing(shape, radii, tuning)
	station_tolerance = maxf(tuning.station_tolerance_min, tuning.station_tolerance_factor * spacing)
	catch_up_distance = tuning.catch_up_factor * spacing
	_slots = FormationGeometry.build_slots(shape, _ships.size(), spacing, _inner_count(candidates))
	_seating = SlotAssigner.assign(shape, _slots, candidates, lead, _previous)
	_previous.clear()
	for ship in _seating:
		_previous[ship] = (_seating[ship] as FormationSlot).index
	_push_limits()


## How much room a ship needs: its own radius, plus the whole extent of any other
## formation it leads (a squadron leader inside a battle group).
func _footprint_of(ship: NpcShip) -> float:
	var radius := ship.get_hit_radius()
	if ship.led_formation != null and ship.led_formation != self:
		radius += ship.led_formation.get_extent()
	return radius


## How many ships belong inside, for shapes that care: freighters inside a ring,
## everyone but the lightest ships behind a screen.
func _inner_count(candidates: Array[SlotCandidate]) -> int:
	match shape.layout:
		FormationShape.Layout.RING:
			var cargo := 0
			for candidate in candidates:
				if candidate.cargo:
					cargo += 1
			return maxi(cargo, 1)
		FormationShape.Layout.SCREEN:
			var lightest := 1 << 30
			var heaviest := -1
			for candidate in candidates:
				lightest = mini(lightest, candidate.tier)
				heaviest = maxi(heaviest, candidate.tier)
			if lightest == heaviest:
				return -1
			var pickets := 0
			for candidate in candidates:
				if candidate.tier == lightest:
					pickets += 1
			return candidates.size() - pickets
	return -1


## Gives the leader the speed limit that lets every member keep up, and works
## out what the turn limit depends on.
func _push_limits() -> void:
	var speeds: Array = []
	_followers.clear()
	for ship in _ships:
		speeds.append(ship.ship_type.stats.max_speed)
		if ship != lead:
			var slot: FormationSlot = _seating.get(ship)
			_followers.append({
				"max_speed": ship.ship_type.stats.max_speed,
				"turn_rate": ship.ship_type.stats.turn_rate,
				"thrust": ship.ship_type.stats.thrust,
				"distance": slot.offset.length() if slot != null else 0.0,
			})
	lead.formation_speed_cap = FormationSteering.speed_cap(speeds, tuning.speed_margin)
	lead.formation_thrust_cap = FormationSteering.thrust_cap(_followers, tuning)
	lead.formation_turn_accel_cap = FormationSteering.turn_accel_cap(_followers, tuning)
	_update_turn_cap()


## The leader may turn as fast as the outer members can follow at the speed the
## leader is flying NOW (a slow leader can turn much more tightly than one at
## cruise speed), never slower than the minimum.
func _update_turn_cap() -> void:
	if not has_valid_lead():
		return
	var speed := minf(lead.velocity.length(), lead.formation_speed_cap)
	lead.formation_turn_cap = FormationSteering.turn_cap(lead.ship_type.stats.turn_rate, _followers, speed, tuning)


func _on_combatant_destroyed(_victim: Combatant, _attacker: Combatant, ship: NpcShip) -> void:
	_remove_ship(ship, REASON_DESTROYED)


## Takes a ship out of the list and deals with what follows: a new leader if it
## was the leader, closing ranks, or breaking up.
func _remove_ship(ship, reason: StringName) -> void:
	if not _ships.has(ship) or _dissolving:
		return
	var was_lead: bool = ship == lead
	_ships.erase(ship)
	_seating.erase(ship)
	_previous.erase(ship)
	_off_station.erase(ship)
	if is_instance_valid(ship):
		var combatant: Combatant = ship.get_combatant()
		var callback := _on_combatant_destroyed.bind(ship)
		if combatant != null and combatant.destroyed.is_connected(callback):
			combatant.destroyed.disconnect(callback)
		if was_lead:
			ship.led_formation = null
			ship.clear_formation_limits()
		elif ship.formation == self:
			ship.formation = null
	member_lost.emit(ship, reason)
	if _ships.size() < shape.min_members:
		_dissolve()
		return
	if was_lead:
		_promote_leader(ship)
	_dirty = true


## The strongest remaining ship takes over as leader and carries on the old
## leader's journey. A convoy prefers another freighter, because the freighters
## are the middle of the convoy and the leader is the centre of the shape.
func _promote_leader(old_lead) -> void:
	var chosen: NpcShip = null
	var chosen_rating := -INF
	var cargo_only := kind == Kind.CONVOY and _has_cargo_ship()
	for ship in _ships:
		var model: ShipStats = ship.ship_type.stats
		if cargo_only and not (model.ship_class != null and model.ship_class.carries_cargo()):
			continue
		var rating: float = CombatRating.of(model)
		if rating > chosen_rating:
			chosen_rating = rating
			chosen = ship
	lead = chosen
	lead.formation = null
	lead.led_formation = self
	if is_instance_valid(old_lead):
		lead.take_over_route_from(old_lead)
	_lead_state = lead.state
	leader_changed.emit(old_lead, lead)


func _has_cargo_ship() -> bool:
	for ship in _ships:
		var model: ShipStats = ship.ship_type.stats
		if model.ship_class != null and model.ship_class.carries_cargo():
			return true
	return false


## Too few ships are left: everyone carries on alone.
func _dissolve() -> void:
	_dissolving = true
	for ship in _ships:
		if not is_instance_valid(ship) or ship.is_queued_for_deletion():
			continue
		if ship == lead:
			ship.led_formation = null
			ship.clear_formation_limits()
		else:
			ship.leave_formation()
	_ships.clear()
	dissolved.emit()
	queue_free()
