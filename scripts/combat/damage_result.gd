class_name DamageResult
extends RefCounted
## What one hit actually did, layer by layer. Used for HUD flashes, hit effects
## and the destruction events.

var shield_damage: float = 0.0
var armour_damage: float = 0.0
var hull_damage: float = 0.0
var destroyed: bool = false


func total() -> float:
	return shield_damage + armour_damage + hull_damage


## True when the hit got past the shields.
func penetrated() -> bool:
	return armour_damage > 0.0 or hull_damage > 0.0
