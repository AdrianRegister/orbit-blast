class_name StarSystem
extends Node2D
## Reusable container for one star system. Individual systems are scenes that
## inherit star_system.tscn and add their objects under the `Objects` node.
## Nothing here needs to change to create a new system.

## Permanent unique id, e.g. &"sol". Save files and the Galaxy use it.
@export var system_id: StringName = &""
@export var system_name: String = ""
## How far from the system centre (in pixels) a ship must be to make a jump.
## Ships arriving from another
## system appear on this circle.
@export var jump_radius: float = 2000.0

## How busy the system's NPC traffic is, relative to the traffic config: it
## scales both how often ships arrive and how many are in the system at once
## (and so how often they leave). 1.0 is a busy core system, which every system
## so far is; a remote or sparsely populated system should use something like
## 0.1 to 0.3. 0 means no traffic at all.
@export_range(0.0, 4.0, 0.05) var traffic_rate: float = 1.0

## Most objects (planets, moons, stations) a system may contain.
const MAX_OBJECTS := 3

@onready var _objects: Node2D = $Objects
@onready var _ships: Node2D = $Ships
@onready var _traffic: TrafficManager = $Traffic


## Every SpaceObject placed in this system.
func get_space_objects() -> Array[SpaceObject]:
	var result: Array[SpaceObject] = []
	for child in _objects.get_children():
		if child is SpaceObject:
			result.append(child)
	return result


## Every inhabited location (planets, stations) NPC ships can travel between.
func get_inhabited_nodes() -> Array[InhabitedNode]:
	var result: Array[InhabitedNode] = []
	for child in _objects.get_children():
		if child is InhabitedNode:
			result.append(child)
	return result


## Parent node of every NPC ship in this system.
func get_ships_root() -> Node2D:
	return _ships


## Tells the traffic which directions lead to other systems (unit vectors, from
## the map positions of the links). Call before start_traffic().
func set_traffic_exits(bearings: Array[Vector2]) -> void:
	_traffic.set_exit_bearings(bearings)


## Starts the ambient NPC traffic of this system, keeping spawns clear of the player.
func start_traffic(player: Node2D) -> void:
	_traffic.start(self, player)


## Removes every NPC ship and starts the traffic again from scratch, as when the
## system is first entered. Used when a saved game is loaded.
func restart_traffic(player: Node2D) -> void:
	_traffic.reset()
	_traffic.start(self, player)


## Human-readable problems with this system; empty when it is sound. Works on a
## system that is not in the tree. Rules: at least one planet, at most
## MAX_OBJECTS objects, and a moon only together with a planet.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if system_id == &"":
		problems.append("system_id is empty")
	if system_name.is_empty():
		problems.append("system_name is empty")
	if traffic_rate < 0.0:
		problems.append("traffic_rate is negative")
	var objects := get_node("Objects").get_children()
	var planets := 0
	var moons := 0
	var count := 0
	for object in objects:
		if not object is SpaceObject:
			continue
		count += 1
		var data = object.get("data")
		if data is PlanetData and data.planet_type != null and data.planet_type.is_moon:
			moons += 1
		elif data is PlanetData:
			planets += 1
	if planets == 0:
		problems.append("a system needs at least one planet")
	if moons > 0 and planets == 0:
		problems.append("a moon needs a planet in the same system")
	if count > MAX_OBJECTS:
		problems.append("a system may hold at most %d objects (has %d)" % [MAX_OBJECTS, count])
	return problems
