class_name ContractRewards
extends Resource
## How a contract's reward is worked out when an offer does not fix it. One
## resource (resources/contracts/reward_rules.tres), used by every source of
## contracts, hand-written or generated, so rewards stay consistent and are
## balanced in one place. Distance is measured in jumps and in fuel (the cost of
## the jumps), so longer journeys pay more.

@export_group("Cargo delivery")
## Multiplies the cargo's value (quantity x base price).
@export var cargo_value_factor: float = 2.5
@export var cargo_per_jump: int = 2500
@export var cargo_per_fuel: int = 50

@export_group("Exploration")
@export var exploration_base: int = 20000
@export var exploration_per_jump: int = 4000
@export var exploration_per_fuel: int = 100

## Rewards are rounded to a multiple of this, so they read as round numbers.
@export var rounding: int = 50


func cargo_reward(commodity: Commodity, quantity: int, jumps: int, fuel: int, multiplier: float = 1.0) -> int:
	var value := float(quantity * commodity.base_price) * cargo_value_factor
	var distance := float(jumps * cargo_per_jump + fuel * cargo_per_fuel)
	return _round((value + distance) * multiplier)


func exploration_reward(jumps: int, fuel: int, multiplier: float = 1.0) -> int:
	var distance := float(jumps * exploration_per_jump + fuel * exploration_per_fuel)
	return _round((float(exploration_base) + distance) * multiplier)


func _round(value: float) -> int:
	return maxi(rounding, roundi(value / rounding) * rounding)
