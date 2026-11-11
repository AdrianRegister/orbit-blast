class_name OfferContractSource
extends ContractSource
## Offers exactly the contract offers listed on the location: its cargo offers
## (`contract_offers`) and its exploration offers (`exploration_offers`). An
## offer is skipped, with an error, if it is invalid or cannot be achieved
## (unknown or unreachable destination, impossible quantity), and exact
## duplicates (same title) are dropped. Exploration offers whose target has
## already been scouted are not offered.


func generate(location: InhabitedData, context: ContractContext) -> Array[Contract]:
	var contracts: Array[Contract] = []
	var titles := {}
	for offer in location.contract_offers:
		if offer == null:
			continue
		var problems := offer.validate(location, context)
		if not problems.is_empty():
			push_error("%s: contract offer '%s' skipped: %s" % [location.display_name, offer.title, problems])
			continue
		if titles.has(offer.title):
			push_error("%s: contract offer '%s' is listed twice; the duplicate is skipped" % [location.display_name, offer.title])
			continue
		titles[offer.title] = true
		var contract := CargoDeliveryContract.new()
		contract.title = offer.title
		contract.description = offer.description
		contract.origin = location
		contract.destination = offer.get_destination()
		contract.commodity = offer.commodity
		contract.quantity = offer.quantity
		contract.reward = offer.reward if offer.reward > 0 else _cargo_reward(offer, location, contract.destination, context)
		contracts.append(contract)
	for offer in location.exploration_offers:
		if offer == null:
			continue
		var problems := offer.validate(location, context)
		if not problems.is_empty():
			push_error("%s: exploration offer '%s' skipped: %s" % [location.display_name, offer.title, problems])
			continue
		if titles.has(offer.title):
			push_error("%s: exploration offer '%s' is listed twice; the duplicate is skipped" % [location.display_name, offer.title])
			continue
		if context.travel != null and context.travel.is_scouted(offer.target_system):
			continue  # nothing left to explore
		titles[offer.title] = true
		var contract := ExplorationContract.new()
		contract.title = offer.title
		contract.description = offer.description
		contract.origin = location
		contract.target_system = offer.target_system
		contract.reward = offer.reward if offer.reward > 0 else _exploration_reward(offer, location, context)
		contracts.append(contract)
	return contracts


func _cargo_reward(offer: ContractOffer, origin: InhabitedData, destination: InhabitedData, context: ContractContext) -> int:
	var journey := context.journey(context.system_of(origin), context.system_of(destination))
	return context.rewards.cargo_reward(offer.commodity, offer.quantity, maxi(journey.x, 0), maxi(journey.y, 0), offer.reward_multiplier)


func _exploration_reward(offer: ExplorationOffer, origin: InhabitedData, context: ContractContext) -> int:
	var journey := context.journey(context.system_of(origin), offer.target_system)
	return context.rewards.exploration_reward(maxi(journey.x, 0), maxi(journey.y, 0), offer.reward_multiplier)
