class_name ContractGenerationRules
extends Resource
## The tunable numbers and wording behind procedurally generated contracts, in
## one resource (resources/contracts/generation_rules.tres). How much a contract
## pays is not here: see ContractRewards.
##
## Text templates may contain {origin}, {place} (the destination or target),
## {system}, {commodity}, {passengers}; unknown placeholders are left as they are.

@export_group("Offers per mission computer")
## A mission computer is topped up to this many offers each time the player docks.
@export var target_offers: int = 4
## Every inhabited location always has at least this many.
@export var min_offers: int = 1

@export_group("Mix")
## Relative chances of each contract type.
@export var cargo_weight: float = 5.0
@export var ferry_weight: float = 4.0
@export var exploration_weight: float = 1.0

@export_group("Cargo delivery")
@export var cargo_quantity_min: int = 10
@export var cargo_quantity_max: int = 100
## Chance that a delivery is a bulk one.
@export_range(0.0, 1.0) var bulk_chance: float = 0.15
@export var bulk_quantity_min: int = 200
@export var bulk_quantity_max: int = 600
## Bulk loads are only made of goods up to this price per unit.
@export var bulk_max_price: int = 100
@export var cargo_max_jumps: int = 4
## Chance (against 1) multiplier that a destination importing the cargo is picked.
@export var importer_weight: float = 3.0

@export_group("Ferry passengers")
@export var ferry_max_passengers: int = 3
@export var ferry_max_jumps: int = 3

@export_group("Exploration")
@export var exploration_max_jumps: int = 3

@export_group("Wording")
@export var cargo_titles: Array[String] = ["{commodity} for {place}"]
@export_multiline var cargo_descriptions: Array[String] = ["{origin} needs {commodity} delivered to {place}."]
@export var bulk_titles: Array[String] = ["Bulk {commodity} for {place}"]
@export_multiline var bulk_descriptions: Array[String] = ["A large shipment of {commodity} bound for {place}. Needs plenty of free cargo space."]
@export var ferry_titles: Array[String] = ["Passage to {place}"]
@export_multiline var ferry_descriptions: Array[String] = ["{passengers} need a lift from {origin} to {place}."]
@export var exploration_titles: Array[String] = ["Chart the {system} system"]
@export_multiline var exploration_descriptions: Array[String] = ["Fly close to every body in the {system} system and report back to {origin}."]


func validate() -> Array[String]:
	var problems: Array[String] = []
	if min_offers < 1:
		problems.append("min_offers must be at least 1")
	if target_offers < min_offers:
		problems.append("target_offers is below min_offers")
	if cargo_weight < 0.0 or ferry_weight < 0.0 or exploration_weight < 0.0 or cargo_weight + ferry_weight + exploration_weight <= 0.0:
		problems.append("type weights must not be negative and must not all be zero")
	if cargo_quantity_min < 1 or cargo_quantity_max < cargo_quantity_min:
		problems.append("cargo quantity range is invalid")
	if bulk_quantity_min < 1 or bulk_quantity_max < bulk_quantity_min:
		problems.append("bulk quantity range is invalid")
	if ferry_max_passengers < 1 or ferry_max_passengers > FerryContract.MAX_PASSENGERS:
		problems.append("ferry_max_passengers must be 1 to %d" % FerryContract.MAX_PASSENGERS)
	if ferry_max_jumps < 0 or cargo_max_jumps < 0 or exploration_max_jumps < 0:
		problems.append("jump limits must not be negative")
	for list in [cargo_titles, cargo_descriptions, bulk_titles, bulk_descriptions, ferry_titles,
			ferry_descriptions, exploration_titles, exploration_descriptions]:
		if list.is_empty():
			problems.append("a wording list is empty")
	return problems
