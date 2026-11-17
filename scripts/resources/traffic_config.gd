class_name TrafficConfig
extends Resource
## How much ambient NPC traffic a star system has and how it behaves. Assigned
## to the Traffic node of a system scene; the default lives in
## resources/traffic/default_traffic.tres and a system can use its own.

## Most NPC ships alive in the system at once, at a traffic_rate of 1.0.
@export var max_ships: int = 8
## Ship types that may spawn, picked by each type's spawn_weight.
@export var ship_types: Array[ShipType] = []

@export_group("Spawning")
## Seconds between new arrivals while below the cap, at a traffic_rate of 1.0.
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

@export_group("Military patrols")
## What a patrol is made of when its system's class names no recipe of its own.
@export var patrol_recipe: FormationRecipe
## Seconds before a patrol that was destroyed is replaced.
@export var patrol_respawn_delay: float = 90.0
## A patrol flies a loop of `patrol_loop_points` points on a circle this fraction of the
## system's jump radius from its centre.
@export_range(0.1, 1.0) var patrol_loop_radius_fraction: float = 0.6
@export_range(3, 12) var patrol_loop_points: int = 6
## Whether the ships of patrols count against `max_ships`. (Patrols are placed whatever the
## count; when they count, the ambient traffic makes room for them instead.)
@export var patrols_count_toward_cap: bool = true

@export_group("Convoys")
## The convoys that sometimes arrive as ambient traffic (cargo ships with their escorts).
@export var convoy_recipe: FormationRecipe
## How likely a convoy is to arrive compared with all the single ships together: the weight of
## the ship types adds up to the other side of the scale (0.5 against, say, 30 is one in sixty).
@export_range(0.0, 100.0) var convoy_spawn_weight: float = 0.5

@export_group("Behaviour")
## Seconds an NPC stays docked, as (min, max).
@export var dock_time_range: Vector2 = Vector2(5.0, 15.0)
## How many locations an NPC visits before leaving the system, as (min, max).
@export var visits_range: Vector2i = Vector2i(2, 4)


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
