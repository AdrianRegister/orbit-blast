class_name SystemClass
extends Resource
## A kind of star system by its strategic and economic role: critical, economic
## centre, military centre, military output, rural, frontier, and any others
## added later. One .tres per class in resources/system_classes/, chosen for a
## system with the optional "class" field of its row in data/galaxy/galaxy_map.json.
##
## A class is what a system IS, set by the designer and permanent. Where a system
## sits relative to a faction's centres of power (its zone) is a different thing:
## it is derived from the jump network and who owns what, and changes in play.
##
## Nothing in code names a class id. Behaviour comes from the fields below, so a
## new class is a new file. Subtypes name a `parent`: an economic centre IS a
## critical system (see is_a()).

## Permanent unique id, e.g. &"economic_centre". Never change it once content or
## saves refer to it.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

## The class this is a kind of (an economic centre is a critical system). Null
## for a top level class.
@export var parent: SystemClass

## Whether a system of this class (or of a subtype) can be a centre of power for
## the faction that controls it, creating a core around it. See ZoneManager.
@export var centre_of_power: bool = false

## Fewest jump links a system of this class must have. Economic centres need
## several because transit is what makes them important; military centres are
## chokepoints and are exempt (0).
@export var min_links: int = 0
## Whether the system must be inhabited (have a settlement people live in).
@export var requires_inhabited: bool = true

## Scales the military value of the system's locations (see MilitaryValueRules).
@export var military_value_multiplier: float = 1.0

## Most objects (planets, moons and stations) a system of this class may hold.
## Ordinary systems hold StarSystem.MAX_OBJECTS; the limit never exceeds
## StarSystem.ABSOLUTE_MAX_OBJECTS.
@export var max_objects: int = 3

@export_group("Generation hints")
## Used by the galaxy generator when it builds a system of this class: how many
## settlements and, of those, how many stations; a multiplier on the population
## its archetype would give; and the economy profile its stations get (null = the
## default).
@export var settlements_min: int = 1
@export var settlements_max: int = 1
@export var stations_min: int = 0
@export var stations_max: int = 1
@export var population_scale: float = 1.0
@export var station_profile: EconomyProfile


## True if this class is `class_id` or a subtype of it.
func is_a(class_id: StringName) -> bool:
	var current := self
	var steps := 0
	while current != null and steps < 16:  # the limit only guards against a loop in the data
		if current.id == class_id:
			return true
		current = current.parent
		steps += 1
	return false


## Whether a system of this class can be a centre of power: this class or any of
## its parents says so.
func can_be_centre() -> bool:
	var current := self
	var steps := 0
	while current != null and steps < 16:
		if current.centre_of_power:
			return true
		current = current.parent
		steps += 1
	return false


## Problems a system with `link_count` jump links and the given inhabited state
## would have being this class; empty when it fits.
func check_system(inhabited: bool, link_count: int) -> Array[String]:
	var problems: Array[String] = []
	if requires_inhabited and not inhabited:
		problems.append("a %s system must be inhabited" % display_name.to_lower())
	if link_count < min_links:
		problems.append("a %s system needs at least %d jump links (has %d)" % [display_name.to_lower(), min_links, link_count])
	return problems


## Human-readable problems with this class; empty when it is valid.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("class '%s' has no display_name" % id)
	if min_links < 0:
		problems.append("class '%s' has a negative min_links" % id)
	if max_objects < 1 or max_objects > StarSystem.ABSOLUTE_MAX_OBJECTS:
		problems.append("class '%s' max_objects must be 1 to %d" % [id, StarSystem.ABSOLUTE_MAX_OBJECTS])
	if military_value_multiplier < 0.0:
		problems.append("class '%s' has a negative military_value_multiplier" % id)
	if settlements_min < 0 or settlements_max < settlements_min:
		problems.append("class '%s' settlement range is wrong" % id)
	if stations_min < 0 or stations_max < stations_min or stations_max > settlements_max:
		problems.append("class '%s' station range is wrong (stations are settlements)" % id)
	if population_scale <= 0.0:
		problems.append("class '%s' population_scale must be positive" % id)
	var current := parent
	var steps := 0
	while current != null:
		steps += 1
		if current == self or steps > 16:
			problems.append("class '%s' is its own ancestor" % id)
			break
		current = current.parent
	return problems
