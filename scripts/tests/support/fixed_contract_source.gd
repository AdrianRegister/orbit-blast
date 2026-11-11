class_name FixedContractSource
extends ContractSource
## A test-only source that offers the same hand-picked contracts every time, so
## tests of the manager, the screens and saving do not depend on the random
## generator. Each location's contracts are made once, the first time it is asked.
##
## Earth:     food 40 to Mars, electronics 30 to Victory I, bulk food 480 to Mars,
##            luxury goods 25 to Talos (another system)
## Mars:      ore 30 to Earth, ore 20 to Victory I
## Victory I: fuel 25 to Earth, fuel 15 to Mars
## Daedalus:  scout Wolf 359

var _made := {}  # location id -> true


func get_target_offers() -> int:
	return 99  # everything on the list, once


func generate(location: InhabitedData, context: ContractContext, _wanted: int, _existing: Array[Contract]) -> Array[Contract]:
	var result: Array[Contract] = []
	# Once per location. A manager that has loaded a save already knows its
	# locations, so anything it already has from here means "not again".
	if _made.has(location.id) or not _existing.is_empty():
		return result
	_made[location.id] = true
	match location.id:
		&"earth":
			result.append(_cargo(location, context, "Food relief for Mars", &"food", 40, &"mars", 12000))
			result.append(_cargo(location, context, "Electronics for Victory I", &"electronics", 30, &"victory_i", 4000))
			result.append(_cargo(location, context, "Bulk food convoy", &"food", 480, &"mars", 30000))
			result.append(_cargo(location, context, "Luxury goods for Talos", &"luxury_goods", 25, &"talos", 0))
		&"mars":
			result.append(_cargo(location, context, "Ore for Earth foundries", &"ore", 30, &"earth", 3000))
			result.append(_cargo(location, context, "Ore for Victory I", &"ore", 20, &"victory_i", 2500))
		&"victory_i":
			result.append(_cargo(location, context, "Fuel for Earth", &"fuel", 25, &"earth", 2500))
			result.append(_cargo(location, context, "Fuel for Mars", &"fuel", 15, &"mars", 2000))
		&"daedalus":
			result.append(_exploration(location, context, "Chart the Wolf 359 system", &"wolf_359"))
	return result


## A cargo delivery. reward 0 = work it out with the reward rules.
func _cargo(origin: InhabitedData, context: ContractContext, title: String, commodity_id: StringName,
		quantity: int, destination_id: StringName, reward: int) -> Contract:
	var contract := CargoDeliveryContract.new()
	contract.title = title
	contract.description = title
	contract.origin = origin
	contract.destination = context.registry.location(destination_id)
	contract.commodity = context.registry.commodity(commodity_id)
	contract.quantity = quantity
	if reward == 0:
		var journey := context.journey(context.system_of(origin), context.system_of(contract.destination))
		reward = context.rewards.cargo_reward(contract.commodity, quantity, maxi(journey.x, 0), maxi(journey.y, 0))
	contract.reward = reward
	return contract


func _exploration(origin: InhabitedData, context: ContractContext, title: String, target: StringName) -> Contract:
	var contract := ExplorationContract.new()
	contract.title = title
	contract.description = title
	contract.origin = origin
	contract.target_system = target
	var journey := context.journey(context.system_of(origin), target)
	contract.reward = context.rewards.exploration_reward(journey.x, journey.y)
	return contract
