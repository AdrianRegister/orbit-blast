class_name Hostility
extends RefCounted
## Who attacks whom on sight. The companion of Allegiance (who are friends): one
## place decides it, so combat AI, the sandbox and later systems agree. Two ships
## are hostile when they are not allies and at least one of these holds, checked
## in this order (get_reason names the first):
##
##   war         their factions are at war (Faction.relations, `at_war`, either way)
##   pirates     one belongs to a faction that is hostile to everyone
##               (Faction.hostile_to_all), or is faction-less meeting such a ship
##   reputation  one is the player and the player's reputation with the other's
##               faction is at or below HostilityRules.attack_player_reputation
##   grudge      one side attacked the other within HostilityRules.grudge_seconds
##
## The rule is symmetric. Peace is the default: factions with no relation, and ships
## that belong to nobody, are not hostile to each other.
##
## Grudges are between SIDES. A side is a faction; the player is a side of their
## own; a ship that belongs to nobody is a side by itself. The player's allies
## (see Allegiance) count as being on the player's side too, so they take up the
## player's quarrels. Grudges live as long as the system: the CombatManager clears
## them when the system changes, and nothing here is saved.

## The side the player (and the player's allies) is on.
const PLAYER_SIDE := &"@player"

const REASON_NONE := &""
const REASON_WAR := &"war"
const REASON_PIRATES := &"pirates"
const REASON_REPUTATION := &"reputation"
const REASON_GRUDGE := &"grudge"

var rules: HostilityRules
## Null: nobody is anybody's ally.
var allegiance: Allegiance
## Callable(faction_id: StringName) -> Faction (or null).
var _faction_lookup: Callable
## Callable(faction_id: StringName) -> the player's reputation with it (an int), or
## null when it is not known. Invalid when there is no reputation (the sandbox).
var _player_reputation: Callable
## Callable() -> float: the time now, in seconds of game time.
var _now: Callable
## victim side -> {attacker side -> time the grudge ends}
var _grudges: Dictionary = {}


func setup(hostility_rules: HostilityRules, ally_rules: Allegiance, faction_lookup: Callable,
		player_reputation: Callable = Callable(), now: Callable = Callable()) -> void:
	rules = hostility_rules if hostility_rules != null else HostilityRules.shared()
	allegiance = ally_rules
	_faction_lookup = faction_lookup
	_player_reputation = player_reputation
	_now = now


## Whether `a` and `b` are hostile to each other. Symmetric; never true for allies.
func are_hostile(a: Combatant, b: Combatant) -> bool:
	return get_reason(a, b) != REASON_NONE


## Why `a` and `b` are hostile (one of the REASON_ constants), or REASON_NONE.
func get_reason(a: Combatant, b: Combatant) -> StringName:
	if a == null or b == null or a == b:
		return REASON_NONE
	if allegiance != null and allegiance.are_allies(a, b):
		return REASON_NONE
	if _at_war(a.faction_id, b.faction_id):
		return REASON_WAR
	if _is_hostile_to_all(a.faction_id) or _is_hostile_to_all(b.faction_id):
		return REASON_PIRATES
	if _player_distrusts(a, b) or _player_distrusts(b, a):
		return REASON_REPUTATION
	if _has_grudge(a, b) or _has_grudge(b, a):
		return REASON_GRUDGE
	return REASON_NONE


## Records that `attacker` hit `victim`: the victim's side is now hostile to the
## attacker's for rules.grudge_seconds. Allies and ships on the same side do not
## start grudges (shots pass through allies anyway).
func record_attack(attacker: Combatant, victim: Combatant) -> void:
	if attacker == null or victim == null or attacker == victim:
		return
	if allegiance != null and allegiance.are_allies(attacker, victim):
		return
	var victim_side := side_of(victim)
	var attacker_side := side_of(attacker)
	if victim_side == attacker_side:
		return
	if not _grudges.has(victim_side):
		_grudges[victim_side] = {}
	_grudges[victim_side][attacker_side] = _time() + rules.grudge_seconds


## The side a ship is on: the player's, its faction, or (belonging to nobody) its own.
func side_of(combatant: Combatant) -> StringName:
	if combatant.is_player:
		return PLAYER_SIDE
	if combatant.faction_id != &"":
		return combatant.faction_id
	return combatant.combat_id


## Whether the side of `victim` holds a grudge against the side of `attacker` now.
func has_grudge(victim: Combatant, attacker: Combatant) -> bool:
	return _has_grudge(victim, attacker)


## Forgets every grudge (the system changed).
func clear() -> void:
	_grudges.clear()


# --------------------------------------------------------------------- rules

## Whether the two factions are at war: either one's relation to the other says so.
func factions_at_war(first: StringName, second: StringName) -> bool:
	return _at_war(first, second)


func _at_war(first: StringName, second: StringName) -> bool:
	if first == &"" or second == &"" or first == second or not _faction_lookup.is_valid():
		return false
	var a: Faction = _faction_lookup.call(first)
	var b: Faction = _faction_lookup.call(second)
	var relation: FactionRelation = a.get_relation(second) if a != null else null
	if relation != null and relation.at_war:
		return true
	relation = b.get_relation(first) if b != null else null
	return relation != null and relation.at_war


func _is_hostile_to_all(faction_id: StringName) -> bool:
	if faction_id == &"" or not _faction_lookup.is_valid():
		return false
	var faction: Faction = _faction_lookup.call(faction_id)
	return faction != null and faction.hostile_to_all


## Whether `player` is the player and their reputation with `other`'s faction is
## bad enough that its ships attack on sight.
func _player_distrusts(player: Combatant, other: Combatant) -> bool:
	if not player.is_player or other.is_player or other.faction_id == &"" or not _player_reputation.is_valid():
		return false
	var reputation = _player_reputation.call(other.faction_id)
	return reputation != null and int(reputation) <= rules.attack_player_reputation


func _has_grudge(victim: Combatant, attacker: Combatant) -> bool:
	if _grudges.is_empty():
		return false
	var now := _time()
	for victim_side in _sides_of(victim):
		var holders: Dictionary = _grudges.get(victim_side, {})
		for attacker_side in _sides_of(attacker):
			if holders.has(attacker_side):
				if holders[attacker_side] > now:
					return true
				holders.erase(attacker_side)  # (expired)
	return false


## The sides a ship counts as: its own, and the player's when it is the player's ally.
func _sides_of(combatant: Combatant) -> Array[StringName]:
	var sides: Array[StringName] = [side_of(combatant)]
	if not combatant.is_player and allegiance != null and allegiance.is_player_ally(combatant.faction_id):
		sides.append(PLAYER_SIDE)
	return sides


func _time() -> float:
	return _now.call() if _now.is_valid() else 0.0
