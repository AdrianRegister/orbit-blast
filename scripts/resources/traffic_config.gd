class_name TrafficConfig
extends Resource
## How much ambient NPC traffic a star system has and how it behaves. Assigned
## to the Traffic node of a system scene; the default lives in
## resources/traffic/default_traffic.tres and a system can use its own.

## Most NPC ships alive in the system at once.
@export var max_ships: int = 8
## Ship types that may spawn, picked by each type's spawn_weight.
@export var ship_types: Array[ShipType] = []

@export_group("Spawning")
## Seconds between new arrivals while below max_ships.
@export var spawn_interval: float = 6.0
## Fraction of max_ships placed in flight when the system loads, so it is not empty.
@export_range(0.0, 1.0) var initial_fill_fraction: float = 0.5
## Never spawn closer than this to the player (pixels).
@export var min_spawn_distance_from_player: float = 800.0
## Extra gap kept from every location's docking range when spawning (pixels).
@export var spawn_clearance: float = 150.0
## Never spawn closer than this to another NPC (pixels).
@export var ship_spacing: float = 150.0
## How far beyond its docking range a ship appears when it leaves a location.
@export var departure_clearance: float = 40.0

@export_group("Behaviour")
## Seconds an NPC stays docked, as (min, max).
@export var dock_time_range: Vector2 = Vector2(5.0, 15.0)
## How many locations an NPC visits before leaving the system, as (min, max).
@export var visits_range: Vector2i = Vector2i(2, 4)
## A ship that has finished its visits only leaves the system when it is
## farther than this from the player, so it never vanishes in view (pixels).
@export var despawn_distance_from_player: float = 2500.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if max_ships < 0:
		problems.append("max_ships is negative")
	if ship_types.is_empty():
		problems.append("ship_types is empty")
	for ship_type in ship_types:
		if ship_type == null:
			problems.append("ship_types has an empty entry")
		else:
			for problem in ship_type.validate():
				problems.append("%s: %s" % [ship_type.display_name, problem])
	return problems
