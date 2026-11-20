class_name BalanceMath
extends RefCounted
## Pure maths on ship models for balancing (see doctrine_balancing.md): which of a ship's weapons can
## hurt another, how long one would take to destroy the other if every shot landed, and which models
## are the same class on the two sides. It reads static data only and changes nothing; the report
## (tools/balance_report.gd) and the rating budget test use it.
##
## The time to kill is a best case: every shot lands and nothing is dodged, the attacker never runs
## short of energy, and the target neither regenerates nor moves. What the real AI does with a ship
## (turning circles, evasion, ranges) is what the duel matrix (tools/balance_matrix.gd) is for.

## No ship can be destroyed in more than this, so a pair that cannot hurt each other reports INF.
const LIMIT_SECONDS := 1200.0


## The weapons of `attacker` that can hurt `defender`: every armed weapon except point defence, and,
## against a nimble ship, only the light ones (medium and larger shots pass through it).
static func weapons_that_hit(attacker: ShipStats, defender: ShipStats) -> Array[WeaponDefinition]:
	var result: Array[WeaponDefinition] = []
	var nimble: bool = defender.ship_class != null and defender.ship_class.is_evasive()
	for weapon in attacker.default_loadout:
		if weapon == null or weapon.point_defence or weapon.fire_interval <= 0.0 or weapon.damage <= 0.0:
			continue
		if nimble and weapon.mount_size >= WeaponMount.Size.MEDIUM:
			continue
		result.append(weapon)
	return result


## The raw damage per second of the weapons of `attacker` that can hurt `defender`.
static func landing_dps(attacker: ShipStats, defender: ShipStats) -> float:
	var total := 0.0
	for weapon in weapons_that_hit(attacker, defender):
		total += weapon.damage / weapon.fire_interval
	return total


## Seconds `attacker` needs to destroy `defender` with every shot landing (INF if it cannot).
## Each weapon fires at time 0 and then every `fire_interval`; shots go through the real damage
## model (shield, armour and hull, with the weapon's multipliers and shield bypass).
static func time_to_kill(attacker: ShipStats, defender: ShipStats, rules: DamageRules = null) -> float:
	var weapons := weapons_that_hit(attacker, defender)
	if weapons.is_empty():
		return INF
	if rules == null:
		rules = DamageRules.shared()
	var state := DefenceState.full(defender.shield_capacity, defender.armour, defender.hull)
	var next: Array[float] = []
	for weapon in weapons:
		next.append(0.0)
	while true:
		var soonest := 0
		for index in weapons.size():
			if next[index] < next[soonest]:
				soonest = index
		var now := next[soonest]
		if now > LIMIT_SECONDS:
			return INF
		DamageModel.resolve(state, Hit.from_weapon(weapons[soonest]), rules)
		if state.is_destroyed():
			return now
		next[soonest] = now + weapons[soonest].fire_interval
	return INF


## How many times faster `a` would destroy `b` than `b` would destroy `a` (above 1: `a` is ahead;
## INF if only `a` can hurt `b`, 0 if only `b` can hurt `a`, 1 if neither can).
static func edge(a: ShipStats, b: ShipStats) -> float:
	var a_kills := time_to_kill(a, b)
	var b_kills := time_to_kill(b, a)
	if is_inf(a_kills) and is_inf(b_kills):
		return 1.0
	if is_inf(a_kills):
		return 0.0
	if is_inf(b_kills):
		return INF
	return b_kills / a_kills


## The models of two factions that are the same class, as [{"class": id, "a": ShipStats, "b": ShipStats}],
## smallest class first. A class one side has no model of is left out.
static func matching_pairs(models: Array[ShipStats], faction_a: StringName, faction_b: StringName) -> Array[Dictionary]:
	var by_class := {}
	for model in models:
		if model.faction == null or model.ship_class == null or model.default_loadout.is_empty():
			continue
		var key: StringName = model.ship_class.id
		if not by_class.has(key):
			by_class[key] = {}
		by_class[key][model.faction.id] = model
	var pairs: Array[Dictionary] = []
	for key in by_class:
		var sides: Dictionary = by_class[key]
		if sides.has(faction_a) and sides.has(faction_b):
			pairs.append({"class": key, "a": sides[faction_a], "b": sides[faction_b]})
	pairs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var tier_x: int = x["a"].ship_class.tier
		var tier_y: int = y["a"].ship_class.tier
		return tier_x < tier_y if tier_x != tier_y else str(x["class"]) < str(y["class"]))
	return pairs


## How far apart the ratings of two models are, as a fraction of the lower: 0.05 is 5%.
static func rating_gap(a: ShipStats, b: ShipStats) -> float:
	var low := minf(CombatRating.of(a), CombatRating.of(b))
	return absf(CombatRating.of(a) - CombatRating.of(b)) / low if low > 0.0 else INF
