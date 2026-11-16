class_name WeaponMount
extends Resource
## One place on a ship model where a weapon can be fitted. A model lists its
## mounts in ShipStats.weapon_mounts; the weapons actually fitted to an owned
## ship are a parallel array (OwnedShip.weapons), so mount N holds weapon N.
## Static data: edit the ship .tres, never change it while playing.

enum Type { FIXED, TURRET }
## A weapon fits a mount of its own size or larger. CAPITAL (added after the others, so older
## resources keep their numbers) is the long-range mount only capital ships have.
enum Size { SMALL, MEDIUM, LARGE, CAPITAL }

## FIXED mounts fire straight ahead. TURRET mounts aim at the target within
## `arc_degrees` either side of the ship's heading.
@export var type: Type = Type.FIXED
@export var size: Size = Size.SMALL
## Where the shots leave the ship, in ship space (x forward, y to the right)
## in world pixels.
@export var offset: Vector2 = Vector2.ZERO
## Half-angle a turret can swing away from the heading. Ignored by fixed mounts.
@export_range(0.0, 180.0) var arc_degrees: float = 90.0


## "Small", "Medium", "Large" or "Capital".
static func size_name(of_size: Size) -> String:
	return str(Size.keys()[of_size]).capitalize()


## "Fixed" or "Turret".
static func type_name(of_type: Type) -> String:
	return str(Type.keys()[of_type]).capitalize()


## For people: "Medium turret".
func describe() -> String:
	return "%s %s" % [size_name(size), type_name(type).to_lower()]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if type == Type.TURRET and arc_degrees <= 0.0:
		problems.append("a turret mount needs an arc above zero")
	return problems
