class_name ShipSpecs
extends RefCounted
## The numbers a ship actually flies and carries with: the model's base values
## with the installed upgrades applied. This is the ONLY place base and upgrades
## are combined. Nothing here is stored; it is recomputed whenever needed, so it
## can never disagree with the ship's upgrade list.

var thrust: float = 0.0
var turn_rate: float = 0.0
var max_speed: float = 0.0
var cargo_capacity: int = 0
## Defences and energy (no upgrade changes these yet; they come from the model).
var shield_capacity: float = 0.0
var shield_regen: float = 0.0
var shield_regen_delay: float = 0.0
var armour: float = 0.0
var hull: float = 0.0
var energy_capacity: float = 0.0
var energy_regen: float = 0.0
var hit_radius: float = 0.0
## How many weapons the ship can carry.
var weapon_mounts: int = 0


## Specs of `model` with `upgrades` (Array of UpgradeDefinition) installed.
## Cargo bonuses add up. For engines and manoeuvrability only the best
## installed tier counts.
static func compute(model: ShipStats, upgrades: Array = []) -> ShipSpecs:
	var specs := ShipSpecs.new()
	var cargo_bonus := 0
	var speed_bonus := 0.0
	var thrust_bonus := 0.0
	var turn_bonus := 0.0
	for upgrade: UpgradeDefinition in upgrades:
		cargo_bonus += upgrade.cargo_bonus
		speed_bonus = maxf(speed_bonus, upgrade.speed_bonus)
		thrust_bonus = maxf(thrust_bonus, upgrade.thrust_bonus)
		turn_bonus = maxf(turn_bonus, upgrade.turn_bonus)
	specs.thrust = model.thrust * (1.0 + thrust_bonus)
	specs.turn_rate = model.turn_rate * (1.0 + turn_bonus)
	specs.max_speed = model.max_speed * (1.0 + speed_bonus)
	specs.cargo_capacity = model.cargo_capacity + cargo_bonus
	specs.shield_capacity = model.shield_capacity
	specs.shield_regen = model.shield_regen
	specs.shield_regen_delay = model.shield_regen_delay
	specs.armour = model.armour
	specs.hull = model.hull
	specs.energy_capacity = model.energy_capacity
	specs.energy_regen = model.energy_regen
	specs.hit_radius = model.get_hit_radius()
	specs.weapon_mounts = model.weapon_mounts.size()
	return specs
