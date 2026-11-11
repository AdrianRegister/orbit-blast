class_name PlayerData
extends Resource
## Runtime data belonging to the player. Created by Main and passed down to
## whatever needs it. It lives for the whole session, so credits and cargo
## persist across docking and star systems. Only the EconomyManager changes
## credits and cargo during play.

## Every ship the player owns, and which one is active. Only ShipManager
## changes it.
var fleet: Fleet = Fleet.new()

## Money, in credits. Never negative.
var credits: int = 0
## What the ship is carrying. Its capacity comes from the active ship.
var cargo: CargoHold = CargoHold.new()
