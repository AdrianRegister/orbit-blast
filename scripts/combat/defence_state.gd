class_name DefenceState
extends RefCounted
## The current defensive layers of one ship: what DamageModel reads and changes.
## Pure data, no nodes, so damage can be calculated and tested without a scene.

var shield: float = 0.0
var armour: float = 0.0
var hull: float = 0.0
var max_shield: float = 0.0
var max_armour: float = 0.0
var max_hull: float = 0.0


static func full(max_shield_value: float, max_armour_value: float, max_hull_value: float) -> DefenceState:
	var state := DefenceState.new()
	state.max_shield = max_shield_value
	state.max_armour = max_armour_value
	state.max_hull = max_hull_value
	state.shield = max_shield_value
	state.armour = max_armour_value
	state.hull = max_hull_value
	return state


func is_destroyed() -> bool:
	return hull <= 0.0
