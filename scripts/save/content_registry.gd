class_name ContentRegistry
extends RefCounted
## Turns the ids stored in save files back into the static Resources they
## stand for (commodities, locations, ship stats, star system scenes). Save
## files never contain Resources or paths, only ids; this is the single place
## that knows where each kind of content lives.
##
## It lists the content folders once when created. Problems found while doing so
## (a missing or duplicate id) are collected in `problems`.

const COMMODITY_DIR := "res://resources/commodities/"
const LOCATION_DIR := "res://resources/locations/"
const SHIP_STATS_DIR := "res://resources/ships/"
const UPGRADE_DIR := "res://resources/upgrades/"
const SYSTEM_CATALOG_PATH := "res://resources/universe/system_catalog.tres"

## Human-readable problems found while building the registry. Empty when sound.
var problems: Array[String] = []

var _commodities: Dictionary = {}  # StringName -> Commodity
var _locations: Dictionary = {}  # StringName -> InhabitedData
var _ship_stats: Dictionary = {}  # StringName -> ShipStats
var _upgrades: Dictionary = {}  # StringName -> UpgradeDefinition
var _catalog: SystemCatalog


## `catalog` replaces the project's system catalog (used by tests).
func _init(catalog: SystemCatalog = null) -> void:
	_index(COMMODITY_DIR, _commodities, "commodity", "id")
	_index(LOCATION_DIR, _locations, "location", "id")
	_index(SHIP_STATS_DIR, _ship_stats, "ship", "id")
	_index(UPGRADE_DIR, _upgrades, "upgrade", "id")
	_catalog = catalog if catalog != null else load(SYSTEM_CATALOG_PATH) as SystemCatalog
	if _catalog == null:
		problems.append("system catalog missing: %s" % SYSTEM_CATALOG_PATH)
	else:
		problems.append_array(_catalog.validate())


func commodity(id: StringName) -> Commodity:
	return _commodities.get(id)


func location(id: StringName) -> InhabitedData:
	return _locations.get(id)


func ship_stats(id: StringName) -> ShipStats:
	return _ship_stats.get(id)


func upgrade(id: StringName) -> UpgradeDefinition:
	return _upgrades.get(id)


func has_system(id: StringName) -> bool:
	return _catalog != null and _catalog.has_system(id)


func system_scene(id: StringName) -> PackedScene:
	return _catalog.get_scene(id) if _catalog != null else null


func _index(directory: String, into: Dictionary, kind: String, id_property: String) -> void:
	for file_name in ResourceLoader.list_directory(directory):
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
