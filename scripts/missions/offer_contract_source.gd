class_name OfferContractSource
extends ContractSource
## Offers exactly the ContractOffer resources listed on the location.


func generate(location: InhabitedData) -> Array[Contract]:
	var contracts: Array[Contract] = []
	for offer in location.contract_offers:
		if offer == null:
			continue
		var problems := offer.validate(location)
		if not problems.is_empty():
			push_error("%s: contract offer '%s' skipped: %s" % [location.display_name, offer.title, problems])
			continue
		var contract := CargoDeliveryContract.new()
		contract.title = offer.title
		contract.description = offer.description
		contract.origin = location
		contract.destination = offer.get_destination()
		contract.commodity = offer.commodity
		contract.quantity = offer.quantity
		contract.reward = offer.reward
		contracts.append(contract)
	return contracts
