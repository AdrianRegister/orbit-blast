class_name CargoHold
extends RefCounted
## The player's cargo: a manifest of commodity id -> quantity within a
## capacity. It only stores and validates cargo; it knows nothing about money
## or markets. Mutators return false (changing nothing) when they cannot comply.

signal changed

## Total quantity the hold can contain. Set from the ship's stats.
var capacity: int = 0:
	set(value):
		capacity = maxi(value, 0)
		changed.emit()

var _manifest: Dictionary = {}  # StringName -> int


func get_used() -> int:
	var total := 0
	for quantity in _manifest.values():
		total += quantity
	return total


func get_free() -> int:
	return maxi(capacity - get_used(), 0)


func get_quantity(id: StringName) -> int:
	return _manifest.get(id, 0)


## A copy of the manifest, so callers cannot modify the hold behind its back.
func get_manifest() -> Dictionary:
	return _manifest.duplicate()


func can_add(quantity: int) -> bool:
	return quantity > 0 and quantity <= get_free()


func add(id: StringName, quantity: int) -> bool:
	if not can_add(quantity):
		return false
	_manifest[id] = get_quantity(id) + quantity
	changed.emit()
	return true


func remove(id: StringName, quantity: int) -> bool:
	if quantity <= 0 or quantity > get_quantity(id):
		return false
	var remaining: int = get_quantity(id) - quantity
	if remaining == 0:
		_manifest.erase(id)
	else:
		_manifest[id] = remaining
	changed.emit()
	return true
