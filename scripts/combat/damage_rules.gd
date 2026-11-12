class_name DamageRules
extends Resource
## The tunable rules for how damage moves through a ship's layers, and what
## repairs and weapon sales cost. One file: resources/combat/damage_rules.tres.
## See DamageModel for how these numbers are used.

const PATH := "res://resources/combat/damage_rules.tres"

static var _shared: DamageRules


## The project's rules (loaded once).
static func shared() -> DamageRules:
	if _shared == null:
		_shared = load(PATH)
	return _shared

## While armour remains, damage reaching the armour layer is cut by this
## fraction (0.25 = armour blocks a quarter of it).
@export_range(0.0, 0.95) var armour_damage_reduction: float = 0.25
## Share of the damage the armour absorbs that ALSO hurts the hull while armour
## holds (0 = the hull is untouched until the armour is gone).
@export_range(0.0, 1.0) var armour_bleed_through: float = 0.0
## Whether shields come back to full when the ship lands.
@export var shield_regen_on_land: bool = true

## Credits to repair one point of armour / of hull at a shipyard.
@export var repair_cost_per_armour: float = 20.0
@export var repair_cost_per_hull: float = 40.0
## Share of a weapon's price paid back when it is sold.
@export_range(0.0, 1.0) var weapon_sell_fraction: float = 0.5


func validate() -> Array[String]:
	var problems: Array[String] = []
	if repair_cost_per_armour < 0.0 or repair_cost_per_hull < 0.0:
		problems.append("repair costs cannot be negative")
	return problems
