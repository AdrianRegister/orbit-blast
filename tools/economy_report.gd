extends SceneTree
## Prints what the economic model gives every inhabited location, for tuning the
## numbers in resources/economy/. Read-only. Run with:
##   Godot --headless --path . --script res://tools/economy_report.gd </dev/null
## It shows each settlement with its listed specialties used (what the game does
## now) and, as "pure", what its population and planet type alone would give.

func _init() -> void:
	var registry := ContentRegistry.new()
	var model := EconomyModel.new(load(EconomyModel.DEFAULT_CONFIG), registry.commodities())
	var places: Array[InhabitedData] = []
	for location in registry.locations():
		if location.is_dockable() and location.population > 0:
			places.append(location)
	places.sort_custom(func(a: InhabitedData, b: InhabitedData) -> bool: return a.population > b.population)

	print("")
	print("%d inhabited locations" % places.size())
	print("")
	print("%-18s %10s %-12s | %s" % ["LOCATION", "POPULATION", "PROFILE", "EXPORTS / IMPORTS (specialties used)  ||  pure model"])
	var exporters := {}
	var importers := {}
	var pure_exporters := {}
	var pure_importers := {}
	var profile_counts := {}
	for place in places:
		var used := model.compute(place, true)
		var pure := model.compute(place, false)
		var profile_id := str(used.profile.id) if used.profile != null else "-"
		profile_counts[profile_id] = profile_counts.get(profile_id, 0) + 1
		for good in used.exports():
			exporters[good.id] = exporters.get(good.id, 0) + 1
		for good in used.imports():
			importers[good.id] = importers.get(good.id, 0) + 1
		for good in pure.exports():
			pure_exporters[good.id] = pure_exporters.get(good.id, 0) + 1
		for good in pure.imports():
			pure_importers[good.id] = pure_importers.get(good.id, 0) + 1
		if place.faction != null and not _is_generated(place):
			print("%-18s %10d %-12s | X: %s  M: %s  ||  X: %s  M: %s" % [
					place.display_name if place.display_name != "" else str(place.id), place.population, profile_id,
					_names(used.exports()), _names(used.imports()), _names(pure.exports()), _names(pure.imports())])

	print("")
	print("Settlements per profile: ", profile_counts)
	print("")
	print("%-22s %9s %9s | %9s %9s   (exporting / importing settlements)" % ["COMMODITY", "export", "import", "pure exp", "pure imp"])
	for good in registry.commodities():
		if good.base_price <= 0:
			continue
		print("%-22s %9d %9d | %9d %9d" % [good.id, exporters.get(good.id, 0), importers.get(good.id, 0),
				pure_exporters.get(good.id, 0), pure_importers.get(good.id, 0)])

	print("")
	print("Galaxy totals, units/day (specialties used | pure model):")
	print("%-22s %10s %10s %6s | %10s %10s %6s" % ["COMMODITY", "made", "used", "ratio", "made", "used", "ratio"])
	for good in registry.commodities():
		if good.base_price <= 0:
			continue
		var made := 0.0
		var used := 0.0
		var pure_made := 0.0
		var pure_used := 0.0
		for place in places:
			var with_specialties := model.compute(place, true)
			var without := model.compute(place, false)
			made += with_specialties.production_of(good)
			used += with_specialties.consumption_of(good)
			pure_made += without.production_of(good)
			pure_used += without.consumption_of(good)
		print("%-22s %10.0f %10.0f %6.2f | %10.0f %10.0f %6.2f   %s" % [good.id, made, used, made / maxf(used, 0.001),
				pure_made, pure_used, pure_made / maxf(pure_used, 0.001), _verdict(good, made, used)])

	print("")
	print("Prices at start (the price of one unit, as a share of the base price) over all markets:")
	print("%-22s %6s %6s %6s %6s   %s" % ["COMMODITY", "low", "median", "high", "bestroute", "(best route: cheapest ask to dearest bid, 50 units, % profit)"])
	var markets: Array[Market] = []
	for place in places:
		markets.append(Market.new(place, model))
	for good in registry.commodities():
		if good.base_price <= 0:
			continue
		var asks: Array[float] = []
		var best_margin := -1.0
		var buy_at: Market
		var sell_at: Market
		for market in markets:
			if market.has_commodity(good):
				asks.append(float(market.get_buy_price(good)) / good.base_price)
		asks.sort()
		for source in markets:
			if not source.has_commodity(good) or source.get_stock(good) < 50:
				continue
			for target in markets:
				if target == source or not target.has_commodity(good):
					continue
				var margin := float(target.sell_total(good, 50)) / source.buy_total(good, 50) - 1.0
				if margin > best_margin:
					best_margin = margin
					buy_at = source
					sell_at = target
		if asks.is_empty():
			continue
		print("%-22s %6.2f %6.2f %6.2f %8.0f%%   %s -> %s" % [good.id, asks[0], asks[asks.size() / 2], asks[-1], best_margin * 100.0,
				buy_at.location.display_name if buy_at != null else "-", sell_at.location.display_name if sell_at != null else "-"])

	print("")
	print("Daily flow (units/day) for sample populations, terrestrial (agricultural) planet, food:")
	var sample := PlanetData.new()
	sample.planet_type = load("res://resources/planet_types/terrestrial.tres")
	var food := registry.commodity(&"food")
	for people in [1000, 10000, 100000, 1000000, 10000000]:
		sample.population = people
		var economy := model.compute(sample, false)
		print("  pop %9d: food made %8.1f used %8.1f" % [people, economy.production_of(food), economy.consumption_of(food)])
	quit(0)


func _is_generated(location: InhabitedData) -> bool:
	return location.resource_path.contains("/generated/")


func _names(goods: Array) -> String:
	var names := PackedStringArray()
	for good in goods:
		names.append(str(good.id))
	return ",".join(names) if not names.is_empty() else "-"


## Goods not held to the 1.0 to 2.0 balance rule, and why. Rare isotopes are short
## on purpose: a rare good.
const EXEMPT := {&"rare_isotopes": "rare by design"}


## Whether the galaxy makes enough of a good: what is made should be between one and
## two times what is used (the real game, with specialties). Military goods have no
## demand until military settlements exist.
func _verdict(good: Commodity, made: float, used: float) -> String:
	if EXEMPT.has(good.id):
		return "exempt (%s)" % EXEMPT[good.id]
	if good.military and used <= 0.0:
		return "NO CONSUMERS YET"
	if good.military and made <= 0.0:
		return "NO PRODUCERS YET"
	var ratio := made / maxf(used, 0.001)
	if ratio < 1.0:
		return "SHORT (%.2f)" % ratio
	if ratio >= 2.0:
		return "OVERSUPPLIED (%.2f)" % ratio
	return "ok"
