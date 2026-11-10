class_name TargetDetails
extends Resource
## Base class for the extra information a targetable object can show in the
## HUD. Subclass it for each kind of object (inhabited nodes now, ships later)
## and override get_rows(). The HUD and the targeting system only ever call
## get_rows(), so they never need to know which kind they are showing.

## Whether the player can dock with / land on objects carrying this data.
func is_dockable() -> bool:
	return false


## Returns display rows as [caption, value] pairs, e.g. ["OWNED BY", "Faction"].
func get_rows() -> Array:
	return []
