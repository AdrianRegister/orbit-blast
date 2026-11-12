class_name ShipStats
extends Resource
## A ship model: everything shared by every ship of one kind (name, price,
## look and base flight numbers). One .tres per model in resources/ships/.
## Individual ships a player owns refer to a model and add their own name and
## upgrades (see OwnedShip); the numbers actually used in play are computed by
## ShipSpecs from the base values here plus the installed upgrades.
## Edit the .tres files, not the code.

## Permanent unique id, e.g. &"shuttle". Save files refer to the ship by this id,
## so it must never change once saves exist.
@export var id: StringName = &""
## Model name shown in shipyards and the HUD, e.g. "Shuttle".
@export var display_name: String = ""
@export_multiline var description: String = ""
## The faction this ship belongs to. A ship with a faction can only be bought at
## a shipyard of a location owned by that faction. Null = any shipyard.
@export var faction: Faction


func get_faction_name() -> String:
	return faction.display_name if faction != null else ""


func faction_id() -> StringName:
	return faction.id if faction != null else &""

## Purchase price in credits. Also what the model is worth as a trade-in.
@export var price: int = 0

## Sprite. Ship art must point up.
@export var texture: Texture2D
## How wide the ship is on screen, in world pixels, whatever size the texture
## is. 0 = use `sprite_scale` instead.
@export var display_width: float = 0.0
## Fallback used only when display_width is 0: a plain multiplier of the
## texture's size (a 500 px sprite at 0.15 is 75 px wide).
@export var sprite_scale: float = 0.15

## Base acceleration while thrusting, in pixels per second squared.
@export var thrust: float = 300.0
## Base rotation speed in radians per second.
@export var turn_rate: float = 3.0
## Base speed limit in pixels per second.
@export var max_speed: float = 500.0
## Base cargo hold size, in units of cargo.
@export var cargo_capacity: int = 500

## Combat. Shields soak damage first and recharge by themselves; armour and hull
## only come back through repairs. Hull at zero destroys the ship (see
## DamageModel). Energy pays for weapon shots and recharges continuously.
@export var shield_capacity: float = 50.0
## Shield points regained per second, starting `shield_regen_delay` seconds
## after the last hit.
@export var shield_regen: float = 5.0
@export var shield_regen_delay: float = 4.0
@export var armour: float = 50.0
@export var hull: float = 100.0
@export var energy_capacity: float = 100.0
@export var energy_regen: float = 15.0
## Radius of the area a shot can hit, in world pixels. 0 = derive it from the
## ship's drawn size.
@export var hit_radius: float = 0.0
## The places weapons can be fitted, and the weapons a ship of this model has
## as new. default_loadout is parallel to weapon_mounts (entry N goes in mount
## N, null = empty); it is also what NPC ships fly with.
@export var weapon_mounts: Array[WeaponMount] = []
@export var default_loadout: Array[WeaponDefinition] = []


## Radius shots can hit: `hit_radius`, or 40% of the larger side of the ship.
func get_hit_radius() -> float:
	if hit_radius > 0.0:
		return hit_radius
	var size := get_size()
	return maxf(size.x, size.y) * 0.4


## The scale to draw the sprite at: display_width spread over the texture's
## width, or `sprite_scale` when no display width is set.
func get_scale() -> float:
	if display_width > 0.0 and texture != null and texture.get_width() > 0:
		return display_width / float(texture.get_width())
	return sprite_scale


## Visual size in world pixels, used for the click area and selection brackets.
func get_size() -> Vector2:
	if texture == null:
		return Vector2(64, 64)
	return texture.get_size() * get_scale()


func validate() -> Array[String]:
	var problems: Array[String] = []
	if id == &"":
		problems.append("id is empty")
	if display_name.is_empty():
		problems.append("display_name is empty")
	if texture == null:
		problems.append("texture is not set")
	if price < 0:
		problems.append("price is negative")
	if display_width < 0.0:
		problems.append("display_width is negative")
	if thrust <= 0.0 or turn_rate <= 0.0 or max_speed <= 0.0:
		problems.append("thrust, turn_rate and max_speed must be above zero")
	if cargo_capacity < 0:
		problems.append("cargo_capacity is negative")
	if hull <= 0.0:
		problems.append("hull must be above zero")
	if shield_capacity < 0.0 or armour < 0.0 or energy_capacity < 0.0:
		problems.append("shield_capacity, armour and energy_capacity cannot be negative")
	if shield_regen < 0.0 or shield_regen_delay < 0.0 or energy_regen < 0.0:
		problems.append("regeneration values cannot be negative")
	if hit_radius < 0.0:
		problems.append("hit_radius is negative")
	if default_loadout.size() > weapon_mounts.size():
		problems.append("default_loadout has more entries than weapon_mounts")
	for mount in weapon_mounts:
		if mount == null:
			problems.append("weapon_mounts has an empty entry")
		else:
			for problem in mount.validate():
				problems.append("mount: " + problem)
	for index in default_loadout.size():
		var weapon := default_loadout[index]
		if weapon != null and index < weapon_mounts.size() and not weapon.fits(weapon_mounts[index]):
			problems.append("default_loadout[%d] (%s) does not fit its mount" % [index, weapon.display_name])
	return problems
