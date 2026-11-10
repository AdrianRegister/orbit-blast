class_name ShipType
extends Resource
## A kind of ship (Shuttle, Freighter, ...) that NPC traffic can use. One .tres
## per type in resources/ship_types/. It bundles the look with the existing
## ShipStats flight numbers, so adding a ship type needs no code.

enum Category { CIVILIAN, MILITARY }

@export var display_name: String = ""
## Shown in the HUD type line and used to pick the sprite.
@export var texture: Texture2D
## Sprite scale. Ship art must point up. A 500 px sprite at 0.15 is 75 px wide.
@export var sprite_scale: float = 0.15
## Flight numbers (thrust, turn rate, top speed). Cargo is unused by NPCs.
@export var stats: ShipStats
## Lets the traffic system split its population between civilian and military later.
@export var category: Category = Category.CIVILIAN
## How likely this type is picked relative to the others in a TrafficConfig.
@export_range(0.0, 100.0) var spawn_weight: float = 1.0


## Visual size in world pixels, used for the click area and selection brackets.
func get_size() -> Vector2:
	if texture == null:
		return Vector2(64, 64)
	return texture.get_size() * sprite_scale


func validate() -> Array[String]:
	var problems: Array[String] = []
	if display_name.is_empty():
		problems.append("display_name is empty")
	if texture == null:
		problems.append("texture is not set")
	if stats == null:
		problems.append("stats is not set")
	return problems
