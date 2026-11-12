class_name PopulationDisplay
extends RefCounted
## Turns a location's population (its economic weight, which the economy uses) into
## the number the player reads: a scaled, rounded figure written in words ("2.6
## billion", "320 million", "480,000"). See PopulationDisplayRules. It reads the
## location and its system's class and changes nothing.

var _galaxy: Galaxy
var _rules: PopulationDisplayRules


func _init(galaxy: Galaxy, rules: PopulationDisplayRules) -> void:
	_galaxy = galaxy
	_rules = rules


## How many times larger than the real population the displayed one is. In order: the
## location's own scale, its economy profile's, the class entry of its system, the default.
func scale_for(location: InhabitedData) -> float:
	if location.population_display_scale > 0.0:
		return location.population_display_scale
	var profile := location.get_economy_profile()
	if profile != null and profile.population_display_scale > 0.0:
		return profile.population_display_scale
	var is_station := not location is PlanetData
	var system_class := _galaxy.get_system_class(_galaxy.system_of_location(location.id))
	var entry := _rules.entry_for(system_class) if system_class != null else null
	if entry != null:
		return entry.station_scale if is_station else entry.planet_scale
	return _rules.default_station_scale if is_station else _rules.default_planet_scale


## The population shown for a location, rounded to the rules' significant figures.
func display_population(location: InhabitedData) -> int:
	return round_significant(location.population * scale_for(location), _rules.significant_figures)


## The displayed population as text: "2.6 billion", "320 million", "4.8 million", or
## the number with commas below a million ("480,000").
func text_for(location: InhabitedData) -> String:
	return format_count(display_population(location))


## Rounds to `figures` significant figures (1,234,567 to 2 figures is 1,200,000).
static func round_significant(value: float, figures: int) -> int:
	if value <= 0.0:
		return 0
	var digits := int(floor(log(value) / log(10.0))) + 1
	var step := pow(10.0, digits - figures)
	if step <= 1.0:
		return roundi(value)
	return int(round(value / step) * step)


## Writes a count in words from a million up, with commas below that.
static func format_count(value: int) -> String:
	if value >= 1000000000:
		return "%s billion" % _trim(value / 1000000000.0)
	if value >= 1000000:
		return "%s million" % _trim(value / 1000000.0)
	return NumberFormat.with_commas(value)


## One decimal place under ten ("2.6", "4.8"), none from ten up ("96", "320"), and no
## trailing ".0" ("1").
static func _trim(value: float) -> String:
	if value >= 10.0:
		return str(roundi(value))
	var text := "%.1f" % value
	return text.trim_suffix(".0")
