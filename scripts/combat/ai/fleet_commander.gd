class_name FleetCommander
extends Node
## The brain of a WarFleet (Phase 3.3, step 5): it holds an objective, decides when the
## fleet fights, and gives orders to the parts below it. A fleet has no formation and no
## states of its own (decided in Phase 3.2), so this has a small state machine of its own.
## It reasons from the flagship, thinks about once a second, and never steers a ship.
##
## Objective (set with `set_objective`, which the future war layer will use):
##   OFFENSIVE  engage what it sees: a named enemy unit first (`target`), or the strongest.
##   DEFENSIVE  hold `point` (the flagship flies there and stops) and engage only hostile
##              ships within `radius` of it.
##   INTERCEPT  fly to catch the moving enemy `target` (the flagship heads for where it will
##              be, the fleet follows on its leash) and engage once it is within the
##              profile's `engage_radius`, or anything else comes that close.
##
## State:
##   FOLLOWING   nothing to fight: the fleet flies its route (or its objective). Battle
##               groups are told to HOLD (they do not go out to meet the enemy on their own)
##               and every capital ship fires at will.
##   ENGAGING    the fleet fights. Each battle group is matched to an enemy unit by strength
##               (the strongest group to the strongest unit, and so round) and given it as its
##               focus; the battle groups then run themselves (UnitCommander). The capital
##               ships (the flagship and the second one) get ENGAGE orders: with their
##               doctrine they stand off and let the groups fight in front.
##   WITHDRAWING the fleet has lost more than the profile allows (80%), or `order_withdraw`
##               was called: every battle group is told to WITHDRAW and the capital ships run
##               and jump. It lasts until nothing hostile is in sight.
## A flagship that is lost is replaced by the next capital ship (WarFleet) and the fleet
## fights on: the fleet withdraws for losses, never for its flagship's hull.

enum State { FOLLOWING, ENGAGING, WITHDRAWING }
enum Objective { OFFENSIVE, DEFENSIVE, INTERCEPT }

signal state_changed(new_state: State)

var profile: TacticalProfile
var state: State = State.FOLLOWING
var objective: Objective = Objective.OFFENSIVE
## DEFENSIVE: the point to hold and how far from it enemies count (0: the profile's sight radius).
var point: Vector2 = Vector2.ZERO
var radius: float = 0.0
## OFFENSIVE: the enemy to go for first. INTERCEPT: the enemy to catch.
var target: Combatant

var _fleet: WarFleet
var _think_left: float = 0.0
var _calm_for: float = 0.0
var _peak_rating: float = 0.0
var _withdraw_ordered: bool = false
var _reallocate_soon: bool = false
## Where the enemy was when the fleet last saw it (for withdrawing).
var _enemy_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	_fleet = get_parent() as WarFleet
	if profile == null:
		profile = TacticalProfile.default()
	objective = profile.default_objective as Objective  # (OFFENSIVE or DEFENSIVE)
	_think_left = randf() * profile.think_interval
	if _fleet == null:
		return
	_fleet.flagship_changed.connect(_on_flagship_changed)
	_fleet.dissolved.connect(_on_dissolved)


# ------------------------------------------------------- from the war layer

## Sets what the fleet is to do (see the class comment).
func set_objective(kind: Objective, hold_point: Vector2 = Vector2.ZERO, enemy: Combatant = null, hold_radius: float = 0.0) -> void:
	objective = kind
	point = hold_point
	target = enemy
	radius = hold_radius
	_reallocate_soon = true


## Withdraws the fleet: it runs and jumps out, and stands down when nothing hostile is in sight.
func order_withdraw() -> void:
	_withdraw_ordered = true
	_reallocate_soon = true


func get_state() -> State:
	return state


# ------------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if _fleet == null or not is_instance_valid(_fleet) or not _fleet.has_flagship():
		return
	_think_left -= delta
	if _think_left > 0.0 and not _reallocate_soon:
		return
	_think_left = profile.think_interval
	_reallocate_soon = false
	_think()


func _exit_tree() -> void:
	_release_all()


func _think() -> void:
	var picture := get_tree().get_first_node_in_group(TacticalPicture.GROUP) as TacticalPicture
	var flagship := _fleet.flagship
	if picture == null or flagship.get_combatant() == null:
		return
	if flagship.state == NpcShip.State.ARRIVING or flagship.state == NpcShip.State.WARPING:
		_enter(State.FOLLOWING)  # (jumping in or out: nobody can fight)
		return
	if objective == Objective.INTERCEPT and (target == null or not is_instance_valid(target) or not target.is_alive()):
		objective = Objective.OFFENSIVE  # (the one it was after is gone)
		target = null
	if objective == Objective.DEFENSIVE and point == Vector2.ZERO:
		point = flagship.global_position  # (a defending fleet holds where it first stands)
	var own: Array[Combatant] = []
	for ship in _fleet.get_all_ships():
		if ship.get_combatant() != null:
			own.append(ship.get_combatant())
	var hostiles := _relevant(picture.hostiles_near(flagship.get_combatant(), profile.fleet_sight_radius), flagship)
	hostiles = profile.filter_hostiles(flagship.get_combatant(), own, hostiles)
	if not hostiles.is_empty():
		_enemy_point = _centre_of(hostiles)
	var strength := _fleet.get_rating()
	_peak_rating = maxf(_peak_rating, strength)

	if _withdraw_ordered and hostiles.is_empty():
		_withdraw_ordered = false  # (it has got away)
	if _withdraw_ordered or state == State.WITHDRAWING and not hostiles.is_empty() \
			or _should_withdraw(hostiles, strength):
		_calm_for = 0.0
		_enter(State.WITHDRAWING)
	elif not hostiles.is_empty():
		_calm_for = 0.0
		_enter(State.ENGAGING)
	else:
		_calm_for += profile.think_interval
		if state != State.FOLLOWING and _calm_for >= profile.calm_seconds:
			_enter(State.FOLLOWING)
	_give_orders(picture, hostiles, flagship)


## The hostile ships the objective makes the fleet's business.
func _relevant(hostiles: Array[Combatant], flagship: NpcShip) -> Array[Combatant]:
	match objective:
		Objective.DEFENSIVE:
			var reach := radius if radius > 0.0 else profile.sight_radius
			var inside: Array[Combatant] = []
			for other in hostiles:
				if other.global_position.distance_to(point) <= reach:
					inside.append(other)
			return inside
		Objective.INTERCEPT:
			# (nothing is its business until it has caught its target, or something else is that close)
			var close: Array[Combatant] = []
			for other in hostiles:
				if other.global_position.distance_to(flagship.global_position) <= profile.engage_radius:
					close.append(other)
			return close
	return hostiles


func _should_withdraw(hostiles: Array[Combatant], strength: float) -> bool:
	if hostiles.is_empty() or _peak_rating <= 0.0:
		return false
	var enemy := 0.0
	for other in hostiles:
		if other.is_armed():
			enemy += other.rating
	if enemy <= 0.0:
		return false
	if profile.max_odds > 0.0 and enemy > strength * profile.max_odds:
		return true  # (the odds are worse than it will take)
	return 1.0 - strength / _peak_rating > profile.withdraw_losses


func _enter(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	_release_all()
	state_changed.emit(state)


# -------------------------------------------------------------------- orders

func _give_orders(picture: TacticalPicture, hostiles: Array[Combatant], flagship: NpcShip) -> void:
	var groups := _fleet.get_battle_groups()
	var capitals := _capitals()
	match state:
		State.FOLLOWING:
			for group in groups:
				group.commander.set_directive(UnitCommander.Directive.HOLD)
			for ship in capitals:
				TargetAllocator.give(ship, CombatOrder.new(CombatOrder.Kind.FIRE_AT_WILL))
			var move := _objective_move(flagship)
			if move != null:
				TargetAllocator.give(flagship, move)
		State.ENGAGING:
			_match_groups(groups, hostiles)
			var orders := TargetAllocator.assign(picture, hostiles, _armed(capitals), profile, {})
			for ship in orders:
				TargetAllocator.give(ship, orders[ship])
		State.WITHDRAWING:
			for group in groups:
				group.commander.set_directive(UnitCommander.Directive.WITHDRAW, _enemy_point)
			for ship in capitals:
				var run := CombatOrder.new(CombatOrder.Kind.WITHDRAW)
				run.point = _enemy_point
				TargetAllocator.give(ship, run)


## What the flagship does while the fleet is not fighting, if the objective gives it somewhere
## to go: hold a point, or head for where the target will be. Null: it flies its route.
func _objective_move(flagship: NpcShip) -> CombatOrder:
	match objective:
		Objective.DEFENSIVE:
			var move := CombatOrder.new(CombatOrder.Kind.MOVE)
			move.point = point
			return move
		Objective.INTERCEPT:
			var move := CombatOrder.new(CombatOrder.Kind.MOVE)
			var gap := flagship.global_position.distance_to(target.global_position)
			var speed := maxf(flagship.effective_max_speed(), 1.0)
			move.point = target.global_position + target.get_velocity() * minf(gap / speed, 30.0)
			return move
	return null


## Matches each battle group to an enemy unit, strongest to strongest, going round again when
## there are more groups than units; the group's commander is told whose ships to go for.
func _match_groups(groups: Array[Formation], hostiles: Array[Combatant]) -> void:
	var units := _enemy_units(hostiles)
	for group in groups:
		group.commander.set_directive(UnitCommander.Directive.FREE)
	if units.is_empty():
		return
	var ordered := groups.duplicate()
	ordered.sort_custom(func(a: Formation, b: Formation) -> bool: return a.get_rating() > b.get_rating())
	for index in ordered.size():
		var unit: Dictionary = units[index % units.size()]
		(ordered[index] as Formation).commander.set_focus(unit["ships"])


## The hostile ships grouped by the unit they belong to (the fleet, or top formation, or alone),
## strongest first: [{"ships": Array[Combatant], "rating": float}]. The named `target` leads.
func _enemy_units(hostiles: Array[Combatant]) -> Array[Dictionary]:
	var by_key := {}
	for other in hostiles:
		var key: Variant = _unit_key(other)
		if not by_key.has(key):
			by_key[key] = {"ships": [], "rating": 0.0}
		by_key[key]["ships"].append(other)
		by_key[key]["rating"] += other.rating
	var units: Array[Dictionary] = []
	for key in by_key:
		units.append(by_key[key])
	units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_first: bool = a["ships"].has(target)
		var b_first: bool = b["ships"].has(target)
		if a_first != b_first:
			return a_first
		return a["rating"] > b["rating"])
	return units


## What `other` is a part of: its fleet, else the top formation it belongs to, else itself.
func _unit_key(other: Combatant) -> Variant:
	var ship := other.get_parent() as NpcShip
	if ship == null:
		return other
	if ship.fleet != null and is_instance_valid(ship.fleet):
		return ship.fleet
	var top: Formation = ship.formation if ship.formation != null else ship.led_formation
	if top == null or not is_instance_valid(top):
		return other
	for step in 8:
		if top.parent == null or not is_instance_valid(top.parent):
			break
		top = top.parent
	return top.fleet if top.fleet != null and is_instance_valid(top.fleet) else top


## The flagship and the other capital ships (the ships on the leash that lead no formation).
func _capitals() -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	if _fleet.has_flagship():
		result.append(_fleet.flagship)
	for ship in _fleet.get_units():
		if ship.led_formation == null and not result.has(ship):
			result.append(ship)
	return result


func _armed(ships: Array[NpcShip]) -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in ships:
		if ship.get_combatant() != null and ship.get_combatant().is_armed():
			result.append(ship)
	result.sort_custom(func(a: NpcShip, b: NpcShip) -> bool: return a.get_combatant().rating > b.get_combatant().rating)
	return result


## Takes every order back: battle groups free, capital ships with nothing to do.
func _release_all() -> void:
	if _fleet == null or not is_instance_valid(_fleet):
		return
	for group in _fleet.get_battle_groups():
		if group.commander != null:
			group.commander.set_directive(UnitCommander.Directive.FREE)
			group.commander.set_focus([])
	for ship in _capitals():
		TargetAllocator.give(ship, null)


func _centre_of(ships: Array[Combatant]) -> Vector2:
	var total := Vector2.ZERO
	for other in ships:
		total += other.global_position
	return total / ships.size() if not ships.is_empty() else Vector2.ZERO


# ------------------------------------------------------------------- events

func _on_flagship_changed(old_flagship, _new_flagship) -> void:
	if is_instance_valid(old_flagship) and not old_flagship.is_queued_for_deletion():
		TargetAllocator.give(old_flagship, null)
	_reallocate_soon = true


func _on_dissolved() -> void:
	_release_all()
