class_name TargetScorer
extends RefCounted
## How a ship ranks possible targets. Pure maths on plain data (ShooterInfo,
## TargetInfo, CombatDoctrine), like DamageModel, so it can be tested without a scene.
##
## The score of a target is a sum, each term from 0 to 1 and weighted by the doctrine:
##   effectiveness  the share of my firepower that can hurt it. A nimble target is only
##                  hurt by light weapons, so cruisers (no light weapons) cannot target
##                  fighters at all and leave them to the fighters
##   affinity       is it the size of ship my class is meant for
##   threat         how fast it could destroy me (a smooth curve, so bigger is always worse); counted protect_bonus times over when it
##                  is attacking something I protect, so escort fighters go for the
##                  fighters chewing on their cruiser
##   distance       inside my weapon reach, full; falling to nothing at max_distance
##   finish         how damaged it already is
##   focus          a commander named it for me
##   overkill       (a penalty) enough ships are already on it
## plus `bias`, a profile's liking for this kind of target.

## The score of a target that cannot be chosen (out of sight, or unhurtable).
const EXCLUDED := -1000000.0
## What affinity falls by for each size class a target is outside the preferred range.
const AFFINITY_PER_TIER := 0.34


## The share (0 to 1) of the shooter's firepower that can hurt the target.
static func effectiveness(shooter: ShooterInfo, target: TargetInfo) -> float:
	if shooter.dps <= 0.0:
		return 0.0
	return clampf(shooter.light_dps / shooter.dps, 0.0, 1.0) if target.nimble else 1.0


## 1 for a target in the doctrine's preferred sizes, less the further outside.
static func affinity(doctrine: CombatDoctrine, tier: int) -> float:
	var away := 0
	if tier < doctrine.preferred_tier_min:
		away = doctrine.preferred_tier_min - tier
	elif tier > doctrine.preferred_tier_max:
		away = tier - doctrine.preferred_tier_max
	return maxf(1.0 - AFFINITY_PER_TIER * away, 0.0)


## How dangerous the target is to the shooter, from 0 to 1 (up to `protect_bonus`
## when it threatens a ship the shooter protects). It is 1 - e^-k, where k is how
## many times over the target could destroy the shooter within the doctrine's
## threat horizon: it rises smoothly and never quite reaches 1, so a bigger threat
## always scores higher than a smaller one.
static func threat(shooter: ShooterInfo, doctrine: CombatDoctrine, target: TargetInfo) -> float:
	var kills := target.threat_dps * doctrine.threat_horizon / shooter.staying_power
	var value := 1.0 - exp(-kills)
	if target.attacking_protected:
		value *= doctrine.protect_bonus
	return value


## 1 inside the shooter's weapon reach, falling in a straight line to 0 at max_distance.
static func closeness(shooter: ShooterInfo, target: TargetInfo, max_distance: float) -> float:
	if target.distance <= shooter.weapon_range:
		return 1.0
	if max_distance <= shooter.weapon_range:
		return 0.0
	return clampf(1.0 - (target.distance - shooter.weapon_range) / (max_distance - shooter.weapon_range), 0.0, 1.0)


## The score of `target` for `shooter`, or EXCLUDED when it cannot be chosen: beyond
## `max_distance`, or nothing the shooter has can hurt it.
static func score(shooter: ShooterInfo, doctrine: CombatDoctrine, target: TargetInfo, max_distance: float) -> float:
	if target.distance > max_distance:
		return EXCLUDED
	var hurt := effectiveness(shooter, target)
	if hurt <= 0.0:
		return EXCLUDED
	var total := doctrine.weight_effectiveness * hurt
	total += doctrine.weight_affinity * affinity(doctrine, target.tier)
	total += doctrine.weight_threat * threat(shooter, doctrine, target)
	total += doctrine.weight_distance * closeness(shooter, target, max_distance)
	total += doctrine.weight_finish * (1.0 - target.hull_fraction)
	if target.is_focus:
		total += doctrine.weight_focus
	if target.targeted_by >= target.attackers_wanted:
		total -= doctrine.weight_overkill
	return total + target.bias


## The candidates that can be chosen, best first: [{"ref", "score"}].
static func rank(shooter: ShooterInfo, doctrine: CombatDoctrine, candidates: Array[TargetInfo], max_distance: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate in candidates:
		var value := score(shooter, doctrine, candidate, max_distance)
		if value > EXCLUDED:
			result.append({"ref": candidate.ref, "score": value})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	return result


## The target to shoot at: the best-scoring candidate, unless `current` is still a
## candidate and the best does not beat it by the doctrine's hysteresis (so a ship
## does not keep changing its mind). Null when nothing can be chosen.
static func choose(shooter: ShooterInfo, doctrine: CombatDoctrine, candidates: Array[TargetInfo], max_distance: float, current: Variant = null) -> Variant:
	var ranked := rank(shooter, doctrine, candidates, max_distance)
	if ranked.is_empty():
		return null
	var best: Dictionary = ranked[0]
	if current != null:
		for entry in ranked:
			if entry["ref"] == current:
				var margin: float = doctrine.hysteresis * maxf(absf(entry["score"]), 1.0)
				if best["score"] - entry["score"] <= margin:
					return current
				break
	return best["ref"]
