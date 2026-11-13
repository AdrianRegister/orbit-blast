class_name Allegiance
extends RefCounted
## Who counts as an ally in combat. The single place that decides it: shots pass
## through allies (no friendly fire), and later the NPC combat AI will use it so
## ships never pick an ally as a target.
##
##  - Two ships are allies if they belong to the same faction.
##  - The player belongs to no faction, but is an ally of a faction (and that
##    faction's ships are the player's allies) while their reputation with it is at
##    least AllegianceRules.min_reputation.
##  - A ship that belongs to nobody is an ally of nobody.
##
## Both directions are the same, so the rule is symmetric.

var rules: AllegianceRules
## Callable(faction_id: StringName) -> the player's reputation with it (an int), or
## null when it is not known. Invalid when there is no reputation (the sandbox), in
## which case the player has no allies.
var _player_reputation: Callable


func setup(allegiance_rules: AllegianceRules, player_reputation: Callable = Callable()) -> void:
	rules = allegiance_rules if allegiance_rules != null else AllegianceRules.shared()
	_player_reputation = player_reputation


## Whether `a` and `b` are allies. Symmetric. A combatant is its own ally.
func are_allies(a: Combatant, b: Combatant) -> bool:
	if a == null or b == null:
		return false
	if a == b:
		return true
	if a.is_player and b.is_player:
		return true
	if a.is_player:
		return _player_allied_with(b.faction_id)
	if b.is_player:
		return _player_allied_with(a.faction_id)
	return a.faction_id != &"" and a.faction_id == b.faction_id


## Whether the player is an ally of the faction `faction_id` through their
## reputation (Hostility uses it to put the player's friends on the player's side).
func is_player_ally(faction_id: StringName) -> bool:
	return _player_allied_with(faction_id)


## Whether the player is an ally of `faction_id` through their reputation.
func _player_allied_with(faction_id: StringName) -> bool:
	if faction_id == &"" or not _player_reputation.is_valid():
		return false
	var reputation = _player_reputation.call(faction_id)
	return reputation != null and int(reputation) >= rules.min_reputation
