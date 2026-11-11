class_name ShipType
extends Resource
## A kind of ship that NPC traffic can use. One .tres per type in
## resources/ship_types/. The look and flight numbers come from the ship model
## (ShipStats), so a model is defined once and used by both the player and the
## traffic; this adds only what traffic needs to know.

enum Category { CIVILIAN, MILITARY }

## The ship model: name, sprite and base flight numbers.
@export var stats: ShipStats
## Lets the traffic system split its population between civilian and military later.
## Military ships spawn as traffic but are never sold to the player until faction
## reputation exists: they are simply not listed by any shipyard.
@export var category: Category = Category.CIVILIAN
## How likely this type is picked relative to the others in a TrafficConfig.
@export_range(0.0, 100.0) var spawn_weight: float = 1.0

## Shown in the HUD type line.
var display_name: String:
	get:
		return stats.display_name if stats != null else ""
var texture: Texture2D:
	get:
		return stats.texture if stats != null else null
var sprite_scale: float:
	get:
		return stats.get_scale() if stats != null else 0.15


## Visual size in world pixels, used for the click area and selection brackets.
func get_size() -> Vector2:
	return stats.get_size() if stats != null else Vector2(64, 64)


func validate() -> Array[String]:
	var problems: Array[String] = []
	if stats == null:
		problems.append("stats is not set")
	else:
		problems.append_array(stats.validate())
	return problems
