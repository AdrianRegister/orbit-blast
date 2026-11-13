class_name FleetComposer
extends RefCounted
## Decides what a unit is made of: given a recipe, who it belongs to and the ship
## models that exist, it draws a FormationPlan. Pure (no nodes), so it can be
## tested with thousands of random units.
##
## The rules are all in the recipe (FormationRecipe, RecipeGroup); this only applies
## them:
##  - each group gets a random size inside its range, trimmed so the unit's ships
##    stay within the recipe's range;
##  - a group's size is split between its classes in proportion to their weights,
##    by largest remainder (so 2:1 gives 3 -> 2+1, 4 -> 3+1, 5 -> 3+2, 6 -> 4+2),
##    with ties broken at random;
##  - each class is filled with ship models that belong to it, the faction and the
##    category;
##  - a class with no ship model is left out and the others take its share (no heavy
##    fighters: only fighters); a group that must have ships but has none, makes the
##    whole unit impossible, and compose() returns null.


## Draws a plan for `recipe` for `faction_id`, from `available` ship models. Null if
## the unit cannot be built from them.
static func compose(recipe: FormationRecipe, faction_id: StringName, available: Array[ShipType],
		rng: RandomNumberGenerator = null) -> FormationPlan:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var plan := FormationPlan.new()
	plan.recipe = recipe

	# How many ships each group has.
	var options: Array = []  # per group: Array of {"class", "weight", "types"}
	var counts: Array[int] = []
	for group in recipe.groups:
		var group_options := options_for(group, recipe, faction_id, available)
		options.append(group_options)
		if group_options.is_empty():
			if group.min_count > 0:
				return null
			counts.append(0)
		else:
			counts.append(rng.randi_range(group.min_count, group.max_count))
	if not _fit_total(recipe, counts, options, rng):
		return null

	# Which ships fill them.
	for index in recipe.groups.size():
		if counts[index] == 0:
			continue
		var group := recipe.groups[index]
		var group_options: Array = options[index]
		var weights: Array[float] = []
		for option in group_options:
			weights.append(option["weight"])
		var shares := allocate(counts[index], weights, group.min_each, rng)
		for option_index in group_options.size():
			for n in shares[option_index]:
				plan.ships.append(_pick_type(group_options[option_index]["types"], rng))

	# The units inside it.
	for child in recipe.children:
		var wanted := rng.randi_range(child.min_count, child.max_count)
		for n in wanted:
			var inner := compose(child.recipe, faction_id, available, rng)
			if inner == null:
				if n < child.min_count:
					return null
				break
			plan.children.append(inner)

	if not recipe.shapes.is_empty():
		plan.shape = recipe.shapes[rng.randi_range(0, recipe.shapes.size() - 1)]
	return plan


## Splits `count` ships between entries in proportion to `weights` by largest
## remainder, ties broken at random. With `min_each`, every entry with a weight
## keeps at least that many when there are enough ships to go round. The result
## adds up to `count`.
static func allocate(count: int, weights: Array[float], min_each: int, rng: RandomNumberGenerator) -> Array[int]:
	var shares: Array[int] = []
	var total := 0.0
	for weight in weights:
		total += maxf(weight, 0.0)
		shares.append(0)
	if count <= 0 or total <= 0.0:
		return shares
	var remainders: Array[float] = []
	var given := 0
	for index in weights.size():
		var quota := count * maxf(weights[index], 0.0) / total
		shares[index] = int(floor(quota + 0.000001))
		remainders.append(quota - shares[index])
		given += shares[index]
	# The leftover ships go to the biggest remainders; equal remainders are drawn at random.
	var order: Array[int] = []
	var keys: Array[float] = []
	for index in weights.size():
		order.append(index)
		keys.append(rng.randf())
	order.sort_custom(func(a: int, b: int) -> bool:
		if absf(remainders[a] - remainders[b]) > 0.000001:
			return remainders[a] > remainders[b]
		return keys[a] < keys[b])
	var position := 0
	while given < count:
		var index := order[position % order.size()]
		if weights[index] > 0.0:
			shares[index] += 1
			given += 1
		position += 1
	# Keep a minimum of each class, taking from the largest share.
	if min_each > 0:
		var present := 0
		for weight in weights:
			if weight > 0.0:
				present += 1
		if count >= min_each * present:
			for index in weights.size():
				while weights[index] > 0.0 and shares[index] < min_each:
					var donor := _largest(shares, min_each)
					if donor < 0:
						break
					shares[donor] -= 1
					shares[index] += 1
	return shares


## The ship models a group could use, by class: [{"class": ShipClass, "weight": float,
## "types": Array[ShipType]}], only for classes that have a weight and at least one
## model. (A missing class drops out and the others share its part.)
static func options_for(group: RecipeGroup, recipe: FormationRecipe, faction_id: StringName,
		available: Array[ShipType]) -> Array:
	var result: Array = []
	for index in group.classes.size():
		var weight := group.weight_of(index)
		if weight <= 0.0:
			continue
		var types: Array[ShipType] = []
		for type in available:
			if _fits(type, group, group.classes[index], recipe, faction_id):
				types.append(type)
		if not types.is_empty():
			result.append({"class": group.classes[index], "weight": weight, "types": types})
	return result


## Every ship model in resources/ship_types/ (what the game has to compose from).
static func all_ship_types() -> Array[ShipType]:
	return ShipType.load_all()


# ------------------------------------------------------------------ internals

static func _fits(type: ShipType, group: RecipeGroup, wanted: ShipClass, recipe: FormationRecipe,
		faction_id: StringName) -> bool:
	var model := type.stats
	if model == null or model.ship_class == null or not model.ship_class.is_a(wanted):
		return false
	match group.category:
		RecipeGroup.Category.CIVILIAN:
			if type.category != ShipType.Category.CIVILIAN:
				return false
		RecipeGroup.Category.MILITARY:
			if type.category != ShipType.Category.MILITARY:
				return false
	var model_faction := model.faction_id()
	if recipe.civilian and model_faction != &"":
		return false
	match group.faction_rule:
		RecipeGroup.FactionRule.OWN:
			return model_faction == faction_id
		_:
			return model_faction == &"" or model_faction == faction_id


## Brings the group sizes inside the recipe's overall range. False if it cannot be done.
static func _fit_total(recipe: FormationRecipe, counts: Array[int], options: Array, rng: RandomNumberGenerator) -> bool:
	var total := 0
	for count in counts:
		total += count
	if recipe.max_ships > 0:
		while total > recipe.max_ships:
			var index := _trim_candidate(recipe, counts)
			if index < 0:
				return false
			counts[index] -= 1
			total -= 1
	if recipe.min_ships > 0:
		while total < recipe.min_ships:
			var index := _grow_candidate(recipe, counts, options, rng)
			if index < 0:
				return false
			counts[index] += 1
			total += 1
	return true


## The group to take a ship from: the biggest one that is above its minimum.
static func _trim_candidate(recipe: FormationRecipe, counts: Array[int]) -> int:
	var best := -1
	for index in counts.size():
		if counts[index] > recipe.groups[index].min_count and (best < 0 or counts[index] > counts[best]):
			best = index
	return best


## The group to add a ship to: one that has models and room, at random.
static func _grow_candidate(recipe: FormationRecipe, counts: Array[int], options: Array, rng: RandomNumberGenerator) -> int:
	var open: Array[int] = []
	for index in counts.size():
		if not (options[index] as Array).is_empty() and counts[index] < recipe.groups[index].max_count:
			open.append(index)
	if open.is_empty():
		return -1
	return open[rng.randi_range(0, open.size() - 1)]


static func _largest(shares: Array[int], keep: int) -> int:
	var best := -1
	for index in shares.size():
		if shares[index] > keep and (best < 0 or shares[index] > shares[best]):
			best = index
	return best


## A ship model from `types`, chosen by spawn_weight.
static func _pick_type(types: Array, rng: RandomNumberGenerator) -> ShipType:
	var total := 0.0
	for type in types:
		total += maxf(type.spawn_weight, 0.0)
	if total <= 0.0:
		return types[rng.randi_range(0, types.size() - 1)]
	var roll := rng.randf() * total
	for type in types:
		roll -= maxf(type.spawn_weight, 0.0)
		if roll <= 0.0:
			return type
	return types[types.size() - 1]
