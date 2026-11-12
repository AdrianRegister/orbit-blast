class_name SystemAssessor
extends RefCounted
## Works out a SystemAssessment for any star system from the static data (its
## locations, their economy profiles, its class) and, if given, how damaged each
## location is. It decides nothing and changes nothing: it is the read access a
## future war simulation and the zone calculation use.
##
## Everything flows one way: locations -> economy -> value -> importance. Nothing
## computed here (and nothing derived from it, such as zones) feeds back into a
## location's production or population.

var _galaxy: Galaxy
var _registry: ContentRegistry
var _model: EconomyModel
var _rules: MilitaryValueRules
## Callable(location id) -> float damage 0 to 1; null/invalid = nothing is damaged.
var _damage: Callable
## Callable(location id) -> float share of production made now (1 undamaged).
var _scale: Callable


## `damage` and `scale` are optional Callables that take a location id: its damage
## (0 to 1) and the share of normal production it makes now. Without them every
## location is whole. Typically Main passes the InfrastructureManager's methods.
func _init(galaxy: Galaxy, registry: ContentRegistry, model: EconomyModel, rules: MilitaryValueRules,
		damage: Callable = Callable(), scale: Callable = Callable()) -> void:
	_galaxy = galaxy
	_registry = registry
	_model = model
	_rules = rules
	_damage = damage
	_scale = scale


## The military value of one location with no damage: 0 unless people live there.
func location_value(location: InhabitedData) -> float:
	if location == null or not location.is_dockable() or location.population <= 0:
		return 0.0
	var profile := location.get_economy_profile()
	if profile == null:
		profile = _model.config.station_profile
	var kind := profile.military_value if profile != null else 0.0
	var ratio := float(location.population) / _model.config.reference_population
	var size := clampf(pow(ratio, _rules.size_exponent), _rules.size_min, _rules.size_max)
	var value := kind * size + location.military_value_bonus
	if not location.shipyard_ships.is_empty():
		value += _rules.shipyard_value
	if location.has_outfitter():
		value += _rules.outfitter_value
	return value


## The military value of one location as it is now, lowered by damage.
func current_location_value(location: InhabitedData) -> float:
	var damage := float(_damage.call(location.id)) if _damage.is_valid() else 0.0
	return location_value(location) * (1.0 - _rules.damage_weight * damage)


func assess(system_id: StringName) -> SystemAssessment:
	var result := SystemAssessment.new()
	result.system_id = system_id
	var summary := _galaxy.get_summary(system_id)
	var system_class := _galaxy.get_system_class(system_id)
	result.class_id = system_class.id if system_class != null else &""
	result.connectivity = _galaxy.get_neighbours(system_id).size()
	var multiplier := system_class.military_value_multiplier if system_class != null else 1.0
	if summary == null:
		return result

	var made_weight := 0.0
	var made_scaled := 0.0
	for location_id in summary.location_ids:
		var location := _registry.location(location_id)
		if location == null or not location.is_dockable() or location.population <= 0:
			continue
		result.location_ids.append(location_id)
		result.population += location.population
		var structural := location_value(location)
		result.location_values[location_id] = structural * multiplier
		result.military_value += structural * multiplier
		result.current_military_value += current_location_value(location) * multiplier
		var economy := _model.of(location)
		var made := 0.0
		for good in economy.goods():
			made += economy.production_of(good) * good.base_price
			result.consumption_value += economy.consumption_of(good) * good.base_price
		result.production_value += made
		made_weight += made
		made_scaled += made * (float(_scale.call(location_id)) if _scale.is_valid() else 1.0)
	result.infrastructure = made_scaled / made_weight if made_weight > 0.0 else 1.0
	result.importance = (result.military_value * _rules.weight_military
			+ result.production_value * _rules.weight_production
			+ float(result.population) / 1000000.0 * _rules.weight_population
			+ result.connectivity * _rules.weight_connectivity) if result.is_inhabited() else 0.0
	return result


## Every system's assessment: {system id: SystemAssessment}.
func assess_all() -> Dictionary:
	var result := {}
	for id in _galaxy.get_system_ids():
		result[id] = assess(id)
	return result
