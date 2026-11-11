class_name SystemLink
extends Resource
## A two-way jump connection between two star systems. Travel is only possible
## along links. Systems are referred to by their permanent system ids.

@export var a: StringName = &""
@export var b: StringName = &""
## Jump cost in fuel units. 0 = derive it from the map distance between the two
## systems (Galaxy.fuel_per_unit). Set it to override a particular link.
@export var fuel_cost: int = 0


func connects(first: StringName, second: StringName) -> bool:
	return (a == first and b == second) or (a == second and b == first)
