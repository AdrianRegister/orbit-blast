class_name TacticalPicture
extends Node
## What is going on in the current star system, in one place, for combat AI to ask:
## who is near me, who is hostile, who is shooting at whom. A node under the star
## system (the CombatManager adds it), so it is freed with the system and nothing
## outlives a jump. It decides nothing and moves nothing; pilots and commanders read it.
##
## It keeps a list of the live combatants and who each is targeting, refreshed
## `REFRESH_INTERVAL` seconds apart (public refresh() for tests). Positions are read
## live, so a query is always about where ships are now; the list changes only at
## the refresh, so a ship that has just appeared is seen within a fifth of a second.
##
## Hostility comes from Hostility (through Combatant.is_hostile_to), and grudges are
## recorded by the CombatManager, so they are not kept here.

## Seconds between refreshes.
const REFRESH_INTERVAL := 0.2
## An armed hostile counts as a threat to a ship when it is within this multiple of
## its own weapon reach of it, whether or not it has chosen the ship as its target.
const THREAT_RANGE_FACTOR := 1.2

var _combatants: Array = []  # (untyped: ships get freed)
## target Combatant -> the Combatants that are targeting it (the player's own selection
## does not count: it is not an attack).
var _targeters: Dictionary = {}
var _since_refresh: float = REFRESH_INTERVAL


func _physics_process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh >= REFRESH_INTERVAL:
		refresh()


## Looks at every combatant in play again (the player's and every NPC's: a jump frees
## the old system's ships, so these are the current system's).
func refresh() -> void:
	_since_refresh = 0.0
	_combatants = []
	_targeters = {}
	for node in get_tree().get_nodes_in_group(Combatant.GROUP):
		var combatant := node as Combatant
		if combatant == null or not combatant.is_alive():
			continue
		_combatants.append(combatant)
	for combatant: Combatant in _combatants:
		if combatant.is_player:
			continue
		var target := combatant.get_target()
		if target != null:
			if not _targeters.has(target):
				_targeters[target] = []
			_targeters[target].append(combatant)


## Every live combatant (the player's too), as of the last refresh.
func get_combatants() -> Array[Combatant]:
	var result: Array[Combatant] = []
	for combatant in _combatants:
		if is_instance_valid(combatant) and combatant.is_alive():
			result.append(combatant)
	return result


## The live combatants hostile to `ship` and within `radius` of it, nearest first.
func hostiles_near(ship: Combatant, radius: float) -> Array[Combatant]:
	var found: Array[Combatant] = []
	var distances := {}
	for other in get_combatants():
		if other == ship or not ship.is_hostile_to(other):
			continue
		var distance := ship.global_position.distance_to(other.global_position)
		if distance <= radius:
			found.append(other)
			distances[other] = distance
	found.sort_custom(func(a: Combatant, b: Combatant) -> bool: return distances[a] < distances[b])
	return found


## The ships (never the player) that are targeting `target` now.
func targeters_of(target: Combatant) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for combatant in _targeters.get(target, []):
		if is_instance_valid(combatant) and combatant.is_alive() and combatant.get_target() == target:
			result.append(combatant)
	return result


## How many ships are targeting `target` now.
func count_targeters(target: Combatant) -> int:
	return targeters_of(target).size()


## The hostile ships that threaten `ship`: those that have chosen it as their target,
## and armed ones within THREAT_RANGE_FACTOR times their weapon reach of it.
func threats_to(ship: Combatant) -> Array[Combatant]:
	var result: Array[Combatant] = []
	for other in get_combatants():
		if other == ship or not other.is_hostile_to(ship):
			continue
		if other.get_target() == ship and not other.is_player:
			result.append(other)
		elif other.is_armed():
			var reach := other.weapons.get_longest_range() * THREAT_RANGE_FACTOR
			if other.global_position.distance_to(ship.global_position) <= reach:
				result.append(other)
	return result

