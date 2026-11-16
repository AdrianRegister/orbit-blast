class_name ShipPilot
extends RefCounted
## The pilot of one NPC ship: decides who to fight (or whether to run) and how, and
## shoots. It is owned by the NpcShip, flies nothing itself and has no say over
## groups: it produces a SteeringIntent that the ship flies with its own physics, and
## fires through the ship's Combatant with the same weapons and rules as the player.
## It acts for a ship that is on its own (see NpcShip.is_free_agent). A ship in a
## formation waits for its unit's commander (UnitCommander), which gives its pilot a
## CombatOrder: fire at will from its slot, or take control and fight, guard, move or
## withdraw. (Fleets get theirs in step 5.)
##
## It thinks every AiTuning.decision_interval seconds and flies and fires every frame.
## What it does:
##   - sees the hostile ships around it (TacticalPicture, Hostility) within its
##     doctrine's sensor range;
##   - ATTACK: picks the best target (TargetScorer), flies at it in its doctrine's
##     style (dogfight, skirmish or standoff, CombatSteering), weaves when it is under
##     attack, and fires what would hit (Combatant.fire_at_will);
##   - BATTLE LINE: with armed friends nearby, a cruiser or capital ship (ANCHOR) picks
##     its target from anywhere in sight (by threat, size and distance: it cannot hurt
##     fighters, so it goes for big ships) and advances on it, at a fraction of its top
##     speed so that its screen keeps up, until it is at its fighting range. With nothing
##     it can hurt it SUPPORTS: if its own fighters are fighting, it flies up to within
##     point-defence range of what they are fighting (SUPPORT), so that its point defence
##     covers them; failing that it holds (HOLD). Fighters and frigates (SCREEN) fight
##     around the nearest anchor, or the middle of their friends, and are drawn back to it
##     (CombatDoctrine.LineRole, AiTuning "Battle line"). With no friends nearby a ship
##     fights wherever its target goes;
##   - RETREAT: runs, still firing what it can, when its hull is below the doctrine's
##     limit, jumping out of the system if there is a way out;
##   - FLEE: the same for a ship with no doctrine (a freighter): it never fights;
##   - when it has seen no enemy for AiTuning.calm_time it stands down, and the ship
##     goes back to what it was doing;
##   - under an order: ENGAGE is ATTACK with the commander's target preferred, GUARD is
##     ATTACK tethered to the ship it protects (it takes no target further from it than
##     the order's radius), MOVE flies to a point, and WITHDRAW runs for the exit, both at
##     the formation's limits.

enum Mode { IDLE, ATTACK, RETREAT, FLEE, HOLD, MOVE, SUPPORT }

## How hard a ship with no doctrine weaves while it runs (a fraction of its top speed).
const FLEE_WEAVE := 0.25

var mode: Mode = Mode.IDLE
## What the unit's commander has told this pilot to do (null: nothing, or it is a free agent).
var order: CombatOrder
## What the pilot wants the ship to do this frame (valid while mode is not IDLE).
var intent := SteeringIntent.new()
var tuning: AiTuning
## How this kind of ship fights; null for a ship that never fights.
var doctrine: CombatDoctrine

var _ship: NpcShip
var _combatant: Combatant
var _think_left: float = 0.0
var _calm_for: float = 0.0
## The hostile ships it knows of that could hurt it (for running and weaving).
var _threats: Array = []
var _since_hit: float = 1000.0
var _since_shot: float = 0.0
var _commit_left: float = 0.0
var _jink_side: float = 1.0
var _jink_left: float = 0.0
var _strafe_side: float = 1.0
var _strafe_left: float = 0.0
var _status_shown: String = ""
## Seconds this pilot has been alive (the clock the give-up times are measured on).
var _clock: float = 0.0
## Where the ship was when it began this fight (what the pursuit leash is measured from).
var _engage_origin: Vector2 = Vector2.ZERO
## Targets it has given up on: Combatant -> the time (_clock) it ignores them until.
var _ignored: Dictionary = {}
## The role in the battle line as of the last decision (FREE: no friends nearby).
var _role: CombatDoctrine.LineRole = CombatDoctrine.LineRole.FREE
## Where an anchor with nothing to shoot goes to cover its fighters (see _find_support).
var _has_support: bool = false
var _support_point: Vector2 = Vector2.ZERO
## What a screen ship stays near (its anchor, or the middle of its friends), if it has one.
var _has_tether: bool = false
var _tether_point: Vector2 = Vector2.ZERO


func setup(ship: NpcShip, combatant: Combatant) -> void:
	_ship = ship
	_combatant = combatant
	tuning = AiTuning.shared()
	var ship_class: ShipClass = ship.ship_type.stats.ship_class
	doctrine = ship_class.get_doctrine() if ship_class != null else null
	_think_left = randf() * tuning.decision_interval  # (so ships do not all think on the same frame)
	_jink_side = 1.0 if randf() < 0.5 else -1.0
	_strafe_side = _jink_side
	combatant.damaged.connect(func(_result: DamageResult, _hit: Hit) -> void: _since_hit = 0.0)


func is_active() -> bool:
	return mode != Mode.IDLE


## Takes an order from the commander (null cancels it). One that does not take control
## of the ship hands it back to its slot at once.
func set_order(new_order: CombatOrder) -> void:
	var was_controlling := controls_ship()
	order = new_order
	if was_controlling and not controls_ship() and mode != Mode.IDLE:
		_stand_down()
	if order == null:
		_combatant.set_target(null)


## Whether an order has put the pilot in charge of flying the ship.
func controls_ship() -> bool:
	return order != null and order.takes_control()


## Whether the ship keeps its formation's speed and turn limits (see NpcShip._engaged).
func keeps_formation_limits() -> bool:
	return order != null and order.keeps_formation_limits()


func get_intent() -> SteeringIntent:
	return intent


## Called by the ship at the start of every physics frame.
func tick(delta: float) -> void:
	if order != null and order.kind == CombatOrder.Kind.FIRE_AT_WILL:
		_tick_fire_at_will(delta)
		return
	if not (_ship.is_free_agent() or controls_ship()) or not _ship.can_fight():
		if mode != Mode.IDLE:
			_stand_down()
		return
	_clock += delta
	_since_hit += delta
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = tuning.decision_interval
		_decide()
	if mode == Mode.IDLE:
		return
	if _ship.state != NpcShip.State.ENGAGED:
		_ship.engage()
		if _ship.state != NpcShip.State.ENGAGED:
			_stand_down()
			return
	_update_timers(delta)
	match mode:
		Mode.ATTACK:
			_steer_attack()
		Mode.HOLD:
			_steer_hold()
		Mode.MOVE:
			_steer_move()
		Mode.SUPPORT:
			_steer_support()
		_:
			_steer_flee()
	if doctrine != null and _combatant.get_target() != null:
		if _combatant.fire_at_will(doctrine.fire_tolerance_degrees) > 0:
			_since_shot = 0.0
		else:
			_since_shot += delta


## A ship that keeps its place in a formation shoots what comes in reach, without
## flying: it picks the nearest hostile ship its weapons reach and fires what is aimed.
func _tick_fire_at_will(delta: float) -> void:
	if doctrine == null:
		return
	_think_left -= delta
	if _think_left <= 0.0:
		_think_left = tuning.decision_interval
		_combatant.set_target(_nearest_in_reach())
	if _combatant.get_target() != null:
		_combatant.fire_at_will(doctrine.fire_tolerance_degrees)


## The nearest hostile ship within reach of the ship's weapons, or null. `hostiles` (nearest
## first) saves a second look when the caller has the list.
func _nearest_in_reach(hostiles: Array[Combatant] = []) -> Combatant:
	var reach := _combatant.weapons.get_longest_range()
	if hostiles.is_empty():
		var picture := _picture()
		if picture == null:
			return null
		hostiles = picture.hostiles_near(_combatant, reach)
	for other in hostiles:
		if _combatant.global_position.distance_to(other.global_position) <= reach:
			return other
	return null


# ----------------------------------------------------------------- deciding

func _decide() -> void:
	var picture := _picture()
	if picture == null:
		return
	var sensor := _sensor_range()
	var hostiles := picture.hostiles_near(_combatant, sensor)
	if order != null and (order.kind == CombatOrder.Kind.MOVE or order.kind == CombatOrder.Kind.WITHDRAW):
		_decide_ordered_move(hostiles)
		return
	if doctrine == null:
		_decide_unarmed(hostiles)
		return
	if hostiles.is_empty() and _commanded_target() == null:
		_combatant.set_target(null)
		_threats = []
		_calm_for += tuning.decision_interval
		if mode != Mode.IDLE and _calm_for >= tuning.calm_time:
			_stand_down()
		return
	_calm_for = 0.0
	_threats = _armed_in(hostiles)
	_update_line(picture)
	var target: Combatant = _choose_target(picture, hostiles, sensor)
	if order == null and _role == CombatDoctrine.LineRole.FREE and mode == Mode.ATTACK and target != null and _ship.global_position.distance_to(_engage_origin) > tuning.pursuit_leash:
		_ignored[target] = _clock + tuning.give_up_seconds  # (it will not be caught: let it go)
		_stand_down()
		return
	_combatant.set_target(target)
	if not _fights_to_the_death() and (mode == Mode.RETREAT or _hull_fraction() < doctrine.retreat_hull_fraction):
		_set_mode(Mode.RETREAT)  # (it runs until it is safe)
	elif target != null:
		_set_mode(Mode.ATTACK)
	elif _role == CombatDoctrine.LineRole.ANCHOR and _find_support(picture):
		_set_mode(Mode.SUPPORT)  # (nothing it can hurt, but its fighters are fighting: it goes to cover them)
	elif _role != CombatDoctrine.LineRole.FREE:
		_set_mode(Mode.HOLD)  # (in a line, it keeps its place rather than wander off)
	elif mode == Mode.ATTACK:
		_stand_down()  # nothing it can hurt is left in sight


## An order to move or to withdraw: the pilot goes where it was told (or runs), shooting
## what is in reach on the way. The commander decides when it stops.
func _decide_ordered_move(hostiles: Array[Combatant]) -> void:
	_calm_for = 0.0
	_threats = _armed_in(hostiles)
	_combatant.set_target(_nearest_in_reach(hostiles) if doctrine != null else null)
	_set_mode(Mode.MOVE if order.kind == CombatOrder.Kind.MOVE else Mode.RETREAT)


## A ship that never fights runs from armed enemies close by.
func _decide_unarmed(hostiles: Array[Combatant]) -> void:
	var close: Array = []
	for other in hostiles:
		if other.is_armed() and _combatant.global_position.distance_to(other.global_position) <= tuning.flee_alarm_range:
			close.append(other)
	if not close.is_empty():
		_threats = close
		_calm_for = 0.0
		_set_mode(Mode.FLEE)
		return
	_threats = []
	_calm_for += tuning.decision_interval
	if mode != Mode.IDLE and _calm_for >= tuning.calm_time:
		_stand_down()


func _choose_target(picture: TacticalPicture, hostiles: Array[Combatant], sensor: float) -> Combatant:
	var me := ShooterInfo.from_combatant(_combatant)
	var candidates: Array[TargetInfo] = []
	var commanded := _commanded_target()
	for other in hostiles:
		if _is_ignored(other) or (other != commanded and not _in_reach_of_line(other)):
			continue  # (the commander's choice counts wherever it is)
		candidates.append(_describe(other, picture, me))
	if commanded != null and not hostiles.has(commanded):
		# (the commander's choice counts, though this ship cannot see so far itself)
		candidates.append(_describe(commanded, picture, me))
		sensor = maxf(sensor, _combatant.global_position.distance_to(commanded.global_position))
	return TargetScorer.choose(me, doctrine, candidates, sensor, _combatant.get_target()) as Combatant


## A ship its commander has ordered to fight or guard does not run when it is hurt: the
## unit stands or withdraws as one (a leader that jumped out would take the whole unit with
## it), and a ship that is lost is replaced by promotion.
func _fights_to_the_death() -> bool:
	return order != null and (order.kind == CombatOrder.Kind.ENGAGE or order.kind == CombatOrder.Kind.GUARD)


## The target the commander named, if it is still there.
func _commanded_target() -> Combatant:
	if order != null and is_instance_valid(order.target) and order.target.is_alive():
		return order.target
	return null


func _describe(other: Combatant, picture: TacticalPicture, me: ShooterInfo) -> TargetInfo:
	var info := TargetInfo.from_combatant(other, _combatant, me, picture.count_targeters(other))
	if order != null:
		info.is_focus = order.target == other
	return info


## Works out the ship's place in a battle line: its doctrine's role if it has armed
## friends nearby, else FREE. A screen ship finds what to stay near.
func _update_line(picture: TacticalPicture) -> void:
	var friends := picture.friends_near(_combatant, tuning.line_join_range)
	_role = doctrine.line_role if not friends.is_empty() else CombatDoctrine.LineRole.FREE
	_has_tether = false
	if order != null and order.kind == CombatOrder.Kind.GUARD and is_instance_valid(order.protectee):
		_role = CombatDoctrine.LineRole.SCREEN  # (an escort screens the ship it guards, wherever it is)
		_tether_point = order.protectee.global_position
		_has_tether = true
		return
	if order != null and order.kind == CombatOrder.Kind.ENGAGE and _role == CombatDoctrine.LineRole.SCREEN:
		_role = CombatDoctrine.LineRole.FREE  # (the commander's order replaces the battle line: it owns the leash)
	if _role == CombatDoctrine.LineRole.SCREEN:
		var anchor := picture.nearest_anchor(friends)
		_tether_point = anchor.global_position if anchor != null else picture.centre_of(_combatant, friends)
		_has_tether = true


## Whether the pilot may pick `other` from where its line stands: a screen ship only what
## is within the screen radius of what it stays near. An anchor may pick anything in sight.
func _in_reach_of_line(other: Combatant) -> bool:
	if _role == CombatDoctrine.LineRole.SCREEN and _has_tether:
		return _tether_point.distance_to(other.global_position) <= _tether_radius()
	return true


## Changes mode, remembering where a fight began when the pilot takes over.
func _set_mode(new_mode: Mode) -> void:
	if mode == Mode.IDLE and new_mode != Mode.IDLE:
		_engage_origin = _ship.global_position
	mode = new_mode


## Whether the pilot has given up on `other` (and for how long yet).
func _is_ignored(other: Combatant) -> bool:
	if not _ignored.has(other):
		return false
	if _ignored[other] <= _clock or not is_instance_valid(other):
		_ignored.erase(other)
		return false
	return true


func _stand_down() -> void:
	mode = Mode.IDLE
	_has_support = false
	_role = CombatDoctrine.LineRole.FREE
	_has_tether = false
	_threats = []
	_calm_for = 0.0
	_combatant.set_target(null)
	_status_shown = ""
	_ship.disengage()


# ------------------------------------------------------------------ flying

func _update_timers(delta: float) -> void:
	_jink_left -= delta
	if _jink_left <= 0.0:
		_jink_side = -_jink_side
		_jink_left = randf_range(tuning.jink_period_min, tuning.jink_period_max)
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_side = -_strafe_side
		_strafe_left = tuning.strafe_period
	_commit_left = maxf(_commit_left - delta, 0.0)
	if doctrine != null and _since_shot > tuning.reposition_limit and _commit_left <= 0.0:
		_commit_left = tuning.commit_time  # (stop manoeuvring and attack directly for a while)
		_since_shot = 0.0


func _steer_attack() -> void:
	var target := _combatant.get_target()
	if target == null:
		intent = SteeringIntent.new(_ship.velocity)
		return
	var stats := _ship.ship_type.stats
	var position := _ship.global_position
	var top := stats.max_speed
	var target_pos := target.global_position
	var target_velocity := target.get_velocity()
	var weapons := _combatant.weapons
	var preferred := doctrine.preferred_range_fraction * weapons.get_effective_range()
	var brake := stats.thrust * tuning.brake_fraction
	var back := top * tuning.max_back_speed_fraction
	var lead := CombatSteering.lead_point(position, _ship.velocity, target_pos, target_velocity, weapons.get_effective_projectile_speed())
	var wanted: Vector2
	match doctrine.style:
		CombatDoctrine.Style.DOGFIGHT:
			var forward := CombatSteering.forward_of(target_velocity, target.get_heading())
			var off_tail := CombatSteering.angle_off_tail(position, target_pos, forward)
			var weight := CombatSteering.rear_weight(doctrine.rear_attack_weight, off_tail, deg_to_rad(tuning.tail_cone_degrees), _commit_left > 0.0)
			var tail := CombatSteering.trail_point(target_pos, target_velocity, target.get_heading(), preferred)
			wanted = CombatSteering.close_velocity(position, target_pos.lerp(tail, weight), target_velocity, preferred * (1.0 - weight), top, brake, back)
		CombatDoctrine.Style.SKIRMISH:
			wanted = CombatSteering.close_velocity(position, target_pos, target_velocity, preferred, top, brake, back)
			wanted += CombatSteering.strafe_velocity(position, target_pos, doctrine.strafe * tuning.strafe_speed, _strafe_side)
		_:
			wanted = CombatSteering.close_velocity(position, target_pos, target_velocity, preferred, top, brake, back)
	if _role == CombatDoctrine.LineRole.ANCHOR:
		wanted = _cap_advance(wanted, target_pos - position, top)  # (it closes slowly, so its screen keeps up)
	elif _has_tether:
		wanted = CombatSteering.tether_velocity(position, wanted, _tether_point, _tether_radius(), tuning.screen_soft_band, top)
	if _is_under_attack():
		wanted += CombatSteering.evade_velocity(position, _nearest_threat_position(target_pos), doctrine.evasion, tuning.evade_speed, _jink_side)
	intent = SteeringIntent.new(wanted.limit_length(top), (lead - position).angle())
	_show_status("Engaging %s" % target.display_name)


## Keeps the ship's place in the line with nothing to shoot or cover: an anchor where it is,
## a screen ship within half its radius of what it stays near, nose toward the enemy.
func _steer_hold() -> void:
	var stats := _ship.ship_type.stats
	var position := _ship.global_position
	var point := position
	var hold := 0.0
	if _has_tether:
		point = _tether_point
		hold = _tether_radius() * 0.5
	var wanted := CombatSteering.close_velocity(position, point, Vector2.ZERO, hold, stats.max_speed, stats.thrust * tuning.brake_fraction, stats.max_speed * tuning.max_back_speed_fraction)
	var aim := _combatant.get_heading()
	var threats := _threat_positions()  # (it skips the ones destroyed since the last decision)
	if not threats.is_empty():
		aim = (threats[0] - position).angle()
	intent = SteeringIntent.new(wanted.limit_length(stats.max_speed), aim)
	_show_status("Holding the line")


## An anchor with nothing it can hurt, whose fighters are engaged, flies to within point-
## defence range of what they are fighting (`AiTuning.support_range_fraction` of it), at the
## anchors' advancing speed, nose toward it, so that its point defence covers them.
func _steer_support() -> void:
	var stats := _ship.ship_type.stats
	var position := _ship.global_position
	var top := stats.max_speed
	var hold := _combatant.weapons.get_point_defence_range() * tuning.support_range_fraction
	var wanted := CombatSteering.close_velocity(position, _support_point, Vector2.ZERO, hold, top,
			stats.thrust * tuning.brake_fraction, top * tuning.max_back_speed_fraction)
	wanted = _cap_advance(wanted, _support_point - position, top)
	intent = SteeringIntent.new(wanted.limit_length(top), (_support_point - position).angle())
	_show_status("Supporting the fighters")


## Finds where an anchor should go to cover its fighters: the target of the nearest friendly
## fighter that is fighting. False if it has no point defence, or no fighter of its own is
## fighting. (Sets _support_point.)
func _find_support(picture: TacticalPicture) -> bool:
	_has_support = false
	if not _combatant.weapons.has_point_defence():
		return false
	var best := INF
	for friend in picture.friends_near(_combatant, tuning.line_join_range):
		if not friend.evasive:
			continue  # (fighters are what point defence protects)
		var theirs := friend.get_target()
		if theirs == null or not is_instance_valid(theirs) or not theirs.is_alive():
			continue
		var distance := _combatant.global_position.distance_to(theirs.global_position)
		if distance < best:
			best = distance
			_support_point = theirs.global_position
			_has_support = true
	return _has_support


## An anchor does not rush: when `wanted` heads toward `toward` it is held to
## `AiTuning.anchor_advance_speed` of the ship's top speed.
func _cap_advance(wanted: Vector2, toward: Vector2, top: float) -> Vector2:
	var cap := top * tuning.anchor_advance_speed
	if wanted.dot(toward) > 0.0 and wanted.length() > cap:
		return wanted.normalized() * cap
	return wanted


## Flies to the point the commander named (a leader closing on the enemy).
func _steer_move() -> void:
	var stats := _ship.ship_type.stats
	var top := _ship.effective_max_speed()
	var wanted := CombatSteering.close_velocity(_ship.global_position, order.point, Vector2.ZERO, 0.0, top,
			stats.thrust * tuning.brake_fraction, top * tuning.max_back_speed_fraction)
	intent = SteeringIntent.new(wanted.limit_length(top), NAN)
	_show_status("Closing on the enemy")


func _steer_flee() -> void:
	var top := _ship.effective_max_speed() if keeps_formation_limits() else _ship.ship_type.stats.max_speed
	var position := _ship.global_position
	var threats := _threat_positions()
	if order != null and order.kind == CombatOrder.Kind.WITHDRAW:
		threats.append(order.point)  # (the commander can see the enemy from further off than the pilot can)
	var exit := Vector2.ZERO
	if _ship.can_flee_by_jump():
		exit = CombatSteering.best_exit(position, threats, _ship.get_exit_bearings())
		if _ship.can_jump():
			_ship.begin_jump_out()
			return
	var wanted := CombatSteering.flee_velocity(position, threats, exit, top)
	var evasion := doctrine.evasion if doctrine != null else FLEE_WEAVE
	if wanted.length() > 0.0 and not threats.is_empty() and not keeps_formation_limits():  # (a leader does not weave: its unit follows it)
		wanted += CombatSteering.evade_velocity(position, threats[0], evasion, tuning.evade_speed, _jink_side)
	intent = SteeringIntent.new(wanted.limit_length(top), NAN)
	_show_status("Retreating" if mode == Mode.RETREAT else "Fleeing")


# ------------------------------------------------------------------ helpers

## How far a screen ship may stray from what it stays near: a guard's order says, else
## the shared screen radius.
func _tether_radius() -> float:
	if order != null and order.kind == CombatOrder.Kind.GUARD and order.radius > 0.0:
		return order.radius
	return tuning.screen_radius


func _picture() -> TacticalPicture:
	return _ship.get_tree().get_first_node_in_group(TacticalPicture.GROUP) as TacticalPicture


func _sensor_range() -> float:
	var reach := _combatant.weapons.get_longest_range()
	if doctrine == null:
		return tuning.flee_alarm_range
	return doctrine.sensor_range(reach)


func _hull_fraction() -> float:
	var defence := _combatant.health.state
	return defence.hull / defence.max_hull if defence.max_hull > 0.0 else 1.0


## The ones of `ships` that are armed.
func _armed_in(ships: Array[Combatant]) -> Array:
	var result: Array = []
	for other in ships:
		if other.is_armed():
			result.append(other)
	return result


func _threat_positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for other in _threats:
		if is_instance_valid(other) and other.is_alive():
			result.append(other.global_position)
	return result


## Whether it has been hit lately or something is aiming at it: time to weave.
func _is_under_attack() -> bool:
	if _since_hit < tuning.damage_alarm_seconds:
		return true
	var picture := _picture()
	return picture != null and not picture.targeters_of(_combatant).is_empty()


## Where to weave away from: the nearest ship targeting it, else the target.
func _nearest_threat_position(fallback: Vector2) -> Vector2:
	var picture := _picture()
	var best := fallback
	var best_distance := INF
	if picture != null:
		for other in picture.targeters_of(_combatant):
			var distance := _ship.global_position.distance_to(other.global_position)
			if distance < best_distance:
				best_distance = distance
				best = other.global_position
	return best


func _show_status(text: String) -> void:
	if text != _status_shown:
		_status_shown = text
		_ship.set_combat_status(text)
