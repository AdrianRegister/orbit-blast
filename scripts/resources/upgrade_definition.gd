class_name UpgradeDefinition
extends Resource
## A ship upgrade that can be installed at an outfitter. One .tres per upgrade
## in resources/upgrades/. The definition is static data shared by every ship;
## which upgrades a ship has is stored on the ship (OwnedShip).
##
## Cargo upgrades stack: each copy adds `cargo_bonus`, up to `max_per_ship`.
## Engine and manoeuvrability upgrades come in tiers: tier N needs tier N-1
## installed and its bonus REPLACES the lower tier's (it is not added to it).

enum Category { CARGO, ENGINE, MANOEUVRE }

## Permanent unique id, e.g. &"engine_1". Save files refer to it.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.CARGO
## Price in credits.
@export var price: int = 0
## For tiered categories: 1 for the first level, 2 for the next, and so on.
@export var tier: int = 1
## How many copies one ship can have installed.
@export var max_per_ship: int = 1

## Extra cargo units (flat).
@export var cargo_bonus: int = 0
## Fractions of the ship model's BASE value, e.g. 0.10 = +10%.
@export var speed_bonus: float = 0.0
@export var thrust_bonus: float = 0.0
@export var turn_bonus: float = 0.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if price < 0:
		problems.append("price is negative")
	if tier < 1:
		problems.append("tier must be at least 1")
	if max_per_ship < 1:
		problems.append("max_per_ship must be at least 1")
	if category == Category.CARGO and cargo_bonus <= 0:
		problems.append("a cargo upgrade needs a cargo_bonus")
	if category == Category.ENGINE and (speed_bonus <= 0.0 or thrust_bonus <= 0.0):
		problems.append("an engine upgrade needs speed_bonus and thrust_bonus")
	if category == Category.MANOEUVRE and turn_bonus <= 0.0:
		problems.append("a manoeuvrability upgrade needs a turn_bonus")
	if category != Category.CARGO and max_per_ship != 1:
		problems.append("tiered upgrades must have max_per_ship 1")
	return problems
