class_name WeaponDefinition
extends Resource
## A weapon that can be fitted to a ship mount and bought at an outfitter. One
## .tres per weapon in resources/weapons/. The definition is static data shared
## by every ship; which weapons a ship carries is stored on the ship (OwnedShip).
##
## Only projectile weapons exist so far. `kind` is the extension point for beams,
## missiles and so on: the combat code asks the weapon to fire, it does not
## assume projectiles everywhere.

enum Kind { PROJECTILE }

## Permanent unique id, e.g. &"light_blaster". Save files refer to it.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.PROJECTILE
## Price in credits.
@export var price: int = 0
## How many copies one ship can carry.
@export var max_per_ship: int = 4

## The smallest mount this weapon fits.
@export var mount_size: WeaponMount.Size = WeaponMount.Size.SMALL
## Whether the weapon can sit on a fixed mount / on a turret mount.
@export var fixed_capable: bool = true
@export var turret_capable: bool = true

## Raw damage of one shot, before shield and armour rules.
@export var damage: float = 10.0
## Seconds between shots.
@export var fire_interval: float = 0.5
## Energy taken from the ship for each shot.
@export var energy_per_shot: float = 2.0
## Muzzle speed of a shot in pixels per second.
@export var projectile_speed: float = 900.0
## How far a shot travels before it fades, in pixels. Its lifetime is
## range / projectile_speed.
@export var range: float = 700.0
## How much of the shooter's own velocity a shot keeps (0 to 1).
@export_range(0.0, 1.0) var inherit_velocity: float = 1.0
## Random aim error either side of the aim direction, in degrees.
@export_range(0.0, 45.0) var spread_degrees: float = 0.0

## Per-layer damage multipliers (see DamageModel). Above 1 is strong against
## that layer, below 1 is weak.
@export var shield_multiplier: float = 1.0
@export var armour_multiplier: float = 1.0
## Share of each shot (0 to 1) that ignores shields completely.
@export_range(0.0, 1.0) var shield_bypass: float = 0.0

## Scene used for the shot. Null = the shared default projectile.
@export var projectile_scene: PackedScene
@export var projectile_color: Color = Color(1.0, 0.85, 0.3)


## Seconds a shot lives, from range and speed.
func get_lifetime() -> float:
	return range / projectile_speed if projectile_speed > 0.0 else 0.0


## One line of numbers for the outfitter: damage, rate, range, energy, speed.
func get_stats_text() -> String:
	var text := "Damage %d   Fire rate %.1f/s   Range %d\nEnergy %d per shot   Shot speed %d" % [
			roundi(damage), 1.0 / fire_interval, roundi(range), roundi(energy_per_shot), roundi(projectile_speed)]
	if shield_multiplier != 1.0:
		text += "\nShields x%.1f" % shield_multiplier
	if armour_multiplier != 1.0:
		text += "   Armour x%.1f" % armour_multiplier
	if shield_bypass > 0.0:
		text += "\n%d%% ignores shields" % roundi(shield_bypass * 100.0)
	return text


## Whether this weapon can be fitted to `mount`.
func fits(mount: WeaponMount) -> bool:
	if mount == null:
		return false
	if mount.size < mount_size:
		return false
	if mount.type == WeaponMount.Type.FIXED:
		return fixed_capable
	return turret_capable


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if price < 0:
		problems.append("price is negative")
	if max_per_ship < 1:
		problems.append("max_per_ship must be at least 1")
	if not fixed_capable and not turret_capable:
		problems.append("the weapon must fit a fixed mount, a turret mount or both")
	if damage <= 0.0:
		problems.append("damage must be above zero")
	if fire_interval <= 0.0:
		problems.append("fire_interval must be above zero")
	if energy_per_shot < 0.0:
		problems.append("energy_per_shot is negative")
	if projectile_speed <= 0.0:
		problems.append("projectile_speed must be above zero")
	if range <= 0.0:
		problems.append("range must be above zero")
	if shield_multiplier < 0.0 or armour_multiplier < 0.0:
		problems.append("damage multipliers cannot be negative")
	return problems
