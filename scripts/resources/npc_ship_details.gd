class_name NpcShipDetails
extends TargetDetails
## The extra information the HUD shows for a targeted NPC ship. It is a
## TargetDetails like InhabitedData, so the HUD and targeting code need no
## knowledge of NPCs. Ships are not dockable.

var ship_type_name: String = ""
var faction_name: String = ""
var status: String = "":
	set(value):
		if value != status:
			status = value
			emit_changed()


func get_rows() -> Array:
	return [
		["FACTION", faction_name],
		["SHIP", ship_type_name],
		["STATUS", status],
	]
