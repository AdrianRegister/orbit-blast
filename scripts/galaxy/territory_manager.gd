class_name TerritoryManager
extends Node
## Who owns what, right now. Settlements (inhabited planets and stations) own
## themselves: the owner of a location is the single fact; who controls a star
## system is worked out from its settlements (get_control), so a system can be
## contested (settlements of different factions) without any system-level
## bookkeeping.
##
## Two layers: the Faction on a location's InhabitedData is its starting owner
## (static content); changes made while playing (a war, later) are kept here as
## overrides and saved in the "territory" section. Everything that needs an
## owner asks this class, so ownership can change at runtime without anything
## holding a stale copy; listen to the signals to refresh what you show.
##
## It is a Node in main.tscn (no Autoload) and the "territory" save section.

## A settlement changed hands. `previous` or `current` is null for "independent".
signal settlement_owner_changed(location_id: StringName, previous: Faction, current: Faction)
## The control status of a system changed (not merely which settlement changed).
signal system_control_changed(system_id: StringName)
## A system that was not contested became contested.
signal system_became_contested(system_id: StringName)
## Anything about ownership changed, including a load. For redrawing views.
signal territory_changed

var _galaxy: Galaxy
var _registry: ContentRegistry
## location id -> Faction (null = independent). Only locations that differ from
## their starting owner.
var _owners: Dictionary = {}


func setup(galaxy: Galaxy, registry: ContentRegistry) -> void:
	_galaxy = galaxy
	_registry = registry
	_owners.clear()


# ------------------------------------------------------------------- settlements

## The faction that owns a location now, or null if nobody does.
func owner_of(location: InhabitedData) -> Faction:
	if location == null:
		return null
	if _owners.has(location.id):
		return _owners[location.id]
	return location.faction


func owner_id_of(location: InhabitedData) -> StringName:
	var faction := owner_of(location)
	return faction.id if faction != null else &""


func owner_name_of(location: InhabitedData) -> String:
	var faction := owner_of(location)
	return faction.display_name if faction != null else ""


## Gives a settlement to a faction (null = independent). Announces the change,
## and a change in the control of its system.
func transfer_settlement(location: InhabitedData, faction: Faction) -> void:
	var previous := owner_of(location)
	if _same(previous, faction):
		return
	var system_id := _galaxy.system_of_location(location.id)
	var before := get_control(system_id)
	if _same(location.faction, faction):
		_owners.erase(location.id)
	else:
		_owners[location.id] = faction
	settlement_owner_changed.emit(location.id, previous, faction)
	var after := get_control(system_id)
	if not before.equals(after):
		system_control_changed.emit(system_id)
		if after.is_contested() and not before.is_contested():
			system_became_contested.emit(system_id)
	territory_changed.emit()


# ------------------------------------------------------------------------ systems

## Who controls a system. Only settlements count (dockable places with people).
## One faction owning them all means it controls the system; two or more means
## the system is contested and has no owner; settlements nobody owns are
## independent and do not count. A system with no settlements goes to whoever
## claims it on the galaxy map.
func get_control(system_id: StringName) -> SystemControl:
	var control := SystemControl.new()
	var summary := _galaxy.get_summary(system_id)
	if summary == null:
		return control
	var present := {}
	var settlements := 0
	for location_id in summary.location_ids:
		var location := _registry.location(location_id)
		if location == null or not location.is_dockable() or location.population <= 0:
			continue
		settlements += 1
		var faction := owner_of(location)
		if faction != null:
			present[faction.id] = faction
	if settlements == 0:
		var claim := _galaxy.get_claim(system_id)
		if claim != null:
			present[claim.id] = claim
	var ids := present.keys()
	ids.sort_custom(func(a, b) -> bool: return str(a) < str(b))  # (StringNames do not sort alphabetically)
	for id in ids:
		control.factions.append(present[id])
	if control.factions.size() == 1:
		control.status = SystemControl.Status.CONTROLLED
		control.controller = control.factions[0]
	elif control.factions.size() > 1:
		control.status = SystemControl.Status.CONTESTED
	return control


func is_contested(system_id: StringName) -> bool:
	return get_control(system_id).is_contested()


func _same(a: Faction, b: Faction) -> bool:
	if a == null or b == null:
		return a == b
	return a.id == b.id


# --------------------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var owners := {}
	for location_id in _owners:
		var faction: Faction = _owners[location_id]
		owners[str(location_id)] = str(faction.id) if faction != null else ""
	return {"owners": owners}


func validate_state(data: Variant, registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary or not data.get("owners") is Dictionary:
		return ["territory owners is not an object"]
	for location_id in data["owners"]:
		var location := registry.location(StringName(location_id))
		if location == null or not location.is_dockable():
			problems.append("territory refers to unknown settlement '%s'" % location_id)
			continue
		var faction_id = data["owners"][location_id]
		if not faction_id is String or (faction_id != "" and registry.faction(StringName(faction_id)) == null):
			problems.append("settlement '%s' is owned by unknown faction '%s'" % [location_id, faction_id])
	return problems


## Replaces ownership with validated saved data.
func load_state(data: Dictionary, registry: ContentRegistry) -> void:
	_owners.clear()
	for location_id in data["owners"]:
		var location := registry.location(StringName(location_id))
		var faction_id: String = data["owners"][location_id]
		var faction := registry.faction(StringName(faction_id)) if faction_id != "" else null
		if not _same(location.faction, faction):
			_owners[location.id] = faction
	territory_changed.emit()


## Every settlement back with its starting owner (a new game, or a save from
## before territory was saved).
func reset_state() -> void:
	_owners.clear()
	territory_changed.emit()
