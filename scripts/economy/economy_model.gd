class_name EconomyModel
extends RefCounted
## Works out what every settlement makes and uses from its population, planet
## type and listed specialties. Change a location's population, planet type or
## profile in its .tres and its goods follow; nothing else needs editing.
##
##   scale_p   = max(population / reference, min_scale) ^ production_exponent
##   scale_d   = max(population / reference, min_scale) ^ demand_exponent
##   production(good)  = profile.production * scale_p
##   consumption(good) = profile.industrial_demand * scale_p
##                       + commodity.civilian_demand * scale_d
##
## Specialties (the location's own exported_goods / imported_goods) then
## override the result for the goods they name; see EconomyConfig. A place that is
## uninhabited or cannot be landed on has no economy.
##
## The model is stateless apart from a cache, so it is safe to share.

const DEFAULT_CONFIG := "res://resources/economy/economy_config.tres"
const COMMODITY_DIR := "res://resources/commodities/"

static var _shared: EconomyModel

var config: EconomyConfig

var _commodities: Dictionary = {}  # id -> Commodity (only goods that can be traded)
var _cache: Dictionary = {}  # location id -> {"signature": int, "economy": LocationEconomy}


## A model using the game's own config and every commodity in the game. Used by
## code that has no model handed to it (such as the galaxy map's summaries).
static func shared() -> EconomyModel:
	if _shared == null:
		var commodities: Array[Commodity] = []
		for file in DirAccess.get_files_at(COMMODITY_DIR):
			if file.ends_with(".tres"):
				var commodity := load(COMMODITY_DIR + file) as Commodity
				if commodity != null:
					commodities.append(commodity)
		_shared = EconomyModel.new(load(DEFAULT_CONFIG), commodities)
	return _shared


func _init(economy_config: EconomyConfig, commodities: Array[Commodity]) -> void:
	config = economy_config
	for commodity in commodities:
		if commodity != null and commodity.base_price > 0:
			_commodities[commodity.id] = commodity


## The economy of a location, recomputed if its population, profile or listed
## specialties have changed since the last call.
func of(location: InhabitedData) -> LocationEconomy:
	if location == null:
		return LocationEconomy.new()
	var signature := _signature(location)
	var cached = _cache.get(location.id)
	if cached != null and cached["signature"] == signature:
		return cached["economy"]
	var economy := compute(location)
	_cache[location.id] = {"signature": signature, "economy": economy}
	return economy


## Works the economy out afresh. With `use_specialties` false the listed
## exported_goods / imported_goods are ignored, which shows what the population
## and planet type alone would give.
func compute(location: InhabitedData, use_specialties: bool = true) -> LocationEconomy:
	var economy := LocationEconomy.new(_commodities, config.balance_threshold)
	if location == null:
		return economy
	economy.location_id = location.id
	if not location.is_dockable() or location.population <= 0:
		return economy
	var ratio := maxf(float(location.population) / config.reference_population, config.min_scale)
	var production_scale := pow(ratio, config.production_exponent)
	var demand_scale := pow(ratio, config.demand_exponent)

	var profile := location.get_economy_profile()
	if profile == null:
		profile = config.station_profile
	economy.profile = profile
	if profile != null:
		for line in profile.goods:
			if line == null or not _commodities.has(line.commodity.id):
				continue
			var id := line.commodity.id
			_add(economy.production, id, line.production * production_scale)
			_add(economy.consumption, id, line.industrial_demand * production_scale)
	for id in _commodities:
		var need: float = _commodities[id].civilian_demand
		if need > 0.0:
			_add(economy.consumption, id, need * demand_scale)

	if use_specialties:
		for good in location.exported_goods:
			if good == null or not _commodities.has(good.id):
				continue
			var made: float = economy.production.get(good.id, 0.0)
			var used: float = economy.consumption.get(good.id, 0.0)
			economy.production[good.id] = maxf(maxf(made * config.specialty_multiplier,
					used * config.specialty_export_margin), config.specialty_export_flow * production_scale)
		for good in location.imported_goods:
			if good == null or not _commodities.has(good.id):
				continue
			var used: float = economy.consumption.get(good.id, 0.0)
			economy.production.erase(good.id)
			economy.consumption[good.id] = maxf(used * config.specialty_multiplier,
					config.specialty_import_flow * demand_scale)
	return economy


func _add(rates: Dictionary, id: StringName, amount: float) -> void:
	if amount > 0.0:
		rates[id] = rates.get(id, 0.0) + amount


func _signature(location: InhabitedData) -> int:
	var profile := location.get_economy_profile()
	var parts: Array = [location.population, location.is_dockable(), profile.id if profile != null else &""]
	for good in location.exported_goods:
		parts.append(good.id if good != null else &"")
	parts.append("|")
	for good in location.imported_goods:
		parts.append(good.id if good != null else &"")
	return hash(parts)
