class_name CombatManager
extends Node
## Watches every ship in the current star system for hits and destruction and
## tells the rest of the game. It keeps the combat parts independent of the
## wider game: reputation, the clock and the HUD hear about combat only here.
##
## Signals are transient notifications. Anything that must outlive them (a war
## history, the player's reputation) is stored by its own system.

## A ship was hit (by anything). `attacker` may be null.
signal ship_attacked(victim: Combatant, attacker: Combatant, result: DamageResult)
## A ship other than the player's was destroyed.
signal ship_destroyed(report: DestructionReport)
## The player's ship was destroyed. Main handles what happens next.
signal player_destroyed(report: DestructionReport)

## How a ship stands to the player, for the HUD's colours: an ally (a friend of the
## player), hostile (will attack the player), or neither.
enum Relation { NEUTRAL, HOSTILE, ALLY }

const ATTACK_SHIP: HostileActionType = preload("res://resources/reputation/hostile_actions/attack_ship.tres")
const DESTROY_SHIP: HostileActionType = preload("res://resources/reputation/hostile_actions/destroy_ship.tres")
const SPARK_SHIELD := Color(0.4, 0.8, 1.0)
const SPARK_HULL := Color(1.0, 0.65, 0.25)

var _reputation: ReputationManager
## Callable(faction_id: StringName) -> Faction (or null).
var _faction_lookup: Callable
var _clock: GameClock
## Who counts as an ally and who as hostile; every ship registered here gets them
## (see Allegiance and Hostility).
var _allegiance := Allegiance.new()
var _hostility := Hostility.new()
## What is going on in the current system, for combat AI (see TacticalPicture).
var _picture: TacticalPicture
## Seconds of game time since the game started: what grudges are timed by (it
## stops while the game is paused).
var _time: float = 0.0
var _system: StarSystem
var _player: Combatant
## instance id -> true, for combatants already hooked up.
var _registered: Dictionary = {}


## `faction_lookup` turns a faction id into a Faction (the content registry).
func setup(reputation: ReputationManager, faction_lookup: Callable, clock: GameClock) -> void:
	_reputation = reputation
	_faction_lookup = faction_lookup
	_clock = clock
	# Without a reputation (the combat sandbox) the player has no allies.
	var player_reputation := _player_reputation if reputation != null else Callable()
	_allegiance.setup(AllegianceRules.shared(), player_reputation)
	_hostility.setup(HostilityRules.shared(), _allegiance, faction_lookup, player_reputation, func() -> float: return _time)


## The player's combatant. Registered like any other ship.
func set_player(combatant: Combatant) -> void:
	_player = combatant
	register(combatant)


func get_player() -> Combatant:
	return _player


## Who is hostile to whom (see Hostility).
func get_hostility() -> Hostility:
	return _hostility


## What is going on in the current system (null before the first set_system).
func get_picture() -> TacticalPicture:
	return _picture


func _physics_process(delta: float) -> void:
	_time += delta


## How the ship `targetable` belongs to stands to the player. Anything that is not a
## ship with a combatant (planets, stations) is neutral.
func get_player_relation(targetable: Targetable) -> Relation:
	var combatant := find_combatant(targetable)
	if combatant == null or _player == null or combatant == _player:
		return Relation.NEUTRAL
	if _allegiance.are_allies(_player, combatant):
		return Relation.ALLY
	if _hostility.are_hostile(_player, combatant):
		return Relation.HOSTILE
	return Relation.NEUTRAL


## The hostile ships that are targeting the player now (as of the picture's last
## look, a fifth of a second at most).
func get_player_attackers() -> Array[Combatant]:
	var result: Array[Combatant] = []
	if _picture == null or _player == null:
		return result
	for attacker in _picture.targeters_of(_player):
		if _hostility.are_hostile(attacker, _player):
			result.append(attacker)
	return result


## The same ships as their Targetables (what the HUD and the TargetingManager use).
func get_player_attacker_targetables() -> Array[Targetable]:
	var result: Array[Targetable] = []
	for attacker in get_player_attackers():
		var targetable := attacker.get_parent().get_node_or_null("Targetable") as Targetable
		if targetable != null:
			result.append(targetable)
	return result


## The system now loaded. Its ships (present and future) are watched, and shots
## and effects are added to its Projectiles node so they go with the system.
func set_system(system: StarSystem) -> void:
	_system = system
	_hostility.clear()  # grudges end with the system
	var existing := system.get_node_or_null("TacticalPicture") as TacticalPicture
	if existing != null:
		_picture = existing  # (the same system set again: no second picture)
	else:
		_picture = TacticalPicture.new()
		_picture.name = "TacticalPicture"
		system.add_child(_picture)
	var ships := system.get_ships_root()
	ships.child_entered_tree.connect(_on_ship_entered)
	for child in ships.get_children():
		_register_ship_node(child)
	if _player != null:
		_player.projectile_root_provider = _get_projectile_root


## Hooks a combatant up. Safe to call twice.
func register(combatant: Combatant) -> void:
	var key := combatant.get_instance_id()
	if _registered.has(key):
		return
	_registered[key] = true
	# Ships leave (jump out, are freed with their system): forget them then.
	combatant.tree_exited.connect(func() -> void: _registered.erase(key))
	combatant.projectile_root_provider = _get_projectile_root
	combatant.allegiance = _allegiance
	combatant.hostility = _hostility
	combatant.damaged.connect(_on_damaged.bind(combatant))
	combatant.destroyed.connect(_on_destroyed)


## Connect to TargetingManager.target_changed. The player's turrets and the
## HUD follow the selected ship; selecting a planet or nothing clears it.
func on_target_changed(targetable: Targetable) -> void:
	if _player == null:
		return
	_player.set_target(find_combatant(targetable))


## The Combatant of the ship a Targetable belongs to (null for planets etc.).
static func find_combatant(targetable: Targetable) -> Combatant:
	if targetable == null or targetable.get_parent() == null:
		return null
	return targetable.get_parent().get_node_or_null("Combatant") as Combatant


func _on_ship_entered(node: Node) -> void:
	# The ship's own Combatant is set up in its _ready, which has not run yet.
	_register_ship_node.call_deferred(node)


## `node` is untyped on purpose: a ship freed before this deferred call runs
## would fail the argument conversion of a typed parameter.
func _register_ship_node(node) -> void:
	if not is_instance_valid(node):
		return
	var combatant := node.get_node_or_null("Combatant") as Combatant
	if combatant != null:
		register(combatant)


## The player's reputation with the faction `faction_id` (null when there is no such
## faction): what Allegiance asks to decide whether the player is an ally of it.
func _player_reputation(faction_id: StringName):
	var faction: Faction = _faction_lookup.call(faction_id) if _faction_lookup.is_valid() else null
	if faction == null or _reputation == null:
		return null
	return _reputation.get_reputation(faction)


func _get_projectile_root() -> Node:
	return _system.get_projectiles_root() if _system != null and is_instance_valid(_system) else self


func _on_damaged(result: DamageResult, hit: Hit, victim: Combatant) -> void:
	var attacker := hit.attacker as Combatant
	_hostility.record_attack(attacker, victim)
	_spawn_effect(BurstEffect.spark(hit.position, SPARK_HULL if result.penetrated() else SPARK_SHIELD))
	ship_attacked.emit(victim, attacker, result)
	if attacker != null and attacker.is_player and not victim.is_player:
		_report_hostile(ATTACK_SHIP, victim, StringName("attack:%s" % victim.combat_id))


func _on_destroyed(victim: Combatant, attacker: Combatant) -> void:
	var report := DestructionReport.new()
	report.victim_id = victim.combat_id
	report.victim_model = victim.model_id
	report.victim_faction = victim.faction_id
	report.victim_is_player = victim.is_player
	if attacker != null:
		report.attacker_id = attacker.combat_id
		report.attacker_faction = attacker.faction_id
		report.attacker_is_player = attacker.is_player
	var ship := victim.get_parent() as NpcShip
	if ship != null:
		var unit := ship.get_organisation()
		report.victim_formation_kind = unit["kind"]
		report.victim_formation_id = unit["id"]
		report.victim_fleet_id = unit["fleet_id"]
	report.system_id = _system.system_id if _system != null else &""
	report.position = victim.global_position
	report.day = _clock.day if _clock != null else 0
	_spawn_effect(BurstEffect.explosion(victim.global_position, victim.specs.hit_radius * 2.0))
	if victim.is_player:
		player_destroyed.emit(report)
		return
	ship_destroyed.emit(report)
	if attacker != null and attacker.is_player:
		_report_hostile(DESTROY_SHIP, victim, StringName("destroy:%s" % victim.combat_id))


## Charges the player for attacking or destroying `victim`: the faction the ship
## belongs to loses reputation; a ship that belongs to nobody (one passing
## through) is charged to whoever controls the system it is in, if anyone.
func _report_hostile(type: HostileActionType, victim: Combatant, event_id: StringName) -> void:
	if _reputation == null:
		return
	if victim.faction_id != &"":
		var faction: Faction = _faction_lookup.call(victim.faction_id) if _faction_lookup.is_valid() else null
		_reputation.report_hostile_action(type, faction, event_id)
	elif _system != null:
		_reputation.report_hostile_action_in_system(type, _system.system_id, event_id)


func _spawn_effect(effect: Node) -> void:
	_get_projectile_root().add_child(effect)
