class_name ContractContext
extends RefCounted
## What contracts need to know about the world to describe themselves and to be
## generated: the galaxy (systems, routes), the player's discovery and scouting
## progress, where the player is now, and the reward rules. The ContractManager
## owns one and hands it to every contract, so a contract can say "2 jumps, 41
## fuel" or "scouted 1 of 2 bodies" without knowing any manager.

var galaxy: Galaxy
var travel: TravelManager
## The game's content (all locations and commodities), for generating contracts.
var registry: ContentRegistry
var rewards: ContractRewards = ContractRewards.new()
## The biggest cargo hold any ship model has; offers asking for more than this
## are not achievable and are skipped. 0 = do not check.
var max_cargo: int = 0
## Callable() -> StringName: the system the player is in now.
var current_system: Callable = func() -> StringName: return &""


## The id of the system a location is in, or &"".
func system_of(location: InhabitedData) -> StringName:
	return galaxy.system_of_location(location.id) if galaxy != null and location != null else &""


## The display name of a system, or its id if the galaxy does not list it.
func system_name(system_id: StringName) -> String:
	var summary := galaxy.get_summary(system_id) if galaxy != null else null
	return summary.system_name if summary != null else str(system_id)


## "Sol > Sirius > Tau Ceti: 2 jumps, 41 fuel". The fuel is the cost of the
## jumps as shown on the galaxy map; it is not used up yet.
func journey_text(from_system: StringName, to_system: StringName) -> String:
	if galaxy == null or from_system == &"" or to_system == &"":
		return ""
	if from_system == to_system:
		return "Same system, no jump needed"
	var route := galaxy.find_route(from_system, to_system)
	if route.is_empty():
		return "No jump route"
	var names := PackedStringArray()
	for id in route:
		names.append(system_name(id))
	var jumps := route.size() - 1
	return "%s: %d %s, %d fuel" % [" > ".join(names), jumps, "jump" if jumps == 1 else "jumps", galaxy.get_route_cost(route)]


## (jumps, fuel) of the cheapest route, or (-1, -1) if there is none.
func journey(from_system: StringName, to_system: StringName) -> Vector2i:
	if galaxy == null:
		return Vector2i(-1, -1)
	var route := galaxy.find_route(from_system, to_system)
	if route.is_empty():
		return Vector2i(-1, -1)
	return Vector2i(route.size() - 1, galaxy.get_route_cost(route))
