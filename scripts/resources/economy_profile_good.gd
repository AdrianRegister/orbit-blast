class_name EconomyProfileGood
extends Resource
## One line of an EconomyProfile: how much of a commodity a settlement of this
## kind makes, and how much it burns through as an input to its industry. Both
## are in units per day for a settlement of the reference population (see
## EconomyConfig), and are scaled up or down for the real population.

@export var commodity: Commodity
## Units made per day.
@export var production: float = 0.0
## Units used per day by the settlement's industry (on top of what its people
## need, which comes from Commodity.civilian_demand).
@export var industrial_demand: float = 0.0
