class_name InfrastructureManager
extends Node
## The damage done to each planet and station, and how it wears off. It holds only
## damage (0 = undamaged, 1 = devastated); what damage does to production is worked
## out here too (production_scale), and the markets use it. Damage never destroys
## anything and never lasts: it recovers a fixed amount every day.
##
## Recovery is lazy. Only the damage at the moment it last changed and that day are
## stored; the damage on any later day is worked out from them, so nothing ticks and
## the answer is the same whether the player is nearby or far away.
##
## Nothing here decides who damages what. A future war system calls apply_damage().

## Emitted just BEFORE a location's damage changes, so anything that has been
## following the old production (a market) can bring itself up to date first.
signal damage_about_to_change(location_id: StringName)
## Emitted after a location's damage changed (`damage` is the new value).
signal damage_changed(location_id: StringName, damage: float)
## Emitted when all damage is replaced at once (a loaded save, a new game).
signal damage_reset

const DEFAULT_CONFIG := "res://resources/infrastructure/infrastructure_config.tres"

var config: InfrastructureConfig

var _clock: GameClock
var _records: Dictionary = {}  # location id -> {"damage": float, "day": int}


## `clock` is the calendar recovery follows (without one, time stands still at day
## 0, so nothing recovers). `infrastructure_config` defaults to the game's own.
func setup(clock: GameClock = null, infrastructure_config: InfrastructureConfig = null) -> void:
	_clock = clock
	config = infrastructure_config if infrastructure_config != null else load(DEFAULT_CONFIG)


func _today() -> int:
	return _clock.day if _clock != null else 0


# ------------------------------------------------------------------ reading

## The damage of a location on `day` (default: today), from 0 to 1. Days before the
## damage was last changed give the damage as it was then.
func get_damage(location_id: StringName, day: int = -1) -> float:
	var record = _records.get(location_id)
	if record == null:
		return 0.0
	var at := maxi(day if day >= 0 else _today(), record["day"])
	return maxf(0.0, record["damage"] - config.recovery_per_day * (at - record["day"]))


## The damage as a whole percent for display: 0 undamaged, 100 devastated.
func get_damage_percent(location_id: StringName) -> int:
	return roundi(get_damage(location_id) * 100.0)


## What share of its normal production a location makes on `day` (default today):
## 1.0 undamaged, less the more it is damaged.
func production_scale(location_id: StringName, day: int = -1) -> float:
	return clampf(1.0 - get_damage(location_id, day) * config.max_production_loss, 0.0, 1.0)


## Ids of the locations with any damage today.
func get_damaged_locations() -> Array[StringName]:
	var result: Array[StringName] = []
	for id in _records:
		if get_damage(id) > 0.0:
			result.append(id)
	return result


# ----------------------------------------------------------------- changing

## Adds damage (or repairs, with a negative amount) to a location. The damage is
## first brought up to today, then changed, then kept within 0 to 1. Returns the new
## damage. `source` says why (a bombardment, a raid) for listeners that care.
func apply_damage(location_id: StringName, amount: float, _source: StringName = &"") -> float:
	return set_damage(location_id, get_damage(location_id) + amount)


## Sets a location's damage as of today (0 repairs it completely).
func set_damage(location_id: StringName, damage: float) -> float:
	var value := clampf(damage, 0.0, 1.0)
	damage_about_to_change.emit(location_id)
	if value <= 0.0:
		_records.erase(location_id)
	else:
		_records[location_id] = {"damage": value, "day": _today()}
	damage_changed.emit(location_id, value)
	return value


# ------------------------------------------------------------------- saving

## Plain data for the save file: the damage of every damaged location, as of today.
## (Undamaged locations are not saved.)
func save_state() -> Dictionary:
	var locations := {}
	var today := _today()
	for id in _records:
		var damage := get_damage(id)
		if damage > 0.0:
			locations[str(id)] = {"damage": snappedf(damage, 0.0001), "day": today}
	return {"locations": locations}


func validate_state(data: Variant, registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary or not data.get("locations") is Dictionary:
		return ["infrastructure locations is not an object"]
	for id in data["locations"]:
		var location := registry.location(StringName(id))
		if location == null or not location.is_dockable() or location.population <= 0:
			problems.append("infrastructure damage refers to '%s', which is not an inhabited location" % id)
			continue
		var record = data["locations"][id]
		if not record is Dictionary:
			problems.append("infrastructure record of '%s' is not an object" % id)
			continue
		if not SaveData.is_number(record.get("damage")) or record["damage"] <= 0.0 or record["damage"] > 1.0:
			problems.append("damage of '%s' is not a number above 0 and at most 1" % id)
		if not SaveData.is_int(record.get("day")) or record["day"] < 0:
			problems.append("damage day of '%s' is not a non-negative whole number" % id)
	return problems


func load_state(data: Dictionary, _registry: ContentRegistry) -> void:
	_records.clear()
	for id in data["locations"]:
		var record: Dictionary = data["locations"][id]
		_records[StringName(id)] = {"damage": float(record["damage"]), "day": int(record["day"])}
	damage_reset.emit()


## Every location undamaged (a new game, or a save from before damage existed).
func reset_state() -> void:
	_records.clear()
	damage_reset.emit()
