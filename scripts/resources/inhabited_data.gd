class_name InhabitedData
extends TargetDetails
## Everything individual about one inhabited location (a planet or a station).
## Lives in a .tres file under resources/locations/ and is assigned to an
## InhabitedNode instance. Position is not stored here: it belongs to the
## star system the location is placed in.
## Goods are Commodity resources. The faction is a Faction resource.

## Permanent unique id, e.g. &"earth". Save files and contracts refer to the
## location by this id, so it must never change once saves exist.
@export var id: StringName = &""

## Name shown in the HUD and on the settlement screen.
@export var display_name: String = "":
	set(value):
		display_name = value
		emit_changed()

## Who owns this location. Null = nobody.
@export var faction: Faction:
	set(value):
		faction = value
		emit_changed()

## The people living here, as the economy sees them: its economic weight. Production,
## markets, military value and importance are all tuned around it, so it is not changed
## to make a place feel bigger. What the player reads is this times a display scale
## (see PopulationDisplayRules).
@export var population: int = 0:
	set(value):
		population = value
		emit_changed()

## Overrides how many times larger the population shown to the player is than
## `population`, for this location only. 0 = use the economy profile's or the system
## class's scale. (Earth, which holds billions.)
@export var population_display_scale: float = 0.0

## Overrides the economy this location would get from its planet type (or, for a
## station, the default station economy). Leave empty to use the default.
@export var economy_profile: EconomyProfile

## Specialties: commodities this location is especially known for making. They
## add to what its population and profile give (see EconomyModel); the goods
## shown as exports on screen are worked out, not read from here.
## Must not overlap imported_goods.
@export var exported_goods: Array[Commodity] = []:
	set(value):
		exported_goods = value
		emit_changed()

## Specialties: commodities this location is especially short of. Must not
## overlap exported_goods.
@export var imported_goods: Array[Commodity] = []:
	set(value):
		imported_goods = value
		emit_changed()

## Extra military value for a place built for war, on top of what its economy profile
## and size give: a fortress, a major shipbuilding hub (see MilitaryValueRules).
@export var military_value_bonus: float = 0.0

## Ship models this location's shipyard sells. Empty = no shipyard.
@export var shipyard_ships: Array[ShipStats] = []

## Upgrades this location's outfitter offers. Empty = no outfitter.
@export var outfitter_upgrades: Array[UpgradeDefinition] = []

## Weapons this location's outfitter sells. A location with upgrades, weapons or
## both has an outfitter (see has_outfitter()).
@export var outfitter_weapons: Array[WeaponDefinition] = []

## Optional picture for the settlement screen. Empty = the screen's default.
@export var picture: Texture2D

## Visual size in world pixels: a planet's diameter, or a station ring's diameter.
@export var size: float = 100.0

## Distance within which the player may dock. 0 = automatic: the edge of the
## yellow selection box (half the object's size plus its margin).
@export var docking_range: float = 0.0


## Picture for the settlement screen, or null to use the screen's default.
## Subclasses may supply a fallback when `picture` is not set.
func get_picture() -> Texture2D:
	return picture


func is_dockable() -> bool:
	return true


## The owning faction's display name, or "" if nobody owns the location.
func get_faction_name() -> String:
	return faction.display_name if faction != null else ""


## The owning faction's id, or &"" if nobody owns the location.
func faction_id() -> StringName:
	return faction.id if faction != null else &""


## The economy this location gets by default: its own profile if it names one.
## Subclasses add a fallback (a planet's type). Null = the default station economy.
func get_economy_profile() -> EconomyProfile:
	return economy_profile


func get_rows() -> Array:
	var economy := EconomyModel.shared().of(self)
	return [
		["OWNED BY", get_faction_name()],
		["POPULATION", _format_number(population)],
		["EXPORTS", _join_goods(economy.exports())],
		["IMPORTS", _join_goods(economy.imports())],
	]


## Goods that appear in both lists. Should always be empty.
func get_conflicting_goods() -> Array[Commodity]:
	var conflicts: Array[Commodity] = []
	for good in exported_goods:
		if good != null and _has_good(imported_goods, good):
			conflicts.append(good)
	return conflicts


## Human-readable problems with this data; empty when it is valid.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	for good in get_conflicting_goods():
		problems.append("'%s' is both imported and exported" % good.display_name)
	for ship in shipyard_ships:
		if ship == null:
			problems.append("shipyard_ships has an empty entry")
	for upgrade in outfitter_upgrades:
		if upgrade == null:
			problems.append("outfitter_upgrades has an empty entry")
	for weapon in outfitter_weapons:
		if weapon == null:
			problems.append("outfitter_weapons has an empty entry")
	return problems


## Whether this location has an outfitter: it sells upgrades, weapons or both.
func has_outfitter() -> bool:
	return not outfitter_upgrades.is_empty() or not outfitter_weapons.is_empty()


## Whether this location has a shipyard (it sells ships; also where ships are repaired).
func has_shipyard() -> bool:
	return not shipyard_ships.is_empty()


func _has_good(goods: Array[Commodity], good: Commodity) -> bool:
	for candidate in goods:
		if candidate != null and candidate.id == good.id:
			return true
	return false


func _join_goods(goods: Array) -> String:
	var names := PackedStringArray()
	for good in goods:
		if good != null:
			names.append(good.display_name)
	if names.is_empty():
		return "None"
	return ", ".join(names)


func _format_number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return result
