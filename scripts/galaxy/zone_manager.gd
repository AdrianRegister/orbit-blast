class_name ZoneManager
extends Node
## The strategic geography of each faction: where its centres of power are and which
## zone (capital, core, inner, frontier) every system it holds falls in. Everything
## is derived from the jump network, who owns what (TerritoryManager) and what each
## system is worth (SystemAssessor); nothing about zones is stored except the day a
## critical system last changed hands, which decides when it becomes a centre of
## power for its new owner.
##
## Centres of power. A faction's capital (Faction.capital_system) is one while the
## faction controls it. So is every critical-class system (SystemClass.can_be_centre)
## the faction controls outright, that is important enough (ZoneRules.
## centre_min_importance) and has been held long enough (ZoneRules.establish_days).
## A conquered enemy capital or critical system therefore becomes a regional centre, a
## mini-core, a while after the conquest; losing the system ends it at once. If the
## capital is lost, the most important remaining centre acts as the capital (a rule
## in ZoneRules).
##
## Zones never feed back: nothing here changes a location's production, consumption,
## population or class. It is the one-way end of the chain graph -> class -> economy ->
## value -> importance -> centres -> zones.

## The zones of a faction changed (a centre appeared or went, or a system moved zone).
signal zones_changed(faction_id: StringName)

const DEFAULT_RULES := "res://resources/zones/zone_rules.tres"

var rules: ZoneRules

var _galaxy: Galaxy
var _territory: TerritoryManager
var _assessor: SystemAssessor
var _registry: ContentRegistry
var _clock: GameClock
var _graph: GalaxyGraph
## System id -> {"faction": StringName, "day": int}: when the current controller of a
## system that has changed hands took it. Systems held by their starting owner have none.
var _claims: Dictionary = {}
var _importance: Dictionary = {}  # system id -> float, worked out once (static data)
var _maps: Dictionary = {}  # faction id -> ZoneMap, rebuilt when territory or the day changes
var _chokepoints: Dictionary = {}


## `assessor` values the systems; `clock` (optional) is the calendar centres are
## established by. `zone_rules` defaults to the game's own.
func setup(galaxy: Galaxy, territory: TerritoryManager, assessor: SystemAssessor, registry: ContentRegistry,
		clock: GameClock = null, zone_rules: ZoneRules = null) -> void:
	_galaxy = galaxy
	_territory = territory
	_assessor = assessor
	_registry = registry
	_clock = clock
	rules = zone_rules if zone_rules != null else load(DEFAULT_RULES)
	_graph = GalaxyGraph.from_galaxy(galaxy)
	_chokepoints.clear()
	for id in _graph.articulation_points():
		_chokepoints[id] = true
	_territory.system_control_changed.connect(_on_control_changed)
	_territory.territory_changed.connect(_rebuild)
	if _clock != null:
		_clock.day_advanced.connect(func(_day: int, _elapsed: int) -> void: _rebuild())
		_clock.clock_reset.connect(_rebuild)
	_rebuild()


func _today() -> int:
	return _clock.day if _clock != null else 0


## The assessor that values systems, for whoever needs system values alongside zones.
func get_assessor() -> SystemAssessor:
	return _assessor


# ------------------------------------------------------------------ queries

## The zone of a system for a faction (default: the faction that controls it).
## ZoneMap.Zone.NONE if the faction is not present there.
func zone_of(system_id: StringName, faction_id: StringName = &"") -> ZoneMap.Zone:
	var id := faction_id if faction_id != &"" else _controller_id(system_id)
	if id == &"":
		return ZoneMap.Zone.NONE
	return _map_for(id).zone_of(system_id)


## The name of the zone of a system for a faction ("CAPITAL", "CORE", ...).
func zone_name_of(system_id: StringName, faction_id: StringName = &"") -> String:
	return ZoneMap.ZONE_NAMES[zone_of(system_id, faction_id)]


## The centre of power a system belongs to (its region), or &"" if it is cut off or
## the faction is not present.
func region_centre_of(system_id: StringName, faction_id: StringName = &"") -> StringName:
	var id := faction_id if faction_id != &"" else _controller_id(system_id)
	return _map_for(id).region_of(system_id) if id != &"" else &""


## Jumps from a system to its centre of power (-1 if cut off or not present).
func hops_from_centre(system_id: StringName, faction_id: StringName = &"") -> int:
	var id := faction_id if faction_id != &"" else _controller_id(system_id)
	return _map_for(id).hops_of(system_id) if id != &"" else -1


## A faction's centres of power, most important first.
func centres_of(faction_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_map_for(faction_id).centres)
	return result


func is_centre(system_id: StringName, faction_id: StringName = &"") -> bool:
	var id := faction_id if faction_id != &"" else _controller_id(system_id)
	return id != &"" and _map_for(id).centres.has(system_id)


## The faction's capital: its own while it holds it, otherwise (if the rules allow) the
## most important remaining centre acting as capital, otherwise &"".
func capital_of(faction_id: StringName) -> StringName:
	var faction := _registry.faction(faction_id)
	if faction == null:
		return &""
	if faction.capital_system != &"" and _controller_id(faction.capital_system) == faction_id:
		return faction.capital_system
	if rules.relocate_capital:
		var centres := _map_for(faction_id).centres
		if not centres.is_empty():
			return centres[0]
	return &""


## Whether the system is a faction's border: it is present there and next to a system
## where it is not but another faction is.
func is_border(system_id: StringName, faction_id: StringName = &"") -> bool:
	var id := faction_id if faction_id != &"" else _controller_id(system_id)
	if id == &"" or not _present(id, system_id):
		return false
	for other in _graph.neighbours(system_id):
		if not _present(id, other) and _held_by_another(id, other):
			return true
	return false


## Jumps from a system to the nearest system held by a faction other than `faction_id`
## (the front line), over the whole network. -1 if there is none.
func hops_to_enemy(system_id: StringName, faction_id: StringName) -> int:
	var enemies: Array = []
	for id in _graph.nodes():
		if not _present(faction_id, id) and _held_by_another(faction_id, id):
			enemies.append(id)
	return _graph.hops_from(enemies).get(system_id, -1)


## Whether losing this system would cut the jump network in two.
func is_chokepoint(system_id: StringName) -> bool:
	return _chokepoints.has(system_id)


# ------------------------------------------------------------------- building

func _controller_id(system_id: StringName) -> StringName:
	var control := _territory.get_control(system_id)
	return control.controller.id if control.status == SystemControl.Status.CONTROLLED else &""


## Whether the faction owns a settlement in the system (it controls it outright, or is
## one side of a contested system).
func _present(faction_id: StringName, system_id: StringName) -> bool:
	var control := _territory.get_control(system_id)
	for faction in control.factions:
		if faction.id == faction_id:
			return true
	return false


func _held_by_another(faction_id: StringName, system_id: StringName) -> bool:
	for faction in _territory.get_control(system_id).factions:
		if faction.id != faction_id:
			return true
	return false


func _importance_of(system_id: StringName) -> float:
	if not _importance.has(system_id):
		_importance[system_id] = _assessor.assess(system_id).importance
	return _importance[system_id]


## Whether a critical system the faction controls has been held long enough.
func _established(system_id: StringName, faction_id: StringName) -> bool:
	var claim = _claims.get(system_id)
	return claim == null or claim["faction"] != faction_id or _today() - claim["day"] >= rules.establish_days


func _centres_for(faction: Faction) -> Array:
	var result: Array = []
	for id in _graph.nodes():
		var system_class := _galaxy.get_system_class(id)
		if system_class == null or not system_class.can_be_centre():
			continue
		if _controller_id(id) != faction.id or _importance_of(id) < rules.centre_min_importance:
			continue
		if _established(id, faction.id):
			result.append(id)
	var capital := faction.capital_system
	if capital != &"" and _controller_id(capital) == faction.id and not result.has(capital):
		result.append(capital)
	return result


func _map_for(faction_id: StringName) -> ZoneMap:
	if _maps.has(faction_id):
		return _maps[faction_id]
	var faction := _registry.faction(faction_id)
	if faction == null:
		return ZoneMap.new()
	var centres := _centres_for(faction)
	# The capital is the faction's own while held; otherwise the most important centre
	# acts as it (see capital_of), which only matters for the zone name of that system.
	var capital := faction.capital_system if _controller_id(faction.capital_system) == faction_id else &""
	var map := ZoneMap.compute(_graph, func(id: StringName) -> bool: return _present(faction_id, id), centres, capital,
			_importance_of, rules)
	if capital == &"" and rules.relocate_capital and not map.centres.is_empty():
		var acting: StringName = map.centres[0]
		map.zones[acting] = ZoneMap.Zone.CAPITAL
	_maps[faction_id] = map
	return map


## Redraws every faction's zones, and announces the factions whose zones changed.
func _rebuild() -> void:
	if _registry == null:
		return
	var before := _maps
	_maps = {}
	for faction in _registry.factions():
		var map := _map_for(faction.id)
		var old: ZoneMap = before.get(faction.id)
		if old != null and (old.zones != map.zones or old.centres != map.centres or old.regions != map.regions):
			zones_changed.emit(faction.id)


## A system changed hands: note who holds it and since when.
func _on_control_changed(system_id: StringName) -> void:
	var control := _territory.get_control(system_id)
	if control.status != SystemControl.Status.CONTROLLED:
		_claims.erase(system_id)
		return
	var holder := control.controller.id
	if holder == _starting_controller(system_id):
		_claims.erase(system_id)  # back with its starting owner: established at once
	elif not _claims.has(system_id) or _claims[system_id]["faction"] != holder:
		_claims[system_id] = {"faction": holder, "day": _today()}


## The faction that held the system when the game began (from the static data), or &""
## if it was not held by exactly one.
func _starting_controller(system_id: StringName) -> StringName:
	var summary := _galaxy.get_summary(system_id)
	if summary == null:
		return &""
	var holders := {}
	var settlements := 0
	for location_id in summary.location_ids:
		var location := _registry.location(location_id)
		if location == null or not location.is_dockable() or location.population <= 0:
			continue
		settlements += 1
		if location.faction != null:
			holders[location.faction.id] = true
	if settlements == 0:
		var claim := _galaxy.get_claim(system_id)
		return claim.id if claim != null else &""
	return holders.keys()[0] if holders.size() == 1 else &""


# ------------------------------------------------------------------- saving

func save_state() -> Dictionary:
	var claims := {}
	for system_id in _claims:
		claims[str(system_id)] = {"faction": str(_claims[system_id]["faction"]), "day": _claims[system_id]["day"]}
	return {"claims": claims}


func validate_state(data: Variant, registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary or not data.get("claims") is Dictionary:
		return ["zones claims is not an object"]
	for system_id in data["claims"]:
		if not registry.has_system(StringName(system_id)):
			problems.append("a zone claim refers to unknown system '%s'" % system_id)
			continue
		var claim = data["claims"][system_id]
		if not claim is Dictionary:
			problems.append("the zone claim on '%s' is not an object" % system_id)
			continue
		if not SaveData.is_id(claim.get("faction")) or registry.faction(StringName(claim["faction"])) == null:
			problems.append("the zone claim on '%s' refers to an unknown faction" % system_id)
		if not SaveData.is_int(claim.get("day")) or claim["day"] < 0:
			problems.append("the zone claim on '%s' has a day that is not a non-negative whole number" % system_id)
	return problems


func load_state(data: Dictionary, _registry_unused: ContentRegistry) -> void:
	_claims.clear()
	for system_id in data["claims"]:
		var claim: Dictionary = data["claims"][system_id]
		_claims[StringName(system_id)] = {"faction": StringName(claim["faction"]), "day": int(claim["day"])}
	_rebuild()


## No system has changed hands (a new game, or a save from before zones existed).
func reset_state() -> void:
	_claims.clear()
	_rebuild()
