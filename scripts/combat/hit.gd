class_name Hit
extends RefCounted
## One piece of damage arriving at a ship. Built by whatever deals the damage
## (a projectile today; beams, missiles or mines later) and given to
## Combatant.take_hit. DamageModel turns it into changes to the defence layers.

## Damage before shield and armour rules.
var damage: float = 0.0
## Multipliers against each layer (1 = no change).
var shield_multiplier: float = 1.0
var armour_multiplier: float = 1.0
## Share of the damage (0 to 1) that skips the shields.
var shield_bypass: float = 0.0
## Who dealt it: the attacking Combatant, or null (hazard, test).
var attacker: Node = null
## Where it landed, in world space.
var position: Vector2 = Vector2.ZERO


static func from_weapon(weapon: WeaponDefinition, attacker_node: Node = null, at: Vector2 = Vector2.ZERO) -> Hit:
	var hit := Hit.new()
	hit.damage = weapon.damage
	hit.shield_multiplier = weapon.shield_multiplier
	hit.armour_multiplier = weapon.armour_multiplier
	hit.shield_bypass = weapon.shield_bypass
	hit.attacker = attacker_node
	hit.position = at
	return hit
