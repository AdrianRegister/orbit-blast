class_name CombatRating
extends RefCounted
## One number for how strong a ship is in a fight, so code can pick "the strongest
## ship": a formation's flagship, the tip of a wedge, the heaviest escort. Later
## it can also feed abstract fleet battles and a faction's military strength.
##
## It is the geometric mean of staying power and firepower, so a ship that is
## tough but harmless, or armed but fragile, rates below one that is both:
##   staying power = shields + hull + armour counted for the share of damage it
##                   absorbs (see DamageRules.armour_damage_reduction)
##   firepower     = damage per second of every fitted weapon
## A small baseline firepower keeps unarmed ships (freighters) comparable by
## their staying power alone instead of all rating zero.
##
## Pure maths on static data; it reads nothing that changes while playing.

## Firepower credited to every ship, so unarmed ships still rank by durability.
const BASELINE_DPS := 1.0


## The rating of `model` with `loadout` fitted (an Array of WeaponDefinition,
## null entries are empty mounts). Without a loadout, the model's default weapons.
static func of(model: ShipStats, loadout: Variant = null) -> float:
	var weapons: Array = loadout if loadout != null else model.default_loadout
	return sqrt(staying_power(model) * (damage_per_second(weapons) + BASELINE_DPS))


## Shields, hull and armour, with armour counted for how much more damage it
## lets the ship take (an armour point absorbs 1 / (1 - reduction) points).
static func staying_power(model: ShipStats) -> float:
	var reduction := clampf(DamageRules.shared().armour_damage_reduction, 0.0, 0.95)
	return model.shield_capacity + model.hull + model.armour / (1.0 - reduction)


## Damage per second of the fitted weapons, ignoring energy limits.
static func damage_per_second(weapons: Array) -> float:
	var total := 0.0
	for weapon: WeaponDefinition in weapons:
		if weapon != null and weapon.fire_interval > 0.0:
			total += weapon.damage / weapon.fire_interval
	return total
