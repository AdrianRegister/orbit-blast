class_name PlayerShip
extends CharacterBody2D
## Escape Velocity-style flight: rotate, thrust along the facing direction,
## and drift with inertia. `rotation` is the ship's heading (0 = facing right).

## Flight numbers (base values with upgrades applied). Set by apply_ship().
var stats: ShipSpecs

@onready var _sprite: Sprite2D = $Sprite2D

## False while docked: the ship stops dead and ignores the flight controls.
var flight_enabled: bool = true


func _ready() -> void:
	# Top-down space: there is no floor or wall concept for movement.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING


## Becomes the given ship: its flight numbers and its model's sprite. Used at
## the start, after a purchase or ship switch, and after loading a save.
func apply_ship(ship: OwnedShip) -> void:
	stats = ship.get_specs()
	_sprite.texture = ship.model.texture
	_sprite.scale = Vector2(ship.model.sprite_scale, ship.model.sprite_scale)


func set_flight_enabled(enabled: bool) -> void:
	flight_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if stats == null or not flight_enabled:
		return

	var max_turn_step: float = stats.turn_rate * delta

	# Left/Right: rotate only. Velocity is untouched.
	rotation += Input.get_axis("turn_left", "turn_right") * max_turn_step

	# Down: turn to face against the direction of travel (retrograde),
	# so that thrusting afterwards slows the ship down.
	if Input.is_action_pressed("reverse") and velocity.length() > 1.0:
		var retrograde: float = (-velocity).angle()
		rotation += clampf(angle_difference(rotation, retrograde), -max_turn_step, max_turn_step)

	# Up: add acceleration in the facing direction. No drag, so speed persists.
	if Input.is_action_pressed("thrust"):
		velocity += Vector2.from_angle(rotation) * stats.thrust * delta

	velocity = velocity.limit_length(stats.max_speed)
	move_and_slide()
