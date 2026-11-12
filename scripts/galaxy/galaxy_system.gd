class_name GalaxySystem
extends Resource
## One star system's place in the galaxy: which scene it is, and where it sits
## on the galaxy map. Its id and name are NOT copied here; they stay on the
## scene (StarSystem.system_id / system_name), the single source of truth.

## The system scene (inherits star_system.tscn).
@export var scene: PackedScene
## Position on the galaxy map, in map units. Unrelated to where objects are
## placed inside the system. Sol is the origin by convention.
@export var map_position: Vector2 = Vector2.ZERO
## True for systems the player knows about from the start of a new game.
@export var start_discovered: bool = false
## The faction this system belongs to on the map: its territory. It does not say
## who owns the settlements in it (each settlement owns itself, see
## TerritoryManager); it only decides the system when it has no settlements, and
## is the default owner for the settlements generated in it. Null = unclaimed.
@export var claim: Faction
## What kind of system this is (critical, rural, ...), or null for an ordinary
## unclassified one. Set with the "class" field of the system's row in
## data/galaxy/galaxy_map.json; never changes while playing.
@export var system_class: SystemClass


## Most objects this system may hold: its class's limit, or the ordinary one.
func object_limit() -> int:
	return system_class.max_objects if system_class != null else StarSystem.MAX_OBJECTS
