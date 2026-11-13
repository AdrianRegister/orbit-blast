class_name ShooterInfo
extends RefCounted
## What TargetScorer needs to know about the ship that is choosing a target, as
## plain data (so the scoring can be tested without a scene).

## Damage per second of all its weapons, and of its light weapons alone.
var dps: float = 0.0
var light_dps: float = 0.0
## How far its longest weapon reaches.
var weapon_range: float = 0.0
## How much damage it takes to destroy it (see CombatRating.staying_power).
var staying_power: float = 1.0
var rating: float = 1.0
## Whether it is a nimble ship (only light weapons can hurt it).
var nimble: bool = false


static func from_combatant(combatant: Combatant) -> ShooterInfo:
	var info := ShooterInfo.new()
	info.dps = combatant.weapons.get_dps()
	info.light_dps = combatant.weapons.get_dps(true)
	info.weapon_range = combatant.weapons.get_longest_range()
	info.staying_power = maxf(combatant.staying_power, 1.0)
	info.rating = maxf(combatant.rating, 1.0)
	info.nimble = combatant.evasive
	return info
