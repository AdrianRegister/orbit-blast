class_name RecipeGroup
extends Resource
## One line of a FormationRecipe: "this many ships from these classes". For
## example a squadron's fighters and heavy fighters (weights 2 and 1), or a
## convoy's freighters (any cargo ship).
##
## The numbers are data: edit the recipe's .tres to change who goes in a group.

enum Category { ANY, CIVILIAN, MILITARY }
enum FactionRule {
	## Ships of the group's own faction only (a faction's warships).
	OWN,
	## Ships of the group's own faction, or of no faction (merchants, escorts anyone can field).
	OWN_OR_NONE,
}

## A name for the group in messages and tests ("fighters", "escorts").
@export var label: String = ""
## The classes a ship in this group may have. A ship matches a class if its own class
## is that class or a kind of it (so an abstract class like "cargo ship" takes every
## freighter, including ones added later).
@export var classes: Array[ShipClass] = []
## How the group's ships are shared between `classes`, in the same order. 2 and 1 gives
## two thirds and one third. Left empty, every class counts the same.
@export var weights: Array[float] = []
## How many ships the group has, at least and at most.
@export var min_count: int = 1
@export var max_count: int = 1
## Each class with a weight keeps at least this many ships (when the group has enough).
@export var min_each: int = 0
## Which ship models may fill it.
@export var category: Category = Category.ANY
@export var faction_rule: FactionRule = FactionRule.OWN_OR_NONE


## The weight of the class at `index` (1 when no weights are given).
func weight_of(index: int) -> float:
	if weights.is_empty():
		return 1.0
	return weights[index] if index < weights.size() else 0.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if classes.is_empty():
		problems.append("%s: no classes" % label)
	for ship_class in classes:
		if ship_class == null:
			problems.append("%s: an empty class entry" % label)
	if not weights.is_empty() and weights.size() != classes.size():
		problems.append("%s: weights and classes differ in length" % label)
	var total := 0.0
	for index in classes.size():
		var weight := weight_of(index)
		if weight < 0.0:
			problems.append("%s: a negative weight" % label)
		total += weight
	if total <= 0.0:
		problems.append("%s: the weights add up to nothing" % label)
	if min_count < 0 or max_count < min_count:
		problems.append("%s: min_count and max_count do not make a range" % label)
	if min_each < 0:
		problems.append("%s: min_each is negative" % label)
	return problems
