class_name PopulationDisplayRules
extends Resource
## How the population shown to the player relates to the number the economy uses
## (resources/economy/population_display_rules.tres).
##
## A location's `population` is its economic weight: markets, production, military
## value and importance are all tuned around it, so it is never changed to make the
## galaxy feel bigger. What the player reads (the POPULATION row of the target panel
## and the settlement screen) is that number times a scale, so Earth can hold billions
## while the economy still sees 8.5 million. Display only: nothing here is saved or
## fed back into any calculation.
##
## The scale of a location comes from, in order: its own population_display_scale,
## its economy profile's population_display_scale, the entry for its system's class
## (planets and stations separately), then the defaults below. See PopulationDisplay.

## Scales for locations in systems with no class, or a class with no entry.
@export var default_planet_scale: float = 4.0
@export var default_station_scale: float = 8.0

## Scales by system class. A subtype with no entry of its own uses its parent's.
@export var entries: Array[PopulationScaleEntry] = []

## The displayed number is rounded to this many significant figures, so a huge figure
## does not look measured (2,550,000,000 is shown as 2.6 billion).
@export_range(1, 6) var significant_figures: int = 2


## The entry for a class: its own, or the nearest parent's. Null if there is none.
func entry_for(system_class: SystemClass) -> PopulationScaleEntry:
	var current := system_class
	var steps := 0
	while current != null and steps < 16:  # the limit only guards against a loop in the data
		for entry in entries:
			if entry != null and entry.system_class != null and entry.system_class.id == current.id:
				return entry
		current = current.parent
		steps += 1
	return null


func validate() -> Array[String]:
	var problems: Array[String] = []
	if default_planet_scale <= 0.0 or default_station_scale <= 0.0:
		problems.append("the default scales must be positive")
	var seen := {}
	for entry in entries:
		if entry == null or entry.system_class == null:
			problems.append("an entry has no system class")
			continue
		if entry.planet_scale <= 0.0 or entry.station_scale <= 0.0:
			problems.append("the entry for '%s' needs positive scales" % entry.system_class.id)
		if seen.has(entry.system_class.id):
			problems.append("the class '%s' has two entries" % entry.system_class.id)
		seen[entry.system_class.id] = true
	return problems
