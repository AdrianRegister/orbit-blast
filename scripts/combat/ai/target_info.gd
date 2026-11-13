class_name TargetInfo
extends RefCounted
## What TargetScorer needs to know about one possible target, as plain data. The
## caller fills it in (see from_combatant) and adds what only it knows: whether the
## target threatens something the shooter protects, whether a commander named it.

## The thing this describes, returned by TargetScorer.choose (the Combatant).
var ref: Variant
var distance: float = 0.0
## Size of the ship (ShipClass.tier) and whether it is nimble.
var tier: int = 0
var nimble: bool = false
var rating: float = 1.0
## Hull left, from 0 to 1.
var hull_fraction: float = 1.0
## Damage per second it can do to the shooter (nimble shooters are only hurt by light weapons).
var threat_dps: float = 0.0
## It is attacking a ship the shooter protects (an escort's reason to go for it).
var attacking_protected: bool = false
## How many ships are already targeting it, and how many it takes to deal with it.
var targeted_by: int = 0
var attackers_wanted: int = 1
## A commander assigned it to the shooter.
var is_focus: bool = false
## Added to the score as it stands: a profile's liking for this kind of target.
var bias: float = 0.0


## Describes `target` as seen by `shooter`. `targeters` is how many ships already
## aim at it. The caller sets attacking_protected, is_focus and bias itself.
static func from_combatant(target: Combatant, shooter: Combatant, shooter_info: ShooterInfo, targeters: int) -> TargetInfo:
	var info := TargetInfo.new()
	info.ref = target
	info.distance = shooter.global_position.distance_to(target.global_position)
	info.tier = target.ship_class.tier if target.ship_class != null else 0
	info.nimble = target.evasive
	info.rating = maxf(target.rating, 1.0)
	var defence: DefenceState = target.health.state
	info.hull_fraction = clampf(defence.hull / defence.max_hull, 0.0, 1.0) if defence.max_hull > 0.0 else 1.0
	info.threat_dps = target.weapons.get_dps(shooter_info.nimble)
	info.targeted_by = targeters
	info.attackers_wanted = clampi(ceili(info.rating / shooter_info.rating), 1, 8)
	return info
