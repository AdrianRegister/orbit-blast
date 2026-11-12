class_name GameClock
extends Node
## The game calendar: a whole number of days since the game began. Time does not
## run in real time. It moves only when something spends it: a jump costs days in
## proportion to its length, and landing at a settlement costs a fixed number.
## Systems that care about time (market stock, later contract deadlines and wars)
## read `day` or listen to `day_advanced`.

## Emitted after the day changes. `elapsed` is how many days just passed.
signal day_advanced(day: int, elapsed: int)
## Emitted when the day is replaced wholesale (a loaded save or a new game).
signal clock_reset

## Days a jump takes per unit of fuel it costs (fuel cost follows jump length).
## 0.1 makes the longest link in the galaxy (Sol to Kerella, 83 fuel) take 8 days
## and a typical one 2. Keep the longest link at 10 days or less: wars run on
## this calendar and the player must be able to reach a front in time.
@export var days_per_fuel_unit: float = 0.1
## Days spent each time the player lands at a settlement.
@export var days_per_landing: int = 1

var day: int = 0


## Moves time forward. Ignores zero and negative amounts. `reason` is only
## informational (&"jump", &"landing") for listeners that care why time passed.
func advance(days: int, _reason: StringName = &"") -> void:
	if days <= 0:
		return
	day += days
	day_advanced.emit(day, days)


## Days a jump with this fuel cost takes (always at least one).
func jump_days(fuel_cost: int) -> int:
	return maxi(1, roundi(fuel_cost * days_per_fuel_unit))


func save_state() -> Dictionary:
	return {"day": day}


func validate_state(data: Variant, _registry: ContentRegistry, _document: Dictionary = {}) -> Array[String]:
	if not data is Dictionary or not SaveData.is_int(data.get("day")) or data["day"] < 0:
		return ["clock day is not a non-negative whole number"]
	return []


func load_state(data: Dictionary, _registry: ContentRegistry) -> void:
	day = int(data["day"])
	clock_reset.emit()


## Back to day zero (a new game, or a save from before the clock existed).
func reset_state() -> void:
	day = 0
	clock_reset.emit()
