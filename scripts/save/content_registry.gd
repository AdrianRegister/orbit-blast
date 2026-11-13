class_name ContentRegistry
extends RefCounted
## Turns the ids stored in save files back into the static Resources they
## stand for (commodities, locations, ship stats, star system scenes). Save
## files never contain Resources or paths, only ids; this is the single place
## that knows where each kind of content lives.
##
## It lists the content folders once when created. Problems found while doing so
## (a missing or duplicate id) are collected in `problems`.

const FACTION_DIR := "res://resources/factions/"
const COMMODITY_DIR := "res://resources/commodities/"
const LOCATION_DIR := "res://resources/locations/"
const SHIP_STATS_DIR := "res://resources/ships/"
const UPGRADE_DIR := "res://resources/upgrades/"
const WEAPON_DIR := "res://resources/weapons/"
const SHIP_CLASS_DIR := "res://resources/ship_classes/"
const FORMATION_SHAPE_DIR := "res://resources/formations/shapes/"
const FORMATION_RECIPE_DIR := "res://resources/formations/recipes/"
const SYSTEM_CLASS_DIR := "res://resources/system_classes/"
const GALAXY_PATH := "res://resources/universe/galaxy.tres"

## Human-readable problems found while building the registry. Empty when sound.
var problems: Array[String] = []

var _factions: Dictionary = {}  # StringName -> Faction
var _commodities: Dictionary = {}  # StringName -> Commodity
var _locations: Dictionary = {}  # StringName -> InhabitedData
var _ship_stats: Dictionary = {}  # StringName -> ShipStats
var _upgrades: Dictionary = {}  # StringName -> UpgradeDefinition
var _weapons: Dictionary = {}  # StringName -> WeaponDefinition
var _ship_classes: Dictionary = {}  # StringName -> ShipClass
var _formation_shapes: Dictionary = {}  # StringName -> FormationShape
var _formation_recipes: Dictionary = {}  # StringName -> FormationRecipe
var _system_classes: Dictionary = {}  # StringName -> SystemClass
var _galaxy: Galaxy


## `galaxy` replaces the project's galaxy (used by tests).
func _init(galaxy: Galaxy = null) -> void:
	_index(FACTION_DIR, _factions, "faction", "id")
	_index(COMMODITY_DIR, _commodities, "commodity", "id")
	_index(LOCATION_DIR, _locations, "location", "id")
	_index(SHIP_STATS_DIR, _ship_stats, "ship", "id")
	_index(UPGRADE_DIR, _upgrades, "upgrade", "id")
	_index(WEAPON_DIR, _weapons, "weapon", "id")
	_index(SHIP_CLASS_DIR, _ship_classes, "ship class", "id")
	_index(FORMATION_SHAPE_DIR, _formation_shapes, "formation shape", "id")
	_index(FORMATION_RECIPE_DIR, _formation_recipes, "formation recipe", "id")
	_index(SYSTEM_CLASS_DIR, _system_classes, "system class", "id")
	_galaxy = galaxy if galaxy != null else load(GALAXY_PATH) as Galaxy
	if _galaxy == null:
		problems.append("galaxy missing: %s" % GALAXY_PATH)
	else:
		problems.append_array(_galaxy.validate())
		problems.append_array(_check_capitals())


func faction(id: StringName) -> Faction:
	return _factions.get(id)


func factions() -> Array[Faction]:
	var result: Array[Faction] = []
	var ids := _factions.keys()
	ids.sort_custom(func(a, b) -> bool: return str(a) < str(b))  # (StringNames do not sort alphabetically)
	for id in ids:
		result.append(_factions[id])
	return result


func commodity(id: StringName) -> Commodity:
	return _commodities.get(id)


func location(id: StringName) -> InhabitedData:
	return _locations.get(id)


## Every location, sorted by id (so anything built from them is reproducible).
func locations() -> Array[InhabitedData]:
	var result: Array[InhabitedData] = []
	var ids := _locations.keys()
	ids.sort_custom(func(a, b) -> bool: return str(a) < str(b))  # (StringNames do not sort alphabetically)
	for id in ids:
		result.append(_locations[id])
	return result


## Every commodity, sorted by id.
func commodities() -> Array[Commodity]:
	var result: Array[Commodity] = []
	var ids := _commodities.keys()
	ids.sort_custom(func(a, b) -> bool: return str(a) < str(b))  # (StringNames do not sort alphabetically)
	for id in ids:
		result.append(_commodities[id])
	return result


func ship_stats(id: StringName) -> ShipStats:
	return _ship_stats.get(id)


func upgrade(id: StringName) -> UpgradeDefinition:
	return _upgrades.get(id)


func weapon(id: StringName) -> WeaponDefinition:
	return _weapons.get(id)


func ship_class(id: StringName) -> ShipClass:
	return _ship_classes.get(id)


## Every ship class, smallest tier first (ties by id).
func ship_classes() -> Array[ShipClass]:
	var result: Array[ShipClass] = []
	result.assign(_ship_classes.values())
	result.sort_custom(func(a: ShipClass, b: ShipClass) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return str(a.id) < str(b.id))
	return result


func formation_shape(id: StringName) -> FormationShape:
	return _formation_shapes.get(id)


## Every formation shape, sorted by id.
func formation_shapes() -> Array[FormationShape]:
	var result: Array[FormationShape] = []
	result.assign(_formation_shapes.values())
	result.sort_custom(func(a: FormationShape, b: FormationShape) -> bool: return str(a.id) < str(b.id))
	return result


func formation_recipe(id: StringName) -> FormationRecipe:
	return _formation_recipes.get(id)


## Every formation recipe, sorted by id.
func formation_recipes() -> Array[FormationRecipe]:
	var result: Array[FormationRecipe] = []
	result.assign(_formation_recipes.values())
	result.sort_custom(func(a: FormationRecipe, b: FormationRecipe) -> bool: return str(a.id) < str(b.id))
	return result


## Every ship model, cheapest first (ties by id).
func all_ship_stats() -> Array[ShipStats]:
	var result: Array[ShipStats] = []
	result.assign(_sorted_by_price(_ship_stats.values()))
	return result


## Every upgrade, cheapest first (ties by id).
func all_upgrades() -> Array[UpgradeDefinition]:
	var result: Array[UpgradeDefinition] = []
	result.assign(_sorted_by_price(_upgrades.values()))
	return result


## Every weapon, cheapest first (ties by id).
func all_weapons() -> Array[WeaponDefinition]:
	var result: Array[WeaponDefinition] = []
	result.assign(_sorted_by_price(_weapons.values()))
	return result


func _sorted_by_price(items: Array) -> Array:
	var sorted := items.duplicate()
	sorted.sort_custom(func(a, b) -> bool:
		if a.price != b.price:
			return a.price < b.price
		return str(a.id) < str(b.id))
	return sorted


## The description of a system for the map and for contracts; null if unknown.
func system_summary(id: StringName) -> SystemSummary:
	return _galaxy.get_summary(id) if _galaxy != null else null


## The largest cargo capacity of any ship model.
func max_cargo_capacity() -> int:
	var best := 0
	for model: ShipStats in _ship_stats.values():
		best = maxi(best, model.cargo_capacity)
	return best


func system_class(id: StringName) -> SystemClass:
	return _system_classes.get(id)


func system_classes() -> Array[SystemClass]:
	var result: Array[SystemClass] = []
	var ids := _system_classes.keys()
	ids.sort_custom(func(a, b) -> bool: return str(a) < str(b))
	for id in ids:
		result.append(_system_classes[id])
	return result


func has_system(id: StringName) -> bool:
	return _galaxy != null and _galaxy.has_system(id)


func system_scene(id: StringName) -> PackedScene:
	return _galaxy.get_scene(id) if _galaxy != null else null


func _index(directory: String, into: Dictionary, kind: String, id_property: String) -> void:
	for file_name in ResourceLoader.list_directory(directory):
		if file_name.ends_with("/"):
			_index(directory + file_name, into, kind, id_property)  # a sub folder (generated content)
			continue
		if not file_name.ends_with(".tres"):
			continue
		var resource := load(directory + file_name)
		if resource == null:
			problems.append("%s file %s could not be loaded" % [kind, file_name])
			continue
		var id: StringName = resource.get(id_property)
		if id == &"":
			problems.append("%s file %s has no id" % [kind, file_name])
		elif into.has(id):
			problems.append("%s id '%s' is used twice" % [kind, id])
		else:
			into[id] = resource


## Problems with the factions' capitals: each must be an inhabited system whose
## class can be a centre of power.
func _check_capitals() -> Array[String]:
	var found: Array[String] = []
	for faction in _factions.values():
		if faction.capital_system == &"":
			continue
		if not _galaxy.has_system(faction.capital_system):
			found.append("the capital of '%s' (%s) is not a system" % [faction.id, faction.capital_system])
			continue
		if not _galaxy.is_inhabited(faction.capital_system):
			found.append("the capital of '%s' (%s) is not inhabited" % [faction.id, faction.capital_system])
		var system_class := _galaxy.get_system_class(faction.capital_system)
		if system_class == null or not system_class.can_be_centre():
			found.append("the capital of '%s' (%s) must be a system whose class can be a centre of power" % [faction.id, faction.capital_system])
	return found
