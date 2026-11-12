class_name PopulationScaleEntry
extends Resource
## One line of PopulationDisplayRules: how much larger the number shown to the player
## is than a location's real population, for locations in systems of one class. Planets
## and stations are scaled separately (a station is a town, a planet a world).

## The system class this applies to. It also covers the class's subtypes unless they
## have an entry of their own (an economic centre uses the critical entry).
@export var system_class: SystemClass
@export var planet_scale: float = 1.0
@export var station_scale: float = 1.0
