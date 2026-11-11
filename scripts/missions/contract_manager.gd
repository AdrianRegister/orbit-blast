class_name ContractManager
extends Node
## Owns every contract: which are on offer at each location, which the player
## has accepted and which are done. It never touches credits or cargo itself;
## it asks the EconomyManager to load contract cargo, unload it and pay rewards.
## The mission computer only reads from here and calls accept().

signal contracts_changed
signal contract_completed(contract: Contract)

enum AcceptResult { OK, NOT_AVAILABLE, WRONG_LOCATION, INSUFFICIENT_CARGO_SPACE }

var _economy: EconomyManager
## Returns the name of the star system a location is in ("" if unknown). Set by
## Main; replace it when there is more than one system.
var _system_name_of: Callable = func(_location: InhabitedData) -> String: return ""
var _source: ContractSource = OfferContractSource.new()
var _available: Dictionary = {}  # InhabitedData -> Array[Contract]
var _active: Array[Contract] = []
var _completed: Array[Contract] = []
## Nothing fails a contract yet; kept so saves already have the list when it does.
var _failed: Array[Contract] = []
var _next_id: int = 1


func setup(economy: EconomyManager) -> void:
	_economy = economy


## Tells the manager how to find the system a location is in, so cargo lists
## can say where contract cargo is going. `lookup(location) -> String`.
func set_system_lookup(lookup: Callable) -> void:
	_system_name_of = lookup


## Replaces where contracts come from (for example a procedural generator).
## Call before the first visit to any location.
func set_source(source: ContractSource) -> void:
	_source = source


## Contracts still on offer at a location, created on first use.
func get_available(location: InhabitedData) -> Array[Contract]:
	if location == null:
		return []
	if not _available.has(location):
		var contracts := _source.generate(location)
		for contract in contracts:
			contract.id = StringName("contract_%d" % _next_id)
			_next_id += 1
		_available[location] = contracts
	var open: Array[Contract] = []
	open.assign(_available[location])
	return open


func get_active() -> Array[Contract]:
	return _active.duplicate()


func get_completed() -> Array[Contract]:
	return _completed.duplicate()


func get_failed() -> Array[Contract]:
	return _failed.duplicate()


## Whether the location has anything for the mission computer to show.
func has_contracts_for(location: InhabitedData) -> bool:
	if not get_available(location).is_empty():
		return true
	for contract in _active + _completed:
		if contract.origin == location or contract.destination == location:
			return true
	return false


func check_accept(contract: Contract, location: InhabitedData) -> AcceptResult:
	if contract.status != Contract.Status.AVAILABLE or not get_available(location).has(contract):
		return AcceptResult.NOT_AVAILABLE
	if contract.origin != location:
		return AcceptResult.WRONG_LOCATION
	var delivery := contract as CargoDeliveryContract
	if delivery != null and not _economy.get_cargo().can_add(delivery.quantity):
		return AcceptResult.INSUFFICIENT_CARGO_SPACE
	return AcceptResult.OK


## Accepts a contract offered at `location` (where the player is docked). The
## issuer's cargo is loaded into the hold. Returns why it failed, or OK.
func accept(contract: Contract, location: InhabitedData) -> AcceptResult:
	var result := check_accept(contract, location)
	if result != AcceptResult.OK:
		return result
	var delivery := contract as CargoDeliveryContract
	if delivery != null:
		if not _economy.load_contract_cargo(delivery.id, delivery.commodity, delivery.quantity,
				_cargo_note(delivery)):
			return AcceptResult.INSUFFICIENT_CARGO_SPACE
		delivery.quantity_in_hold = delivery.quantity
	_available[location].erase(contract)
	contract.status = Contract.Status.ACCEPTED
	_active.append(contract)
	contracts_changed.emit()
	return AcceptResult.OK


## Completes every accepted contract destined for the docked location. Connect
## to the docking manager's `docked` signal. Other locations never match.
func on_docked(target: Targetable) -> void:
	var location := target.details as InhabitedData
	if location == null:
		return
	for contract in _active.duplicate():
		if contract.destination == location:
			_try_complete(contract)


## What the cargo list says after the commodity name, e.g.
## "contract, Earth in the Sol system".
func _cargo_note(contract: Contract) -> String:
	var system_name: String = _system_name_of.call(contract.destination)
	if system_name.is_empty():
		return "contract, %s" % contract.destination.display_name
	return "contract, %s in the %s system" % [contract.destination.display_name, system_name]


static func get_result_message(result: AcceptResult) -> String:
	match result:
		AcceptResult.NOT_AVAILABLE:
			return "CONTRACT NO LONGER AVAILABLE"
		AcceptResult.WRONG_LOCATION:
			return "ACCEPT THIS CONTRACT AT ITS ISSUER"
		AcceptResult.INSUFFICIENT_CARGO_SPACE:
			return "NOT ENOUGH FREE CARGO SPACE"
	return ""


func _try_complete(contract: Contract) -> void:
	var delivery := contract as CargoDeliveryContract
	if delivery != null:
		if _economy.get_cargo().get_lot_quantity(delivery.id) < delivery.quantity:
			push_error("Contract %s: cargo missing from the hold; not completed." % delivery.id)
			return
		_economy.unload_contract_cargo(delivery.id)
		delivery.quantity_in_hold = 0
	_economy.award_credits(contract.reward)
	contract.status = Contract.Status.COMPLETED
	_active.erase(contract)
	_completed.append(contract)
	contracts_changed.emit()
	contract_completed.emit(contract)


## Plain data for the save file. Every contract is stored in full, wherever it
## came from, so the save does not depend on how contracts were generated.
func save_state() -> Dictionary:
	var available: Array = []
	var generated: Array = []
	for location in _available:
		generated.append(str(location.id))
		for contract in _available[location]:
			available.append(contract.to_dict())
	return {
		"next_id": _next_id,
		"generated_locations": generated,
		"available": available,
		"active": _dicts(_active),
		"completed": _dicts(_completed),
		"failed": _dicts(_failed),
	}


## Problems with saved contract data; empty when load_state() can use it.
## `document` is the whole save, used to check contracts against cargo.
func validate_state(data: Variant, registry: ContentRegistry, document: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	if not data is Dictionary:
		return ["contracts is not an object"]
	if not SaveData.is_int(data.get("next_id")) or data["next_id"] < 1:
		problems.append("contracts next_id is not a positive whole number")
	var generated = data.get("generated_locations")
	if not generated is Array:
		problems.append("contracts generated_locations is not a list")
	else:
		for id in generated:
			if not SaveData.is_id(id) or registry.location(StringName(id)) == null:
				problems.append("generated location '%s' is not known" % id)
	var lists := {"available": Contract.Status.AVAILABLE, "active": Contract.Status.ACCEPTED,
			"completed": Contract.Status.COMPLETED, "failed": Contract.Status.FAILED}
	var seen := {}
	for list_name in lists:
		var entries = data.get(list_name, [])
		if not entries is Array:
			problems.append("contracts %s is not a list" % list_name)
			continue
		for entry in entries:
			var entry_problems := ContractFactory.validate(entry, registry)
			if not entry_problems.is_empty():
				problems.append_array(entry_problems)
				continue
			if entry["status"] != Contract.Status.keys()[lists[list_name]]:
				problems.append("contract '%s' is %s but is listed as %s" % [entry["id"], entry["status"], list_name])
			if seen.has(entry["id"]):
				problems.append("contract id '%s' is used twice" % entry["id"])
			seen[entry["id"]] = entry
			var number: String = str(entry["id"]).trim_prefix("contract_")
			if not str(entry["id"]).begins_with("contract_") or not number.is_valid_int() \
					or int(number) >= int(data.get("next_id", 0)):
				problems.append("contract id '%s' is not below next_id" % entry["id"])
			if list_name == "available" and generated is Array and not generated.has(entry["origin"]):
				problems.append("available contract '%s' is from a location that was never visited" % entry["id"])
	if problems.is_empty() and document.has("economy"):
		problems.append_array(_check_against_cargo(data, document["economy"]))
	return problems


## Replaces all contracts with validated saved data.
func load_state(data: Dictionary, registry: ContentRegistry) -> void:
	_available.clear()
	_active.clear()
	_completed.clear()
	_failed.clear()
	_next_id = int(data["next_id"])
	for id in data["generated_locations"]:
		_available[registry.location(StringName(id))] = []
	for entry in data["available"]:
		var contract := ContractFactory.from_dict(entry, registry)
		_available[contract.origin].append(contract)
	_load_list(data.get("active", []), _active, registry)
	_load_list(data.get("completed", []), _completed, registry)
	_load_list(data.get("failed", []), _failed, registry)
	contracts_changed.emit()


func _load_list(entries: Array, into: Array[Contract], registry: ContentRegistry) -> void:
	for entry in entries:
		into.append(ContractFactory.from_dict(entry, registry))


func _dicts(contracts: Array[Contract]) -> Array:
	var result: Array = []
	for contract in contracts:
		result.append(contract.to_dict())
	return result


## Active delivery contracts and the cargo lots must match one to one: a lot
## without a contract, or a contract without its cargo, means a damaged save.
func _check_against_cargo(data: Dictionary, economy: Variant) -> Array[String]:
	var problems: Array[String] = []
	if not economy is Dictionary or not economy.get("cargo") is Dictionary \
			or not economy["cargo"].get("lots") is Dictionary:
		return problems  # The economy section reports its own problems.
	var lots: Dictionary = economy["cargo"]["lots"]
	var matched := {}
	for entry in data.get("active", []):
		if entry.get("type") != "cargo_delivery":
			continue
		var lot = lots.get(entry["id"])
		if lot == null:
			problems.append("active contract '%s' has no cargo in the hold" % entry["id"])
		elif lot["commodity"] != entry["commodity"] or int(lot["quantity"]) != int(entry["quantity_in_hold"]):
			problems.append("cargo for contract '%s' does not match the contract" % entry["id"])
		matched[entry["id"]] = true
	for contract_id in lots:
		if not matched.has(contract_id):
			problems.append("cargo lot '%s' belongs to no active contract" % contract_id)
	return problems
