class_name FormationEnvironment
extends RefCounted
## What a group of NPC ships needs to know about its surroundings to steer clear of
## things: the other ships in the star system, the player, and the planets and
## stations. A Formation and a WarFleet each own one. Call update() once a frame
## before asking for avoidance.
##
## The maths is FormationSteering's; this only gathers the bodies.

var _system: StarSystem
var _player: Node2D
var _bodies: Array[Dictionary] = []
var _obstacles: Array[Dictionary] = []


## `system` is the star system the ships are in, `player` the player's ship (or null).
func setup(system: StarSystem, player: Node2D) -> void:
	_system = system
	_player = player
	_obstacles.clear()
	for node in system.get_inhabited_nodes():
		_obstacles.append({"node": node, "position": node.global_position, "radius": _body_radius(node)})


## Reads where every ship is now. Call once per physics frame.
func update() -> void:
	_bodies.clear()
	for child in _system.get_ships_root().get_children():
		var other := child as NpcShip
		if other != null and other.visible and not other.is_queued_for_deletion():
			_bodies.append({"node": other, "position": other.global_position, "radius": other.get_hit_radius()})
	if _player != null and is_instance_valid(_player):
		var specs = _player.get("stats")
		var player_radius: float = specs.hit_radius if specs != null else 30.0
		_bodies.append({"node": _player, "position": _player.global_position, "radius": player_radius})


## A push (a velocity) that keeps `ship` clear of other ships (the player too) and of
## planets and stations. `ignored_obstacle` is a place the ship is allowed to go close
## to (the one it is heading for).
func get_avoidance(ship: NpcShip, tuning: FormationTuning, ignored_obstacle: Node = null) -> Vector2:
	var max_speed := ship.ship_type.stats.max_speed
	var radius := ship.get_hit_radius()
	var push := FormationSteering.separation(ship, ship.global_position, radius, _bodies,
			tuning.separation_margin, max_speed, tuning.separation_strength)
	var obstacles: Array[Dictionary] = []
	for obstacle in _obstacles:
		if ignored_obstacle != null and obstacle["node"] == ignored_obstacle:
			continue
		obstacles.append(obstacle)
	return push + FormationSteering.obstacle_push(ship.global_position, radius, obstacles,
			tuning.obstacle_margin, max_speed, tuning.obstacle_strength)


## Radius of a planet or station, from its location data (its size is a diameter).
func _body_radius(node: InhabitedNode) -> float:
	return node.data.size * 0.5 if node.data != null else 100.0
