class_name ShipCondition
extends RefCounted
## The lasting damage on one owned ship: how much armour and hull it has left.
## Shields and energy are not kept (they come back by themselves). A value of
## FULL means "undamaged", so a ship that has never been hit needs no numbers
## and a ship whose model changes in a later version is not left with stale ones.
## The running ship's ShipHealth writes into the same object, so the save always
## sees the current condition.

const FULL := -1.0

var armour: float = FULL
var hull: float = FULL


func is_full() -> bool:
	return armour < 0.0 and hull < 0.0


func repair_fully() -> void:
	armour = FULL
	hull = FULL


## Armour and hull points missing, given the ship's maximums.
func armour_missing(max_armour: float) -> float:
	return 0.0 if armour < 0.0 else maxf(max_armour - armour, 0.0)


func hull_missing(max_hull: float) -> float:
	return 0.0 if hull < 0.0 else maxf(max_hull - hull, 0.0)
