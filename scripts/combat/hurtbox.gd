class_name Hurtbox
extends Area2D
## The area of a ship that shots can hit. A child of its Combatant. It is only
## ever searched by projectile rays (physics layer 3); it detects nothing and
## blocks nothing, so it never affects how ships move.

## Physics layer 3, as a bit mask ("ship_hurtbox" in the project settings).
const COLLISION_LAYER := 4

## The ship this area belongs to. Set by the Combatant.
var combatant: Combatant

@onready var _shape: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = COLLISION_LAYER
	collision_mask = 0
	monitoring = false
	# Each hurtbox needs its own shape: scene instances share sub-resources.
	_shape.shape = CircleShape2D.new()


func set_radius(radius: float) -> void:
	(_shape.shape as CircleShape2D).radius = radius


## A ship that is destroyed (or docked) stops being hit.
func set_active(active: bool) -> void:
	_shape.set_deferred("disabled", not active)
