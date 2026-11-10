class_name PlayerData
extends Resource
## Runtime data belonging to the player. Created by Main and passed down to
## whatever needs it. It lives for the whole session, so credits and cargo
## persist across docking and star systems. Only the EconomyManager changes
## credits and cargo during play.

@export var ship_stats: ShipStats

## Money, in credits. Never negative.
var credits: int = 0
## What the ship is carrying. Its capacity comes from ship_stats.
var cargo: CargoHold = CargoHold.new()
