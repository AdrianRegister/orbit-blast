class_name RecipeChild
extends Resource
## A sub-unit in a FormationRecipe: "2 to 3 squadrons" in a battle group, "2 to 3
## battle groups" in a fleet.

@export var recipe: FormationRecipe
@export var min_count: int = 1
@export var max_count: int = 1


func validate() -> Array[String]:
	var problems: Array[String] = []
	if recipe == null:
		problems.append("a child has no recipe")
	if min_count < 0 or max_count < min_count:
		problems.append("a child's min_count and max_count do not make a range")
	return problems
