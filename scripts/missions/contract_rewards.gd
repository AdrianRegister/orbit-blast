class_name ContractRewards
extends Resource
## How a contract's reward is worked out. One resource
## (resources/contracts/reward_rules.tres), used by every source of contracts so
## rewards stay consistent and are balanced in one place. Distance is measured in
## jumps and in fuel (the cost of the jumps), so longer journeys pay more.
## Cargo rewards also have hard ceilings, so whatever the commodity or quantity
## a normal delivery never pays more than `cargo_cap` and a bulk one (at least
## `bulk_quantity` units) never more than `bulk_cap`.

@export_group("Cargo delivery")
## Multiplies the cargo's value (quantity x base price).
@export var cargo_value_factor: float = 0.25
@export var cargo_per_jump: int = 1000
@export var cargo_per_fuel: int = 20
@export var cargo_cap: int = 20000
## A delivery of at least this many units is a bulk delivery.
@export var bulk_quantity: int = 200
@export var bulk_cap: int = 45000

@export_group("Ferry passengers")
@export var ferry_base: int = 300
@export var ferry_per_passenger: int = 150
@export var ferry_per_jump: int = 400
@export var ferry_per_fuel: int = 5

@export_group("Exploration")
@export var exploration_base: int = 8000
@export var exploration_per_jump: int = 1500
@export var exploration_per_fuel: int = 40

## Rewards are rounded to a multiple of this, so they read as round numbers.
@export var rounding: int = 50


func is_bulk(quantity: int) -> bool:
	return quantity >= bulk_quantity


## The largest reward a cargo delivery of this size may pay.
func get_cargo_cap(quantity: int) -> int:
	return bulk_cap if is_bulk(quantity) else cargo_cap


func cargo_reward(commodity: Commodity, quantity: int, jumps: int, fuel: int) -> int:
	var value := float(quantity * commodity.base_price) * cargo_value_factor
	var distance := float(jumps * cargo_per_jump + fuel * cargo_per_fuel)
	return mini(_round(value + distance), get_cargo_cap(quantity))


func ferry_reward(passengers: int, jumps: int, fuel: int) -> int:
	return _round(float(ferry_base + passengers * ferry_per_passenger + jumps * ferry_per_jump + fuel * ferry_per_fuel))


func exploration_reward(jumps: int, fuel: int) -> int:
	return _round(float(exploration_base + jumps * exploration_per_jump + fuel * exploration_per_fuel))


func _round(value: float) -> int:
	return maxi(rounding, roundi(value / rounding) * rounding)
