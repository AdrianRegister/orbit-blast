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
