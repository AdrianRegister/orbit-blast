class_name Faction
extends Resource
## One faction (a government, a company, ...). One .tres per faction in
## resources/factions/. Everything that belongs to a faction (locations, star
## systems, ship models) holds a reference to its Faction resource, so the
## faction's name is written in exactly one place and can be changed there.
## Comparisons between factions use `id`, never the display name.
##
## This is the faction's identity and its politics. The player's standing with a
## faction is separate (ReputationManager), and so are who owns what
## (TerritoryManager) and, later, wars.

## Permanent unique id, e.g. &"faction_1". Never change it once content or saves
## refer to it; change `display_name` instead.
@export var id: StringName = &""
## The name shown to the player, e.g. "Federation".
@export var display_name: String = ""
## Colours that identify the faction on maps and screens.
@export var primary_colour: Color = Color(0.35, 0.6, 1.0)
@export var secondary_colour: Color = Color.WHITE
## One or two sentences: what the faction is.
@export_multiline var description: String = ""
## How it is run and what holds it together.
@export_multiline var political_identity: String = ""
## Its history and internal politics.
@export_multiline var background: String = ""
## How much war the faction can wage. An arbitrary number for now; it will be
## computed from the faction's territory and fleets (see wars_system.md).
@export var military_strength: int = 0
## How this faction regards the others (see FactionRelation).
@export var relations: Array[FactionRelation] = []


## The relation to another faction, or null if none is defined (which means no
## particular feelings either way).
func get_relation(other_id: StringName) -> FactionRelation:
	for relation in relations:
		if relation != null and relation.other_faction_id == other_id:
			return relation
	return null


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if military_strength < 0:
		problems.append("military_strength is negative")
	var seen := {}
	for relation in relations:
		if relation == null:
			problems.append("relations has an empty entry")
		elif relation.other_faction_id == &"" or relation.other_faction_id == id:
			problems.append("a relation must name a different faction")
		elif seen.has(relation.other_faction_id):
			problems.append("relation to '%s' is listed twice" % relation.other_faction_id)
		else:
			seen[relation.other_faction_id] = true
	return problems
