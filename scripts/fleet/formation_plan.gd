class_name FormationPlan
extends RefCounted
## What FleetComposer decided a unit consists of: which ship models, in which
## sub-units, in which shape. Pure data; FleetSpawner turns it into ships.

## The recipe it was drawn from.
var recipe: FormationRecipe
## The unit's own ships (a squadron's fighters, a battle group's frigates and
## cruisers, a fleet's capital ships, a convoy's freighters and escorts).
var ships: Array[ShipType] = []
## The smaller units inside it (a battle group's squadrons).
var children: Array[FormationPlan] = []
## The shape chosen for it (null for a fleet).
var shape: FormationShape


## Every ship in the plan, the sub-units' included.
func ship_count() -> int:
	var total := ships.size()
	for child in children:
		total += child.ship_count()
	return total


## Every ship model in the plan, the sub-units' included.
func all_ship_types() -> Array[ShipType]:
	var result: Array[ShipType] = []
	result.append_array(ships)
	for child in children:
		result.append_array(child.all_ship_types())
	return result


## How many ships of `ship_class` (or a kind of it) the unit has of its own.
func count_of(ship_class: ShipClass) -> int:
	var total := 0
	for type in ships:
		if type.stats.ship_class != null and type.stats.ship_class.is_a(ship_class):
			total += 1
	return total


## A line for people: "Squadron (Wedge): 3 x Federation Fighter, 1 x Federation Heavy Fighter".
func describe() -> String:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for type in ships:
		var name := type.display_name
		if not counts.has(name):
			order.append(name)
		counts[name] = counts.get(name, 0) + 1
	var parts: Array[String] = []
	for name in order:
		parts.append("%d x %s" % [counts[name], name])
	for child in children:
		parts.append("[%s]" % child.describe())
	var title := recipe.display_name if recipe != null else "Unit"
	if shape != null:
		title += " (%s)" % shape.display_name
	return "%s: %s" % [title, ", ".join(parts)]
