class_name InhabitedData
extends TargetDetails
## Everything individual about one inhabited location (a planet or a station).
## Lives in a .tres file under resources/locations/ and is assigned to an
## InhabitedNode instance. Position is not stored here: it belongs to the
## star system the location is placed in.
## Faction and trade goods are plain strings until those systems exist.

## Name shown in the HUD and on the settlement screen.
@export var display_name: String = "":
	set(value):
		display_name = value
		emit_changed()

@export var faction_name: String = "":
	set(value):
		faction_name = value
		emit_changed()

@export var population: int = 0:
	set(value):
		population = value
		emit_changed()

@export var exported_goods: Array[String] = []:
	set(value):
		exported_goods = value
		emit_changed()

@export var imported_goods: Array[String] = []:
	set(value):
		imported_goods = value
		emit_changed()

## Optional picture for the settlement screen. Empty = the screen's default.
@export var picture: Texture2D

## Visual size in world pixels: a planet's diameter, or a station ring's diameter.
@export var size: float = 100.0

## Distance within which the player may dock. 0 = automatic: the edge of the
## yellow selection box (half the object's size plus its margin).
@export var docking_range: float = 0.0


func is_dockable() -> bool:
	return true


func get_rows() -> Array:
	return [
		["OWNED BY", faction_name],
		["POPULATION", _format_number(population)],
		["EXPORTS", _join_goods(exported_goods)],
		["IMPORTS", _join_goods(imported_goods)],
	]


## Goods that appear in both lists. Should always be empty.
func get_conflicting_goods() -> Array[String]:
	var conflicts: Array[String] = []
	for good in exported_goods:
		if good in imported_goods:
			conflicts.append(good)
	return conflicts


## Human-readable problems with this data; empty when it is valid.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if display_name.is_empty():
		problems.append("display_name is empty")
	for good in get_conflicting_goods():
		problems.append("'%s' is both imported and exported" % good)
	return problems


func _join_goods(goods: Array[String]) -> String:
	if goods.is_empty():
		return "None"
	return ", ".join(PackedStringArray(goods))


func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return result
