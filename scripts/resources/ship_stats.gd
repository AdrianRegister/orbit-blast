class_name ShipStats
extends Resource
## A ship model: everything shared by every ship of one kind (name, price,
## look and base flight numbers). One .tres per model in resources/ships/.
## Individual ships a player owns refer to a model and add their own name and
## upgrades (see OwnedShip); the numbers actually used in play are computed by
## ShipSpecs from the base values here plus the installed upgrades.
## Edit the .tres files, not the code.

## Permanent unique id, e.g. &"shuttle". Save files refer to the ship by this id,
## so it must never change once saves exist.
@export var id: StringName = &""
## Model name shown in shipyards and the HUD, e.g. "Shuttle".
@export var display_name: String = ""
@export_multiline var description: String = ""
## The faction this ship belongs to, as plain text until factions exist (the
## Federation is "TestFaction_1" for now). A ship with a faction can only be
## bought at a shipyard of a location owned by that faction. Empty = any shipyard.
@export var faction_name: String = ""
## Purchase price in credits. Also what the model is worth as a trade-in.
@export var price: int = 0

## Sprite. Ship art must point up. A 500 px sprite at 0.15 is 75 px wide.
@export var texture: Texture2D
@export var sprite_scale: float = 0.15

## Base acceleration while thrusting, in pixels per second squared.
@export var thrust: float = 300.0
## Base rotation speed in radians per second.
@export var turn_rate: float = 3.0
## Base speed limit in pixels per second.
@export var max_speed: float = 500.0
## Base cargo hold size, in units of cargo.
@export var cargo_capacity: int = 500


## Visual size in world pixels, used for the click area and selection brackets.
func get_size() -> Vector2:
	if texture == null:
		return Vector2(64, 64)
	return texture.get_size() * sprite_scale


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if texture == null:
		problems.append("texture is not set")
	if price < 0:
		problems.append("price is negative")
	if thrust <= 0.0 or turn_rate <= 0.0 or max_speed <= 0.0:
		problems.append("thrust, turn_rate and max_speed must be above zero")
	if cargo_capacity < 0:
		problems.append("cargo_capacity is negative")
	return problems
