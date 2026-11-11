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
## Contract cargo, kept apart from the manifest so it can never be sold: a lot
## per contract, contract id -> {"commodity", "quantity", "note"}.
## Lots take up the same capacity as ordinary cargo.
var _lots: Dictionary = {}


## Ordinary cargo plus contract lots: the one capacity calculation.
func get_used() -> int:
	var total := 0
	for quantity in _manifest.values():
		total += quantity
	for lot in _lots.values():
		total += lot["quantity"]
	return total


func get_free() -> int:
	return maxi(capacity - get_used(), 0)


## Ordinary (sellable) cargo only; contract lots are not included.
func get_quantity(id: StringName) -> int:
	return _manifest.get(id, 0)


## A copy of the ordinary manifest (no contract lots), so callers cannot modify
## the hold behind its back.
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


## Loads contract cargo as its own lot. Fails (changing nothing) if the contract
## already has a lot or the quantity does not fit.
func add_lot(contract_id: StringName, commodity_id: StringName, quantity: int, note: String = "") -> bool:
	if _lots.has(contract_id) or not can_add(quantity):
		return false
	_lots[contract_id] = {"commodity": commodity_id, "quantity": quantity, "note": note}
	changed.emit()
	return true


func remove_lot(contract_id: StringName) -> bool:
	if not _lots.has(contract_id):
		return false
	_lots.erase(contract_id)
	changed.emit()
	return true


func get_lot_quantity(contract_id: StringName) -> int:
	return _lots[contract_id]["quantity"] if _lots.has(contract_id) else 0


## A copy of the lots: contract id -> {"commodity": StringName, "quantity": int, "note": String}.
func get_lots() -> Dictionary:
	return _lots.duplicate(true)
