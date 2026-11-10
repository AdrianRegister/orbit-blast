class_name Planet
extends InhabitedNode
## A planet drawn from a sprite. Its data must be a PlanetData: the sprite comes
## from the planet's type (`planet_type.texture`) and its size in world pixels
## from `size`, so one scene serves every planet.

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if data != null and not data is PlanetData:
		push_error("%s: a Planet needs PlanetData, not plain InhabitedData." % name)
	super()
	_apply_visual()


func _apply_visual() -> void:
	var planet_data := data as PlanetData
	if planet_data == null or planet_data.planet_type == null \
			or planet_data.planet_type.texture == null:
		return
	var texture: Texture2D = planet_data.planet_type.texture
	_sprite.texture = texture
	var uniform_scale: float = planet_data.size / float(texture.get_width())
	_sprite.scale = Vector2(uniform_scale, uniform_scale)


## HUD type text, e.g. "Planet (Terrestrial)".
func _type_label() -> String:
	var planet_data := data as PlanetData
	if planet_data == null or planet_data.planet_type == null:
		return super()
	return "%s (%s)" % [super(), planet_data.planet_type.display_name]


func _get_object_type() -> ObjectType:
	return ObjectType.PLANET


func _get_target_bounds() -> Vector2:
	var diameter: float = data.size if data != null else 64.0
	return Vector2(diameter, diameter)


func _is_target_round() -> bool:
	return true
