class_name SystemAssessment
extends RefCounted
## What a star system is worth, as numbers a war can read: its military value, what it
## makes and uses, its people, how damaged it is, and how connected it is. Built by
## SystemAssessor from the system's locations and class; a plain value, never saved.
## "Structural" figures ignore damage; "current" figures include it.

var system_id: StringName = &""
## The id of the system's class, or &"" if it has none.
var class_id: StringName = &""

## People living in the system.
var population: int = 0
## Locations that count: inhabited and dockable.
var location_ids: Array[StringName] = []

## Military value with no damage: the sum over the locations times the class's
## multiplier. What the system is worth when whole.
var military_value: float = 0.0
## Military value as it is now, lowered by damage.
var current_military_value: float = 0.0

## Credits' worth of goods made and used each day (undamaged), at base prices.
var production_value: float = 0.0
var consumption_value: float = 0.0

## The share of normal production the system's locations make now: 1.0 undamaged,
## the average over its inhabited locations, weighted by what each makes.
var infrastructure: float = 1.0

## Number of jump links.
var connectivity: int = 0

## A score of the system's worth to a faction (see MilitaryValueRules): military
## value, production, population and connectivity combined. Structural: damage does
## not change it, so a raid cannot make a centre of power come and go.
var importance: float = 0.0

## Military value of each location: {location id: structural value}.
var location_values: Dictionary = {}


func is_inhabited() -> bool:
	return not location_ids.is_empty()
