class_name PlayerShip
extends CharacterBody2D
## Escape Velocity-style flight: rotate, thrust along the facing direction,
## and drift with inertia. `rotation` is the ship's heading (0 = facing right).

## Flight numbers (base values with upgrades applied). Set by apply_ship().
var stats: ShipSpecs

@onready var _sprite: Sprite2D = $Sprite2D
## The ship's combat side: defences, weapons and hit area.
@onready var combatant: Combatant = $Combatant

## Speed (px/s) and acceleration (px/s^2) of a warp jump. Purely a visual effect.
const WARP_SPEED := 9000.0
const WARP_ACCELERATION := 6000.0

## True from pressing J until the jump completes: the controls are ignored and
## the ship accelerates to warp speed along its heading.
var warping: bool = false

## False while docked: the ship stops dead and ignores the flight controls.
var flight_enabled: bool = true


func _ready() -> void:
	# Top-down space: there is no floor or wall concept for movement.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	combatant.is_player = true
	combatant.combat_id = &"player"
	# Shows where to aim to hit the selected ship.
	var lead := LeadIndicator.new()
	lead.combatant = combatant
	add_child(lead)


## Becomes the given ship: its flight numbers, its model's sprite, and its
## defences and weapons (shields and energy start full; armour and hull follow
## the ship's saved condition). Used at the start, after a purchase or ship
## switch, and after loading a save.
func apply_ship(ship: OwnedShip) -> void:
	stats = ship.get_specs()
	_sprite.texture = ship.model.texture
	_sprite.scale = Vector2.ONE * ship.model.get_scale()
	if combatant != null:  # (not yet in the scene tree: nothing to set up)
		combatant.setup(ship.model, stats, ship.weapons, ship.condition,
				func() -> float: return rotation, func() -> Vector2: return velocity)


func set_flight_enabled(enabled: bool) -> void:
	flight_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO


func begin_warp() -> void:
	warping = true


func end_warp() -> void:
	warping = false


func _physics_process(delta: float) -> void:
	if warping:
		velocity += Vector2.from_angle(rotation) * WARP_ACCELERATION * delta
		velocity = velocity.limit_length(WARP_SPEED)
		move_and_slide()
		return
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

	# Space: fire every weapon that is ready.
	if Input.is_action_pressed("fire_primary"):
		combatant.fire()
