class_name EconomyConfig
extends Resource
## The tunable numbers of the economic model, in one resource
## (resources/economy/economy_config.tres). Nothing here changes while playing.
## Rates are units per day.

## The population that the rates in EconomyProfile and Commodity.civilian_demand
## are written for. A settlement of this size gets exactly those rates.
@export var reference_population: int = 1000000

## How production grows with population. Below 1.0 a huge world makes less per
## person than a small one (it is harder to organise), so big worlds do not
## swamp the economy.
@export var production_exponent: float = 0.9

## How the people's own needs (Commodity.civilian_demand) grow with population.
## 1.0 = proportional: twice the people eat twice as much.
@export var demand_exponent: float = 1.0

## Population ratio (population / reference) never counts as less than this, so
## a tiny outpost still has a market worth visiting.
@export var min_scale: float = 0.02

## A good is an export when production beats consumption by more than this
## fraction of the larger of the two, an import when it falls short by that much.
## In between the settlement is self-sufficient and neither exports nor imports.
@export_range(0.0, 0.5) var balance_threshold: float = 0.1

## A location's own exported_goods / imported_goods list its specialties. A
## listed export makes at least this many units a day (at the reference
## population) and at least `specialty_export_margin` times what the place uses.
@export var specialty_export_flow: float = 80.0
@export var specialty_export_margin: float = 1.5
## A listed import is consumed at least this many units a day (at the reference
## population), and the location stops producing it.
@export var specialty_import_flow: float = 40.0
## Other production and demand of a specialty good is multiplied by this.
@export var specialty_multiplier: float = 1.5

## Profile used by a location with no planet type and no profile of its own
## (stations).
@export var station_profile: EconomyProfile

@export_group("Stock")
## How much a market can hold, in days of its throughput (the larger of what it
## makes and uses). Production slows as stock approaches this and stops at it.
@export var cover_days: float = 40.0
## The stock level prices treat as normal, in days of throughput. Above it goods
## are cheap, below it dear.
@export var target_cover_days: float = 8.0
## Consumers go short when stock falls below this many days of their use.
@export var reserve_days: float = 10.0
## Share of a shortfall (use minus production) that background freight brings in
## each day while stock is below the normal level, fading to nothing at it. So a
## market the player ignores never runs dry for good, but freight never feeds a glut.
@export_range(0.0, 1.0) var ambient_share: float = 0.5
## Small markets count as having at least this throughput (units/day) when stock
## limits and the normal level are worked out, so every market holds a few units.
@export var min_flow: float = 3.0
## Days of the simulation run when a market is first created, so it starts at a
## natural level instead of empty.
@export var warmup_days: int = 90
## A market catches up at most this many days when it is next visited. By then
## it has long settled, so more days would change nothing.
@export var max_sync_days: int = 1000

@export_group("Prices")
## How steeply price follows stock: price factor = (stock / normal) ^ -exponent.
@export var price_exponent: float = 0.25
## The price factor never goes below or above these (a glut or a famine).
@export var min_price_factor: float = 0.5
@export var max_price_factor: float = 2.0
## Stock below this fraction of the normal level is priced as if it were this
## much, which keeps the price finite when a market is empty.
@export var min_supply_ratio: float = 0.05
## Gap between what a market charges and what it pays, as a fraction of the
## price. 0.1 = it charges 5% above the price and pays 5% below.
@export_range(0.0, 0.5) var spread: float = 0.1

@export_group("Supply labels")
## How the trading screen words a market's stock, by stock compared with normal
## (1.0). Below `scarce_below` is Scarce, below `low_below` Low, up to
## `plentiful_above` Normal, up to `glut_above` Plentiful, and beyond that Glut.
## An importer usually sits at Low, a self-sufficient good at Normal and an
## exporter at Plentiful; a glut means someone has dumped goods here.
@export var scarce_below: float = 0.25
@export var low_below: float = 0.75
@export var plentiful_above: float = 1.4
@export var glut_above: float = 6.0


func validate() -> Array[String]:
	var problems: Array[String] = []
	if cover_days <= 0.0 or target_cover_days <= 0.0 or reserve_days <= 0.0:
		problems.append("cover, target and reserve days must be positive")
	if min_flow <= 0.0:
		problems.append("min_flow must be positive")
	if warmup_days < 0 or max_sync_days < 1:
		problems.append("warmup_days and max_sync_days are out of range")
	if price_exponent <= 0.0 or min_price_factor <= 0.0 or max_price_factor < min_price_factor:
		problems.append("price curve settings are out of range")
	if min_supply_ratio <= 0.0:
		problems.append("min_supply_ratio must be positive")
	if not (scarce_below < low_below and low_below < plentiful_above and plentiful_above < glut_above):
		problems.append("supply label limits must rise: scarce < low < plentiful < glut")
	if reference_population <= 0:
		problems.append("reference_population must be positive")
	if min_scale <= 0.0:
		problems.append("min_scale must be positive")
	if production_exponent <= 0.0 or demand_exponent <= 0.0:
		problems.append("exponents must be positive")
	if station_profile == null:
		problems.append("station_profile is not set")
	return problems
