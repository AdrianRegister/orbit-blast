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
## Owning faction, as plain text until factions exist.
@export var faction_name: String = ""
