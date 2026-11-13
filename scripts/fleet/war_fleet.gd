class_name WarFleet
extends Node
## A fleet: 2 to 3 battle groups and 1 to 2 capital ships (see the fleet recipe).
## Its flagship is the strongest capital ship. It is NOT a formation: it has no
## shape and no slots. Each part flies its own route, and the fleet holds together
## with a leash:
##
##  - a battle group's leader or the second capital ship that gets farther from the
##    flagship than the cohesion radius is recalled: it leaves its route, flies back
##    to a point inside the radius matching the flagship's velocity, and carries on
##    with its route once it is back within `fleet_release_fraction` of the radius;
##  - the flagship's speed is limited to what the slowest part can keep up with, so
##    nothing is ever left behind for good.
##
## Each battle group is an ordinary Formation (with its squadrons nested inside), so
## it stays together by itself; only its leader is on the leash.
##
## The fleet lives under the star system's `Formations` node and runs before the
## formations. Like a Formation it only moves ships: deciding what the fleet does
## (engage, hold, withdraw when the flagship falls) comes with the NPC combat AI.

## The flagship was lost and `new_flagship` (the next strongest capital ship) took over.
signal flagship_changed(old_flagship, new_flagship)
## The fleet has broken up (its last capital ship was lost).
signal dissolved

## Unique among fleets ("fleet_3"): what combat reports name the fleet by.
var id: StringName = &""
var flagship: NpcShip
var tuning: FormationTuning
## How far a part may stray from the flagship before it is recalled (pixels).
var cohesion_radius: float = 0.0

## Every ship on the leash: the second capital ship and each battle group's leader.
## (Untyped on purpose: ships get freed.)
var _units: Array = []
var _formations: Array = []
var _recalled: Dictionary = {}  # NpcShip -> true while it is being recalled
var _environment := FormationEnvironment.new()
var _dissolving: bool = false


static var _created: int = 0


func _init() -> void:
	_created += 1
	id = StringName("fleet_%d" % _created)


## `capitals` are the capital ships other than the flagship, `battle_groups` the
## fleet's battle group formations (already set up). The ships must be in the tree.
func setup(system: StarSystem, player: Node2D, flagship_ship: NpcShip, capitals: Array[NpcShip],
		battle_groups: Array[Formation], radius: float, fleet_tuning: FormationTuning = null) -> void:
	tuning = fleet_tuning if fleet_tuning != null else FormationTuning.shared()
	cohesion_radius = radius
	process_physics_priority = -12  # before the battle groups and squadrons
	_environment.setup(system, player)
	flagship = flagship_ship
	flagship.fleet = self
	for ship in capitals:
		ship.fleet = self
		_units.append(ship)
	for group in battle_groups:
		_formations.append(group)
		group.fleet = self
		group.lead.fleet = self
		_units.append(group.lead)
		group.leader_changed.connect(_on_leader_changed)
		group.dissolved.connect(_on_group_dissolved.bind(group))
	_limit_flagship_speed()  # (from the first frame)


# ------------------------------------------------------------------ queries

func has_flagship() -> bool:
	return flagship != null and is_instance_valid(flagship) and not flagship.is_queued_for_deletion()


## The ships on the leash: the other capital ships and the battle groups' leaders.
func get_units() -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in _units:
		if is_instance_valid(ship):
			result.append(ship)
	return result


func get_battle_groups() -> Array[Formation]:
	var result: Array[Formation] = []
	for group in _formations:
		if is_instance_valid(group):
			result.append(group)
	return result


## Every ship in the fleet, each once.
func get_all_ships() -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	if has_flagship():
		result.append(flagship)
	for ship in get_units():
		if not result.has(ship):
			result.append(ship)
	for group in get_battle_groups():
		for ship in group.get_all_ships():
			if not result.has(ship):
				result.append(ship)
	return result


## The fleet's strength: the sum of its ships' ratings.
func get_rating() -> float:
	var total := 0.0
	for ship in get_all_ships():
		total += CombatRating.of(ship.ship_type.stats)
	return total


## Whether `ship` has strayed and is being called back.
func is_recalled(ship: NpcShip) -> bool:
	return _recalled.has(ship)


## Avoidance for a fleet ship that leads no formation (the flagship, the second
## capital ship).
func get_avoidance(ship: NpcShip) -> Vector2:
	return _environment.get_avoidance(ship, tuning, flagship.destination if has_flagship() else null)


# ------------------------------------------------------------------ per frame

func _physics_process(_delta: float) -> void:
	if _dissolving:
		return
	_forget_lost_units()
	if not has_flagship():
		_replace_flagship()
		if _dissolving:
			return
	_environment.update()
	_limit_flagship_speed()
	_keep_on_leash()


func _forget_lost_units() -> void:
	_units = _units.filter(func(ship) -> bool: return is_instance_valid(ship) and not ship.is_queued_for_deletion())
	_formations = _formations.filter(func(group) -> bool: return is_instance_valid(group))
	for ship in _recalled.keys():
		if not is_instance_valid(ship):
			_recalled.erase(ship)


## The flagship is slower than nothing: it may not outrun the slowest part.
func _limit_flagship_speed() -> void:
	var speeds: Array = [flagship.ship_type.stats.max_speed]
	for ship in _units:
		speeds.append(ship.effective_max_speed())
	flagship.formation_speed_cap = FormationSteering.speed_cap(speeds, tuning.speed_margin)


func _keep_on_leash() -> void:
	var release_distance := cohesion_radius * tuning.fleet_release_fraction
	for ship in _units:
		var gap: float = ship.global_position.distance_to(flagship.global_position)
		if gap > cohesion_radius:
			ship.recall_target = flagship
			ship.recall_distance = cohesion_radius * tuning.fleet_station_fraction
			_recalled[ship] = true
		elif _recalled.has(ship) and gap <= release_distance:
			ship.recall_target = null
			_recalled.erase(ship)


## The flagship is gone: the strongest other capital ship takes over, if there is
## one. Otherwise the fleet is over and everyone carries on alone.
func _replace_flagship() -> void:
	var old = flagship
	var best: NpcShip = null
	var best_rating := -INF
	for ship in _units:
		var ship_class: ShipClass = ship.ship_type.stats.ship_class
		if ship_class == null or not ship_class.is_capital():
			continue
		var rating := CombatRating.of(ship.ship_type.stats)
		if rating > best_rating:
			best_rating = rating
			best = ship
	if best == null:
		_dissolve()
		return
	_units.erase(best)
	_recalled.erase(best)
	best.recall_target = null
	flagship = best
	if is_instance_valid(old):
		best.take_over_route_from(old)
	flagship_changed.emit(old, best)


func _dissolve() -> void:
	_dissolving = true
	var ships: Array = _units.duplicate()
	for ship in ships:
		if is_instance_valid(ship):
			ship.fleet = null
			ship.recall_target = null
	for group in _formations:
		if is_instance_valid(group):
			group.fleet = null
	_units.clear()
	_formations.clear()
	_recalled.clear()
	dissolved.emit()
	queue_free()


# --------------------------------------------------------------------- signals

## A battle group lost its leader and a new one took over: the new one is on the
## leash instead.
func _on_leader_changed(old_lead, new_lead) -> void:
	if not is_instance_valid(new_lead):
		return
	var index := _units.find(old_lead)
	if index >= 0:
		_units[index] = new_lead
	else:
		_units.append(new_lead)
	_recalled.erase(old_lead)
	new_lead.fleet = self


## A battle group broke up. Its old leader is still a warship of the fleet and stays
## on the leash.
func _on_group_dissolved(group) -> void:
	_formations.erase(group)
