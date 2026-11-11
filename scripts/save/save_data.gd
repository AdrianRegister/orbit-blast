class_name SaveData
extends RefCounted
## Helpers for reading values out of parsed save data. JSON has one number
## type, so every number comes back from the parser as a float; these check
## and convert, and are used by every section's validation.


## True for an int, or a float with no fractional part (as JSON gives).
static func is_int(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floorf(value) and absf(value) < 9.0e15


static func is_number(value: Variant) -> bool:
	return (value is int) or (value is float and is_finite(value))


static func is_id(value: Variant) -> bool:
	return value is String and not (value as String).is_empty()


## An [x, y] pair of numbers.
static func is_vector(value: Variant) -> bool:
	return value is Array and (value as Array).size() == 2 \
			and is_number(value[0]) and is_number(value[1])


static func to_vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func from_vector(value: Vector2) -> Array:
	return [value.x, value.y]
