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


## Plain data for the save file: capacity, ordinary manifest and contract lots.
func save_state() -> Dictionary:
	var manifest := {}
	for id in _manifest:
		manifest[str(id)] = _manifest[id]
	var lots := {}
	for contract_id in _lots:
		var lot: Dictionary = _lots[contract_id]
		lots[str(contract_id)] = {"commodity": str(lot["commodity"]),
				"quantity": lot["quantity"], "note": lot["note"]}
	return {"capacity": capacity, "manifest": manifest, "lots": lots}


## Problems with saved cargo data; empty when load_state() can use it.
func validate_state(data: Variant, registry: ContentRegistry) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary:
		return ["cargo is not an object"]
	if not SaveData.is_int(data.get("capacity")) or data["capacity"] < 0:
		problems.append("cargo capacity is not a non-negative whole number")
	var manifest = data.get("manifest")
	if not manifest is Dictionary:
		problems.append("cargo manifest is not an object")
	else:
		for id in manifest:
			if registry.commodity(StringName(id)) == null:
				problems.append("cargo holds unknown commodity '%s'" % id)
			if not SaveData.is_int(manifest[id]) or manifest[id] <= 0:
				problems.append("cargo quantity of '%s' is not a positive whole number" % id)
	var lots = data.get("lots")
	if not lots is Dictionary:
		problems.append("cargo lots is not an object")
	else:
		for contract_id in lots:
			var lot = lots[contract_id]
			if not lot is Dictionary:
				problems.append("cargo lot '%s' is not an object" % contract_id)
				continue
			if not SaveData.is_id(lot.get("commodity")) or registry.commodity(StringName(lot["commodity"])) == null:
				problems.append("cargo lot '%s' has an unknown commodity" % contract_id)
			if not SaveData.is_int(lot.get("quantity")) or lot["quantity"] <= 0:
				problems.append("cargo lot '%s' quantity is not a positive whole number" % contract_id)
			if not lot.get("note", "") is String:
				problems.append("cargo lot '%s' note is not text" % contract_id)
	# Cargo above the capacity is allowed: the capacity really comes from the
	# active ship, and an old save can hold more than the ship now carries. The
	# hold just stays full until some is sold or delivered.
	return problems


## Replaces the whole hold with validated saved data.
func load_state(data: Dictionary, _registry: ContentRegistry) -> void:
	_manifest.clear()
	_lots.clear()
	for id in data["manifest"]:
		_manifest[StringName(id)] = int(data["manifest"][id])
	for contract_id in data["lots"]:
		var lot: Dictionary = data["lots"][contract_id]
		_lots[StringName(contract_id)] = {"commodity": StringName(lot["commodity"]),
				"quantity": int(lot["quantity"]), "note": lot.get("note", "")}
	capacity = int(data["capacity"])  # also announces the change
