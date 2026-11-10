class_name StarSystem
extends Node2D
## Reusable container for one star system. Individual systems are scenes that
## inherit star_system.tscn and add their objects under the `Objects` node.
## Nothing here needs to change to create a new system.

@export var system_name: String = ""

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


## Starts the ambient NPC traffic of this system, keeping spawns clear of the player.
func start_traffic(player: Node2D) -> void:
	_traffic.start(self, player)
