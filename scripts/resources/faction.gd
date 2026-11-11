class_name Faction
extends Resource
## One faction (a government, a company, ...). One .tres per faction in
## resources/factions/. Everything that belongs to a faction (locations, star
## systems, ship models) holds a reference to its Faction resource, so the
## faction's name is written in exactly one place and can be changed there.
## Comparisons between factions use `id`, never the display name.
##
## Relations between factions and reputation will be added here later.

## Permanent unique id, e.g. &"faction_1". Never change it once content or saves
## refer to it; change `display_name` instead.
@export var id: StringName = &""
## The name shown to the player, e.g. "Federation".
@export var display_name: String = ""
## Colour used for this faction on maps.
@export var colour: Color = Color(0.35, 0.6, 1.0)
@export_multiline var description: String = ""


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	return problems
