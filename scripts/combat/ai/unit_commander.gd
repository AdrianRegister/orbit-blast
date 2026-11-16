class_name UnitCommander
extends Node
## The brain of one Formation (a squadron, a battle group or a convoy): it decides what
## the unit does about enemies and gives its ships' pilots orders (CombatOrder). It
## never steers a ship, and pilots never decide what a group does. A Formation makes
## its own commander in setup; the numbers are a TacticalProfile.
##
## It reasons from the flagship, thinks about once a second, and runs a small state
## machine (Formation.State, kept on the formation so others can read it):
##
##   FOLLOWING     no enemy in sight. The unit flies its route in shape and every ship
##                 shoots at what comes in reach from its slot.
##   INTERCEPTING  an enemy is in sight but not yet close. The leader flies at it, the
##                 shape is chosen for what the enemy is, and the rest keep their slots.
##   ATTACKING     an enemy is close. The unit breaks: every armed ship fights under an
##                 ENGAGE order, with targets shared out between them (TargetAllocator).
##   DEFENDING     a convoy with an enemy in sight. The freighters keep flying; the armed
##                 escorts guard them: they go for enemies near the freighters and come
##                 back to their slots afterwards (GUARD orders).
##   WITHDRAWING   losing: the unit has lost more than the profile allows (or a higher
##                 commander said so). The leader runs for the way out and jumps, and the
##                 unit goes with it.
##   HOLDING       reserved for the player's formation commands (step 9).
##
## A unit that sees no enemy for the profile's calm time goes back to FOLLOWING, and its
## ships re-form: their pilots stand down and they fly back to their slots.
##
## The chain of command (step 5):
##   - A battle group's commander gives each of its squadrons a ROLE while it attacks:
##     SCREEN (guard the battle group's own big ships against what threatens them, like a
##     convoy's escorts) or STRIKE (attack, going for small craft first). When the enemy has
##     light craft, `profile.screen_squadrons` of them screen.
##   - A squadron inside a battle group takes its orders from that role and makes no
##     decisions of its own: with no role it keeps its slot and fires at will.
##   - A fleet's commander (FleetCommander) gives a battle group a DIRECTIVE (hold, or
##     withdraw) and a FOCUS (the enemy unit to deal with); with neither it is free.
## A ship that leads a squadron inside a battle group takes its orders from its squadron's
## commander; a commander orders only the ships that lead no unit of their own.

const State := Formation.State

## What a battle group asks of one of its squadrons.
enum Role { NONE, SCREEN, STRIKE }
## What a fleet asks of a battle group: FREE (decide for yourself), HOLD (do not go out to
## meet the enemy: fire at will from your place) or WITHDRAW.
enum Directive { FREE, HOLD, WITHDRAW }

var profile: TacticalProfile
var state: State = State.FOLLOWING
var role: Role = Role.NONE
var directive: Directive = Directive.FREE

var _formation: Formation
var _think_left: float = 0.0
## Game seconds this commander has been thinking for (what `_ignored` is timed against).
var _clock: float = 0.0
## Where the flagship was when the unit began a fight (what the pursuit leash is measured from).
var _fight_origin: Vector2 = Vector2.ZERO
## Enemies it has given up chasing: Combatant -> the time (_clock) it ignores them until.
var _ignored: Dictionary = {}
var _calm_for: float = 0.0
## The strongest the unit has been (CombatRating), to measure losses against.
var _peak_rating: float = 0.0
## The unit's own shape, to go back to after changing it for a fight.
var _travel_shape: FormationShape
var _reallocate_soon: bool = false
## The enemy ships a higher commander wants dealt with (they count extra when choosing).
var _focus: Array = []
## Where the enemy is, for a WITHDRAW directive given when none is in sight.
var _withdraw_from: Vector2 = Vector2.ZERO


func _ready() -> void:
	_formation = get_parent() as Formation
	if profile == null:
		profile = TacticalProfile.default()
	_think_left = randf() * profile.think_interval  # (so units do not all think on the same frame)
	if _formation == null:
		return
	_formation.member_lost.connect(_on_member_lost)
	_formation.leader_changed.connect(_on_leader_changed)
	_formation.dissolved.connect(_on_dissolved)


func get_state() -> State:
	return state


# ------------------------------------------------------------ from above

## A battle group's commander gives a squadron a role (NONE: back in its slots).
func set_role(new_role: Role) -> void:
	if new_role != role:
		role = new_role
		_reallocate_soon = true


## A fleet's commander gives a battle group a directive. `from` is where the enemy is.
func set_directive(new_directive: Directive, from: Vector2 = Vector2.ZERO) -> void:
	_withdraw_from = from
	if new_directive != directive:
		directive = new_directive
		_reallocate_soon = true


## The enemy ships a higher commander wants dealt with (a soft preference).
func set_focus(targets: Array) -> void:
	_focus = targets


## The ships this unit gives orders to itself: what a screen squadron protects.
func get_core_ships() -> Array[NpcShip]:
	return _own_ships()


# ------------------------------------------------------------------- loop


func _physics_process(delta: float) -> void:
	if _formation == null or not is_instance_valid(_formation) or not _formation.has_valid_lead():
		return
	_think_left -= delta
	if _think_left > 0.0 and not _reallocate_soon:
		return
	_think_left = profile.think_interval
	_clock += profile.think_interval
	_reallocate_soon = false
	_think()


func _exit_tree() -> void:
	_clear_orders()


# ------------------------------------------------------------------ deciding

func _think() -> void:
	var picture := get_tree().get_first_node_in_group(TacticalPicture.GROUP) as TacticalPicture
	var flagship := _formation.get_flagship()
	if picture == null or flagship == null or flagship.get_combatant() == null:
		return
	if _formation.is_slaved() or _formation.is_warping():
		_enter(State.FOLLOWING)  # (jumping in or out: nobody can fight)
		return
	var lead_combatant: Combatant = flagship.get_combatant()
	var hostiles := picture.hostiles_near(lead_combatant, profile.sight_radius)
	if _is_sub():
		_think_squadron(picture, hostiles)
		return
	hostiles = _concerning_me(picture, lead_combatant, hostiles)
	var strength := _rating_of(_formation.get_all_ships())
	_peak_rating = maxf(_peak_rating, strength)

	if directive == Directive.WITHDRAW:
		_calm_for = 0.0
		_enter(State.WITHDRAWING, hostiles)
	elif directive == Directive.HOLD or hostiles.is_empty():
		if directive == Directive.HOLD:
			hostiles = []  # (it does not go out to meet the enemy)
		_calm_for += profile.think_interval
		if state != State.FOLLOWING and _calm_for >= profile.calm_seconds:
			_enter(State.FOLLOWING)
	else:
		_calm_for = 0.0
		var next := _next_state(hostiles, flagship, strength)
		if next != state:
			_enter(next, hostiles)
		if _chased_too_far(hostiles, flagship):
			hostiles = []
			_enter(State.FOLLOWING)  # (it gives up the chase and goes back to its route)
	_give_orders(picture, hostiles)


## The hostile ships in sight that the unit takes any notice of: not the ones it has given up
## chasing, and, if the profile is not proactive, only ones that have attacked it or are
## targeting one of its ships (then, once there is such a one, all of them: the whole enemy
## force is its business).
func _concerning_me(picture: TacticalPicture, lead_combatant: Combatant, hostiles: Array[Combatant]) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for other in hostiles:
		if not _is_ignored(other):
			result.append(other)
	var mine: Array[Combatant] = []
	for ship in _formation.get_all_ships():
		if ship.get_combatant() != null:
			mine.append(ship.get_combatant())
	return profile.filter_hostiles(lead_combatant, mine, result)


func _is_ignored(other: Combatant) -> bool:
	if not _ignored.has(other):
		return false
	if _ignored[other] <= _clock or not is_instance_valid(other):
		_ignored.erase(other)
		return false
	return true


## Whether the unit has gone further from where the fight began than its profile lets it chase.
## If so the enemy it was after is ignored for a while.
func _chased_too_far(hostiles: Array[Combatant], flagship: NpcShip) -> bool:
	if profile.pursuit_leash <= 0.0 or state == State.FOLLOWING or state == State.WITHDRAWING:
		return false
	if flagship.global_position.distance_to(_fight_origin) <= profile.pursuit_leash:
		return false
	for other in hostiles:
		_ignored[other] = _clock + profile.give_up_seconds
	return true


## The state the unit should be in now that it sees `hostiles`.
func _next_state(hostiles: Array[Combatant], flagship: NpcShip, strength: float) -> State:
	if state == State.WITHDRAWING:
		return state  # (it runs until it is out of sight, or gone)
	if _formation.kind != Formation.Kind.CONVOY and _should_withdraw(hostiles, flagship, strength):
		return State.WITHDRAWING
	if _formation.kind == Formation.Kind.CONVOY:
		return State.DEFENDING
	if state == State.ATTACKING or _nearest_distance(hostiles) <= profile.engage_radius:
		return State.ATTACKING
	return State.INTERCEPTING


func _should_withdraw(hostiles: Array[Combatant], flagship: NpcShip, strength: float) -> bool:
	var enemy := _rating_of_combatants(hostiles, true)
	if enemy <= 0.0:
		return false  # (nothing armed to run from)
	if profile.max_odds > 0.0 and enemy > strength * profile.max_odds:
		return true  # (the odds are worse than it will take)
	if _peak_rating > 0.0 and 1.0 - strength / _peak_rating > profile.withdraw_losses:
		return true
	if profile.flagship_withdraw_hull <= 0.0:
		return false
	var defence: DefenceState = flagship.get_combatant().health.state
	return defence.max_hull > 0.0 and defence.hull / defence.max_hull < profile.flagship_withdraw_hull


## Switches state: the formation hears of it, the shape is changed to suit, and the old
## orders are dropped (new ones follow at once, in _give_orders).
func _enter(new_state: State, hostiles: Array[Combatant] = []) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	if old == State.FOLLOWING:
		_fight_origin = _formation.lead.global_position  # (where the fight began)
	_formation.set_state(new_state)
	_clear_orders()
	if old == State.ATTACKING:
		_release_squadrons()
	if new_state == State.FOLLOWING:
		if _travel_shape != null and _formation.kind != Formation.Kind.CONVOY:
			_formation.set_shape(_travel_shape)
		_travel_shape = null
	elif old == State.FOLLOWING and _formation.kind != Formation.Kind.CONVOY:
		_travel_shape = _formation.shape
	if new_state == State.INTERCEPTING and _formation.kind != Formation.Kind.CONVOY:
		_formation.set_shape(_shape_for(hostiles))


## The shape to meet this enemy in, from the profile's rules (the current one if none apply).
func _shape_for(hostiles: Array[Combatant]) -> FormationShape:
	var armed := 0
	var light := 0
	var heavy := 0
	for other in hostiles:
		if not other.is_armed():
			continue
		armed += 1
		if other.evasive:
			light += 1
		elif other.ship_class != null and other.ship_class.tier >= 2:
			heavy += 1
	var chosen: FormationShape = profile.shape_otherwise
	if armed > 0:
		if float(light) / armed >= profile.shape_majority and profile.shape_against_light != null:
			chosen = profile.shape_against_light
		elif float(heavy) / armed >= profile.shape_majority and profile.shape_against_heavy != null:
			chosen = profile.shape_against_heavy
	return chosen if chosen != null else _formation.shape


# ----------------------------------------------------------------- squadrons

## A squadron inside a battle group: it does what its role says.
func _is_sub() -> bool:
	var parent := _formation.parent
	return parent != null and is_instance_valid(parent) and parent.commander != null


func _think_squadron(picture: TacticalPicture, hostiles: Array[Combatant]) -> void:
	match role:
		Role.STRIKE:
			_enter(State.ATTACKING, hostiles)
			var orders := TargetAllocator.assign(picture, hostiles, _fighters(), profile, {}, null, [], _focus, true)
			for ship in orders:
				_set_order(ship, orders[ship])
		Role.SCREEN:
			_enter(State.DEFENDING, hostiles)
			_guard_with(picture, hostiles, _formation.parent.commander.get_core_ships(), _fighters())
		_:
			_enter(State.FOLLOWING)
			_order_all(CombatOrder.Kind.FIRE_AT_WILL)


## The commanders of the squadrons inside this battle group.
func _squadron_commanders() -> Array[UnitCommander]:
	var result: Array[UnitCommander] = []
	for ship in _formation.get_ships():
		var sub: Formation = ship.led_formation
		if sub != null and sub != _formation and is_instance_valid(sub) and sub.commander != null:
			result.append(sub.commander)
	return result


## While the battle group attacks, its squadrons are given roles: when the enemy has light
## craft the weakest `screen_squadrons` of them screen the big ships, and the rest strike.
func _assign_roles(hostiles: Array[Combatant]) -> void:
	var squadrons := _squadron_commanders()
	if squadrons.is_empty():
		return
	var light := false
	for other in hostiles:
		light = light or (other.is_armed() and other.evasive)
	squadrons.sort_custom(func(a: UnitCommander, b: UnitCommander) -> bool: return a._formation.get_rating() < b._formation.get_rating())
	for index in squadrons.size():
		squadrons[index].set_role(Role.SCREEN if light and index < profile.screen_squadrons else Role.STRIKE)
		squadrons[index].set_focus(_focus)


func _release_squadrons() -> void:
	for sub in _squadron_commanders():
		sub.set_role(Role.NONE)
		sub.set_focus([])


# -------------------------------------------------------------------- orders

func _give_orders(picture: TacticalPicture, hostiles: Array[Combatant]) -> void:
	match state:
		State.FOLLOWING, State.HOLDING:
			_order_all(CombatOrder.Kind.FIRE_AT_WILL)
		State.INTERCEPTING:
			_order_all(CombatOrder.Kind.FIRE_AT_WILL, _formation.lead)
			var move := CombatOrder.new(CombatOrder.Kind.MOVE)
			move.point = _intercept_point(hostiles)
			_set_order(_formation.lead, move)
		State.ATTACKING:
			if _formation.kind == Formation.Kind.BATTLE_GROUP:
				_assign_roles(hostiles)
			var orders := TargetAllocator.assign(picture, hostiles, _fighters(), profile, {}, null, [], _focus)
			for ship in orders:
				_set_order(ship, orders[ship])
		State.DEFENDING:
			_defend(picture, hostiles)
		State.WITHDRAWING:
			_order_all(CombatOrder.Kind.FIRE_AT_WILL, _formation.lead)
			var run := CombatOrder.new(CombatOrder.Kind.WITHDRAW)
			run.point = _centre_of(hostiles, _withdraw_from if _withdraw_from != Vector2.ZERO else _formation.lead.global_position)
			_set_order(_formation.lead, run)


## Where an intercepting unit's leader heads: the nearest big enemy ship (tier 2 and up) if
## there is one, else the nearest enemy of any kind, else where it is.
func _intercept_point(hostiles: Array[Combatant]) -> Vector2:
	for other in hostiles:  # (nearest first)
		if other.ship_class != null and other.ship_class.tier >= 2:
			return other.global_position
	return hostiles[0].global_position if not hostiles.is_empty() else _formation.lead.global_position


## The ships this commander gives orders to: the formation's own, not a squadron's leader
## (the squadron's commander has that one).
func _own_ships() -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in _formation.get_ships():
		if ship.led_formation == null or ship.led_formation == _formation:
			result.append(ship)
	return result


## Own ships with weapons, strongest first.
func _fighters() -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in _own_ships():
		var combatant: Combatant = ship.get_combatant()
		if combatant != null and combatant.is_armed():
			result.append(ship)
	result.sort_custom(func(a: NpcShip, b: NpcShip) -> bool: return a.get_combatant().rating > b.get_combatant().rating)
	return result


func _order_all(kind: CombatOrder.Kind, except: NpcShip = null) -> void:
	for ship in _own_ships():
		if ship == except:
			continue
		_set_order(ship, CombatOrder.new(kind))


func _set_order(ship: NpcShip, order: CombatOrder) -> void:
	TargetAllocator.give(ship, order)


func _clear_orders() -> void:
	if _formation == null or not is_instance_valid(_formation):
		return
	for ship in _own_ships():
		_set_order(ship, null)


## A convoy: the freighters (and anything unarmed) fly on; the armed escorts guard them.
func _defend(picture: TacticalPicture, hostiles: Array[Combatant]) -> void:
	var protectees := _protectees()
	var escorts: Array[NpcShip] = []
	for ship in _fighters():
		if not protectees.has(ship):
			escorts.append(ship)
	_guard_with(picture, hostiles, protectees, escorts)


## `escorts` guard `protectees`: each guards the nearest, and takes only enemies within 1.5
## times the guard radius of any of them (the ones attacking what it guards count most).
## The rest of the unit's ships keep their places and fire at will.
func _guard_with(picture: TacticalPicture, hostiles: Array[Combatant], protectees: Array[NpcShip], escorts: Array[NpcShip]) -> void:
	for ship in _own_ships():
		if not escorts.has(ship):
			_set_order(ship, CombatOrder.new(CombatOrder.Kind.FIRE_AT_WILL))
	var threats: Array[Combatant] = []
	for other in hostiles:
		for protectee in protectees:
			if is_instance_valid(protectee) and other.global_position.distance_to(protectee.global_position) <= profile.guard_radius * 1.5:
				threats.append(other)
				break
	var counts := {}
	for ship in escorts:
		var guarded := _nearest_ship(protectees, ship.global_position)
		if guarded == null:
			continue
		if threats.is_empty():
			_set_order(ship, CombatOrder.new(CombatOrder.Kind.FIRE_AT_WILL))
		else:
			var orders := TargetAllocator.assign(picture, hostiles, [ship] as Array[NpcShip], profile, counts, guarded, threats)
			_set_order(ship, orders[ship])


## What a convoy protects: its cargo ships, or its leader if it has none.
func _protectees() -> Array[NpcShip]:
	var result: Array[NpcShip] = []
	for ship in _formation.get_ships():
		var model: ShipStats = ship.ship_type.stats
		if model.ship_class != null and model.ship_class.carries_cargo():
			result.append(ship)
	if result.is_empty():
		result.append(_formation.lead)
	return result


# ------------------------------------------------------------------- events

func _on_member_lost(ship, _reason: StringName) -> void:
	if is_instance_valid(ship) and not ship.is_queued_for_deletion() and ship.get_pilot() != null:
		ship.get_pilot().set_order(null)  # (it is on its own now, or gone)
	_reallocate_soon = true  # (the targets are shared out again straight away)


func _on_leader_changed(old_lead, _new_lead) -> void:
	if is_instance_valid(old_lead) and not old_lead.is_queued_for_deletion() and old_lead.get_pilot() != null:
		old_lead.get_pilot().set_order(null)
	_reallocate_soon = true


func _on_dissolved() -> void:
	_release_squadrons()
	_clear_orders()


# ------------------------------------------------------------------- helpers

func _rating_of(ships: Array[NpcShip]) -> float:
	var total := 0.0
	for ship in ships:
		total += CombatRating.of(ship.ship_type.stats)
	return total


func _rating_of_combatants(combatants: Array[Combatant], armed_only: bool) -> float:
	var total := 0.0
	for other in combatants:
		if not armed_only or other.is_armed():
			total += other.rating
	return total


## The middle of the armed ships in `hostiles` (all of them if none is armed), or `fallback`.
func _centre_of(hostiles: Array[Combatant], fallback: Vector2) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for other in hostiles:
		if other.is_armed():
			total += other.global_position
			count += 1
	if count == 0:
		for other in hostiles:
			total += other.global_position
			count += 1
	return total / count if count > 0 else fallback


func _nearest_distance(hostiles: Array[Combatant]) -> float:
	var best := INF
	for ship in _formation.get_ships():
		for other in hostiles:
			best = minf(best, ship.global_position.distance_to(other.global_position))
	return best


func _nearest_ship(ships: Array[NpcShip], point: Vector2) -> NpcShip:
	var best: NpcShip = null
	var best_distance := INF
	for ship in ships:
		if not is_instance_valid(ship):
			continue
		var distance := ship.global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = ship
	return best
