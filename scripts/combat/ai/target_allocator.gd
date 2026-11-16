class_name TargetAllocator
extends RefCounted
## Shares the enemies out between the ships of a unit (Phase 3.3, steps 4 and 5): the
## part of a commander's job that decides who shoots whom. Ships are taken strongest first;
## each gets the target the TargetScorer likes best, counting the ships already given it
## (`counts`, shared between calls so a whole fleet can be shared out one unit at a time),
## so they do not all pile on one enemy: at least `profile.min_attackers` go for each, so
## fighters work in pairs. It only makes the orders; the caller gives them to the pilots.


## Returns {NpcShip: CombatOrder}, one ENGAGE order for each of `ships` (GUARD orders when
## `guard`, the ship they protect, is given: then only `allowed` can be chosen, and a target
## is a bigger threat when it is the one attacking `guard`). `focus` (the enemy a higher
## commander wants dealt with) adds to a target's score; `strike` makes small craft (tier 1
## and under, then tier 2 at half) more attractive, which is a strike squadron's job.
static func assign(picture: TacticalPicture, hostiles: Array[Combatant], ships: Array[NpcShip],
		profile: TacticalProfile, counts: Dictionary, guard: NpcShip = null, allowed: Array[Combatant] = [],
		focus: Array = [], strike: bool = false) -> Dictionary:
	var orders := {}
	var targets: Array[Combatant] = allowed if guard != null else hostiles
	var attackers_of_guard: Array[Combatant] = []
	if guard != null and guard.get_combatant() != null:
		attackers_of_guard = picture.targeters_of(guard.get_combatant())
	for ship in ships:
		var combatant: Combatant = ship.get_combatant()
		var ship_class: ShipClass = ship.ship_type.stats.ship_class
		var doctrine: CombatDoctrine = ship_class.get_doctrine() if ship_class != null else null
		var order := CombatOrder.new(CombatOrder.Kind.GUARD if guard != null else CombatOrder.Kind.ENGAGE)
		if guard != null:
			order.protectee = guard
			order.radius = profile.guard_radius
		if doctrine != null:
			var me := ShooterInfo.from_combatant(combatant)
			var candidates: Array[TargetInfo] = []
			for other in targets:
				if not is_instance_valid(other) or not other.is_alive():
					continue
				var info := TargetInfo.from_combatant(other, combatant, me, picture.count_targeters(other) + counts.get(other, 0))
				info.attackers_wanted = maxi(info.attackers_wanted, profile.min_attackers)
				if guard != null:
					info.attacking_protected = attackers_of_guard.has(other)
				info.is_focus = focus.has(other)
				if strike:
					info.bias = strike_bias(profile, other)
				if profile.target_bias_cargo > 0.0 and other.ship_class != null and other.ship_class.carries_cargo():
					info.bias += profile.target_bias_cargo
				candidates.append(info)
			var pilot: ShipPilot = ship.get_pilot()
			var current: Combatant = pilot.order.target if pilot != null and pilot.order != null else null
			order.target = TargetScorer.choose(me, doctrine, candidates, profile.sight_radius * 2.0, current) as Combatant
			if order.target != null:
				counts[order.target] = counts.get(order.target, 0) + 1
		orders[ship] = order
	return orders


## How much a strike squadron likes `target`: small craft (fighters, heavy fighters,
## gunboats: tier 1 and under) fully, a frigate half, bigger ships not at all.
static func strike_bias(profile: TacticalProfile, target: Combatant) -> float:
	var tier: int = target.ship_class.tier if target.ship_class != null else 0
	if tier <= 1:
		return profile.strike_bias
	if tier == 2:
		return profile.strike_bias * 0.5
	return 0.0


## Gives `order` to `ship`'s pilot (null clears it).
static func give(ship: NpcShip, order: CombatOrder) -> void:
	if is_instance_valid(ship) and ship.get_pilot() != null:
		ship.get_pilot().set_order(order)
