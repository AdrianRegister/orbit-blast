class_name ZoneRules
extends Resource
## How faction zones are drawn (resources/zones/zone_rules.tres): how far each zone
## reaches from a centre of power, and when a system becomes or stops being one. All
## distances are jumps along the jump network, never map distance.
##
## The zones, from the centre out: CAPITAL (the capital itself), CORE (the centres of
## power and their near neighbours), INNER (the next few jumps) and FRONTIER (beyond).
## A faction can have several centres (its capital and any critical system it holds),
## so it can have several cores; see ZoneManager.

@export_group("Reach")
## Systems up to this many jumps from a centre are its core.
@export var core_max_hops: int = 1
## Up to this many jumps is inner territory; beyond it is frontier.
@export var inner_max_hops: int = 3
## A centre with fewer jump links than this projects no core onto its neighbours
## (they are inner territory): a dead end cannot make its neighbours a core.
@export var core_requires_links: int = 2
## A system with at least this many links is promoted one zone toward the core
## (inner becomes core, frontier becomes inner): heavy transit brings development
## whatever the distance. 0 turns promotion off.
@export var hub_promotion_links: int = 4

@export_group("Centres of power")
## A critical system must score at least this importance (SystemAssessment.importance)
## to be a centre of power. Importance does not change with damage, so a raid cannot
## remove a centre.
@export var centre_min_importance: float = 25.0
## A critical system that changes hands must be held this many days before it
## becomes a centre of power for its new owner. A system held since the start of the
## game, or retaken by its starting owner, counts at once.
@export var establish_days: int = 10
## If a faction loses its capital, its most important remaining centre acts as the
## capital until it is retaken. False = no capital zone until then.
@export var relocate_capital: bool = true


func validate() -> Array[String]:
	var problems: Array[String] = []
	if core_max_hops < 0 or inner_max_hops < core_max_hops:
		problems.append("zone reach must satisfy 0 <= core_max_hops <= inner_max_hops")
	if core_requires_links < 0 or hub_promotion_links < 0:
		problems.append("link limits must not be negative")
	if centre_min_importance < 0.0 or establish_days < 0:
		problems.append("centre_min_importance and establish_days must not be negative")
	return problems
