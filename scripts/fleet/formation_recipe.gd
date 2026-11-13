class_name FormationRecipe
extends Resource
## The composition rules of one kind of military or civilian unit, as data: a
## squadron, a battle group, a fleet, a cargo convoy. One .tres per recipe in
## resources/formations/recipes/. FleetComposer turns a recipe into a plan (which
## ship models, how many); FleetSpawner turns the plan into ships.
##
## A recipe lists groups of ships (RecipeGroup: "fighters and heavy fighters, 2:1,
## 3 to 6 of them") and sub-units (RecipeChild: "2 to 3 squadrons"). Changing who
## may be in a unit is an edit to a .tres file, not to code.

## What the unit is. SQUADRON, BATTLE_GROUP and CONVOY become a Formation; a FLEET
## becomes a WarFleet (no shape: its parts keep to a leash around the flagship).
enum Unit { SQUADRON, BATTLE_GROUP, FLEET, CONVOY }

## Permanent unique id, e.g. &"squadron". Never change it once content refers to it.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var unit: Unit = Unit.SQUADRON

## The ships the unit has of its own.
@export var groups: Array[RecipeGroup] = []
## The most and fewest ships those groups add up to (0 = no limit). A squadron has
## 3 to 6 ships however its groups are drawn.
@export var min_ships: int = 0
@export var max_ships: int = 0
## The smaller units it is made of.
@export var children: Array[RecipeChild] = []

## The shapes a unit of this recipe may take, when none is asked for (the first is
## the default). Not used by a fleet.
@export var shapes: Array[FormationShape] = []
## A convoy is civilian: no military faction escorts it, whatever the system.
@export var civilian: bool = false


## The Formation kind this recipe builds (not valid for a fleet).
func formation_kind() -> Formation.Kind:
	match unit:
		Unit.BATTLE_GROUP:
			return Formation.Kind.BATTLE_GROUP
		Unit.CONVOY:
			return Formation.Kind.CONVOY
	return Formation.Kind.SQUADRON


## The shape a unit of this recipe takes by default, or null (a fleet has none).
func default_shape() -> FormationShape:
	return shapes[0] if not shapes.is_empty() else null


## The fewest and most ships a unit built from this recipe can have, counting
## everything inside it.
func ship_count_range() -> Vector2i:
	var low := 0
	var high := 0
	for group in groups:
		low += group.min_count
		high += group.max_count
	if min_ships > 0:
		low = maxi(low, min_ships)
	if max_ships > 0:
		high = mini(high, max_ships)
	for child in children:
		if child.recipe == null:
			continue
		var inner := child.recipe.ship_count_range()
		low += child.min_count * inner.x
		high += child.max_count * inner.y
	return Vector2i(low, high)


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if groups.is_empty() and children.is_empty():
		problems.append("%s: has neither groups nor children" % id)
	var direct_low := 0
	var direct_high := 0
	for group in groups:
		if group == null:
			problems.append("%s: an empty group entry" % id)
			continue
		for problem in group.validate():
			problems.append("%s: %s" % [id, problem])
		direct_low += group.min_count
		direct_high += group.max_count
	for child in children:
		if child == null:
			problems.append("%s: an empty child entry" % id)
			continue
		for problem in child.validate():
			problems.append("%s: %s" % [id, problem])
		if child.recipe != null and child.recipe.unit == Unit.FLEET:
			problems.append("%s: a fleet cannot be inside another unit" % id)
	if max_ships > 0 and (max_ships < min_ships or min_ships > direct_high or max_ships < direct_low):
		problems.append("%s: min_ships and max_ships cannot be met by the groups" % id)
	if unit != Unit.FLEET and shapes.is_empty():
		problems.append("%s: needs at least one shape" % id)
	for shape in shapes:
		if shape == null:
			problems.append("%s: an empty shape entry" % id)
	return problems
