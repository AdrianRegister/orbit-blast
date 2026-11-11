class_name ReputationManager
extends Node
## The player's reputation with each faction, independent of everything the
## factions think of each other. Reputation is about military service and hostile
## acts: military contracts can raise it, attacking a faction's assets lowers it,
## and civilian contracts never touch it. Other systems ask this class (never the
## numbers directly) whether the player is liked, trusted or eligible.
##
## It also acts as the "reputation" save section. Missing factions are neutral, so
## adding a faction later needs nothing here.

## The player's reputation with a faction changed.
signal reputation_changed(faction_id: StringName, old_value: int, new_value: int)
## The standing name changed too (for example Neutral to Favourable).
signal standing_changed(faction_id: StringName, old_standing: String, new_standing: String)

## Reputation was replaced wholesale (a load or a reset): refresh everything.
signal reputation_reset

const STANDINGS_PATH := "res://resources/reputation/standings.tres"

var standings: ReputationStandings = load(STANDINGS_PATH)

var _territory: TerritoryManager
## faction id -> int. Only factions whose reputation is not the starting value.
var _values: Dictionary = {}
## Hostile acts already counted this session (by event id), so one act is only
## ever charged once.
var _seen_events: Dictionary = {}


## `territory` is only needed to charge hostile acts to the faction that controls
## a system (report_hostile_action_in_system).
func setup(territory: TerritoryManager = null) -> void:
	_territory = territory
	reset_state()


# ----------------------------------------------------------------------- reading

## The player's reputation with a faction (the starting value if never changed).
func get_reputation(faction: Faction) -> int:
	if faction == null:
		return standings.start
	return _values.get(faction.id, standings.start)


## The standing name for it, e.g. "Neutral".
func get_standing(faction: Faction) -> String:
	return standings.get_standing_name(get_reputation(faction))


## Whether the player's reputation with a faction is at least `minimum`. The one
## check eligibility rules (contracts, services, special opportunities) use.
func meets(faction: Faction, minimum: int) -> bool:
	return get_reputation(faction) >= minimum


# ----------------------------------------------------------------------- changing

## Changes the reputation with a faction by `amount`, within the scale. Returns
## the new value.
func change(faction: Faction, amount: int, _reason: String = "") -> int:
	if faction == null or amount == 0:
		return get_reputation(faction)
	var old_value := get_reputation(faction)
	var new_value := standings.clamp_value(old_value + amount)
	if new_value == old_value:
		return old_value
	if new_value == standings.start:
		_values.erase(faction.id)
	else:
		_values[faction.id] = new_value
	var old_standing := standings.get_standing_name(old_value)
	var new_standing := standings.get_standing_name(new_value)
	reputation_changed.emit(faction.id, old_value, new_value)
	if old_standing != new_standing:
		standing_changed.emit(faction.id, old_standing, new_standing)
	return new_value


## Awards a completed contract's reputation, once. Only military contracts change
## reputation: a civilian contract never does, whatever number it carries. The
## faction is the contract's issuer. Connect to ContractManager.contract_completed.
## Returns whether anything was applied.
func apply_contract(contract: Contract) -> bool:
	if contract == null or contract.reputation_applied:
		return false
	if contract.authority != Contract.Authority.MILITARY or contract.reputation_change == 0:
		return false
	var faction := contract.get_issuing_faction()
	if faction == null:
		return false
	contract.reputation_applied = true
	change(faction, contract.reputation_change, "contract %s" % contract.id)
	return true


## A hostile act against a faction's assets (a ship, a station, a settlement, or
## a civilian ship in its space): the player loses the reputation the act type
## names with `victim`. `event_id` identifies this one act (for example the
## victim ship's instance and the kind of attack); the same id is only ever
## charged once. Returns whether it was applied. Combat will call this.
func report_hostile_action(type: HostileActionType, victim: Faction, event_id: StringName) -> bool:
	if type == null or victim == null:
		return false
	if event_id == &"":
		push_error("A hostile action needs an event id so it is only counted once.")
		return false
	if _seen_events.has(event_id):
		return false
	_seen_events[event_id] = true
	change(victim, -type.penalty, str(type.id))
	return true


## The same for an act in space: the faction that controls the system is the
## victim. A contested or unclaimed system has no single faction to blame, so
## nobody loses reputation for it.
func report_hostile_action_in_system(type: HostileActionType, system_id: StringName, event_id: StringName) -> bool:
	if _territory == null:
		return false
	var control := _territory.get_control(system_id)
	if control.controller == null:
		return false
	return report_hostile_action(type, control.controller, event_id)


# ------------------------------------------------------------------------ saving

func save_state() -> Dictionary:
	var values := {}
	for faction_id in _values:
		values[str(faction_id)] = _values[faction_id]
	return {"values": values}


func validate_state(data: Variant, registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary or not data.get("values") is Dictionary:
		return ["reputation values is not an object"]
	for faction_id in data["values"]:
		if registry.faction(StringName(faction_id)) == null:
			problems.append("reputation refers to unknown faction '%s'" % faction_id)
			continue
		var value = data["values"][faction_id]
		if not SaveData.is_int(value) or value < standings.minimum or value > standings.maximum:
			problems.append("reputation with '%s' is not a whole number within the scale" % faction_id)
	return problems


## Replaces reputation with validated saved data.
func load_state(data: Dictionary, _registry: ContentRegistry) -> void:
	_values.clear()
	for faction_id in data["values"]:
		var value := int(data["values"][faction_id])
		if value != standings.start:
			_values[StringName(faction_id)] = value
	_seen_events.clear()
	reputation_reset.emit()


## Every faction back to the starting reputation (a new game, or a save from
## before reputation existed).
func reset_state() -> void:
	_values.clear()
	_seen_events.clear()
	reputation_reset.emit()
