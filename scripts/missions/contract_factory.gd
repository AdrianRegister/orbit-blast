class_name ContractFactory
extends RefCounted
## Creates the right Contract subclass for a saved contract's `type`. A new
## mission type is added here (one line) and by giving the subclass its own
## `type id`, `to_dict()`, `validate_dict()` and `load_dict()`.


static func create(type: StringName) -> Contract:
	match type:
		&"cargo_delivery":
			return CargoDeliveryContract.new()
		&"ferry":
			return FerryContract.new()
		&"exploration":
			return ExplorationContract.new()
	return null


## Problems with a saved contract; empty when it can be loaded.
static func validate(data: Variant, registry: ContentRegistry) -> Array[String]:
	if not data is Dictionary:
		return ["contract is not an object"]
	var contract := create(StringName(str(data.get("type", ""))))
	if contract == null:
		return ["unknown contract type '%s'" % data.get("type", "")]
	return contract.validate_dict(data, registry)


## Builds a contract from validated data.
static func from_dict(data: Dictionary, registry: ContentRegistry) -> Contract:
	var contract := create(StringName(data["type"]))
	contract.load_dict(data, registry)
	return contract
