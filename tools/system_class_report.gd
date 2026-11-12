extends SceneTree
## Prints what the jump network says about every inhabited system, and a SUGGESTED
## class for each, to help a designer choose the "class" field in
## data/galaxy/galaxy_map.json. It changes nothing and decides nothing: the suggestion
## combines connectivity with geography but cannot see the things a designer knows
## (history, existing infrastructure, where an enemy will be). Read it as a list of
## candidates. Run with:
##   Godot --headless --path . --script res://tools/system_class_report.gd </dev/null

## Fewest jump links for a system to be a candidate hub (an economic centre).
const HUB_LINKS := 4
## Hops from the capital: up to this is core, then inner territory, then frontier.
const CORE_HOPS := 1
const INNER_HOPS := 3
## A chokepoint this close to the capital is a military centre candidate.
const CHOKE_HOPS := 2


func _init() -> void:
	var registry := ContentRegistry.new()
	var galaxy: Galaxy = load("res://resources/universe/galaxy.tres")
	var graph := GalaxyGraph.from_galaxy(galaxy)
	var between := graph.betweenness()
	var most := 0.0
	for id in between:
		most = maxf(most, between[id])
	var chokepoints := graph.articulation_points()

	# Hops from the capital of each faction, walking only that faction's own systems.
	var hops_from_capital := {}
	var capital_of := {}
	for faction in registry.factions():
		if faction.capital_system == &"":
			continue
		var claimed := func(id: StringName) -> bool:
			var claim := galaxy.get_claim(id)
			return claim != null and claim.id == faction.id
		var reach := graph.hops_from([faction.capital_system], claimed)
		for id in reach:
			hops_from_capital[id] = reach[id]
			capital_of[id] = faction.capital_system

	var rows: Array = []
	var counts := {}
	for id in galaxy.get_system_ids():
		var summary := galaxy.get_summary(id)
		if not summary.inhabited:
			continue
		var settlements := 0
		var stations := 0
		var people := 0
		for location_id in summary.location_ids:
			var location := registry.location(location_id)
			if location != null and location.is_dockable() and location.population > 0:
				settlements += 1
				people += location.population
				if not location is PlanetData:
					stations += 1
		var links := graph.degree(id)
		var hops: int = hops_from_capital.get(id, -1)
		var choke := chokepoints.has(id)
		var current := galaxy.get_system_class(id)
		var suggestion := _suggest(links, hops, choke)
		if current != null:
			suggestion = "(set: %s)" % current.id
		counts[suggestion] = counts.get(suggestion, 0) + 1
		rows.append({"id": id, "name": summary.system_name, "links": links, "hops": hops,
				"between": between[id] / most * 100.0 if most > 0.0 else 0.0, "choke": choke,
				"settlements": settlements, "stations": stations, "people": people, "suggestion": suggestion})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["links"] != b["links"]:
			return a["links"] > b["links"]
		return str(a["id"]) < str(b["id"]))

	print("")
	print("%d inhabited systems (of %d). Hops are measured from the faction capital over its own systems." % [rows.size(), galaxy.get_system_ids().size()])
	print("%-18s %-16s %5s %4s %7s %5s %5s %5s %11s  %s" % ["ID", "NAME", "LINKS", "HOPS", "TRANSIT", "CHOKE", "SETTL", "STATN", "POPULATION", "SUGGESTED"])
	for row in rows:
		print("%-18s %-16s %5d %4s %6.0f%% %5s %5d %5d %11d  %s" % [row["id"], row["name"], row["links"],
				str(row["hops"]) if row["hops"] >= 0 else "-", row["between"], "yes" if row["choke"] else "", row["settlements"],
				row["stations"], row["people"], row["suggestion"]])
	print("")
	print("Suggestions:")
	var keys := counts.keys()
	keys.sort()
	for key in keys:
		print("  %-60s %d" % [key, counts[key]])
	quit(0)


## A suggestion from connectivity and distance from the capital only.
func _suggest(links: int, hops: int, choke: bool) -> String:
	if hops == 0:
		return "capital: economic centre"
	if links >= HUB_LINKS:
		return "critical candidate (economic centre: %d links)" % links
	if choke and hops >= 0 and hops <= CHOKE_HOPS:
		return "military centre candidate (chokepoint %d hops from the capital)" % hops
	if hops < 0 or hops > INNER_HOPS:
		return "frontier" if links <= 2 else "frontier or inner (%d links, %d hops)" % [links, hops]
	if links == 1 and hops <= CORE_HOPS:
		return "rural (dead end beside the capital)"
	return "rural" if links <= 3 else "inner"
