class_name ShipPilot
extends RefCounted
## The pilot of one NPC ship: decides who to fight (or whether to run) and how, and
## shoots. It is owned by the NpcShip, flies nothing itself and has no say over
## groups: it produces a SteeringIntent that the ship flies with its own physics, and
## fires through the ship's Combatant with the same weapons and rules as the player.
## It only acts for a ship that is on its own (see NpcShip.is_free_agent); ships in
## formations and fleets are left to their commanders (Phase 3.3, steps 4 and 5).
##
## It thinks every AiTuning.decision_interval seconds and flies and fires every frame.
## What it does:
##   - sees the hostile ships around it (TacticalPicture, Hostility) within its
##     doctrine's sensor range;
##   - ATTACK: picks the best target (TargetScorer), flies at it in its doctrine's
##     style (dogfight, skirmish or standoff, CombatSteering), weaves when it is under
##     attack, and fires what would hit (Combatant.fire_at_will);
##   - BATTLE LINE: with armed friends nearby, a cruiser or capital ship (ANCHOR) holds the
##     place where the fight reached it and only shoots what is in reach of it (creeping
##     up on the enemy, slowly and only so far, when it has nothing to shoot), and
##     fighters and frigates (SCREEN) fight around the nearest anchor, or the middle of
##     their friends, and are drawn back to it (CombatDoctrine.LineRole, AiTuning "Battle
##     line"). With no friends nearby a ship fights wherever its target goes. HOLD is a
##     ship in a line with nothing it can shoot: it keeps its place;
##   - RETREAT: runs, still firing what it can, when its hull is below the doctrine's
##     limit, jumping out of the system if there is a way out;
##   - FLEE: the same for a ship with no doctrine (a freighter): it never fights;
##   - when it has seen no enemy for AiTuning.calm_time it stands down, and the ship
##     goes back to what it was doing.

enum Mode { IDLE, ATTACK, RETREAT, FLEE, HOLD }

## How hard a ship with no doctrine weaves while it runs (a fraction of its top speed).
const FLEE_WEAVE := 0.25

var mode: Mode = Mode.IDLE
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
## An anchor's fixed place, once it has taken one up (it never moves while it holds it).
var _anchored: bool = false
var _anchor_point: Vector2 = Vector2.ZERO
## Seconds an anchored ship has had nothing to shoot.
var _idle_anchored_for: float = 0.0
## An anchor with nothing in reach is creeping up on the enemy: its place moves toward
## the target, slowly, until the target is in reach or the place is `anchor_advance_limit`
## from where the line first formed (`_line_origin`).
var _creeping: bool = false
var _creep_spent: bool = false
var _line_origin: Vector2 = Vector2.ZERO
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


func get_intent() -> SteeringIntent:
	return intent


## Called by the ship at the start of every physics frame.
func tick(delta: float) -> void:
	if not _ship.is_free_agent() or not _ship.can_fight():
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
	_creep(delta)
	match mode:
		Mode.ATTACK:
			_steer_attack()
		Mode.HOLD:
			_steer_hold()
		_:
			_steer_flee()
	if doctrine != null and _combatant.get_target() != null:
		if _combatant.fire_at_will(doctrine.fire_tolerance_degrees) > 0:
			_since_shot = 0.0
		else:
			_since_shot += delta


# ----------------------------------------------------------------- deciding

func _decide() -> void:
	var picture := _picture()
	if picture == null:
		return
	var sensor := _sensor_range()
	var hostiles := picture.hostiles_near(_combatant, sensor)
	if doctrine == null:
		_decide_unarmed(hostiles)
		return
	if hostiles.is_empty():
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
	_update_anchor(target)
	if _role == CombatDoctrine.LineRole.FREE and mode == Mode.ATTACK and target != null and _ship.global_position.distance_to(_engage_origin) > tuning.pursuit_leash:
		_ignored[target] = _clock + tuning.give_up_seconds  # (it will not be caught: let it go)
		_stand_down()
		return
	_combatant.set_target(target)
	if mode == Mode.RETREAT or _hull_fraction() < doctrine.retreat_hull_fraction:
		_set_mode(Mode.RETREAT)  # (it runs until it is safe)
	elif target != null:
		_set_mode(Mode.ATTACK)
	elif _role != CombatDoctrine.LineRole.FREE:
		_set_mode(Mode.HOLD)  # (in a line, it keeps its place rather than wander off)
	elif mode == Mode.ATTACK:
		_stand_down()  # nothing it can hurt is left in sight


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
	for other in hostiles:
		if _is_ignored(other) or not _in_reach_of_line(other):
			continue
		candidates.append(TargetInfo.from_combatant(other, _combatant, me, picture.count_targeters(other)))
	return TargetScorer.choose(me, doctrine, candidates, sensor, _combatant.get_target()) as Combatant


## Works out the ship's place in a battle line: its doctrine's role if it has armed
## friends nearby, else FREE. A screen ship finds what to stay near.
func _update_line(picture: TacticalPicture) -> void:
	var friends := picture.friends_near(_combatant, tuning.line_join_range)
	_role = doctrine.line_role if not friends.is_empty() else CombatDoctrine.LineRole.FREE
	_has_tether = false
	if _role == CombatDoctrine.LineRole.SCREEN:
		var anchor := picture.nearest_anchor(friends)
		_tether_point = anchor.global_position if anchor != null else picture.centre_of(_combatant, friends)
		_has_tether = true
	elif _role != CombatDoctrine.LineRole.ANCHOR:
		_anchored = false
		_creeping = false


## Whether the pilot may shoot `other` from where its line stands: an anchored ship
## only what is in reach of its place, a screen ship only what is within the screen
## radius of what it stays near.
func _in_reach_of_line(other: Combatant) -> bool:
	if _role == CombatDoctrine.LineRole.ANCHOR and _anchored and not _creeping:
		return _anchor_point.distance_to(other.global_position) <= _anchor_reach()
	if _role == CombatDoctrine.LineRole.SCREEN and _has_tether:
		return _tether_point.distance_to(other.global_position) <= tuning.screen_radius
	return true


## An anchor takes up its place when something it can shoot is in reach, or when it is
## attacked (it does not leave to hunt before the line has formed). Once placed, if it has
## had nothing to shoot for `anchor_advance_delay`, even under fire from ships it cannot
## hit, it creeps up on the best target it can hurt (see _creep) and takes up a new place
## when that is in reach, or stops at the advance limit.
func _update_anchor(target: Combatant) -> void:
	if _role != CombatDoctrine.LineRole.ANCHOR:
		return
	var in_reach := target != null and _ship.global_position.distance_to(target.global_position) <= _anchor_reach()
	if not _anchored:
		if in_reach or _is_under_attack():
			_anchored = true
			_anchor_point = _ship.global_position
			_line_origin = _anchor_point
			_idle_anchored_for = 0.0
			_creeping = false
			_creep_spent = false
		return
	if _creeping:
		if in_reach:
			_creeping = false  # (in range: the line forms here)
			_anchor_point = _ship.global_position
			_idle_anchored_for = 0.0
		return
	if in_reach:
		_idle_anchored_for = 0.0
	elif not _creep_spent:
		_idle_anchored_for += tuning.decision_interval
		if _idle_anchored_for >= tuning.anchor_advance_delay:
			_creeping = true


## Moves a creeping anchor's place toward its target at `anchor_advance_speed` of its top
## speed (the ship follows it, so the screen can keep up), and stops at the limit.
func _creep(delta: float) -> void:
	if not _creeping:
		return
	var target := _combatant.get_target()
	if target == null:
		return
	if _anchor_point.distance_to(_line_origin) >= tuning.anchor_advance_limit:
		_creeping = false
		_creep_spent = true  # (it holds at the limit)
		return
	var step := _ship.ship_type.stats.max_speed * tuning.anchor_advance_speed * delta
	_anchor_point = _anchor_point.move_toward(target.global_position, step)


func _anchor_reach() -> float:
	return _combatant.weapons.get_longest_range() * tuning.anchor_reach_margin


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
	_anchored = false
	_creeping = false
	_creep_spent = false
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
	if _role == CombatDoctrine.LineRole.ANCHOR and _anchored:
		wanted = CombatSteering.close_velocity(position, _anchor_point, Vector2.ZERO, 0.0, top, brake, back)  # (it holds its place: the target comes to it)
	elif _has_tether:
		wanted = CombatSteering.tether_velocity(position, wanted, _tether_point, tuning.screen_radius, tuning.screen_soft_band, top)
	if _is_under_attack():
		wanted += CombatSteering.evade_velocity(position, _nearest_threat_position(target_pos), doctrine.evasion, tuning.evade_speed, _jink_side)
	intent = SteeringIntent.new(wanted.limit_length(top), (lead - position).angle())
	_show_status("Engaging %s" % target.display_name)


## Keeps the ship's place in the line with nothing to shoot: an anchor at its place, a
## screen ship within half its radius of what it stays near, nose toward the enemy.
func _steer_hold() -> void:
	var stats := _ship.ship_type.stats
	var position := _ship.global_position
	var point := position
	var hold := 0.0
	if _role == CombatDoctrine.LineRole.ANCHOR:
		if not _anchored:
			_anchored = true
			_anchor_point = position
		point = _anchor_point
	elif _has_tether:
		point = _tether_point
		hold = tuning.screen_radius * 0.5
	var wanted := CombatSteering.close_velocity(position, point, Vector2.ZERO, hold, stats.max_speed, stats.thrust * tuning.brake_fraction, stats.max_speed * tuning.max_back_speed_fraction)
	var aim := _combatant.get_heading()
	var threats := _threat_positions()  # (it skips the ones destroyed since the last decision)
	if not threats.is_empty():
		aim = (threats[0] - position).angle()
	intent = SteeringIntent.new(wanted.limit_length(stats.max_speed), aim)
	_show_status("Holding the line")


func _steer_flee() -> void:
	var top := _ship.ship_type.stats.max_speed
	var position := _ship.global_position
	var threats := _threat_positions()
	var exit := Vector2.ZERO
	if _ship.can_flee_by_jump():
		exit = CombatSteering.best_exit(position, threats, _ship.get_exit_bearings())
		if _ship.can_jump():
			_ship.begin_jump_out()
			return
	var wanted := CombatSteering.flee_velocity(position, threats, exit, top)
	var evasion := doctrine.evasion if doctrine != null else FLEE_WEAVE
	if wanted.length() > 0.0 and not threats.is_empty():
		wanted += CombatSteering.evade_velocity(position, threats[0], evasion, tuning.evade_speed, _jink_side)
	intent = SteeringIntent.new(wanted.limit_length(top), NAN)
	_show_status("Retreating" if mode == Mode.RETREAT else "Fleeing")


# ------------------------------------------------------------------ helpers

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
