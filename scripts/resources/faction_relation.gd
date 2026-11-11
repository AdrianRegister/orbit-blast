class_name FactionRelation
extends Resource
## How one faction regards another. Listed in `Faction.relations`. This belongs
## to the pair of factions and has nothing to do with the player's reputation:
## factions have politics of their own (alliances, rivalries, wars). The values
## here are the starting relations; when wars exist they will be changed while
## playing by a runtime layer, in the way TerritoryManager does for ownership.

## The id of the other faction.
@export var other_faction_id: StringName = &""
## -100 (bitter enemies) to +100 (close allies); 0 = no strong feelings.
@export_range(-100, 100) var attitude: int = 0
## Whether the two are at war.
@export var at_war: bool = false
