class_name NpcShipDetails
extends TargetDetails
## The extra information the HUD shows for a targeted NPC ship. It is a
## TargetDetails like InhabitedData, so the HUD and targeting code need no
## knowledge of NPCs. Ships are not dockable.

var ship_type_name: String = ""
var faction_name: String = ""
## Where the ship stands in its formation ("Wedge squadron, 3 of 5") and what it
## does there ("Squadron leader"). Empty for a ship in no formation: no rows then.
var formation_text: String = "":
	set(value):
		if value != formation_text:
			formation_text = value
			emit_changed()
var role_text: String = "":
	set(value):
		if value != role_text:
			role_text = value
			emit_changed()
var status: String = "":
	set(value):
		if value != status:
			status = value
			emit_changed()


func get_rows() -> Array:
	var rows: Array = [
		["FACTION", faction_name],
		["SHIP", ship_type_name],
		["STATUS", status],
	]
	if not formation_text.is_empty():
		rows.append(["FORMATION", formation_text])
		rows.append(["ROLE", role_text])
	return rows
