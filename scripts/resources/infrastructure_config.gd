class_name InfrastructureConfig
extends Resource
## How damage to planets and stations works (resources/infrastructure/
## infrastructure_config.tres). Damage is a number from 0 (undamaged) to 1
## (devastated). It lowers what a location produces and wears off with time. It is
## never permanent and never kills anyone: it is the foundation for bombardment and
## infrastructure raids, which are not built yet.

## How much damage wears off each day, as a share of the whole (0.02 = a devastated
## location is whole again after 50 days). Recovery is linear, so a raid that
## does half the damage is repaired in half the time.
@export_range(0.0, 1.0) var recovery_per_day: float = 0.02

## How much of a location's production is lost at full damage. 1.0 = a devastated
## location produces nothing; 0.9 would leave it a tenth. Production is lost in
## proportion to the damage below that.
@export_range(0.0, 1.0) var max_production_loss: float = 1.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if recovery_per_day < 0.0:
		problems.append("recovery_per_day must not be negative")
	if max_production_loss < 0.0 or max_production_loss > 1.0:
		problems.append("max_production_loss must be between 0 and 1")
	return problems
