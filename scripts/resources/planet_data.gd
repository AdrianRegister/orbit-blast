class_name PlanetData
extends InhabitedData
## InhabitedData for a planet: everything a station has, plus the planet's type.

## Terrestrial, Rocky, ... Decides the planet's sprite (see PlanetType).
@export var planet_type: PlanetType


## False for bodies that cannot be landed on, such as gas giants. An undockable
## body must be uninhabited and offer no services.
@export var dockable: bool = true


func is_dockable() -> bool:
	return dockable


## The planet's own picture if set, otherwise its type's settlement picture.
func get_picture() -> Texture2D:
	if picture != null:
		return picture
	return planet_type.settlement_picture if planet_type != null else null


## The location's own profile if set, otherwise the one its planet type gives.
func get_economy_profile() -> EconomyProfile:
	if economy_profile != null:
		return economy_profile
	return planet_type.economy_profile if planet_type != null else null


func validate() -> Array[String]:
	var problems: Array[String] = super()
	if planet_type == null:
		problems.append("planet_type is not set")
	elif planet_type.texture == null:
		problems.append("planet_type '%s' has no texture" % planet_type.display_name)
	if not dockable:
		if population > 0 or not shipyard_ships.is_empty() or not outfitter_upgrades.is_empty():
			problems.append("an undockable body must have no population or services")
	return problems
