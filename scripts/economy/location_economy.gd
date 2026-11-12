class_name LocationEconomy
extends RefCounted
## What one settlement makes and uses, per day, worked out by EconomyModel from
## its population, its planet type (or profile) and its listed specialties. A
## plain value: nothing here is saved, and it is recomputed when the data changes.

var location_id: StringName = &""
## The profile the numbers came from, or null for a place with no economy.
var profile: EconomyProfile
## Commodity id -> units made per day.
var production: Dictionary = {}
## Commodity id -> units used per day (people plus industry).
var consumption: Dictionary = {}

var _commodities: Dictionary = {}  # id -> Commodity, for the goods this place deals in
var _threshold: float = 0.1


func _init(commodities: Dictionary = {}, balance_threshold: float = 0.1) -> void:
	_commodities = commodities
	_threshold = balance_threshold


## False for a place with nothing going on (uninhabited, or cannot be landed on).
func has_economy() -> bool:
	return not production.is_empty() or not consumption.is_empty()


func production_of(commodity: Commodity) -> float:
	return production.get(commodity.id, 0.0)


func consumption_of(commodity: Commodity) -> float:
	return consumption.get(commodity.id, 0.0)


## Production minus consumption: positive = surplus, negative = shortfall.
func net_of(commodity: Commodity) -> float:
	return production_of(commodity) - consumption_of(commodity)


## Every good this place makes or uses, sorted by id.
func goods() -> Array[Commodity]:
	var ids := {}
	for id in production:
		ids[id] = true
	for id in consumption:
		ids[id] = true
	var sorted_ids := ids.keys()
	sorted_ids.sort_custom(func(a, b): return str(a) < str(b))
	var result: Array[Commodity] = []
	for id in sorted_ids:
		if _commodities.has(id):
			result.append(_commodities[id])
	return result


func is_export(commodity: Commodity) -> bool:
	var big := maxf(production_of(commodity), consumption_of(commodity))
	return big > 0.0 and net_of(commodity) > _threshold * big


func is_import(commodity: Commodity) -> bool:
	var big := maxf(production_of(commodity), consumption_of(commodity))
	return big > 0.0 and net_of(commodity) < -_threshold * big


func exports() -> Array[Commodity]:
	var result: Array[Commodity] = []
	for good in goods():
		if is_export(good):
			result.append(good)
	return result


func imports() -> Array[Commodity]:
	var result: Array[Commodity] = []
	for good in goods():
		if is_import(good):
			result.append(good)
	return result
