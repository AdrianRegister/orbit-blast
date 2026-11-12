class_name DamageModel
extends RefCounted
## The layered damage rules, as pure functions on data: no nodes, no signals.
##
## A hit is handled in this order:
##  1. A share of the damage (`shield_bypass`) skips the shields.
##  2. The rest hits the shields, scaled by the hit's `shield_multiplier`. What
##     the shields cannot absorb carries on (turned back into raw damage).
##  3. Damage reaching the armour is cut by `armour_damage_reduction` and scaled
##     by the hit's `armour_multiplier`, and taken from the armour. What the
##     armour cannot absorb carries on to the hull. While armour holds,
##     `armour_bleed_through` of the absorbed damage also reaches the hull.
##  4. The hull takes the rest. At zero the ship is destroyed.
##
## Every number comes from DamageRules and the hit, so tuning is data only.


## Applies `hit` to `state` and returns what happened. `state` is changed.
static func resolve(state: DefenceState, hit: Hit, rules: DamageRules) -> DamageResult:
	var result := DamageResult.new()
	if state.hull <= 0.0 or hit.damage <= 0.0:
		result.destroyed = state.hull <= 0.0
		return result

	var bypass := clampf(hit.shield_bypass, 0.0, 1.0)
	var bypassing := hit.damage * bypass
	var shielded := hit.damage - bypassing

	# Shields.
	var carry := bypassing
	if shielded > 0.0:
		var shield_mult := maxf(hit.shield_multiplier, 0.0)
		var effective := shielded * shield_mult
		var absorbed := minf(state.shield, effective)
		state.shield -= absorbed
		result.shield_damage = absorbed
		var overflow := effective - absorbed
		# A weapon that does nothing to shields does nothing to anything it
		# could not absorb either, so only convert back when it can.
		if overflow > 0.0 and shield_mult > 0.0:
			carry += overflow / shield_mult
		elif overflow > 0.0:
			carry += shielded

	# Armour.
	var to_hull := 0.0
	if carry > 0.0:
		if state.armour > 0.0:
			var armour_mult := maxf(hit.armour_multiplier, 0.0)
			var reduction := 1.0 - clampf(rules.armour_damage_reduction, 0.0, 0.95)
			var per_raw := reduction * armour_mult
			var effective_armour := carry * per_raw
			var taken := minf(state.armour, effective_armour)
			state.armour -= taken
			result.armour_damage = taken
			to_hull += taken * clampf(rules.armour_bleed_through, 0.0, 1.0)
			var armour_overflow := effective_armour - taken
			if armour_overflow > 0.0 and per_raw > 0.0:
				to_hull += armour_overflow / per_raw
			elif armour_overflow > 0.0:
				to_hull += carry
		else:
			to_hull += carry

	# Hull.
	if to_hull > 0.0:
		var dealt := minf(state.hull, to_hull)
		state.hull -= dealt
		result.hull_damage = dealt
	result.destroyed = state.hull <= 0.0
	return result
