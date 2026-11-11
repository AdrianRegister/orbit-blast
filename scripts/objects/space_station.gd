class_name SpaceStation
extends InhabitedNode
## A space station drawn from a sprite. Like a planet, its size in world pixels
## (the sprite's width) comes from the InhabitedData `size`. The sprite is set
## in the scene (`texture`), so another station look is a different scene or
## an override on the instance.

## The station sprite. Art points up; it is not rotated.
@export var texture: Texture2D

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	super()
	_apply_visual()


func _apply_visual() -> void:
	if texture == null:
		return
	_sprite.texture = texture
	var uniform_scale: float = _diameter() / float(texture.get_width())
	_sprite.scale = Vector2(uniform_scale, uniform_scale)


func _diameter() -> float:
	return data.size if data != null else 100.0


func _get_object_type() -> ObjectType:
	return ObjectType.STATION


func _get_target_bounds() -> Vector2:
	return Vector2(_diameter(), _diameter())


func _is_target_round() -> bool:
	return true
