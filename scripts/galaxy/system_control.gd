class_name SystemControl
extends RefCounted
## Who controls a star system, worked out from who owns its settlements (see
## TerritoryManager.get_control). A snapshot: read it, do not keep it.
##
##   UNCLAIMED  - nobody owns anything there.
##   CONTROLLED - one faction owns it: all of its settlements, or the system
##                itself when it has none.
##   CONTESTED  - settlements belong to two or more factions. The system then has
##                no owner; `factions` lists who is there.
## A later war system can add a "dominant controller" for contested systems here.

enum Status { UNCLAIMED, CONTROLLED, CONTESTED }

var status: Status = Status.UNCLAIMED
## The controlling faction. Null unless the status is CONTROLLED.
var controller: Faction
## Every faction that owns a settlement in the system (or the claimant of an
## empty system), sorted by id.
var factions: Array[Faction] = []


func is_contested() -> bool:
	return status == Status.CONTESTED


func is_controlled_by(faction: Faction) -> bool:
	return status == Status.CONTROLLED and controller != null and faction != null and controller.id == faction.id


## Whether a faction owns a settlement here (for a contested system, one of the
## sides).
func involves(faction: Faction) -> bool:
	for candidate in factions:
		if faction != null and candidate.id == faction.id:
			return true
	return false


## For the map and panels: "Federation", "Contested: Federation, Rebels" or "None".
func get_text() -> String:
	match status:
		Status.CONTROLLED:
			return controller.display_name
		Status.CONTESTED:
			var names := PackedStringArray()
			for faction in factions:
				names.append(faction.display_name)
			return "Contested: %s" % ", ".join(names)
	return "None"


## Same status and the same factions (used to tell whether control changed).
func equals(other: SystemControl) -> bool:
	if other == null or status != other.status or factions.size() != other.factions.size():
		return false
	for i in factions.size():
		if factions[i].id != other.factions[i].id:
			return false
	return true
