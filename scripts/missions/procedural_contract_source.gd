class_name ProceduralContractSource
extends ContractSource
## Invents contracts for a location from the galaxy as it is: who owns what, how
## far apart things are, what the issuer produces and what the ship holds can
## carry. All the numbers and wording are in the ContractGenerationRules.
##
## - Cargo delivery: goods the issuer exports (or any trade good) to another
##   inhabited location owned by the same faction, at most a few jumps away.
## - Ferry passengers: one to three passengers to any inhabited location within a
##   few jumps. Quick, small, early-game work.
## - Exploration: scout an uninhabited system nobody has fully scouted yet.
##
## Only inhabited locations (dockable, with people) get contracts. All generated
## contracts are civilian.

const DEFAULT_RULES := "res://resources/contracts/generation_rules.tres"

var rules: ContractGenerationRules
var _rng := RandomNumberGenerator.new()


func _init(generation_rules: ContractGenerationRules = null) -> void:
	rules = generation_rules if generation_rules != null else load(DEFAULT_RULES)
	_rng.randomize()


func get_target_offers() -> int:
	return rules.target_offers


## Makes the generator reproducible (for tests).
func seed_rng(value: int) -> void:
	_rng.seed = value


## Whether a location is somewhere people live and ships can land.
static func is_inhabited(location: InhabitedData) -> bool:
	return location != null and location.is_dockable() and location.population > 0


func generate(location: InhabitedData, context: ContractContext, wanted: int, existing: Array[Contract]) -> Array[Contract]:
	var result: Array[Contract] = []
	if wanted <= 0 or not is_inhabited(location) or context.galaxy == null or context.registry == null:
		return result
	var taken := {}
	for contract in existing:
		taken[_key(contract)] = true
	var attempts := wanted * 12
	while result.size() < wanted and attempts > 0:
		attempts -= 1
		var contract := _make(_pick_type(), location, context)
		if contract != null and not taken.has(_key(contract)):
			taken[_key(contract)] = true
			result.append(contract)
	if result.is_empty() and existing.is_empty():
		# Never leave a mission computer empty: try each type in turn.
		for type in [&"ferry", &"cargo", &"exploration"]:
			for _try in 20:
				var contract := _make(type, location, context)
				if contract != null and not taken.has(_key(contract)):
					result.append(contract)
					return result
	return result


func _pick_type() -> StringName:
	var total := rules.cargo_weight + rules.ferry_weight + rules.exploration_weight
	var roll := _rng.randf() * total
	if roll < rules.cargo_weight:
		return &"cargo"
	if roll < rules.cargo_weight + rules.ferry_weight:
		return &"ferry"
	return &"exploration"


func _make(type: StringName, location: InhabitedData, context: ContractContext) -> Contract:
	match type:
		&"cargo":
			return _make_cargo(location, context)
		&"ferry":
			return _make_ferry(location, context)
		&"exploration":
			return _make_exploration(location, context)
	return null


# ------------------------------------------------------------------- cargo

func _make_cargo(origin: InhabitedData, context: ContractContext) -> Contract:
	var origin_system := context.system_of(origin)
	var faction := context.galaxy.get_faction_id(origin_system)
	if faction == &"" or origin.faction_id() != faction:
		return null  # unowned places do not send cargo anywhere
	var bulk := _rng.randf() < rules.bulk_chance
	var commodity := _pick_commodity(origin, context, bulk)
	if commodity == null:
		return null
	var low := rules.bulk_quantity_min if bulk else rules.cargo_quantity_min
	var high := rules.bulk_quantity_max if bulk else rules.cargo_quantity_max
	if context.max_cargo > 0:
		high = mini(high, context.max_cargo)
	if high < low:
		return null
	var quantity := _rng.randi_range(low, high)
	# Same-faction places only, so nobody is sent into someone else's territory.
	var options: Array = []
	var weights: Array[float] = []
	for place in _places_within(origin, context, rules.cargo_max_jumps):
		if context.galaxy.get_faction_id(context.system_of(place)) != faction or place.faction_id() != faction:
			continue
		options.append(place)
		weights.append(rules.importer_weight if _imports(place, commodity) else 1.0)
	var destination: InhabitedData = _pick_weighted(options, weights)
	if destination == null:
		return null
	var journey := _jumps(context, origin_system, context.system_of(destination))
	if journey.x < 0 or journey.x > rules.cargo_max_jumps:
		return null  # the cheapest route is longer than the limit
	var contract := CargoDeliveryContract.new()
	contract.origin = origin
	contract.destination = destination
	contract.commodity = commodity
	contract.quantity = quantity
	contract.reward = context.rewards.cargo_reward(commodity, quantity, journey.x, journey.y)
	var values := {"commodity": commodity.display_name, "place": destination.display_name, "origin": origin.display_name}
	contract.title = _fill(_pick_text(rules.bulk_titles if bulk else rules.cargo_titles), values)
	contract.description = _fill(_pick_text(rules.bulk_descriptions if bulk else rules.cargo_descriptions), values)
	return contract


func _pick_commodity(origin: InhabitedData, context: ContractContext, bulk: bool) -> Commodity:
	var pool: Array[Commodity] = []
	for good in origin.exported_goods:
		if good != null and good.base_price > 0:
			pool.append(good)
	if pool.is_empty():
		for good in context.registry.commodities():
			if good.base_price > 0:
				pool.append(good)
	if bulk:
		var cheap: Array[Commodity] = []
		for good in pool:
			if good.base_price <= rules.bulk_max_price:
				cheap.append(good)
		pool = cheap
	if pool.is_empty():
		return null
	return pool[_rng.randi_range(0, pool.size() - 1)]


func _imports(place: InhabitedData, commodity: Commodity) -> bool:
	for good in place.imported_goods:
		if good != null and good.id == commodity.id:
			return true
	return false


# ------------------------------------------------------------------- ferry

func _make_ferry(origin: InhabitedData, context: ContractContext) -> Contract:
	var passengers_good := context.registry.commodity(&"passengers")
	if passengers_good == null:
		return null
	var origin_system := context.system_of(origin)
	var options := _places_within(origin, context, rules.ferry_max_jumps)
	if options.is_empty():
		return null
	var destination: InhabitedData = options[_rng.randi_range(0, options.size() - 1)]
	var journey := _jumps(context, origin_system, context.system_of(destination))
	if journey.x < 0 or journey.x > rules.ferry_max_jumps:
		return null
	var contract := FerryContract.new()
	contract.origin = origin
	contract.destination = destination
	contract.commodity = passengers_good
	contract.quantity = _rng.randi_range(1, mini(rules.ferry_max_passengers, FerryContract.MAX_PASSENGERS))
	contract.reward = context.rewards.ferry_reward(contract.quantity, journey.x, journey.y)
	var values := {"place": destination.display_name, "origin": origin.display_name,
			"passengers": "%d %s" % [contract.quantity, "passenger" if contract.quantity == 1 else "passengers"]}
	contract.title = _fill(_pick_text(rules.ferry_titles), values)
	contract.description = _fill(_pick_text(rules.ferry_descriptions), values)
	return contract


# -------------------------------------------------------------- exploration

func _make_exploration(origin: InhabitedData, context: ContractContext) -> Contract:
	var origin_system := context.system_of(origin)
	var options: Array[StringName] = []
	for system in _systems_within(origin_system, context, rules.exploration_max_jumps):
		var summary := context.galaxy.get_summary(system)
		if summary == null or summary.inhabited or summary.location_ids.is_empty() or system == origin_system:
			continue
		if context.travel != null and context.travel.is_scouted(system):
			continue
		options.append(system)
	if options.is_empty():
		return null
	var target: StringName = options[_rng.randi_range(0, options.size() - 1)]
	var journey := _jumps(context, origin_system, target)
	if journey.x < 0 or journey.x > rules.exploration_max_jumps:
		return null
	var contract := ExplorationContract.new()
	contract.origin = origin
	contract.target_system = target
	contract.reward = context.rewards.exploration_reward(journey.x, journey.y)
	var values := {"system": context.system_name(target), "origin": origin.display_name, "place": context.system_name(target)}
	contract.title = _fill(_pick_text(rules.exploration_titles), values)
	contract.description = _fill(_pick_text(rules.exploration_descriptions), values)
	return contract


# ----------------------------------------------------------------- helpers

## The systems within `max_jumps` jumps of a system (itself included), sorted by
## id so everything built from them is reproducible. One breadth-first search.
func _systems_within(origin_system: StringName, context: ContractContext, max_jumps: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(context.galaxy.get_reachable(origin_system, max_jumps).keys())
	ids.sort()
	return ids


## Inhabited places, other than the origin, in systems within `max_jumps` jumps.
func _places_within(origin: InhabitedData, context: ContractContext, max_jumps: int) -> Array:
	var places: Array = []
	for system in _systems_within(context.system_of(origin), context, max_jumps):
		var summary := context.galaxy.get_summary(system)
		if summary == null:
			continue
		for location_id in summary.location_ids:
			var place := context.registry.location(location_id)
			if place != null and place != origin and is_inhabited(place):
				places.append(place)
	return places


## (jumps, fuel) between two systems; (0, 0) within one system, (-1, -1) if
## there is no route.
func _jumps(context: ContractContext, from_system: StringName, to_system: StringName) -> Vector2i:
	if from_system == to_system:
		return Vector2i.ZERO
	return context.journey(from_system, to_system)


## Identifies what a contract is about, so one location never offers the same
## thing twice.
func _key(contract: Contract) -> String:
	var delivery := contract as CargoDeliveryContract
	var exploration := contract as ExplorationContract
	if exploration != null:
		return "%s|%s" % [contract.get_type_id(), exploration.target_system]
	if delivery != null:
		return "%s|%s|%s" % [contract.get_type_id(), contract.destination.id, delivery.commodity.id]
	return "%s|%s" % [contract.get_type_id(), contract.destination.id if contract.destination != null else ""]


func _pick_text(options: Array[String]) -> String:
	return options[_rng.randi_range(0, options.size() - 1)] if not options.is_empty() else ""


func _pick_weighted(options: Array, weights: Array[float]) -> Variant:
	if options.is_empty():
		return null
	var total := 0.0
	for weight in weights:
		total += weight
	var roll := _rng.randf() * total
	for i in options.size():
		roll -= weights[i]
		if roll <= 0.0:
			return options[i]
	return options[options.size() - 1]


func _fill(template: String, values: Dictionary) -> String:
	for key in values:
		template = template.replace("{%s}" % key, str(values[key]))
	return template
