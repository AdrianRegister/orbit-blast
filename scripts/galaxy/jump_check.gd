class_name JumpCheck
extends RefCounted
## The result of asking whether the player may jump to a system. Changes
## nothing. `reachable` says whether the destination is linked to the current
## system at all; `ok` says whether the jump can be made right now.

var ok: bool = false
## A link from the current system to the target exists.
var reachable: bool = false
## Why not, when `ok` is false.
var reason: String = ""
## Fuel units the jump costs (-1 when not reachable). Not enforced yet.
var cost: int = -1
## How far the ship is from the system centre, and how far it must be.
var distance: float = 0.0
var required_distance: float = 0.0
