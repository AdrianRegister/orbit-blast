class_name BurstEffect
extends CPUParticles2D
## A short one-shot puff of particles: hit sparks and explosions. Build one with
## spark() or explosion(), add it to the world, and it removes itself when done.


## A small spark where a shot landed.
static func spark(at: Vector2, colour: Color) -> BurstEffect:
	return _make(at, colour, 8, 0.35, 90.0, 220.0, 1.5, 3.0)


## The ship breaking up. `size` scales it (about the ship's width in pixels).
static func explosion(at: Vector2, size: float) -> BurstEffect:
	var effect := _make(at, Color(1.0, 0.6, 0.2), 40, 0.9, 60.0, 260.0 + size, 2.5, 6.0)
	effect.amount = clampi(int(size * 0.5), 30, 120)
	return effect


static func _make(at: Vector2, colour: Color, count: int, life: float, speed_min: float,
		speed_max: float, scale_min: float, scale_max: float) -> BurstEffect:
	var effect := BurstEffect.new()
	effect.position = at
	effect.one_shot = true
	effect.explosiveness = 1.0
	effect.amount = count
	effect.lifetime = life
	effect.emitting = true
	effect.direction = Vector2.RIGHT
	effect.spread = 180.0
	effect.gravity = Vector2.ZERO
	effect.initial_velocity_min = speed_min
	effect.initial_velocity_max = speed_max
	effect.scale_amount_min = scale_min
	effect.scale_amount_max = scale_max
	effect.damping_min = 30.0
	effect.damping_max = 90.0
	effect.z_index = 2
	var fade := Gradient.new()
	fade.set_color(0, colour)
	fade.set_color(1, Color(colour.r, colour.g * 0.4, colour.b * 0.2, 0.0))
	effect.color_ramp = fade
	return effect


func _ready() -> void:
	finished.connect(queue_free)
