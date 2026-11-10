class_name PlanetData
extends InhabitedData
## InhabitedData for a planet: everything a station has, plus the planet's type.

## Terrestrial, Rocky, ... Decides the planet's sprite (see PlanetType).
@export var planet_type: PlanetType


func validate() -> Array[String]:
	var problems: Array[String] = super()
	if planet_type == null:
		problems.append("planet_type is not set")
	elif planet_type.texture == null:
		problems.append("planet_type '%s' has no texture" % planet_type.display_name)
	return problems
