class_name ShipStats
extends Resource
## Static flight characteristics of a ship type. Edit the .tres files, not the code.

## Acceleration while thrusting, in pixels per second squared.
@export var thrust: float = 300.0
## Rotation speed in radians per second.
@export var turn_rate: float = 3.0
## Speed limit in pixels per second.
@export var max_speed: float = 500.0
